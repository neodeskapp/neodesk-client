// The chat window and the Home entry (the console's chat PROTOCOL.md,
// section 9): what the person sees, the keyboard, the screen reader labels,
// German, and the client's small windows.

import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/desktop/pages/nd_chat_page.dart';
import 'package:flutter_hbb/models/nd_chat_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_fakes.dart';
import 'harness.dart';

class Actions {
  final picked = <List<NdChatLocalFile>>[];
  final saved = <String>[];
  final opened = <Uri>[];
  String? saveTo = '/home/me/Downloads/report.pdf';

  NdChatPageActions get it => NdChatPageActions(
        pickFiles: () async => picked.isEmpty ? [] : picked.removeAt(0),
        saveFile: (f) async {
          saved.add(f.id);
          return saveTo;
        },
        picture: (f) async => null,
        openLink: opened.add,
      );
}

class Chat {
  Chat() {
    model = NdChatModel(
        connect: server.connect,
        files: files,
        random: Random(1),
        now: () => t0.add(const Duration(minutes: 5)));
    model.start();
  }

  final server = Server();
  final files = FakeFiles();
  late final NdChatModel model;
  final actions = Actions();
  final focused = ValueNotifier(true);
  var closed = 0;

  void serve(Map<String, dynamic> f) => server.last.serve(f);

  void open({List<Map<String, dynamic>> messages = const [], List<Map<String, dynamic>> reads = const [], Object? helper}) {
    serve(welcome());
    serve({
      'type': 'history',
      'conversation_id': device,
      'before': '0',
      'more': false,
      'messages': messages,
      'reads': reads,
    });
    serve({'type': 'helper', 'name': helper, 'state': 'open'});
  }

  Widget page() => NdChatPage(
        model: model,
        actions: actions.it,
        onClose: () => closed++,
        windowFocused: focused,
      );
}

/// Pumps the chat page, runs [body] and takes everything down again so no
/// timer of the model outlives the test.
Future<void> withChat(WidgetTester tester, Future<void> Function(Chat chat) body,
    {Size size = const Size(520, 640),
    String lang = 'en',
    Brightness brightness = Brightness.light,
    void Function(Chat chat)? before}) async {
  final chat = Chat();
  before?.call(chat);
  await pumpScreen(tester, chat.page(), size: size, lang: lang, brightness: brightness);
  await tester.pump();
  await body(chat);
  await tester.pumpWidget(const SizedBox());
  chat.model.dispose();
  await tester.pump(const Duration(seconds: 5));
}

Map<String, dynamic> file(String name, int size, {bool picture = false}) => {
      'id': (name.hashCode.toRadixString(16) * 8).substring(0, 32).padRight(32, '0'),
      'name': name,
      'type': picture ? 'image/png' : 'application/pdf',
      'size': size,
      if (picture) 'width': 800,
      if (picture) 'height': 600,
      'url': '/api/chat/files/x',
    };

Future<void> enter(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(k);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  testWidgets('says who helps, or that nobody took it yet, or that it was closed', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(helper: null);
      await tester.pump();
      expect(find.text('Waiting for someone'), findsOneWidget);
      chat.serve({'type': 'helper', 'name': 'Anna Weber', 'state': 'open'});
      await tester.pump();
      expect(find.text('Anna Weber is helping you'), findsOneWidget);
      chat.serve({'type': 'helper', 'name': 'Anna Weber', 'state': 'closed'});
      await tester.pump();
      expect(find.text('This conversation was closed. Write to open it again.'), findsOneWidget);
    });
  });

  testWidgets('shows the staff name on their messages, the day, edited, deleted and replies', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [
        msg(1, text: 'The printer blinks orange', from: me),
        msg(2, text: 'Hi, I am looking at it now.', editedAt: t0.millisecondsSinceEpoch),
        msg(3, deleted: true),
        {
          ...msg(4, text: 'Restart it please'),
          'reply_to': {'id': '1', 'from_name': 'reception-01', 'preview': 'The printer blinks orange', 'deleted': false},
        },
        {
          ...msg(5, text: 'And this?'),
          'reply_to': {'id': '3', 'from_name': 'Anna Weber', 'preview': '', 'deleted': true},
        },
      ]);
      await tester.pump();
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Anna Weber'), findsNWidgets(5),
          reason: 'on messages 2 to 5 (a deleted one keeps its sender) and in the quote of 5');
      expect(find.text('reception-01'), findsOneWidget, reason: 'only in the quote, not on own messages');
      expect(find.text('edited'), findsOneWidget);
      expect(find.text('Message deleted'), findsNWidgets(2));
      expect(find.text('The printer blinks orange'), findsNWidgets(2));
      expect(find.text('Restart it please'), findsOneWidget);
    });
  });

  testWidgets('Enter sends, Shift+Enter does not, Escape closes', (tester) async {
    await withChat(tester, (chat) async {
      chat.open();
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await enter(tester, 'first line');
      await key(tester, LogicalKeyboardKey.enter, shift: true);
      expect(chat.server.last.of('send'), isEmpty);
      expect(find.text('first line'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.enter);
      expect(chat.server.last.of('send').single['text'], 'first line');
      expect(find.widgetWithText(TextField, 'first line'), findsNothing);
      expect(find.text('Sending'), findsOneWidget);
      expect(chat.closed, 0);
      await key(tester, LogicalKeyboardKey.escape);
      expect(chat.closed, 1);
    });
  });

  testWidgets('the field takes several lines', (tester) async {
    await withChat(tester, (chat) async {
      chat.open();
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, greaterThan(1));
      expect(field.keyboardType, TextInputType.multiline);
    });
  });

  testWidgets('Escape first stops a reply, then closes', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [msg(1, text: 'Can you send a screenshot?')]);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Message options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to Anna Weber'), findsOneWidget);
      await enter(tester, 'here it is');
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.text('Replying to Anna Weber'), findsNothing);
      expect(chat.closed, 0);
      await key(tester, LogicalKeyboardKey.enter);
      expect(chat.server.last.of('send').single.containsKey('reply_to'), isFalse);
      await key(tester, LogicalKeyboardKey.escape);
      expect(chat.closed, 1);
    });
  });

  testWidgets('replying to a message of files only names its first file', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [
        {...msg(1, text: ''), 'attachments': [file('error.png', 48213, picture: true)]},
      ]);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Message options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to Anna Weber'), findsOneWidget);
      expect(find.text('error.png'), findsOneWidget);
    });
  });

  testWidgets('a reply carries the message it answers', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [msg(1, text: 'Can you send a screenshot?')]);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Message options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      await enter(tester, 'sure');
      await key(tester, LogicalKeyboardKey.enter);
      expect(chat.server.last.of('send').single['reply_to'], '1');
    });
  });

  testWidgets('own messages can be edited and deleted from their options', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [msg(1, text: 'The printer blinks orang', from: me)]);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Message options'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Editing your message'), findsOneWidget);
      await enter(tester, 'The printer blinks orange');
      await key(tester, LogicalKeyboardKey.enter);
      expect(chat.server.last.of('edit').single,
          {'type': 'edit', 'message_id': '1', 'text': 'The printer blinks orange'});
      expect(chat.server.last.of('send'), isEmpty);
      await tester.tap(find.bySemanticsLabel('Message options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this message?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(chat.server.last.of('delete').single, {'type': 'delete', 'message_id': '1'});
    });
  });

  testWidgets('staff messages offer reply and reactions but no edit or delete', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [msg(1)]);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Message options'));
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      await tester.tap(find.bySemanticsLabel('React 👍'));
      await tester.pumpAndSettle();
      expect(chat.server.last.of('react').single,
          {'type': 'react', 'message_id': '1', 'emoji': '👍', 'on': true});
    });
  });

  testWidgets('reactions show with their count, the own one marked, and a click takes it back', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [
        msg(1, reactions: {
          '👍': [me, anna]
        })
      ]);
      await tester.pump();
      expect(find.text('👍 2'), findsOneWidget);
      final chip = tester.getSemantics(find.bySemanticsLabel(RegExp('^👍 from')));
      expect(chip.hasFlag(SemanticsFlag.isSelected), isTrue);
      await tester.tap(find.text('👍 2'));
      await tester.pump();
      expect(chat.server.last.of('react').single['on'], isFalse);
    });
  });

  testWidgets('while not connected it says so, keeps the text and sends nothing', (tester) async {
    await withChat(tester, (chat) async {
      chat.open();
      await tester.pump();
      chat.server.last.drop();
      await tester.pump();
      expect(find.text('Not connected. What you write stays here until the chat is back.'), findsOneWidget);
      await enter(tester, 'still here');
      await key(tester, LogicalKeyboardKey.enter);
      expect(find.text('still here'), findsOneWidget);
      final send = tester.getSemantics(find.bySemanticsLabel('Send'));
      expect(send.hasFlag(SemanticsFlag.isEnabled), isFalse);
    });
  });

  testWidgets('a message that failed says not sent and sends again on a click', (tester) async {
    await withChat(tester, (chat) async {
      chat.open();
      await tester.pump();
      await enter(tester, 'hello');
      await key(tester, LogicalKeyboardKey.enter);
      final clientId = chat.server.last.of('send').single['client_id'];
      chat.serve({'type': 'error', 'code': 'failed', 'for': 'send', 'client_id': clientId});
      await tester.pump();
      expect(find.text('Not sent, try again'), findsOneWidget);
      await tester.tap(find.text('Not sent, try again'));
      await tester.pump();
      expect(chat.server.last.of('send'), hasLength(2));
      expect(find.text('Sending'), findsOneWidget);
    });
  });

  testWidgets('seen shows under the newest own message once staff read it', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [msg(1, from: me), msg(2, from: me)]);
      await tester.pump();
      expect(find.text('Seen'), findsNothing);
      chat.serve({
        'type': 'read',
        'conversation_id': device,
        'reader': {'kind': 'user', 'id': '7'},
        'up_to': '2'
      });
      await tester.pump();
      expect(find.text('Seen'), findsOneWidget);
    });
  });

  testWidgets('typing shows the staff name for 4 seconds', (tester) async {
    await withChat(tester, (chat) async {
      chat.open();
      await tester.pump();
      chat.serve({'type': 'typing', 'conversation_id': device, 'from': anna});
      await tester.pump();
      expect(find.text('Anna Weber is typing'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Anna Weber is typing'), findsNothing);
    });
  });

  testWidgets('pictures open from a thumbnail; other files show name, size and download', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [
        {...msg(1, text: ''), 'attachments': [file('error.png', 48213, picture: true), file('report.pdf', 48213)]},
      ]);
      await tester.pump();
      expect(find.bySemanticsLabel('Open picture error.png'), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('47 KB'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Download report.pdf'));
      await tester.pump();
      expect(chat.actions.saved, hasLength(1));
      expect(find.text('Saved to /home/me/Downloads/report.pdf'), findsOneWidget);
    });
  });

  testWidgets('http and https addresses are links and nothing else is', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [
        msg(1, text: 'See https://help.example.com/printer. Or **bold** <b>x</b> and ftp://x.example.com')
      ]);
      await tester.pump();
      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((r) => r.text.toPlainText().contains('help.example'));
      final links = <TextSpan>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) links.add(span);
        return true;
      });
      expect(links.map((s) => s.text), ['https://help.example.com/printer']);
      (links.single.recognizer as TapGestureRecognizer).onTap!();
      expect(chat.actions.opened.single.toString(), 'https://help.example.com/printer');
      expect(rich.text.toPlainText(), contains('**bold** <b>x</b>'));
    });
  });

  testWidgets('a file sent while the server starts says to try again in a moment', (tester) async {
    await withChat(tester, before: (chat) => chat.files.failWith = 503, (chat) async {
      chat.open();
      await tester.pump();
      chat.actions.picked.add([NdChatLocalFile('/tmp/shot.png', 2048)]);
      await tester.tap(find.bySemanticsLabel('Attach files'));
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Not sent: the server is starting. Try again in a moment.'), findsOneWidget);
      expect(find.text('Not sent, try again'), findsOneWidget);
    });
  });

  testWidgets('files are attached, checked against the limits and sent with the message', (tester) async {
    await withChat(tester, (chat) async {
      chat.open();
      await tester.pump();
      chat.actions.picked.add([for (var i = 0; i < 11; i++) NdChatLocalFile('/f$i.txt', 10)]);
      await tester.tap(find.bySemanticsLabel('Attach files'));
      await tester.pump();
      expect(find.text('You can send up to 10 files at once.'), findsOneWidget);
      chat.actions.picked.add([NdChatLocalFile('/tmp/shot.png', 2048)]);
      await tester.tap(find.bySemanticsLabel('Attach files'));
      await tester.pump();
      expect(find.text('shot.png (2 KB)'), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await key(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      expect(chat.server.last.of('send').single['attachments'], ['id-/tmp/shot.png']);
    });
  });

  testWidgets('the buttons have labels for screen readers', (tester) async {
    await withChat(tester, (chat) async {
      chat.open(messages: [msg(1)]);
      await tester.pump();
      for (final label in ['Close chat', 'Attach files', 'Send', 'Message options']) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(node.hasFlag(SemanticsFlag.isButton), isTrue, reason: label);
      }
    });
  });

  testWidgets('a refused chat says it is not available and offers no field', (tester) async {
    await withChat(tester, (chat) async {
      chat.server.last.drop(403);
      await tester.pump();
      expect(find.text('Chat is not available on this computer.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  testWidgets('in German it speaks with du', (tester) async {
    await withChat(tester, lang: 'de', (chat) async {
      chat.open(messages: [msg(1, from: me)], helper: 'Anna Weber');
      chat.serve({
        'type': 'read',
        'conversation_id': device,
        'reader': {'kind': 'user', 'id': '7'},
        'up_to': '1'
      });
      await tester.pump();
      expect(find.text('Anna Weber hilft dir'), findsOneWidget);
      expect(find.text('Gesehen'), findsOneWidget);
      expect(find.text('Heute'), findsOneWidget);
      expect(find.text('Enter sendet, Umschalt+Enter fügt eine Zeile ein'), findsOneWidget);
      chat.server.last.drop();
      await tester.pump();
      expect(find.textContaining('Was du schreibst'), findsOneWidget);
    });
  });

  for (final size in [const Size(360, 480), const Size(472, 560)]) {
    testWidgets('fits a small window of ${size.width.toInt()} x ${size.height.toInt()}', (tester) async {
      await withChat(tester, size: size, (chat) async {
        chat.open(helper: 'Anna Weber', messages: [
          msg(1, text: 'A rather long message ' * 20, from: me),
          {...msg(2, text: 'x'), 'attachments': [file('a-very-long-file-name-of-a-report-for-the-printer.pdf', 5 << 20), file('shot.png', 1000, picture: true)]},
          {
            ...msg(3, text: 'ok'),
            'reply_to': {'id': '1', 'from_name': 'reception-01', 'preview': 'A rather long message ' * 6, 'deleted': false},
            'reactions': {'👍': [me], '❤️': [anna], '😂': [anna], '😮': [anna], '😢': [anna], '🙏': [anna]},
          },
        ]);
        chat.serve({'type': 'typing', 'conversation_id': device, 'from': {'kind': 'user', 'id': '9', 'name': 'Bartholomäus Wilhelmine-Oberhausen'}});
        await tester.pump();
        expect(tester.takeException(), isNull);
        await enter(tester, 'line\n' * 8);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        await shot(tester, 'chat-${size.width.toInt()}', Brightness.light);
      });
    });
  }

  group('Home entry', () {
    testWidgets('shows only once the server took the chat, with the count of new messages', (tester) async {
      final chat = Chat();
      var opened = 0;
      await pumpScreen(tester, NdChatEntry(model: chat.model, onOpen: () => opened++), size: const Size(400, 200));
      expect(find.text('Chat with support'), findsNothing);
      chat.open(messages: [msg(1), msg(2)], reads: [readOf(me, 0)]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Chat with support'), findsOneWidget);
      expect(find.text('2 new'), findsOneWidget);
      expect(find.bySemanticsLabel('Chat with support, 2 new messages'), findsOneWidget);
      await tester.tap(find.text('Chat with support'));
      expect(opened, 1);
      chat.serve({
        'type': 'read',
        'conversation_id': device,
        'reader': {'kind': 'device', 'id': device},
        'up_to': '2'
      });
      await tester.pump();
      await tester.pump();
      expect(find.text('2 new'), findsNothing);
      chat.server.last.drop(404);
      await tester.pump();
      await tester.pump();
      expect(find.text('Chat with support'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      chat.model.dispose();
    });

    testWidgets('a computer without chat shows no entry', (tester) async {
      final chat = Chat();
      await pumpScreen(tester, NdChatEntry(model: chat.model, onOpen: () {}), size: const Size(400, 200));
      chat.server.last.drop(kNdChatNoToken);
      await tester.pump();
      await tester.pump();
      expect(chat.model.availability, NdChatAvailability.off);
      expect(find.text('Chat with support'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      chat.model.dispose();
    });
  });

  forBothThemes('a conversation as the person sees it', (tester, b) async {
    await withChat(tester, size: const Size(472, 600), brightness: b, (chat) async {
      chat.open(helper: 'Anna Weber', messages: [
        msg(1, from: me, text: 'Hello, my printer stopped working this morning. It blinks orange.'),
        msg(2, text: 'Hi, I am looking at it now. Can you send a screenshot of the error?'),
        {...msg(3, from: me, text: ''), 'attachments': [file('error.png', 48213, picture: true)]},
        {
          ...msg(4, text: 'Thanks. E-42 is the paper sensor, I will restart the spooler. Steps: https://help.example.com/e42'),
          'reply_to': {'id': '3', 'from_name': 'reception-01', 'preview': '', 'deleted': false},
          'reactions': {'👍': [me]},
        },
        {...msg(5, text: 'The driver, in case you need it again:'), 'attachments': [file('printer-driver.zip', 3355443)]},
        msg(6, from: me, text: 'Works again, thank you!'),
      ], reads: [readOf(anna, 6)]);
      chat.serve({'type': 'typing', 'conversation_id': device, 'from': anna});
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Anna Weber is helping you'), findsOneWidget);
      expect(find.text('Seen'), findsOneWidget);
      await shot(tester, 'chat-conversation', b);
    });
  });

  test('sizes and dates read as people write them', () {
    expect(ndChatSize(512), '512 B');
    expect(ndChatSize(48213), '47 KB');
    expect(ndChatSize(3355443), '3.2 MB');
    expect(ndChatSize(50 << 20), '50 MB');
    expect(ndChatDate(DateTime(2026, 11, 3), 'd MMM yyyy'), '3 Nov 2026');
    expect(ndChatDate(DateTime(2026, 11, 3), 'd.M.yyyy'), '3.11.2026');
  });
}
