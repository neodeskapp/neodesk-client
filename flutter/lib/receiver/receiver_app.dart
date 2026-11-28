// The receiver's main window (main.dart runReceiverApp): the home window
// with Get help, Messages and My tickets, the company's name and logo from
// the server's branding, and the bridge to the process that keeps the
// device token (src/nd_tickets.rs, src/nd_screenshot.rs).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/branding_logo.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/models/branding_model.dart';
import 'package:flutter_hbb/models/nd_chat_bridge.dart';
import 'package:flutter_hbb/models/nd_chat_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import 'receiver_home.dart';
import 'receiver_links.dart';
import 'receiver_session.dart';
import 'tickets_model.dart';
import 'tickets_view.dart';

const kReceiverWindowSize = Size(960, 660);
const kReceiverWindowMinSize = Size(760, 520);

/// The ticket requests and the notifications through the client core.
class BridgeReceiverBackend implements ReceiverBackend {
  @override
  Future<NdTicketAnswer> request(String method, String path,
      [Map<String, Object?>? body]) async {
    final request = jsonEncode({
      'method': method,
      'path': path,
      if (body != null) 'body': jsonEncode(body),
    });
    final answer = await bind.mainGetCommon(key: 'nd-tickets-request:$request');
    try {
      final v = jsonDecode(answer) as Map<String, dynamic>;
      return NdTicketAnswer(v['status'] is int ? v['status'] as int : 0,
          v['body'] is String ? v['body'] as String : '');
    } catch (_) {
      return const NdTicketAnswer(0, '');
    }
  }

  @override
  Future<int> download(String path, String to) async {
    final answer = await bind.mainGetCommon(
        key: 'nd-tickets-download:${jsonEncode({'path': path, 'to': to})}');
    try {
      final v = jsonDecode(answer) as Map<String, dynamic>;
      return v['status'] is int ? v['status'] as int : 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<Map<String, String>> about() async {
    try {
      final v = jsonDecode(await bind.mainGetCommon(key: 'nd-tickets-about'))
          as Map<String, dynamic>;
      return {
        for (final k in ['reporter', 'os'])
          if (v[k] is String) k: v[k] as String,
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  void notify(String title, String body, String link) =>
      NdChatService.instance.notifyWith(title, body, link);
}

/// A picture of the screen without this window on it: the window hides,
/// the core reads the main screen, the window comes back. Null when no
/// picture could be taken.
Future<({String path, int size})?> takeScreenshotHidden() async {
  try {
    await windowManager.hide();
    // Windows fades a window out; wait until it is gone from the screen
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final answer = await bind.mainGetCommon(key: 'nd-screenshot');
    final v = jsonDecode(answer) as Map<String, dynamic>;
    final path = v['path'];
    final size = v['size'];
    if (path is String && path.isNotEmpty && size is int) {
      return (path: path, size: size);
    }
    return null;
  } catch (e) {
    debugPrint('screenshot: $e');
    return null;
  } finally {
    await windowManager.show();
    await windowManager.focus();
  }
}

class ReceiverWindow extends StatefulWidget {
  const ReceiverWindow({super.key, required this.onboarding});
  final OnboardingService onboarding;

  @override
  State<ReceiverWindow> createState() => _ReceiverWindowState();
}

class _ReceiverWindowState extends State<ReceiverWindow> with WindowListener {
  final router = ReceiverRouter();
  late final tickets = NdTicketsModel(
    backend: BridgeReceiverBackend(),
    noteTitle: tr('nd-rcv-note-ticket'),
    noteBody: tr('nd-rcv-note-ticket-body'),
  );
  NdChatService get _chat => NdChatService.instance;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    ndReceiverOpen = _open;
    _chat.openLink = _open;
    _chat.model.onOtherFrame = (frame) {
      tickets.othersNotify = _chat.model.othersNotify;
      tickets.onFrame(frame);
    };
    _chat.start();
    tickets.load();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    tickets.dispose();
    super.dispose();
  }

  /// Opens a page of the home window and brings it up.
  void _open(String page) {
    router.open(page);
    windowOnTop(null);
  }

  @override
  void onWindowClose() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  Future<List<NdTicketLocalFile>> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return const [];
    return [
      for (final f in result.files)
        if (f.path != null) NdTicketLocalFile(f.path!, f.size)
    ];
  }

  Future<String?> _saveFile(NdTicketFile file) async {
    final path = await FilePicker.platform.saveFile(
        fileName: file.name, dialogTitle: tr('nd-chat-download', [file.name]));
    if (path == null) return '';
    return await tickets.save(file, path) ? path : null;
  }

  Widget? _logo() {
    final b = BrandingModel.current;
    if (!b.hasLogo.value || b.logoPath.value.isEmpty) return null;
    return BrandingLogoImage(
      path: b.logoPath.value,
      cacheKey: 'branding-rcv-${b.logoPath.value}-${b.logoEpoch.value}',
      maxHeight: 18,
      fit: BoxFit.contain,
      alignment: Alignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final company = BrandingModel.current.companyName.value.trim();
      return NdWindowFrame(
        titleBar: GestureDetector(
          onPanStart: (_) => windowManager.startDragging(),
          child: NdTitleBar(
            height: 36,
            brand: company.isNotEmpty
                ? NdTitleBrand(serverName: company, serverLogo: _logo())
                : const NdTitleBrand(title: 'NeoDesk'),
            controls: NdWindowControls(
              height: 36,
              onMinimize: () => windowManager.minimize(),
              onMaximize: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              onClose: onWindowClose,
            ),
          ),
        ),
        child: ReceiverSession(
          service: widget.onboarding,
          logo: _logo(),
          window: ReceiverWindowActions(
            toFront: () => windowOnTop(null),
            hide: () => windowManager.hide(),
            show: () async {
              await windowManager.show();
              await windowManager.focus();
            },
          ),
          home: ReceiverHome(
          router: router,
          onboarding: widget.onboarding,
          chat: _chat.model,
          company: company,
          messages: (_) => _chat.page(
            showClose: false,
            screenshot: () async {
              final p = await takeScreenshotHidden();
              return p == null ? null : NdChatLocalFile(p.path, p.size);
            },
          ),
          tickets: tickets,
          ticketActions: NdTicketActions(
            pickFiles: _pickFiles,
            saveFile: _saveFile,
            screenshot: () async {
              final p = await takeScreenshotHidden();
              return p == null ? null : NdTicketLocalFile(p.path, p.size);
            },
          ),
          ),
        ),
      );
    });
  }
}
