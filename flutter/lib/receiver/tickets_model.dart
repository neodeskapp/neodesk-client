// My tickets of the receiver: the tickets the person opened from this
// computer, with the public answers of the support team (the console's
// device routes under /api/tickets/nd, server PR #82). The requests go
// through the process that keeps the device token (src/nd_tickets.rs), so
// the model gets them as a ReceiverBackend and the tests give it a fake.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The computer's ticket routes.
const kNdTicketsPath = '/api/tickets/nd';

/// The most files a ticket takes, and the most bytes of the picture and
/// the files together (the server's limits).
const kNdTicketMaxFiles = 10;
const kNdTicketMaxBytes = 25 * 1024 * 1024;

/// [NdTicketAnswer.status] when this computer holds no device token: it
/// isn't enrolled yet (src/nd_chat.rs NO_TOKEN).
const kNdTicketsNoToken = 1;

/// The answer of one request: the HTTP status (0 when nobody answered) and
/// the body as text.
class NdTicketAnswer {
  const NdTicketAnswer(this.status, this.body);
  final int status;
  final String body;

  bool get ok => status >= 200 && status < 300;

  Map<String, dynamic>? get json {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}

/// A file on this computer the person adds.
class NdTicketLocalFile {
  const NdTicketLocalFile(this.path, this.size);
  final String path;
  final int size;

  String get name => path.split(RegExp(r'[\\/]')).last;
}

/// What the receiver's window needs from the process with the device token
/// and from the system.
abstract class ReceiverBackend {
  /// Sends [method] to [path] (under [kNdTicketsPath]) with a JSON [body].
  Future<NdTicketAnswer> request(String method, String path,
      [Map<String, Object?>? body]);

  /// Saves the file at [path] to [to]; answers the HTTP status.
  Future<int> download(String path, String to);

  /// The signed-in person's name and the system, which go with a ticket:
  /// {"reporter", "os"}.
  Future<Map<String, String>> about();

  /// Shows a system notification; a click opens [link] ("chat",
  /// "tickets/<id>").
  void notify(String title, String body, String link);
}

/// A ticket in the list.
@immutable
class NdTicket {
  const NdTicket({
    required this.id,
    required this.title,
    required this.status,
    this.description = '',
    this.createdAt,
    this.updatedAt,
    this.lastReplyAt,
    this.unread = false,
    this.replies = 0,
    this.reporter,
  });

  final int id;
  final String title;

  /// open, in_progress, resolved or closed.
  final String status;
  final String description;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastReplyAt;

  /// Staff wrote something the person hasn't read.
  final bool unread;
  final int replies;
  final String? reporter;

  static NdTicket? of(Object? v) {
    if (v is! Map) return null;
    final id = _int(v['id']);
    if (id == null) return null;
    return NdTicket(
      id: id,
      title: _str(v['title']),
      status: _str(v['status']).isEmpty ? 'open' : _str(v['status']),
      description: _str(v['description']),
      createdAt: ndTicketTime(v['created_at']),
      updatedAt: ndTicketTime(v['updated_at']),
      lastReplyAt: ndTicketTime(v['last_reply_at']),
      unread: v['unread'] == true,
      replies: _int(v['replies']) ?? 0,
      reporter: v['reporter'] is String ? v['reporter'] as String : null,
    );
  }

  NdTicket copyWith({bool? unread, String? status}) => NdTicket(
        id: id,
        title: title,
        status: status ?? this.status,
        description: description,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastReplyAt: lastReplyAt,
        unread: unread ?? this.unread,
        replies: replies,
        reporter: reporter,
      );
}

/// A public comment of a ticket.
@immutable
class NdTicketComment {
  const NdTicketComment({
    required this.id,
    required this.authorName,
    required this.fromStaff,
    required this.body,
    this.createdAt,
  });

  final int id;
  final String authorName;
  final bool fromStaff;
  final String body;
  final DateTime? createdAt;

  static NdTicketComment? of(Object? v) {
    if (v is! Map) return null;
    final id = _int(v['id']);
    if (id == null) return null;
    return NdTicketComment(
      id: id,
      authorName: _str(v['author_name']),
      fromStaff: v['from'] != 'device',
      body: _str(v['body']),
      createdAt: ndTicketTime(v['created_at']),
    );
  }
}

/// A file of a ticket.
@immutable
class NdTicketFile {
  const NdTicketFile(
      {required this.id,
      required this.name,
      this.type = '',
      this.size = 0,
      this.commentId});

  final int id;
  final String name;
  final String type;
  final int size;
  final int? commentId;

  static NdTicketFile? of(Object? v) {
    if (v is! Map) return null;
    final id = _int(v['id']);
    if (id == null) return null;
    return NdTicketFile(
      id: id,
      name: _str(v['name']),
      type: _str(v['type']),
      size: _int(v['size']) ?? 0,
      commentId: _int(v['comment_id']),
    );
  }
}

/// One ticket opened: the ticket, its public comments and its files.
class NdTicketDetail {
  NdTicketDetail(this.ticket, this.comments, this.files);
  final NdTicket ticket;
  final List<NdTicketComment> comments;
  final List<NdTicketFile> files;
}

/// Where the list stands.
enum NdTicketsState { loading, ready, failed, unavailable }

/// Why a new ticket or a reply can't go.
enum NdTicketProblem { tooMany, tooBig, failed }

String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// A time of the console: "2026-11-27 10:00:00" (UTC, as SQLite writes
/// it) or ISO 8601.
DateTime? ndTicketTime(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  var s = v.trim().replaceFirst(' ', 'T');
  final zoned = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(s);
  if (!zoned) s = '${s}Z';
  return DateTime.tryParse(s)?.toLocal();
}

/// The MIME type the console stores for a file of [name].
String ndTicketFileType(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return const {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'bmp': 'image/bmp',
        'pdf': 'application/pdf',
        'txt': 'text/plain',
        'log': 'text/plain',
        'csv': 'text/csv',
        'json': 'application/json',
        'xml': 'application/xml',
        'zip': 'application/zip',
        'doc': 'application/msword',
        'docx':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      }[ext] ??
      'application/octet-stream';
}

class NdTicketsModel extends ChangeNotifier {
  NdTicketsModel({
    required this.backend,
    this.noteTitle = 'nd-rcv-note-ticket',
    this.noteBody = 'nd-rcv-note-ticket-body',
    Future<List<int>> Function(String path)? readFile,
  }) : _readFile = readFile ?? ((p) => File(p).readAsBytes());

  final ReceiverBackend backend;

  /// The notification's words for news about a ticket.
  final String noteTitle;
  final String noteBody;
  final Future<List<int>> Function(String path) _readFile;

  NdTicketsState state = NdTicketsState.loading;
  List<NdTicket> tickets = const [];

  /// The ticket the person has open, with its conversation.
  NdTicketDetail? open;
  int? openId;
  bool openLoading = false;

  /// A tray holds the chat socket and notifies (src/tray_chat.rs): the
  /// window shows no notifications of its own.
  bool othersNotify = false;

  /// The tickets with something unread, for the home window.
  int get unread => tickets.where((t) => t.unread).length;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Loads the list.
  Future<void> load() async {
    final a = await backend.request('GET', kNdTicketsPath);
    if (a.ok) {
      final list = a.json?['tickets'];
      tickets = [
        if (list is List)
          for (final t in list)
            if (NdTicket.of(t) != null) NdTicket.of(t)!
      ]..sort((a, b) => b.id.compareTo(a.id));
      state = NdTicketsState.ready;
    } else if (a.status == kNdTicketsNoToken ||
        a.status == 401 ||
        a.status == 403 ||
        a.status == 404) {
      state = NdTicketsState.unavailable;
    } else if (state != NdTicketsState.ready) {
      state = NdTicketsState.failed;
    }
    _changed();
  }

  /// Opens ticket [id] with its conversation and marks it read.
  Future<void> openTicket(int id) async {
    openId = id;
    openLoading = open?.ticket.id != id;
    if (openLoading) open = null;
    _changed();
    await _loadOpen(id);
    if (openId != id || open == null) return;
    await backend.request('POST', '$kNdTicketsPath/$id/read', const {});
    tickets = [
      for (final t in tickets) t.id == id ? t.copyWith(unread: false) : t
    ];
    _changed();
  }

  Future<void> _loadOpen(int id) async {
    final a = await backend.request('GET', '$kNdTicketsPath/$id');
    if (openId != id) return;
    openLoading = false;
    final v = a.json;
    final ticket = a.ok ? NdTicket.of(v?['ticket']) : null;
    if (ticket != null) {
      final comments = v?['comments'];
      final files = v?['attachments'];
      open = NdTicketDetail(
        ticket,
        [
          if (comments is List)
            for (final c in comments)
              if (NdTicketComment.of(c) != null) NdTicketComment.of(c)!
        ],
        [
          if (files is List)
            for (final f in files)
              if (NdTicketFile.of(f) != null) NdTicketFile.of(f)!
        ],
      );
    }
    _changed();
  }

  /// Back to the list.
  void closeTicket() {
    openId = null;
    open = null;
    openLoading = false;
    _changed();
  }

  /// Whether [files] (and the picture) fit a ticket.
  NdTicketProblem? check(List<NdTicketLocalFile> files,
      [NdTicketLocalFile? picture]) {
    if (files.length > kNdTicketMaxFiles) return NdTicketProblem.tooMany;
    final total = files.fold<int>(picture?.size ?? 0, (sum, f) => sum + f.size);
    if (total > kNdTicketMaxBytes) return NdTicketProblem.tooBig;
    return null;
  }

  Future<Map<String, Object?>> _file(NdTicketLocalFile f) async => {
        'name': f.name,
        'type': ndTicketFileType(f.name),
        'data_b64': base64Encode(await _readFile(f.path)),
      };

  /// The body of a new ticket: what's wrong, the person and the system
  /// (reporter, os), the picture of the screen and the files, as
  /// POST /api/tickets/nd takes them. The computer's ID goes with the
  /// device token; its system details the server attaches itself.
  Future<Map<String, Object?>> createBody(String description,
      {NdTicketLocalFile? picture,
      List<NdTicketLocalFile> files = const []}) async {
    final about = await backend.about();
    // The server takes the title from the first line
    return {
      'description': description.trim(),
      if ((about['reporter'] ?? '').isNotEmpty) 'reporter': about['reporter'],
      if ((about['os'] ?? '').isNotEmpty) 'os': about['os'],
      if (picture != null) 'screenshot': await _file(picture),
      if (files.isNotEmpty) 'files': [for (final f in files) await _file(f)],
    };
  }

  /// Sends a new ticket; answers its id, null when it didn't go.
  Future<int?> create(String description,
      {NdTicketLocalFile? picture,
      List<NdTicketLocalFile> files = const []}) async {
    if (description.trim().isEmpty) return null;
    if (check(files, picture) != null) return null;
    Map<String, Object?> body;
    try {
      body = await createBody(description, picture: picture, files: files);
    } catch (_) {
      return null;
    }
    final a = await backend.request('POST', kNdTicketsPath, body);
    if (!a.ok) return null;
    final v = a.json;
    final id = _int(v?['ticket_id']) ?? NdTicket.of(v?['ticket'])?.id;
    await load();
    return id;
  }

  /// Sends the person's answer to the open ticket.
  Future<bool> reply(String text) async {
    final id = openId;
    final body = text.trim();
    if (id == null || body.isEmpty) return false;
    final a = await backend
        .request('POST', '$kNdTicketsPath/$id/comments', {'body': body});
    if (!a.ok) return false;
    await _loadOpen(id);
    return true;
  }

  /// Saves a file of the open ticket to [to].
  Future<bool> save(NdTicketFile f, String to) async {
    final id = openId;
    if (id == null) return false;
    final status =
        await backend.download('$kNdTicketsPath/$id/attachments/${f.id}', to);
    return status == 200;
  }

  /// A frame of the chat socket that the chat itself doesn't read. For
  /// ticket.updated (PROTOCOL.md) the list and the open ticket are fetched
  /// again; with something unread a notification opens that ticket, unless
  /// a tray tells of it or the person looks at it.
  Future<void> onFrame(Map<dynamic, dynamic> frame) async {
    if (frame['type'] != 'ticket.updated') return;
    final id = _int(frame['ticket_id']);
    if (id == null) return;
    final looking = openId == id;
    if (frame['unread'] == true && !othersNotify && !looking) {
      backend.notify(noteTitle, noteBody, 'tickets/$id');
    }
    await load();
    if (looking) await openTicket(id);
  }
}
