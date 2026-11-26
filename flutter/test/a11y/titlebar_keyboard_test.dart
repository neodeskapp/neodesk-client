// WCAG 2.1.1, 2.5.8 and 4.1.2 for the custom title bar: window buttons are
// named buttons, Settings, Back and the page tabs are reachable by keyboard,
// the chosen tab says so and its close button is big enough.
// (findings.md F10 to F12, F48)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';
import 'a11y_helpers.dart';

SemanticsData _sem(WidgetTester tester, Finder f) =>
    tester.getSemantics(f).getSemanticsData();

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('window buttons are named buttons reachable with Tab',
      (tester) async {
    final handle = tester.ensureSemantics();
    final calls = <String>[];
    await pumpScreen(
        tester,
        Align(
          alignment: Alignment.topRight,
          child: NdWindowControls(
              onMinimize: () => calls.add('min'),
              onMaximize: () => calls.add('max'),
              onClose: () => calls.add('close')),
        ),
        size: const Size(300, 60));
    final buttons = tester.widgetList<NdWinButton>(find.byType(NdWinButton));
    for (final w in buttons) {
      final d = _sem(tester, find.byWidget(w));
      expect(d.hasFlag(SemanticsFlag.isButton), isTrue, reason: w.tooltip);
      expect(d.label, w.tooltip);
    }
    final order = await tabOrder(tester);
    expect(order.length, buttons.length);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, hasLength(1));
    handle.dispose();
  });

  testWidgets('the title bar: Settings, page tabs and their close buttons',
      (tester) async {
    final handle = tester.ensureSemantics();
    final calls = <String>[];
    await pumpScreen(
        tester,
        NdTitleBar(
          brand: const NdTitleBrand(),
          tabs: [
            NdWindowTab(
                label: 'Home',
                selected: false,
                onTap: () => calls.add('home')),
            NdWindowTab(
                label: 'Settings',
                selected: true,
                onTap: () => calls.add('settings'),
                onClose: () => calls.add('close settings')),
          ],
          actions: [
            NdTitleBarText(label: 'Back', onTap: () => calls.add('back'))
          ],
          controls: NdWindowControls(onMinimize: () {}, onClose: () {}),
        ),
        size: const Size(900, 40));
    final settingsTab = _sem(tester, find.text('Settings'));
    expect(settingsTab.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(settingsTab.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(_sem(tester, find.text('Home')).hasFlag(SemanticsFlag.isSelected),
        isFalse);

    final close = find.byWidgetPredicate(
        (w) => w is NdIconButton && w.tooltip == 'Close Settings');
    expect(close, findsOneWidget);
    final size = tester.getSize(close);
    expect(size.width >= 24 && size.height >= 24, isTrue,
        reason: 'WCAG 2.5.8: $size');

    final order = await tabOrder(tester);
    // ignore: avoid_print
    print('title bar tab order: $order');
    for (final want in ['Home', 'Settings', 'Close Settings', 'Back']) {
      expect(order.any((s) => s == want), isTrue,
          reason: '$want is not reachable with Tab');
    }
    // Ctrl+W on the focused Settings tab closes it.
    while (focusedName() != 'Settings') {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(calls, contains('close settings'));
    handle.dispose();
  });
}
