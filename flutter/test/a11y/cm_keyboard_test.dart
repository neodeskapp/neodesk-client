// WCAG 2.1.1 Keyboard and 4.1.3 Status Messages for the connection manager:
// a keyboard user must reach Allow, Decline and the switches, and hear that
// someone wants to connect. (findings.md F42, F34)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/cm/cm_widgets.dart';
import 'package:flutter_hbb/desktop/pages/server_page.dart'
    show cmControlPageBlock, cmRemoteMaySendKeys;
import 'package:flutter_hbb/models/server_model.dart' show Client;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../nd/harness.dart';
import 'a11y_helpers.dart';

Widget _request({bool focusOnArrival = true}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: CmRequestBody(
              focusOnArrival: focusOnArrival,
              header: const CmHeader(
                  name: 'Mara Jensen', subtitle: '702 118 446', mono: true),
              name: 'Mara Jensen',
              permissions: [
                CmPermission(
                    label: tr('nd-cm-perm-input'),
                    value: true,
                    onChanged: (_) {}),
                CmPermission(
                    label: tr('nd-cm-perm-files'),
                    value: false,
                    onChanged: (_) {}),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: CmRequestActions(onDecline: () {}, onAllow: () {}),
        ),
      ],
    );

Widget _page(
        {required bool block,
        bool remoteMaySendKeys = false,
        bool systemBlocksRemoteKeys = false}) =>
    cmControlPageBlock(
        child: _request(),
        block: block.obs,
        remoteMaySendKeys: remoteMaySendKeys,
        systemBlocksRemoteKeys: systemBlocksRemoteKeys);

Client _client(
    {bool authorized = true,
    bool keyboard = true,
    bool fileTransfer = false,
    bool disconnected = false}) {
  final c = Client(1, authorized, fileTransfer, false, 'Mara Jensen',
      '702118446', keyboard, true, true);
  c.disconnected = disconnected;
  return c;
}

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('the local keyboard reaches the switches, Decline and Allow',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester, _page(block: false),
        size: const Size(380, 600));
    final order = await tabOrder(tester);
    // ignore: avoid_print
    print('cm tab order: $order');
    for (final want in [
      tr('nd-cm-perm-input'),
      tr('nd-cm-perm-files'),
      'Decline',
      'Allow'
    ]) {
      expect(order.any((s) => s.contains(want)), isTrue,
          reason: '$want is not reachable with Tab');
    }
    handle.dispose();
  });

  testWidgets('nothing takes focus while the remote mouse is over the window',
      (tester) async {
    await pumpScreen(
        tester, _page(block: true),
        size: const Size(380, 600));
    final order = await tabOrder(tester);
    for (final no in [tr('nd-cm-perm-input'), 'Decline', 'Allow']) {
      expect(order.where((s) => s.contains(no)), isEmpty);
    }
  });

  testWidgets('a request is announced and takes focus on its title',
      (tester) async {
    final handle = tester.ensureSemantics();
    final said = recordAnnouncements(tester);
    await pumpScreen(
        tester, _page(block: false),
        size: const Size(380, 600));
    await tester.pump();
    expect(said.map((a) => a.message),
        contains('Mara Jensen wants to connect to this computer'));
    expect(said.first.assertive, isTrue);
    expect(focusedName(), 'Mara Jensen wants to connect to this computer');
    final title = tester
        .getSemantics(find.text('Mara Jensen wants to connect to this computer'))
        .getSemanticsData();
    expect(title.hasFlag(SemanticsFlag.isHeader), isTrue);
    // The next Tab goes to the first switch.
    final order = await tabOrder(tester, max: 1);
    expect(order.single, contains(tr('nd-cm-perm-input')));
    handle.dispose();
  });

  testWidgets('the title shows no focus ring when the request arrives',
      (tester) async {
    await pumpScreen(
        tester, _page(block: false),
        size: const Size(380, 600));
    await tester.pump();
    expect(focusedName(), 'Mara Jensen wants to connect to this computer');
    expect(find.byType(NdFocusRing), findsNothing);
  });

  for (final (what, data) in [
    ('a screen reader', const MediaQueryData(accessibleNavigation: true)),
    ('high contrast', const MediaQueryData(highContrast: true)),
  ]) {
    testWidgets('with $what on, the title shows its focus ring on arrival',
        (tester) async {
      await pumpScreen(
          tester,
          Builder(
              builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        accessibleNavigation: data.accessibleNavigation,
                        highContrast: data.highContrast),
                    child: _page(block: false),
                  )),
          size: const Size(380, 600));
      await tester.pump();
      expect(find.byType(NdFocusRing), findsOneWidget);
    });
  }

  testWidgets('the title shows its focus ring when Tab brings focus back',
      (tester) async {
    await pumpScreen(
        tester, _page(block: false),
        size: const Size(380, 600));
    await tester.pump();
    await tabOrder(tester, max: 1);
    await tabOrder(tester, max: 1, backwards: true);
    expect(focusedName(), 'Mara Jensen wants to connect to this computer');
    expect(find.byType(NdFocusRing), findsOneWidget);
  });

  testWidgets(
      'while a remote computer may send keys and nothing stops them, the '
      'controls take no keyboard focus', (tester) async {
    await pumpScreen(tester, _page(block: false, remoteMaySendKeys: true),
        size: const Size(380, 600));
    await tester.pump();
    final order = await tabOrder(tester);
    for (final no in [tr('nd-cm-perm-input'), 'Decline', 'Allow']) {
      expect(order.where((s) => s.contains(no)), isEmpty,
          reason: '$no must not take a key the remote computer typed');
    }
    expect(focusedName() ?? '', isNot(contains('wants to connect')));
  });

  testWidgets(
      'when this computer keeps remote keys away, the local keyboard reaches '
      'the controls during a session', (tester) async {
    await pumpScreen(
        tester,
        _page(
            block: false,
            remoteMaySendKeys: true,
            systemBlocksRemoteKeys: true),
        size: const Size(380, 600));
    final order = await tabOrder(tester);
    for (final want in [tr('nd-cm-perm-input'), 'Decline', 'Allow']) {
      expect(order.any((s) => s.contains(want)), isTrue,
          reason: '$want is not reachable with Tab');
    }
  });

  test('a remote computer may send keys only from an accepted session with '
      'keyboard permission', () {
    expect(cmRemoteMaySendKeys([_client()]), isTrue);
    expect(cmRemoteMaySendKeys([]), isFalse);
    expect(cmRemoteMaySendKeys([_client(authorized: false)]), isFalse);
    expect(cmRemoteMaySendKeys([_client(keyboard: false)]), isFalse);
    expect(cmRemoteMaySendKeys([_client(fileTransfer: true)]), isFalse);
    expect(cmRemoteMaySendKeys([_client(disconnected: true)]), isFalse);
    expect(
        cmRemoteMaySendKeys([_client(keyboard: false), _client()]), isTrue);
  });

  testWidgets(
      'with the chat open the message field takes focus while a remote '
      'computer may send keys', (tester) async {
    final field = FocusNode(debugLabel: 'message');
    addTearDown(field.dispose);
    Widget page(bool chatOpen) => cmControlPageBlock(
        child: Material(child: TextField(focusNode: field)),
        block: false.obs,
        remoteMaySendKeys: true,
        systemBlocksRemoteKeys: false,
        chatOpen: chatOpen);
    await pumpScreen(tester, page(false), size: const Size(380, 200));
    field.requestFocus();
    await tester.pump();
    expect(field.hasFocus, isFalse);
    await pumpScreen(tester, page(true), size: const Size(380, 200));
    field.requestFocus();
    await tester.pump();
    expect(field.hasFocus, isTrue);
  });
}
