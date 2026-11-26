// WCAG 4.1.2 and 2.4.7 for buttons: an icon button is a button named by its
// label (Windows does not use a tooltip as the name), a button's name is
// said once, and the focused button tells assistive tech it has focus.
// (findings.md F18, F46)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';

SemanticsData _sem(WidgetTester tester, Finder f) =>
    tester.getSemantics(f).getSemanticsData();

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('NdButton says its label once and reports focus',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester, Center(child: NdButton(label: 'Connect', onPressed: () {})),
        size: const Size(300, 100));
    var d = _sem(tester, find.byType(NdButton));
    expect(d.label, 'Connect');
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    d = _sem(tester, find.byType(NdButton));
    expect(d.hasFlag(SemanticsFlag.isFocused), isTrue);
    handle.dispose();
  });

  testWidgets('NdIconButton is a named button with a focus ring',
      (tester) async {
    final handle = tester.ensureSemantics();
    var pressed = 0;
    await pumpScreen(
        tester,
        Center(
            child: NdIconButton(
                icon: NdIcons.close,
                tooltip: 'Close',
                onPressed: () => pressed++)),
        size: const Size(200, 100));
    var d = _sem(tester, find.byType(NdIconButton));
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.label, 'Close');
    expect(d.tooltip, isEmpty, reason: 'the name is not repeated as tooltip');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.byType(NdFocusRing), findsOneWidget);
    d = _sem(tester, find.byType(NdIconButton));
    expect(d.hasFlag(SemanticsFlag.isFocused), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(pressed, 1);
    handle.dispose();
  });
}
