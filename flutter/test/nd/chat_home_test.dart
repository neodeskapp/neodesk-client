// The chat in the app: shown in place of Home while it is open.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_hbb/desktop/pages/nd_chat_page.dart';
import 'package:flutter_hbb/models/nd_chat_model.dart';
import 'package:flutter_hbb/models/nd_chat_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_fakes.dart';
import 'harness.dart';

void main() {
  testWidgets('the chat shows in place of Home while it is open and Escape brings Home back', (tester) async {
    final service = NdChatService.instance;
    await pumpScreen(tester, const NdChatHome(home: Text('Home page')), size: const Size(472, 560));
    expect(find.text('Home page'), findsOneWidget);
    service.open.value = true;
    await tester.pump();
    expect(find.text('Home page'), findsNothing);
    expect(find.text('Chat with support'), findsOneWidget);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(service.open.value, isFalse);
    expect(find.text('Home page'), findsOneWidget);
  });

  testWidgets('in a wide window the chat fills it and keeps its content in a centred column', (tester) async {
    final service = NdChatService.instance;
    await pumpScreen(tester, const NdChatHome(home: Text('Home page')), size: const Size(1280, 720));
    service.open.value = true;
    await tester.pump();
    expect(tester.getRect(find.byType(NdChatPage)), const Rect.fromLTWH(0, 0, 1280, 720));
    final composer = tester.getRect(find.byKey(const ValueKey('nd-chat-composer')));
    expect(composer.width, 1280, reason: 'the rule above the field reaches both edges');
    final field = tester.getRect(find.byType(TextField));
    final title = tester.getRect(find.text('Chat with support'));
    expect(field.left, greaterThan((1280 - kNdChatColumn) / 2));
    expect(field.right, lessThan((1280 + kNdChatColumn) / 2));
    expect(field.width, greaterThan(kNdChatColumn - 120));
    expect(title.left, greaterThan((1280 - kNdChatColumn) / 2));
    service.open.value = false;
    await tester.pump();
  });

  testWidgets('Home has the chat entry below the hint', (tester) async {
    final server = Server();
    final model = NdChatModel(connect: server.connect, now: () => t0);
    model.start();
    await pumpScreen(
        tester,
        ThisComputerColumn(
          id: '418205739',
          password: 'k7m2qx9w',
          status: const HomeStatus(NdStatusKind.good, 'Ready'),
          chat: NdChatEntry(model: model, onOpen: () {}),
        ),
        size: const Size(472, 640));
    server.last.serve(welcome());
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    final hint = tester.getRect(find.text(tr('nd-home-hint')));
    final entry = tester.getRect(find.text('Chat with support'));
    expect(entry.top, greaterThan(hint.bottom));
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
