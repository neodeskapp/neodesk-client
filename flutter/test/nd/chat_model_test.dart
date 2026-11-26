// The computer's chat model against a fake socket: frames in and out,
// reconnect and catch-up, the resend rule, the unread count and the
// refused upgrades (the console's chat PROTOCOL.md, sections 1, 3 to 7, 9
// and 10).

import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_hbb/models/nd_chat_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_fakes.dart';

NdChatModel model(Server server,
    {List<(String, String)>? notes, DateTime Function()? now}) {
  final m = NdChatModel(
    connect: server.connect,
    notify: notes == null ? null : (title, body) => notes.add((title, body)),
    random: Random(1),
    now: now ?? () => t0,
  );
  m.start();
  return m;
}

/// Opens the model's socket and answers it as the server does.
void open(FakeAsync async, Server server,
    {List<int> ids = const [], bool more = false, List<Map<String, dynamic>> reads = const [],
    Map<String, dynamic> Function(int id)? make}) {
  server.last.serve(welcome());
  server.last.serve(history(ids, more: more, reads: reads, make: make));
  server.last.serve({'type': 'helper', 'name': null, 'state': 'open'});
  async.flushMicrotasks();
}

void main() {
  group('frames in', () {
    test('welcome, history and helper fill the window in order of id', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        async.flushMicrotasks();
        expect(server.sockets, hasLength(1));
        expect(m.connected, isFalse);
        server.last.serve(welcome());
        server.last.serve(history([3, 1, 2], more: true));
        server.last.serve({'type': 'helper', 'name': 'Anna Weber', 'state': 'open'});
        async.flushMicrotasks();
        expect(m.connected, isTrue);
        expect(m.availability, NdChatAvailability.available);
        expect(m.deviceId, device);
        expect(m.messages.map((e) => e.id), ['1', '2', '3']);
        expect(m.olderExist, isTrue);
        expect(m.helperName, 'Anna Weber');
        expect(m.helperClosed, isFalse);
        server.last.serve({'type': 'helper', 'name': 'Anna Weber', 'state': 'closed'});
        async.flushMicrotasks();
        expect(m.helperClosed, isTrue);
      });
    });

    test("helper carries the version of the helper's picture", () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server);
        expect(m.helperPicture, isNull);
        server.last.serve({'type': 'helper', 'name': 'Anna Weber', 'state': 'open', 'picture': 'a1b2'});
        async.flushMicrotasks();
        expect(m.helperPicture, 'a1b2');
        // An older server sends no picture; nobody has none
        server.last.serve({'type': 'helper', 'name': 'Anna Weber', 'state': 'open'});
        async.flushMicrotasks();
        expect(m.helperPicture, isNull);
        server.last.serve({'type': 'helper', 'name': null, 'state': 'open', 'picture': 'a1b2'});
        async.flushMicrotasks();
        expect(m.helperPicture, isNull);
        server.last.serve({'type': 'helper', 'name': 'Anna Weber', 'state': 'open', 'picture': 7});
        async.flushMicrotasks();
        expect(m.helperPicture, isNull);
      });
    });

    test('ids compare as numbers, not as text', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [9, 10, 100]);
        expect(m.messages.map((e) => e.id), ['9', '10', '100']);
      });
    });

    test('frames it does not know, broken JSON and unknown fields change nothing', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        server.last.raw('not json');
        server.last.raw('[1,2]');
        server.last.serve({'type': 'presence', 'user_id': 7, 'status': 'away'});
        server.last.serve({'type': 'something.later', 'x': 1});
        server.last.serve({
          'type': 'message.new',
          'message': {...msg(2), 'future_field': {'a': 1}},
          'also_new': true,
        });
        async.flushMicrotasks();
        expect(m.connected, isTrue);
        expect(m.messages.map((e) => e.id), ['1', '2']);
      });
    });

    test('message.updated replaces the message by id: edits, deletions, reactions', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1, 2]);
        server.last.serve({
          'type': 'message.updated',
          'message': msg(1, text: 'changed', editedAt: t0.millisecondsSinceEpoch),
        });
        server.last.serve({'type': 'message.updated', 'message': msg(2, deleted: true)});
        async.flushMicrotasks();
        expect(m.messages[0].text, 'changed');
        expect(m.messages[0].edited, isTrue);
        expect(m.messages[1].deleted, isTrue);
        expect(m.messages[1].text, '');
        server.last.serve({
          'type': 'message.updated',
          'message': msg(1, reactions: {
            '👍': [me, anna]
          }),
        });
        async.flushMicrotasks();
        expect(m.messages[0].reactions['👍'], hasLength(2));
        expect(m.reactedByMe(m.messages[0], '👍'), isTrue);
      });
    });

    test('typing shows the staff name for 4 s after the last frame', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server);
        server.last.serve({'type': 'typing', 'conversation_id': device, 'from': anna});
        async.flushMicrotasks();
        expect(m.typingName, 'Anna Weber');
        async.elapse(const Duration(seconds: 3));
        server.last.serve({'type': 'typing', 'conversation_id': device, 'from': anna});
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(m.typingName, 'Anna Weber');
        async.elapse(const Duration(milliseconds: 1100));
        expect(m.typingName, isNull);
      });
    });

    test('the computer\'s own typing frames do not show as typing', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server);
        server.last.serve({'type': 'typing', 'conversation_id': device, 'from': me});
        async.flushMicrotasks();
        expect(m.typingName, isNull);
      });
    });
  });

  group('frames out', () {
    test('send carries the text, a new client_id and the reply', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        m.sendMessage('The printer blinks orange  \n ', replyTo: '1');
        m.sendMessage('Second');
        async.flushMicrotasks();
        final sends = server.last.of('send');
        expect(sends, hasLength(2));
        expect(sends[0]['text'], 'The printer blinks orange');
        expect(sends[0]['reply_to'], '1');
        expect(sends[0].containsKey('conversation_id'), isFalse);
        expect(sends[0]['client_id'], isNotEmpty);
        expect(sends[1]['client_id'], isNot(sends[0]['client_id']));
        expect(sends[1].containsKey('reply_to'), isFalse);
        expect(m.pending.map((p) => p.state), [NdChatSendState.sending, NdChatSendState.sending]);
      });
    });

    test('nothing is sent for blank text without files', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server);
        m.sendMessage('   \n  ');
        async.flushMicrotasks();
        expect(server.last.of('send'), isEmpty);
        expect(m.pending, isEmpty);
      });
    });

    test('long text is cut to 4096 characters, multi-byte text too, and the frame fits in 32768 bytes', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        m.sendMessage('a' * 5000);
        m.sendMessage('ü"\n' * 3000);
        m.sendMessage('😀' * 5000);
        m.edit('1', '€' * 5000);
        async.flushMicrotasks();
        final frames = [...server.last.of('send'), ...server.last.of('edit')];
        expect(frames, hasLength(4));
        for (final f in frames) {
          expect((f['text'] as String).runes.length, 4096);
          expect(utf8.encode(jsonEncode(f)).length, lessThanOrEqualTo(32768));
        }
      });
    });

    test('message.new with the client_id ends sending; an error with it marks it not sent', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server);
        m.sendMessage('one');
        m.sendMessage('two');
        async.flushMicrotasks();
        final ids = server.last.of('send').map((f) => f['client_id']).toList();
        server.last.serve({
          'type': 'message.new',
          'message': msg(5, from: me, text: 'one', clientId: ids[0] as String),
        });
        server.last.serve({'type': 'error', 'code': 'failed', 'for': 'send', 'client_id': ids[1]});
        async.flushMicrotasks();
        expect(m.messages.map((e) => e.text), ['one']);
        expect(m.pending, hasLength(1));
        expect(m.pending.single.text, 'two');
        expect(m.pending.single.state, NdChatSendState.failed);
        m.retry(m.pending.single.clientId);
        async.flushMicrotasks();
        expect(server.last.of('send'), hasLength(3));
        expect(server.last.of('send').last['text'], 'two');
        expect(m.pending.single.state, NdChatSendState.sending);
      });
    });

    test('react adds a reaction the computer has not given and takes back one it has', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1, 2], make: (id) => msg(id, reactions: id == 2 ? {'👍': [me]} : {}));
        m.react('1', '👍');
        m.react('2', '👍');
        async.flushMicrotasks();
        final r = server.last.of('react');
        expect(r[0], {'type': 'react', 'message_id': '1', 'emoji': '👍', 'on': true});
        expect(r[1], {'type': 'react', 'message_id': '2', 'emoji': '👍', 'on': false});
      });
    });

    test('edit and delete only for the computer\'s own messages; edit only within 24 hours', () {
      fakeAsync((async) {
        final server = Server();
        var now = t0;
        final m = model(server, now: () => now);
        open(async, server, ids: [1, 2], make: (id) => msg(id, from: id == 1 ? me : anna));
        final own = m.messages[0];
        final staff = m.messages[1];
        expect(m.canEdit(own), isTrue);
        expect(m.canDelete(own), isTrue);
        expect(m.canEdit(staff), isFalse);
        expect(m.canDelete(staff), isFalse);
        m.edit('1', 'fixed');
        m.delete('1');
        async.flushMicrotasks();
        expect(server.last.of('edit').single, {'type': 'edit', 'message_id': '1', 'text': 'fixed'});
        expect(server.last.of('delete').single, {'type': 'delete', 'message_id': '1'});
        now = t0.add(const Duration(hours: 24, seconds: 2));
        expect(m.canEdit(own), isFalse);
        expect(m.canDelete(own), isTrue);
      });
    });

    test('a too_late answer hides edit for the message it names', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1, 2], make: (id) => msg(id, from: me));
        m.edit('1', 'late');
        m.edit('2', 'also late');
        async.flushMicrotasks();
        server.last.serve({'type': 'error', 'code': 'too_late', 'for': 'edit', 'message_id': '1'});
        async.flushMicrotasks();
        expect(m.canEdit(m.byId('1')!), isFalse);
        expect(m.canEdit(m.byId('2')!), isTrue);
      });
    });

    test('a not_yours answer hides edit and delete for the message it names', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1, 2], make: (id) => msg(id, from: me));
        m.delete('2');
        async.flushMicrotasks();
        server.last.serve({'type': 'error', 'code': 'not_yours', 'for': 'delete', 'message_id': '2'});
        async.flushMicrotasks();
        expect(m.canDelete(m.byId('2')!), isFalse);
        expect(m.canEdit(m.byId('2')!), isFalse);
        expect(m.canDelete(m.byId('1')!), isTrue);
      });
    });

    test('typing goes out at most every 2.5 s', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server);
        m.typed();
        async.elapse(const Duration(seconds: 1));
        m.typed();
        async.elapse(const Duration(seconds: 1));
        m.typed();
        expect(server.last.of('typing'), hasLength(1));
        async.elapse(const Duration(milliseconds: 600));
        m.typed();
        expect(server.last.of('typing'), hasLength(2));
        expect(server.last.of('typing').first, {'type': 'typing'});
      });
    });

    test('loading older messages asks before the oldest one', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: range(51, 100), more: true);
        m.loadOlder();
        m.loadOlder();
        async.flushMicrotasks();
        expect(server.last.of('history'), [
          {'type': 'history', 'before': '51', 'limit': 50}
        ]);
        server.last.serve(history(range(1, 50), before: '51', more: false));
        async.flushMicrotasks();
        expect(m.messages, hasLength(100));
        expect(m.messages.first.id, '1');
        expect(m.olderExist, isFalse);
        m.loadOlder();
        async.flushMicrotasks();
        expect(server.last.of('history'), hasLength(1));
      });
    });
  });

  group('reconnect', () {
    test('backoff starts at 1 s, doubles to 30 s with some spread, and resets after welcome', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        async.flushMicrotasks();
        final waits = <Duration>[];
        for (var i = 0; i < 7; i++) {
          final before = server.sockets.length;
          server.last.drop();
          async.flushMicrotasks();
          var waited = Duration.zero;
          while (server.sockets.length == before) {
            async.elapse(const Duration(milliseconds: 50));
            waited += const Duration(milliseconds: 50);
            expect(waited, lessThan(const Duration(seconds: 40)));
          }
          waits.add(waited);
        }
        expect(m.connected, isFalse);
        expect(waits[0].inMilliseconds, inInclusiveRange(700, 1300));
        expect(waits[1].inMilliseconds, inInclusiveRange(1400, 2600));
        expect(waits[2].inMilliseconds, inInclusiveRange(2800, 5200));
        expect(waits[6].inMilliseconds, inInclusiveRange(22000, 30050));
        open(async, server);
        server.last.drop();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1350));
        expect(server.sockets, hasLength(9));
      });
    });

    for (final status in [401, 403]) {
      test('$status says chat is not available and asks the service again after a minute', () {
        fakeAsync((async) {
          final server = Server();
          final m = model(server);
          async.flushMicrotasks();
          server.last.drop(status);
          async.flushMicrotasks();
          expect(m.availability, NdChatAvailability.refused);
          expect(m.showEntry, isFalse);
          async.elapse(const Duration(seconds: 59));
          expect(server.sockets, hasLength(1));
          async.elapse(const Duration(seconds: 2));
          expect(server.sockets, hasLength(2), reason: 'the service decides whether to ask the server');
          server.last.drop(status);
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 61));
          expect(server.sockets, hasLength(3), reason: 'no backoff growth: the service holds the refusal');
          open(async, server);
          expect(m.availability, NdChatAvailability.available);
          expect(m.showEntry, isTrue);
        });
      });
    }

    test('404 and a computer without a device token mean no chat: no entry, a slow check later', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        async.flushMicrotasks();
        server.last.drop(404);
        async.flushMicrotasks();
        expect(m.availability, NdChatAvailability.off);
        expect(m.showEntry, isFalse);
        async.elapse(const Duration(minutes: 9));
        expect(server.sockets, hasLength(1));
        async.elapse(const Duration(minutes: 1, seconds: 1));
        expect(server.sockets, hasLength(2));
        server.last.drop(kNdChatNoToken);
        async.flushMicrotasks();
        expect(m.availability, NdChatAvailability.off);
        async.elapse(const Duration(seconds: 119));
        expect(server.sockets, hasLength(2));
        async.elapse(const Duration(seconds: 2));
        expect(server.sockets, hasLength(3));
        open(async, server);
        expect(m.showEntry, isTrue);
      });
    });

    test('a 404 right after a drop is a server starting: short tries keep the entry, then the long wait', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        server.last.drop();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1300));
        expect(server.sockets, hasLength(2));
        var count = 2;
        for (final wait in [1300, 2500, 5000, 10000, 20000]) {
          server.last.drop(404);
          async.flushMicrotasks();
          expect(m.showEntry, isTrue, reason: 'a server that is starting keeps the entry');
          async.elapse(Duration(milliseconds: wait));
          count++;
          expect(server.sockets, hasLength(count), reason: 'asked again after at most $wait ms');
        }
        server.last.drop(404);
        async.flushMicrotasks();
        expect(m.showEntry, isFalse);
        async.elapse(const Duration(minutes: 9));
        expect(server.sockets, hasLength(count), reason: 'then the long wait');
      });
    });

    test('no device token right after the service restarts keeps the entry and asks again within seconds', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        server.last.drop();
        async.flushMicrotasks();
        // The service is down for a while: the waits grow.
        for (var i = 0; i < 4; i++) {
          async.elapse(const Duration(seconds: 40));
          server.last.drop();
          async.flushMicrotasks();
        }
        async.elapse(const Duration(seconds: 40));
        // It is up, but has no token for this server yet.
        server.last.drop(kNdChatNoToken);
        async.flushMicrotasks();
        expect(m.showEntry, isTrue);
        final sockets = server.sockets.length;
        async.elapse(const Duration(milliseconds: 1300));
        expect(server.sockets, hasLength(sockets + 1), reason: 'the service just started');
        open(async, server, ids: [1]);
        expect(m.showEntry, isTrue);
      });
    });

    test('503 while the server starts keeps the entry and asks again after its Retry-After', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        server.last.drop(503, const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(m.showEntry, isTrue);
        async.elapse(const Duration(milliseconds: 4900));
        expect(server.sockets, hasLength(1), reason: 'not before Retry-After');
        async.elapse(const Duration(milliseconds: 200));
        expect(server.sockets, hasLength(2));
        server.last.drop(404);
        async.flushMicrotasks();
        expect(m.showEntry, isTrue, reason: 'a 404 during the start is part of the start');
        async.elapse(const Duration(milliseconds: 1300));
        expect(server.sockets, hasLength(3));
      });
    });

    test('a socket the server closes for a refused token is a 403, not a drop', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        server.last.drop();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1300));
        open(async, server, ids: [1]);
        server.last.drop(403);
        async.flushMicrotasks();
        expect(m.showEntry, isFalse);
        async.elapse(const Duration(seconds: 59));
        expect(server.sockets, hasLength(2), reason: 'no quick tries once the socket was open again');
      });
    });

    test('chat turned off by an admin: no entry, the next try after Retry-After', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        async.flushMicrotasks();
        server.last.drop(kNdChatOff, const Duration(seconds: 600));
        async.flushMicrotasks();
        expect(m.availability, NdChatAvailability.off);
        expect(m.showEntry, isFalse);
        async.elapse(const Duration(seconds: 599));
        expect(server.sockets, hasLength(1));
        async.elapse(const Duration(seconds: 2));
        expect(server.sockets, hasLength(2));
      });
    });

    test('an open chat closed with chat_off loses its entry and asks again after some minutes', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        expect(m.showEntry, isTrue);
        server.last.drop(kNdChatOff);
        async.flushMicrotasks();
        expect(m.showEntry, isFalse);
        async.elapse(const Duration(minutes: 5));
        expect(server.sockets, hasLength(1));
        async.elapse(const Duration(minutes: 6));
        expect(server.sockets, hasLength(2));
      });
    });

    test('an older server that answers v=2 with frames of version 1 is no chat', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        async.flushMicrotasks();
        server.last.serve({'type': 'history', 'messages': [msg(1)]});
        async.flushMicrotasks();
        expect(server.last.closedByClient, isTrue);
        expect(m.availability, NdChatAvailability.off);
        expect(m.showEntry, isFalse);
        expect(m.messages, isEmpty);
        async.elapse(const Duration(minutes: 9));
        expect(server.sockets, hasLength(1));
        async.elapse(const Duration(minutes: 2));
        expect(server.sockets, hasLength(2));
      });
    });

    test('a welcome of another version is no chat either', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        async.flushMicrotasks();
        server.last.serve({...welcome(), 'v': 1});
        async.flushMicrotasks();
        expect(server.last.closedByClient, isTrue);
        expect(m.showEntry, isFalse);
      });
    });

    test('429 waits at least 30 s; 500 retries with the backoff', () {
      fakeAsync((async) {
        final server = Server();
        model(server);
        async.flushMicrotasks();
        server.last.drop(429);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 29));
        expect(server.sockets, hasLength(1));
        async.elapse(const Duration(seconds: 12));
        expect(server.sockets, hasLength(2));
        server.last.drop(500);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(server.sockets, hasLength(3));
      });
    });

    test('while closed it says not connected and keeps what was shown', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1, 2]);
        server.last.drop();
        async.flushMicrotasks();
        expect(m.connected, isFalse);
        expect(m.showEntry, isTrue);
        expect(m.messages, hasLength(2));
      });
    });

    test('catch-up pages back until it reaches the newest message it had', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: range(71, 120), more: true);
        server.last.drop();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        server.last.serve(welcome());
        server.last.serve(history(range(181, 230), more: true));
        async.flushMicrotasks();
        expect(server.last.of('history'), [
          {'type': 'history', 'before': '181', 'limit': 100}
        ]);
        server.last.serve(history(range(81, 180), before: '181', more: true));
        async.flushMicrotasks();
        expect(server.last.of('history'), hasLength(1));
        expect(m.messages.map((e) => int.parse(e.id)), range(71, 230));
        expect(m.olderExist, isTrue);
      });
    });

    test('catch-up needs no page when the newest page holds the newest message it had', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: range(51, 100), more: true);
        server.last.drop();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        server.last.serve(welcome());
        server.last.serve(history(range(61, 110), more: true));
        async.flushMicrotasks();
        expect(server.last.of('history'), isEmpty);
        expect(m.messages, hasLength(60));
      });
    });

    test('a message whose echo never came is not sent again when the history has its client_id', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        m.sendMessage('did it arrive?');
        async.flushMicrotasks();
        final clientId = server.last.of('send').single['client_id'] as String;
        server.last.drop();
        async.flushMicrotasks();
        expect(m.pending.single.state, NdChatSendState.sending);
        async.elapse(const Duration(seconds: 2));
        server.last.serve(welcome());
        server.last.serve(history([1, 2],
            make: (id) => id == 2
                ? msg(2, from: me, text: 'did it arrive?', clientId: clientId)
                : msg(id)));
        async.flushMicrotasks();
        expect(server.last.of('send'), isEmpty);
        expect(m.pending, isEmpty);
        expect(m.messages.map((e) => e.text), ['message 1', 'did it arrive?']);
      });
    });

    test('a message whose echo never came is sent again when the history lacks its client_id', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        m.sendMessage('lost on the way');
        async.flushMicrotasks();
        final first = server.last.of('send').single;
        server.last.drop();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        server.last.serve(welcome());
        async.flushMicrotasks();
        expect(server.last.of('send'), isEmpty, reason: 'not before the history is in');
        server.last.serve(history([1]));
        async.flushMicrotasks();
        final again = server.last.of('send');
        expect(again, hasLength(1));
        expect(again.single['text'], 'lost on the way');
        expect(again.single['client_id'], first['client_id']);
      });
    });

    test('the resend waits for the catch-up pages', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: range(1, 50));
        m.sendMessage('written before the drop');
        async.flushMicrotasks();
        final clientId = server.last.of('send').single['client_id'] as String;
        server.last.drop();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        server.last.serve(welcome());
        server.last.serve(history(range(101, 150), more: true));
        async.flushMicrotasks();
        expect(server.last.of('send'), isEmpty);
        server.last.serve(history(range(1, 100),
            before: '101',
            make: (id) => id == 51
                ? msg(51, from: me, text: 'written before the drop', clientId: clientId)
                : msg(id)));
        async.flushMicrotasks();
        expect(server.last.of('send'), isEmpty);
        expect(m.pending, isEmpty);
      });
    });

    test('closing the model closes its socket and stops reconnecting', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server);
        m.dispose();
        async.flushMicrotasks();
        expect(server.last.closedByClient, isTrue);
        async.elapse(const Duration(minutes: 5));
        expect(server.sockets, hasLength(1));
      });
    });
  });

  group('the conversation', () {
    test('the computer\'s own message opens a closed conversation again', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1]);
        server.last.serve({'type': 'helper', 'name': 'Anna Weber', 'state': 'closed'});
        async.flushMicrotasks();
        expect(m.helperClosed, isTrue);
        server.last.serve({'type': 'message.new', 'message': msg(2)});
        async.flushMicrotasks();
        expect(m.helperClosed, isTrue, reason: 'a staff message alone changes nothing');
        server.last.serve({'type': 'message.new', 'message': msg(3, from: me)});
        async.flushMicrotasks();
        expect(m.helperClosed, isFalse);
        expect(m.helperName, 'Anna Weber');
      });
    });
  });

  group('unread, seen and notifications', () {
    test('unread counts staff messages after the computer\'s read mark', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server,
            ids: [1, 2, 3, 4],
            make: (id) => msg(id, from: id == 2 ? me : anna, deleted: id == 4),
            reads: [readOf(me, 1)]);
        expect(m.unread, 1);
        server.last.serve({'type': 'message.new', 'message': msg(5)});
        async.flushMicrotasks();
        expect(m.unread, 2);
        server.last.serve({
          'type': 'read',
          'conversation_id': device,
          'reader': {'kind': 'device', 'id': device},
          'up_to': '5'
        });
        async.flushMicrotasks();
        expect(m.unread, 0);
        server.last.serve({
          'type': 'read',
          'conversation_id': device,
          'reader': {'kind': 'device', 'id': device},
          'up_to': '3'
        });
        server.last.serve({'type': 'message.new', 'message': msg(6)});
        async.flushMicrotasks();
        expect(m.unread, 1, reason: 'a read mark never moves back');
      });
    });

    test('a staff message notifies while the window is not in front, with the name and the start of the text', () {
      fakeAsync((async) {
        final server = Server();
        final notes = <(String, String)>[];
        final m = model(server, notes: notes);
        open(async, server, ids: [1]);
        expect(notes, isEmpty, reason: 'the history is not news');
        server.last.serve({'type': 'message.new', 'message': msg(2, text: 'Hi, I am looking at it now.')});
        server.last.serve({'type': 'message.new', 'message': msg(3, from: me, text: 'mine')});
        server.last.serve({'type': 'message.new', 'message': msg(4, text: 'x' * 300)});
        async.flushMicrotasks();
        expect(notes.first, ('Anna Weber', 'Hi, I am looking at it now.'));
        expect(notes, hasLength(2));
        expect(notes.last.$2.length, lessThanOrEqualTo(120));
        m.setFront(true);
        server.last.serve({'type': 'message.new', 'message': msg(5)});
        async.flushMicrotasks();
        expect(notes, hasLength(2));
      });
    });

    test('the window leaves notifications to a tray that holds the chat', () {
      fakeAsync((async) {
        final server = Server();
        final notes = <(String, String)>[];
        final m = model(server, notes: notes);
        open(async, server);
        m.othersNotify = true;
        server.last.serve({'type': 'message.new', 'message': msg(2)});
        async.flushMicrotasks();
        expect(notes, isEmpty);
        m.othersNotify = false;
        server.last.serve({'type': 'message.new', 'message': msg(3)});
        async.flushMicrotasks();
        expect(notes, hasLength(1));
      });
    });

    test('the window says when its chat comes in front and goes', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        final fronts = <bool>[];
        m.onFront = fronts.add;
        open(async, server);
        m.setFront(true);
        m.setFront(true);
        m.setFront(false);
        expect(fronts, [true, false]);
      });
    });

    test('a message of files only notifies with the file name', () {
      fakeAsync((async) {
        final server = Server();
        final notes = <(String, String)>[];
        model(server, notes: notes);
        open(async, server);
        server.last.serve({
          'type': 'message.new',
          'message': {
            ...msg(2, text: ''),
            'attachments': [
              {'id': 'a' * 32, 'name': 'error.png', 'type': 'image/png', 'size': 10, 'width': 8, 'height': 8, 'url': '/x'}
            ]
          }
        });
        async.flushMicrotasks();
        expect(notes.single, ('Anna Weber', 'error.png'));
      });
    });

    test('in front and at the newest message it sends read, also after a catch-up', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1, 2], reads: [readOf(me, 1)]);
        expect(server.last.of('read'), isEmpty);
        m.setFront(true);
        async.flushMicrotasks();
        expect(server.last.of('read'), [
          {'type': 'read'}
        ]);
        server.last.serve({
          'type': 'read',
          'conversation_id': device,
          'reader': {'kind': 'device', 'id': device},
          'up_to': '2'
        });
        async.flushMicrotasks();
        m.setAtNewest(false);
        server.last.serve({'type': 'message.new', 'message': msg(3)});
        async.flushMicrotasks();
        expect(server.last.of('read'), hasLength(1));
        m.setAtNewest(true);
        async.flushMicrotasks();
        expect(server.last.of('read'), hasLength(2));
        server.last.drop();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        server.last.serve(welcome());
        server.last.serve(history([1, 2, 3, 4], reads: [readOf(me, 2)]));
        async.flushMicrotasks();
        expect(server.last.of('read'), [
          {'type': 'read'}
        ]);
      });
    });

    test('seen shows under the computer\'s newest message once a staff read mark reaches it', () {
      fakeAsync((async) {
        final server = Server();
        final m = model(server);
        open(async, server, ids: [1, 2, 3], make: (id) => msg(id, from: id == 1 ? anna : me),
            reads: [readOf(anna, 2), readOf(me, 3)]);
        expect(m.seenId, isNull);
        server.last.serve({
          'type': 'read',
          'conversation_id': device,
          'reader': {'kind': 'user', 'id': '9'},
          'up_to': '3'
        });
        async.flushMicrotasks();
        expect(m.seenId, '3');
      });
    });
  });

  group('files', () {
    test('a message with files uploads each first, then sends the file ids', () {
      fakeAsync((async) {
        final server = Server();
        final files = FakeFiles();
        final m = NdChatModel(connect: server.connect, files: files, random: Random(1), now: () => t0);
        m.start();
        open(async, server);
        m.sendMessage('see the picture', paths: ['/tmp/a.png', '/tmp/b.txt']);
        async.flushMicrotasks();
        expect(files.uploaded, ['/tmp/a.png', '/tmp/b.txt']);
        final send = server.last.of('send').single;
        expect(send['attachments'], ['id-/tmp/a.png', 'id-/tmp/b.txt']);
        expect(send['text'], 'see the picture');
      });
    });

    test('more than 10 files or a file over 50 MB are refused before uploading', () {
      fakeAsync((async) {
        final server = Server();
        final files = FakeFiles();
        final m = NdChatModel(connect: server.connect, files: files, random: Random(1), now: () => t0);
        m.start();
        open(async, server);
        expect(m.checkFiles([for (var i = 0; i < 11; i++) NdChatLocalFile('/f$i', 1)]),
            NdChatFileProblem.tooMany);
        expect(m.checkFiles([NdChatLocalFile('/big', 50 * 1024 * 1024 + 1)]),
            NdChatFileProblem.tooBig);
        expect(m.checkFiles([NdChatLocalFile('/ok', 50 * 1024 * 1024)]), isNull);
      });
    });

    test('a failed upload marks the message not sent and keeps the files for try again', () {
      fakeAsync((async) {
        final server = Server();
        final files = FakeFiles()..failWith = 507;
        final m = NdChatModel(connect: server.connect, files: files, random: Random(1), now: () => t0);
        m.start();
        open(async, server);
        m.sendMessage('', paths: ['/tmp/a.png']);
        async.flushMicrotasks();
        expect(server.last.of('send'), isEmpty);
        expect(m.pending.single.state, NdChatSendState.failed);
        expect(m.pending.single.problem, NdChatFileProblem.storageFull);
        files.failWith = null;
        m.retry(m.pending.single.clientId);
        async.flushMicrotasks();
        expect(server.last.of('send').single['attachments'], ['id-/tmp/a.png']);
      });
    });

    test('an upload while the server starts says to try again in a moment', () {
      fakeAsync((async) {
        final server = Server();
        final files = FakeFiles()..failWith = 503;
        final m = NdChatModel(connect: server.connect, files: files, random: Random(1), now: () => t0);
        m.start();
        open(async, server);
        m.sendMessage('', paths: ['/tmp/a.png']);
        async.flushMicrotasks();
        expect(m.pending.single.state, NdChatSendState.failed);
        expect(m.pending.single.problem, NdChatFileProblem.serverStarting);
      });
    });

    test('bad_attachment uploads the files again on try again', () {
      fakeAsync((async) {
        final server = Server();
        final files = FakeFiles();
        final m = NdChatModel(connect: server.connect, files: files, random: Random(1), now: () => t0);
        m.start();
        open(async, server);
        m.sendMessage('x', paths: ['/tmp/a.png']);
        async.flushMicrotasks();
        final clientId = server.last.of('send').single['client_id'];
        server.last.serve({'type': 'error', 'code': 'bad_attachment', 'for': 'send', 'client_id': clientId});
        async.flushMicrotasks();
        expect(m.pending.single.state, NdChatSendState.failed);
        m.retry(clientId as String);
        async.flushMicrotasks();
        expect(files.uploaded, ['/tmp/a.png', '/tmp/a.png']);
      });
    });
  });
}
