// Fakes and frames for the chat tests: a socket the test answers as the
// server would, the file routes, and the frames of PROTOCOL.md.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_hbb/models/nd_chat_model.dart';

class FakeSocket implements NdChatSocket {
  final _frames = StreamController<String>();
  final sent = <Map<String, dynamic>>[];
  var _status = 0;
  Duration? _retryAfter;
  var closedByClient = false;

  @override
  Stream<String> get frames => _frames.stream;

  @override
  int get closeStatus => _status;

  @override
  Duration? get retryAfter => _retryAfter;

  @override
  void send(String frame) => sent.add(jsonDecode(frame) as Map<String, dynamic>);

  @override
  void close() {
    closedByClient = true;
    if (!_frames.isClosed) _frames.close();
  }

  void serve(Map<String, dynamic> frame) => _frames.add(jsonEncode(frame));
  void raw(String text) => _frames.add(text);

  void drop([int status = 0, Duration? retryAfter]) {
    _status = status;
    _retryAfter = retryAfter;
    _frames.close();
  }

  List<Map<String, dynamic>> of(String type) =>
      sent.where((f) => f['type'] == type).toList();
}

class Server {
  final sockets = <FakeSocket>[];
  FakeSocket get last => sockets.last;
  NdChatSocket connect() {
    final s = FakeSocket();
    sockets.add(s);
    return s;
  }
}

const device = '900100001';
final t0 = DateTime.utc(2026, 11, 25, 9, 0);

Map<String, dynamic> anna = {'kind': 'user', 'id': '7', 'name': 'Anna Weber'};
Map<String, dynamic> me = {'kind': 'device', 'id': device, 'name': 'reception-01'};

Map<String, dynamic> msg(int id,
    {Map<String, dynamic>? from,
    String? text,
    String clientId = '',
    bool deleted = false,
    int? createdAt,
    Map<String, dynamic>? reactions,
    Object? editedAt}) {
  return {
    'id': '$id',
    'conversation_id': device,
    'from': from ?? anna,
    'text': deleted ? '' : (text ?? 'message $id'),
    'reply_to': null,
    'attachments': [],
    'created_at': createdAt ?? t0.millisecondsSinceEpoch + id * 1000,
    'edited_at': editedAt,
    'deleted': deleted,
    'reactions': reactions ?? {},
    'client_id': clientId,
  };
}

Map<String, dynamic> welcome() => {
      'type': 'welcome',
      'v': 2,
      'server_time': t0.millisecondsSinceEpoch,
      'capabilities': ['v2'],
      'device_id': device,
      'name': 'reception-01',
    };

Map<String, dynamic> history(List<int> ids,
        {bool more = false,
        String before = '0',
        List<Map<String, dynamic>> reads = const [],
        Map<String, dynamic> Function(int id)? make}) =>
    {
      'type': 'history',
      'conversation_id': device,
      'before': before,
      'more': more,
      'messages': [for (final i in ids) (make ?? msg)(i)],
      'reads': reads,
    };

Map<String, dynamic> readOf(Map<String, dynamic> who, int upTo) => {
      'reader': {'kind': who['kind'], 'id': who['id']},
      'up_to': '$upTo',
    };

List<int> range(int from, int to) => [for (var i = from; i <= to; i++) i];

class FakeFiles implements NdChatFiles {
  final uploaded = <String>[];
  int? failWith;

  @override
  Future<NdChatUpload> upload(String path) async {
    if (failWith != null) return NdChatUpload(failWith!, null);
    uploaded.add(path);
    return NdChatUpload(200, 'id-$path');
  }

  @override
  Future<int> download(String id, {required bool inline, required String toPath}) async => 200;
}
