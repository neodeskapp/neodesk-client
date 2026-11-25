// The computer's own chat with the console's support staff: the chat
// protocol of version 2 as the console's PROTOCOL.md describes it for a
// computer (sections 1, 3 to 10). The model holds the conversation, talks
// to the socket and decides what the window shows; the window
// (desktop/pages/nd_chat_page.dart) only draws it.
//
// The socket and the files go through the process that keeps the device
// token (models/nd_chat_bridge.dart), so the model gets them as
// NdChatSocket and NdChatFiles and the tests give it fakes.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// [NdChatSocket.closeStatus] when this computer holds no device token for
/// its server: the server is no NeoDesk console or hasn't approved it yet.
const kNdChatNoToken = 1;

/// [NdChatSocket.closeStatus] when an admin turned "Chat with computers"
/// off: refused with 503 and X-NeoDesk-Chat: chat_off, or closed with 1008
/// chat_off.
const kNdChatOff = 2;

/// The most text a message may have (PROTOCOL.md section 6).
const kNdChatMaxText = 4096;

/// The most files of one message, and the largest file.
const kNdChatMaxFiles = 10;
const kNdChatMaxFileBytes = 50 * 1024 * 1024;

/// One chat socket of the computer. [frames] carries the server's text
/// frames and ends when the socket is gone; then [closeStatus] says why:
/// 0 when it dropped or nobody answered, the HTTP status of a refused
/// upgrade (401, 403, 404, 429, 500), or [kNdChatNoToken].
abstract class NdChatSocket {
  Stream<String> get frames;
  int get closeStatus;

  /// The server's Retry-After with [kNdChatOff], when it sent one.
  Duration? get retryAfter;
  void send(String frame);
  void close();
}

typedef NdChatConnect = NdChatSocket Function();

/// The answer of an upload: the HTTP status and, on success, the file id.
class NdChatUpload {
  const NdChatUpload(this.status, this.fileId);
  final int status;
  final String? fileId;
}

/// The file routes of a computer (PROTOCOL.md section 8).
abstract class NdChatFiles {
  Future<NdChatUpload> upload(String path);

  /// Saves the file to [toPath] and answers the HTTP status.
  Future<int> download(String id,
      {required bool inline, required String toPath});
}

class NdChatLocalFile {
  const NdChatLocalFile(this.path, this.size);
  final String path;
  final int size;
}

enum NdChatAvailability {
  /// No answer yet.
  unknown,

  /// The server took the socket at least once.
  available,

  /// 401 or 403: the token is refused, or the server's API port has no
  /// chat (an older server answers 401). Asked again later.
  refused,

  /// 404, or no device token: this server has no chat for computers.
  off,
}

enum NdChatSendState { sending, failed }

enum NdChatFileProblem { tooMany, tooBig, storageFull, uploadFailed }

class NdChatParty {
  const NdChatParty(this.kind, this.id, this.name);
  final String kind;
  final String id;
  final String name;

  bool get isStaff => kind == 'user';

  static NdChatParty of(Object? v) {
    final m = v is Map ? v : const {};
    return NdChatParty(_str(m['kind']), _str(m['id']), _str(m['name']));
  }
}

class NdChatReply {
  const NdChatReply(this.id, this.fromName, this.preview, this.deleted);
  final String id;
  final String fromName;
  final String preview;
  final bool deleted;
}

class NdChatFile {
  const NdChatFile(
      this.id, this.name, this.type, this.size, this.width, this.height);
  final String id;
  final String name;
  final String type;
  final int size;
  final int? width;
  final int? height;

  bool get isPicture => width != null && height != null;
}

class NdChatMessage {
  NdChatMessage({
    required this.id,
    required this.from,
    required this.text,
    required this.replyTo,
    required this.files,
    required this.createdAt,
    required this.edited,
    required this.deleted,
    required this.reactions,
    required this.clientId,
  });

  final String id;
  final NdChatParty from;
  final String text;
  final NdChatReply? replyTo;
  final List<NdChatFile> files;

  /// Milliseconds since 1970 (UTC), as the server keeps them.
  final int createdAt;
  final bool edited;
  final bool deleted;
  final Map<String, List<NdChatParty>> reactions;
  final String clientId;

  static NdChatMessage? of(Object? v) {
    if (v is! Map) return null;
    final id = _str(v['id']);
    if (id.isEmpty) return null;
    final reply = v['reply_to'];
    final reactions = <String, List<NdChatParty>>{};
    final r = v['reactions'];
    if (r is Map) {
      r.forEach((emoji, who) {
        if (who is List && who.isNotEmpty) {
          reactions['$emoji'] = who.map(NdChatParty.of).toList();
        }
      });
    }
    final files = <NdChatFile>[];
    final a = v['attachments'];
    if (a is List) {
      for (final f in a.whereType<Map>()) {
        files.add(NdChatFile(_str(f['id']), _str(f['name']), _str(f['type']),
            _int(f['size']) ?? 0, _int(f['width']), _int(f['height'])));
      }
    }
    final deleted = v['deleted'] == true;
    return NdChatMessage(
      id: id,
      from: NdChatParty.of(v['from']),
      text: deleted ? '' : _str(v['text']),
      replyTo: reply is Map
          ? NdChatReply(_str(reply['id']), _str(reply['from_name']),
              _str(reply['preview']), reply['deleted'] == true)
          : null,
      files: deleted ? const [] : files,
      createdAt: _int(v['created_at']) ?? 0,
      edited: v['edited_at'] != null,
      deleted: deleted,
      reactions: reactions,
      clientId: _str(v['client_id']),
    );
  }
}

/// A message of the person that the server hasn't confirmed yet.
class NdChatPending {
  NdChatPending(this.clientId, this.text, this.replyTo, this.paths);
  final String clientId;
  final String text;
  final String? replyTo;

  /// The files to upload; [fileIds] holds their ids once uploaded.
  final List<String> paths;
  List<String>? fileIds;
  NdChatSendState state = NdChatSendState.sending;

  /// Why sending failed, when it was a file.
  NdChatFileProblem? problem;

  /// Sent on this socket (null: not sent on the socket that is open now).
  Object? sentOn;
}

String _str(Object? v) => v == null ? '' : '$v';

int? _int(Object? v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Orders message ids: they are decimal numbers in strings, a higher one is
/// newer.
int compareChatIds(String a, String b) {
  final na = BigInt.tryParse(a);
  final nb = BigInt.tryParse(b);
  if (na != null && nb != null) return na.compareTo(nb);
  if (a.length != b.length) return a.length.compareTo(b.length);
  return a.compareTo(b);
}

class NdChatModel extends ChangeNotifier {
  NdChatModel({
    required this.connect,
    this.files,
    this.notify,
    Random? random,
    DateTime Function()? now,
  })  : _random = random ?? Random(),
        _now = now ?? DateTime.now;

  final NdChatConnect connect;
  final NdChatFiles? files;

  /// Shows an OS notification with a title and a body.
  final void Function(String title, String body)? notify;
  final Random _random;
  final DateTime Function() _now;

  static const _typingShown = Duration(seconds: 4);
  static const _typingEvery = Duration(milliseconds: 2500);
  static const _noChatRecheck = Duration(minutes: 10);
  static const _noTokenRecheck = Duration(minutes: 2);
  static const _chatOffRecheck = Duration(seconds: 600);
  static const _tooManyWait = Duration(seconds: 30);

  /// After 401 or 403 the service holds the refusal and asks the server
  /// again only after a long wait, with a new token or after it starts
  /// again (src/nd_chat.rs), so asking the service often costs nothing.
  static const _refusedRecheck = Duration(minutes: 1);
  static const _backoffMax = Duration(seconds: 30);
  static const _catchUpPage = 100;
  static const _olderPage = 50;
  static const _notifyChars = 120;
  static const _editFor = Duration(hours: 24);

  NdChatSocket? _socket;
  StreamSubscription<String>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _disposed = false;

  bool connected = false;
  NdChatAvailability availability = NdChatAvailability.unknown;
  String deviceId = '';

  /// Server time minus local time, in milliseconds.
  int _skew = 0;

  final _byId = <String, NdChatMessage>{};
  List<NdChatMessage>? _sorted;

  /// Older messages than the oldest one here exist on the server.
  bool olderExist = false;

  /// The `before` of the history page asked for, null when none is due.
  String? _asked;
  bool _askedForCatchUp = false;

  /// After welcome, until the history has everything since the drop.
  bool _catchingUp = false;

  /// The newest message the window had when the socket closed.
  String? _newestBefore;

  /// Read marks by "kind:id".
  final _reads = <String, String>{};

  String? helperName;
  bool helperClosed = false;
  bool helperKnown = false;

  String? typingName;
  Timer? _typingTimer;

  /// Runs for 2.5 s after the person's typing frame.
  Timer? _typingQuiet;

  final pending = <NdChatPending>[];
  int _clientSeq = 0;
  late final String _clientPrefix =
      'c-${_random.nextInt(1 << 32).toRadixString(36)}';

  /// Messages the server answered too_late (no more edits) or not_yours
  /// (no edit, no delete) for.
  final _tooLate = <String>{};
  final _notMine = <String>{};

  /// The open socket's first frame was not a welcome of version 2: the
  /// server has no chat for computers.
  bool _noChatServer = false;

  bool _front = false;
  bool _atNewest = true;

  /// A tray holds the chat and notifies (src/tray_chat.rs): the window
  /// shows no notifications of its own.
  bool othersNotify = false;

  /// Hears when the window's chat comes in front or goes.
  void Function(bool front)? onFront;
  String? _readSentFor;

  List<NdChatMessage> get messages => _sorted ??=
      (_byId.values.toList()..sort((a, b) => compareChatIds(a.id, b.id)));

  NdChatMessage? byId(String id) => _byId[id];

  /// The window offers the chat: the server took the socket at least once
  /// and hasn't refused it since.
  bool get showEntry => availability == NdChatAvailability.available;

  bool isOwn(NdChatMessage m) =>
      m.from.kind == 'device' && (deviceId.isEmpty || m.from.id == deviceId);

  String get _ownReader => 'device:$deviceId';

  String? get _ownRead => _reads[_ownReader];

  /// Staff messages after the computer's read mark.
  int get unread {
    final mark = _ownRead;
    return messages
        .where((m) =>
            m.from.isStaff &&
            !m.deleted &&
            (mark == null || compareChatIds(m.id, mark) > 0))
        .length;
  }

  /// The id of the person's newest message once staff read it, for "Seen".
  String? get seenId {
    final own = messages.lastWhere(isOwn, orElse: () => _none);
    if (identical(own, _none)) return null;
    for (final e in _reads.entries) {
      if (e.key.startsWith('user:') && compareChatIds(e.value, own.id) >= 0) {
        return own.id;
      }
    }
    return null;
  }

  static final _none = NdChatMessage(
      id: '',
      from: const NdChatParty('', '', ''),
      text: '',
      replyTo: null,
      files: const [],
      createdAt: 0,
      edited: false,
      deleted: false,
      reactions: const {},
      clientId: '');

  DateTime get serverNow => _now().add(Duration(milliseconds: _skew));

  /// A time of the server on this computer's clock, for showing.
  DateTime localTime(int serverMillis) =>
      DateTime.fromMillisecondsSinceEpoch(serverMillis - _skew);

  DateTime get localNow => _now();

  bool canEdit(NdChatMessage m) =>
      isOwn(m) &&
      !m.deleted &&
      !_tooLate.contains(m.id) &&
      !_notMine.contains(m.id) &&
      serverNow.millisecondsSinceEpoch - m.createdAt <
          _editFor.inMilliseconds;

  bool canDelete(NdChatMessage m) =>
      isOwn(m) && !m.deleted && !_notMine.contains(m.id);

  bool reactedByMe(NdChatMessage m, String emoji) =>
      (m.reactions[emoji] ?? const []).any((p) =>
          p.kind == 'device' && (deviceId.isEmpty || p.id == deviceId));

  // ---------------------------------------------------------------- socket

  void start() {
    if (_socket != null || _disposed) return;
    _open();
  }

  void _open() {
    _retry?.cancel();
    _retry = null;
    final socket = connect();
    _socket = socket;
    _sub = socket.frames.listen(
      (text) => _onFrame(socket, text),
      onDone: () => _onClosed(socket),
    );
  }

  void _onClosed(NdChatSocket socket) {
    if (!identical(socket, _socket) || _disposed) return;
    _sub = null;
    _socket = null;
    final wasConnected = connected;
    connected = false;
    _catchingUp = false;
    _asked = null;
    if (wasConnected || _newestBefore == null) {
      final list = messages;
      _newestBefore = list.isEmpty ? null : list.last.id;
    }
    _setTyping(null);
    final status = _noChatServer ? 404 : socket.closeStatus;
    _noChatServer = false;
    Duration wait;
    switch (status) {
      case 401:
      case 403:
        availability = NdChatAvailability.refused;
        wait = _refusedRecheck;
        break;
      case 404:
        availability = NdChatAvailability.off;
        wait = _noChatRecheck;
        break;
      case kNdChatNoToken:
        availability = NdChatAvailability.off;
        wait = _noTokenRecheck;
        break;
      case kNdChatOff:
        availability = NdChatAvailability.off;
        wait = socket.retryAfter ?? _chatOffRecheck;
        break;
      case 429:
        final b = _backoff();
        wait = b < _tooManyWait ? _tooManyWait + b : b;
        break;
      default:
        wait = _backoff();
    }
    _retry = Timer(wait, _open);
    notifyListeners();
  }

  /// 1 s doubling to 30 s, each with up to a fifth more or less.
  Duration _backoff() {
    final base = min(1000 * pow(2, _attempt).toInt(),
        _backoffMax.inMilliseconds);
    _attempt = min(_attempt + 1, 10);
    final spread = 0.8 + _random.nextDouble() * 0.4;
    return Duration(
        milliseconds: min((base * spread).round(), _backoffMax.inMilliseconds));
  }

  void _send(Map<String, Object?> frame) {
    final s = _socket;
    if (s == null || !connected) return;
    s.send(jsonEncode(frame));
  }

  void _onFrame(NdChatSocket socket, String text) {
    if (!identical(socket, _socket) || _noChatServer) return;
    Object? v;
    try {
      v = jsonDecode(text);
    } catch (_) {
      v = null;
    }
    if (!connected && !(v is Map && v['type'] == 'welcome' && v['v'] == 2)) {
      // An older server ignores v=2 and speaks version 1.
      _noChatServer = true;
      socket.close();
      return;
    }
    if (v is! Map) return;
    switch (v['type']) {
      case 'welcome':
        _onWelcome(v);
        break;
      case 'history':
        _onHistory(v);
        break;
      case 'message.new':
        _onNew(v['message']);
        break;
      case 'message.updated':
        _onUpdated(v['message']);
        break;
      case 'read':
        _noteRead(v['reader'], v['up_to']);
        _maybeRead();
        break;
      case 'typing':
        final from = NdChatParty.of(v['from']);
        if (from.isStaff) _setTyping(from.name);
        break;
      case 'helper':
        helperKnown = true;
        final name = v['name'];
        helperName = name is String && name.trim().isNotEmpty ? name : null;
        helperClosed = v['state'] == 'closed';
        break;
      case 'error':
        _onError(v);
        break;
      default:
        return;
    }
    notifyListeners();
  }

  void _onWelcome(Map v) {
    connected = true;
    availability = NdChatAvailability.available;
    _attempt = 0;
    final id = _str(v['device_id']);
    if (id.isNotEmpty) deviceId = id;
    final serverTime = _int(v['server_time']);
    if (serverTime != null) {
      _skew = serverTime - _now().millisecondsSinceEpoch;
    }
    _catchingUp = true;
    _readSentFor = null;
    for (final p in pending) {
      p.sentOn = null;
    }
  }

  void _onHistory(Map v) {
    final before = _str(v['before']);
    final more = v['more'] == true;
    final list = v['messages'];
    final got = <NdChatMessage>[];
    if (list is List) {
      for (final m in list) {
        final msg = NdChatMessage.of(m);
        if (msg != null) got.add(msg);
      }
    }
    final reads = v['reads'];
    if (reads is List) {
      for (final r in reads.whereType<Map>()) {
        _noteRead(r['reader'], r['up_to']);
      }
    }
    final oldestHad = messages.isEmpty ? null : messages.first.id;
    for (final m in got) {
      _put(m);
    }
    got.sort((a, b) => compareChatIds(a.id, b.id));
    final pageOldest = got.isEmpty ? null : got.first.id;

    if (before == '0' || before.isEmpty) {
      // The newest page: the second frame of every socket.
      if (oldestHad == null ||
          (pageOldest != null && compareChatIds(pageOldest, oldestHad) <= 0)) {
        olderExist = more;
      }
      if (_catchingUp) _catchUp(more, pageOldest);
    } else {
      final forCatchUp = _askedForCatchUp && before == _asked;
      if (before == _asked) _asked = null;
      if (forCatchUp) {
        _catchUp(more, pageOldest);
      } else if (oldestHad == null || compareChatIds(before, oldestHad) <= 0) {
        olderExist = more;
      }
    }
  }

  /// Pages back until the newest message from before the drop is here,
  /// then sends what never came back and the read mark.
  void _catchUp(bool more, String? pageOldest) {
    final had = _newestBefore;
    final reached = had == null ||
        pageOldest == null ||
        compareChatIds(pageOldest, had) <= 0;
    if (!reached && more) {
      _asked = pageOldest;
      _askedForCatchUp = true;
      _send({'type': 'history', 'before': pageOldest, 'limit': _catchUpPage});
      return;
    }
    _catchingUp = false;
    _askedForCatchUp = false;
    _newestBefore = null;
    _resendLost();
    _maybeRead();
  }

  /// Messages sent before the socket closed without an answer: done when
  /// the history has their client_id (the server doesn't drop a repeated
  /// one), else sent again.
  void _resendLost() {
    final stored = {
      for (final m in _byId.values)
        if (isOwn(m) && m.clientId.isNotEmpty) m.clientId
    };
    pending.removeWhere((p) => stored.contains(p.clientId));
    for (final p in pending.toList()) {
      if (p.state == NdChatSendState.sending && p.sentOn == null) {
        _deliver(p);
      }
    }
  }

  void _put(NdChatMessage m) {
    _byId[m.id] = m;
    _sorted = null;
  }

  void _onNew(Object? raw) {
    final m = NdChatMessage.of(raw);
    if (m == null) return;
    final known = _byId.containsKey(m.id);
    _put(m);
    if (isOwn(m) && m.clientId.isNotEmpty) {
      pending.removeWhere((p) => p.clientId == m.clientId);
    }
    // The person's message opens a closed conversation again (PROTOCOL.md,
    // the helper frame).
    if (isOwn(m)) helperClosed = false;
    if (m.from.isStaff) {
      if (typingName == m.from.name) _setTyping(null);
      if (!known && !_front) _notifyOf(m);
    }
    _maybeRead();
  }

  void _notifyOf(NdChatMessage m) {
    final n = notify;
    if (n == null || othersNotify) return;
    var body = m.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (body.isEmpty && m.files.isNotEmpty) {
      body = m.files.map((f) => f.name).join(', ');
    }
    if (body.length > _notifyChars) {
      body = '${body.substring(0, _notifyChars - 1)}…';
    }
    n(m.from.name, body);
  }

  void _onUpdated(Object? raw) {
    final m = NdChatMessage.of(raw);
    if (m == null) return;
    final list = messages;
    if (_byId.containsKey(m.id) ||
        list.isEmpty ||
        compareChatIds(m.id, list.first.id) > 0) {
      _put(m);
    }
  }

  void _noteRead(Object? reader, Object? upTo) {
    final who = NdChatParty.of(reader);
    final to = _str(upTo);
    if (who.kind.isEmpty || to.isEmpty || to == '0') return;
    final key = '${who.kind}:${who.id}';
    final had = _reads[key];
    if (had == null || compareChatIds(to, had) > 0) _reads[key] = to;
  }

  void _onError(Map v) {
    final code = _str(v['code']);
    final clientId = _str(v['client_id']);
    if (clientId.isNotEmpty) {
      for (final p in pending) {
        if (p.clientId == clientId) {
          p.state = NdChatSendState.failed;
          p.sentOn = null;
          if (code == 'bad_attachment') p.fileIds = null;
        }
      }
      return;
    }
    final messageId = _str(v['message_id']);
    if (messageId.isEmpty) return;
    if (code == 'too_late') _tooLate.add(messageId);
    if (code == 'not_yours') _notMine.add(messageId);
  }

  void _setTyping(String? name) {
    _typingTimer?.cancel();
    _typingTimer = null;
    typingName = name;
    if (name != null) {
      _typingTimer = Timer(_typingShown, () {
        typingName = null;
        if (!_disposed) notifyListeners();
      });
    }
  }

  // ---------------------------------------------------------------- reading

  /// The window is in front and focused.
  void setFront(bool front) {
    if (_front == front) return;
    _front = front;
    onFront?.call(front);
    _maybeRead();
  }

  /// The window shows the newest message.
  void setAtNewest(bool atNewest) {
    if (_atNewest == atNewest) return;
    _atNewest = atNewest;
    _maybeRead();
  }

  void _maybeRead() {
    if (!_front || !_atNewest || !connected || _catchingUp) return;
    final list = messages;
    if (list.isEmpty) return;
    final newest = list.last.id;
    final mark = _ownRead;
    if (mark != null && compareChatIds(mark, newest) >= 0) return;
    if (_readSentFor == newest) return;
    _readSentFor = newest;
    _send({'type': 'read'});
  }

  // ---------------------------------------------------------------- writing

  /// [text] cut to [kNdChatMaxText] characters; a frame with that much
  /// text always fits in a frame of version 2.
  static String _fit(String text) {
    if (text.runes.length <= kNdChatMaxText) return text;
    return String.fromCharCodes(text.runes.take(kNdChatMaxText));
  }

  NdChatFileProblem? checkFiles(List<NdChatLocalFile> chosen) {
    if (chosen.length > kNdChatMaxFiles) return NdChatFileProblem.tooMany;
    if (chosen.any((f) => f.size > kNdChatMaxFileBytes)) {
      return NdChatFileProblem.tooBig;
    }
    return null;
  }

  /// Sends a message of the person: the text trimmed at the end, the files
  /// of [paths] uploaded first.
  void sendMessage(String text,
      {String? replyTo, List<String> paths = const []}) {
    final trimmed = text.trimRight();
    if (trimmed.trim().isEmpty && paths.isEmpty) return;
    _clientSeq++;
    final p = NdChatPending('$_clientPrefix-$_clientSeq', trimmed, replyTo,
        List.unmodifiable(paths));
    pending.add(p);
    _deliver(p);
    notifyListeners();
  }

  /// Sends a message that failed again.
  void retry(String clientId) {
    for (final p in pending) {
      if (p.clientId == clientId && p.state == NdChatSendState.failed) {
        p.state = NdChatSendState.sending;
        p.problem = null;
        _deliver(p);
      }
    }
    notifyListeners();
  }

  /// Takes a message that failed out of the window.
  void discard(String clientId) {
    pending.removeWhere(
        (p) => p.clientId == clientId && p.state == NdChatSendState.failed);
    notifyListeners();
  }

  Future<void> _deliver(NdChatPending p) async {
    if (p.paths.isNotEmpty && p.fileIds == null) {
      final f = files;
      if (f == null) {
        _fail(p, NdChatFileProblem.uploadFailed);
        return;
      }
      final ids = <String>[];
      for (final path in p.paths) {
        NdChatUpload up;
        try {
          up = await f.upload(path);
        } catch (_) {
          up = const NdChatUpload(0, null);
        }
        if (up.status != 200 || up.fileId == null) {
          _fail(
              p,
              up.status == 507
                  ? NdChatFileProblem.storageFull
                  : up.status == 413
                      ? NdChatFileProblem.tooBig
                      : NdChatFileProblem.uploadFailed);
          return;
        }
        ids.add(up.fileId!);
      }
      p.fileIds = ids;
    }
    if (!pending.contains(p) || p.state != NdChatSendState.sending) return;
    if (_socket == null || !connected || _catchingUp) return;
    final text = _fit(p.text);
    _send(_sendFrame(p, text));
    p.sentOn = _socket;
  }

  Map<String, Object?> _sendFrame(NdChatPending p, String text) => {
        'type': 'send',
        'text': text,
        if (p.replyTo != null) 'reply_to': p.replyTo,
        if ((p.fileIds ?? const []).isNotEmpty) 'attachments': p.fileIds,
        'client_id': p.clientId,
      };

  void _fail(NdChatPending p, NdChatFileProblem problem) {
    p.state = NdChatSendState.failed;
    p.problem = problem;
    if (!_disposed) notifyListeners();
  }

  void edit(String id, String text) {
    final t = text.trimRight();
    if (t.trim().isEmpty) return;
    _send({'type': 'edit', 'message_id': id, 'text': _fit(t)});
  }

  void delete(String id) => _send({'type': 'delete', 'message_id': id});

  void react(String id, String emoji) {
    final m = _byId[id];
    if (m == null || m.deleted) return;
    _send({
      'type': 'react',
      'message_id': id,
      'emoji': emoji,
      'on': !reactedByMe(m, emoji),
    });
  }

  /// The person typed: a typing frame at most every 2.5 s.
  void typed() {
    if (_typingQuiet != null || !connected) return;
    _typingQuiet = Timer(_typingEvery, () => _typingQuiet = null);
    _send({'type': 'typing'});
  }

  void loadOlder() {
    if (!olderExist || _asked != null || !connected || _catchingUp) return;
    final list = messages;
    if (list.isEmpty) return;
    _asked = list.first.id;
    _askedForCatchUp = false;
    _send({'type': 'history', 'before': _asked, 'limit': _olderPage});
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _typingTimer?.cancel();
    _typingQuiet?.cancel();
    _sub?.cancel();
    final s = _socket;
    _socket = null;
    s?.close();
    super.dispose();
  }
}
