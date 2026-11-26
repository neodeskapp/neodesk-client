// WCAG 2.1.1 Keyboard and 4.1.3 Status Messages for the connection manager:
// a keyboard user must reach Allow, Decline and the switches, and hear that
// someone wants to connect. (findings.md F42, F34)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/cm/cm_widgets.dart';
import 'package:flutter_hbb/desktop/pages/server_page.dart'
    show cmControlPageBlock;
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

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('the local keyboard reaches the switches, Decline and Allow',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester, cmControlPageBlock(child: _request(), block: false.obs),
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
        tester, cmControlPageBlock(child: _request(), block: true.obs),
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
        tester, cmControlPageBlock(child: _request(), block: false.obs),
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

  testWidgets('the focused title shows a focus ring', (tester) async {
    await pumpScreen(
        tester, cmControlPageBlock(child: _request(), block: false.obs),
        size: const Size(380, 600));
    await tester.pump();
    expect(find.byType(NdFocusRing), findsOneWidget);
  });
}
