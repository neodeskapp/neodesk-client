// The chat window in the app: the socket and the files of NdChatModel go
// through the process that keeps the device token (src/nd_chat.rs), the
// model lives as long as the main window's process, and the window is
// shown in place of Home.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/nd_chat_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/nd_chat_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

/// One chat socket relayed by the Rust side. Its events arrive as global
/// events named "nd-chat" with the socket's number.
class _BridgeSocket implements NdChatSocket {
  final _frames = StreamController<String>();
  int? number;
  int _status = 0;
  Duration? _retryAfter;
  final _early = <Map<String, dynamic>>[];

  @override
  Stream<String> get frames => _frames.stream;

  @override
  int get closeStatus => _status;

  @override
  Duration? get retryAfter => _retryAfter;

  @override
  void send(String frame) =>
      bind.mainSetCommon(key: 'nd-chat-send', value: frame);

  @override
  void close() {
    bind.mainSetCommon(key: 'nd-chat-close', value: '');
    _end(0);
  }

  void _numbered(int? n) {
    number = n;
    if (n == null) {
      _end(0);
      return;
    }
    for (final evt in _early) {
      if (evt['socket'] == n) _handle(evt);
    }
    _early.clear();
  }

  void _handle(Map<String, dynamic> evt) {
    if (_frames.isClosed) return;
    final frame = evt['frame'];
    if (frame is String) {
      _frames.add(frame);
    } else if (evt.containsKey('closed')) {
      final s = evt['closed'];
      final retry = evt['retry_after'];
      if (retry is int && retry > 0) _retryAfter = Duration(seconds: retry);
      _end(s is int ? s : int.tryParse('$s') ?? 0);
    }
  }

  void _end(int status) {
    if (_frames.isClosed) return;
    _status = status;
    _frames.close();
  }
}

class _BridgeFiles implements NdChatFiles {
  @override
  Future<NdChatUpload> upload(String path) async {
    final answer = await bind.mainGetCommon(key: 'nd-chat-upload:$path');
    try {
      final v = jsonDecode(answer) as Map<String, dynamic>;
      final status = v['status'] is int ? v['status'] as int : 0;
      final id = v['file_id'];
      return NdChatUpload(status, id is String ? id : null);
    } catch (_) {
      return const NdChatUpload(0, null);
    }
  }

  @override
  Future<int> download(String id,
      {required bool inline, required String toPath}) async {
    final request = jsonEncode({'id': id, 'inline': inline, 'path': toPath});
    final answer = await bind.mainGetCommon(key: 'nd-chat-download:$request');
    try {
      final v = jsonDecode(answer) as Map<String, dynamic>;
      return v['status'] is int ? v['status'] as int : 0;
    } catch (_) {
      return 0;
    }
  }
}

class NdChatService with WindowListener {
  NdChatService._();

  static final instance = NdChatService._();

  /// The chat window is shown in place of Home.
  final open = false.obs;

  /// The app's window has the focus.
  final focused = ValueNotifier<bool>(true);

  _BridgeSocket? _socket;
  final _files = _BridgeFiles();
  final _pictures = <String, Uint8List?>{};
  bool _started = false;

  late final NdChatModel model = NdChatModel(
    connect: _connect,
    files: _files,
    notify: (title, body) => bind.mainSetCommon(
        key: 'nd-chat-notify',
        value: jsonEncode({'title': title, 'body': body})),
  );

  /// Connects the chat of this computer, once per process.
  void start() {
    if (_started || !isDesktop) return;
    _started = true;
    platformFFI.registerEventHandler('nd-chat', 'nd-chat', _onEvent);
    windowManager.addListener(this);
    windowManager.isFocused().then((v) => focused.value = v);
    model.onFront = (front) =>
        bind.mainSetCommon(key: 'nd-chat-front', value: front ? '1' : '');
    model.start();
  }

  NdChatSocket _connect() {
    final s = _BridgeSocket();
    _socket = s;
    bind
        .mainGetCommon(key: 'nd-chat-open')
        .then((v) => s._numbered(int.tryParse(v)), onError: (_) => s._end(0));
    return s;
  }

  Future<void> _onEvent(Map<String, dynamic> evt) async {
    if (evt['activated'] == true) {
      show();
      return;
    }
    if (evt.containsKey('tray')) {
      model.othersNotify = evt['tray'] == true;
      return;
    }
    final s = _socket;
    if (s == null) return;
    if (s.number == null) {
      s._early.add(evt);
    } else if (evt['socket'] == s.number) {
      s._handle(evt);
    }
  }

  @override
  void onWindowFocus() => focused.value = true;

  @override
  void onWindowBlur() => focused.value = false;

  @override
  void onWindowMinimize() => focused.value = false;

  /// Brings the main window up with the chat on Home.
  Future<void> show() async {
    for (var i = 0; i < 50 && !Get.isRegistered<DesktopTabController>(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (Get.isRegistered<DesktopTabController>()) {
      Get.find<DesktopTabController>().jumpTo(0);
    }
    open.value = true;
    await windowOnTop(null);
  }

  void close() => open.value = false;

  Widget page() => NdChatPage(
        model: model,
        onClose: close,
        windowFocused: focused,
        actions: NdChatPageActions(
          pickFiles: _pickFiles,
          saveFile: _saveFile,
          picture: _picture,
          openLink: (uri) =>
              launchUrl(uri, mode: LaunchMode.externalApplication),
        ),
      );

  Future<List<NdChatLocalFile>> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return const [];
    return [
      for (final f in result.files)
        if (f.path != null) NdChatLocalFile(f.path!, f.size)
    ];
  }

  Future<String?> _saveFile(NdChatFile file) async {
    final path = await FilePicker.platform
        .saveFile(fileName: file.name, dialogTitle: translate('nd-chat-download')
            .replaceFirst('{}', file.name));
    if (path == null) return '';
    final status = await _files.download(file.id, inline: false, toPath: path);
    return status == 200 ? path : null;
  }

  Future<Uint8List?> _picture(NdChatFile file) async {
    if (_pictures.containsKey(file.id)) return _pictures[file.id];
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}${Platform.pathSeparator}nd-chat'
          '${Platform.pathSeparator}${file.id}';
      final status = await _files.download(file.id, inline: true, toPath: path);
      final bytes = status == 200 ? await File(path).readAsBytes() : null;
      _pictures[file.id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

/// neodesk://chat: the notification and the tray open the chat with it.
Future<void> openChatLink() => NdChatService.instance.show();

/// Home with the chat shown in its place while it is open.
class NdChatHome extends StatelessWidget {
  const NdChatHome({super.key, required this.home});
  final Widget home;

  @override
  Widget build(BuildContext context) {
    final service = NdChatService.instance;
    return Obx(() {
      if (!service.open.value) return home;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: service.page(),
        ),
      );
    });
  }
}
