// WCAG 2.1.1, 2.4.7 and 4.1.2 for the shared NeoDesk controls: each takes
// focus with Tab, works with Enter, Space and (in groups) the arrow keys,
// shows a focus ring, and tells assistive tech its role, name and state.
// (findings.md F02 to F06, F25)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';
import 'a11y_helpers.dart';

SemanticsData _sem(WidgetTester tester, Finder f) =>
    tester.getSemantics(f).getSemanticsData();

Future<void> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyEvent(k);
  await tester.pumpAndSettle();
}

/// Pumps [build] with a value it can change, starting at [initial].
Future<ValueNotifier<T>> _pumpWith<T>(WidgetTester tester, T initial,
    Widget Function(T value, ValueChanged<T> set) build,
    {Size size = const Size(500, 300)}) async {
  final v = ValueNotifier<T>(initial);
  await pumpScreen(
      tester,
      Center(
          child: ValueListenableBuilder<T>(
              valueListenable: v,
              builder: (_, value, __) => build(value, (x) => v.value = x))),
      size: size);
  return v;
}

void main() {
  testWidgets('NdCheckbox: Tab, Space, checked state, name, focus ring',
      (tester) async {
    final handle = tester.ensureSemantics();
    final v = await _pumpWith<bool>(
        tester,
        false,
        (value, set) => NdCheckbox(
            value: value,
            onChanged: set,
            label: 'Clipboard',
            hint: 'What one of you copies, the other can paste.'));
    var d = _sem(tester, find.byType(NdCheckbox));
    expect(d.hasFlag(SemanticsFlag.hasCheckedState), isTrue);
    expect(d.hasFlag(SemanticsFlag.isChecked), isFalse);
    expect(d.label, 'Clipboard');
    expect(d.hint, 'What one of you copies, the other can paste.');

    await _tab(tester);
    expect(focusedName(), contains('Clipboard'));
    expect(find.byType(NdFocusRing), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.space);
    expect(v.value, isTrue);
    d = _sem(tester, find.byType(NdCheckbox));
    expect(d.hasFlag(SemanticsFlag.isChecked), isTrue);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(v.value, isFalse);
    handle.dispose();
  });

  testWidgets('NdSegmented: one Tab stop, arrows choose, selected state',
      (tester) async {
    final handle = tester.ensureSemantics();
    final v = await _pumpWith<int>(
        tester,
        2,
        (value, set) => NdSegmented<int>(
              segments: const [
                NdSegment(0, 'Light'),
                NdSegment(1, 'Dark'),
                NdSegment(2, 'System'),
              ],
              value: value,
              onChanged: set,
            ));
    final dark = _sem(tester, find.text('Dark'));
    expect(dark.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(dark.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
    expect(dark.hasFlag(SemanticsFlag.isSelected), isFalse);
    expect(_sem(tester, find.text('System')).hasFlag(SemanticsFlag.isSelected),
        isTrue);

    final order = await tabOrder(tester);
    expect(order, ['System'], reason: 'only the chosen segment is a Tab stop');
    await _key(tester, LogicalKeyboardKey.arrowLeft);
    expect(v.value, 1);
    expect(focusedName(), 'Dark');
    expect(_sem(tester, find.text('Dark')).hasFlag(SemanticsFlag.isSelected),
        isTrue);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(v.value, 0, reason: 'wraps around');
    handle.dispose();
  });

  testWidgets('NdTabs: one Tab stop, arrows move, selected state',
      (tester) async {
    final handle = tester.ensureSemantics();
    final v = await _pumpWith<int>(
        tester,
        0,
        (value, set) => SizedBox(
              width: 400,
              child: NdTabs<int>(tabs: const [
                NdTab(0, 'Recent'),
                NdTab(1, 'Favourites'),
                NdTab(2, 'Address book'),
              ], value: value, onChanged: set),
            ));
    expect(_sem(tester, find.text('Recent')).hasFlag(SemanticsFlag.isSelected),
        isTrue);
    expect(_sem(tester, find.text('Favourites')).hasFlag(SemanticsFlag.isButton),
        isTrue);
    final order = await tabOrder(tester);
    expect(order, ['Recent']);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(v.value, 1);
    expect(focusedName(), 'Favourites');
    await _key(tester, LogicalKeyboardKey.end);
    expect(v.value, 2);
    await _key(tester, LogicalKeyboardKey.home);
    expect(v.value, 0);
    handle.dispose();
  });

  testWidgets('NdSelect: named, says its value, opens with Enter and picks',
      (tester) async {
    final handle = tester.ensureSemantics();
    final v = await _pumpWith<String>(
        tester,
        'en',
        (value, set) => NdSelect<String>(
              semanticLabel: 'Language',
              options: const [
                NdOption('en', 'English'),
                NdOption('de', 'Deutsch'),
              ],
              value: value,
              onChanged: set,
            ));
    var d = _sem(tester, find.byType(NdPressable));
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.label, 'Language');
    expect(d.value, 'English');
    expect(d.hasFlag(SemanticsFlag.hasExpandedState), isTrue);
    expect(d.hasFlag(SemanticsFlag.isExpanded), isFalse);

    await _tab(tester);
    expect(focusedName(), contains('Language'));
    await _key(tester, LogicalKeyboardKey.enter);
    d = _sem(tester, find.byType(NdPressable));
    expect(d.hasFlag(SemanticsFlag.isExpanded), isTrue);
    expect(focusedName(), contains('English'),
        reason: 'focus goes to the chosen option');
    final english = tester.getSemantics(find.descendant(
        of: find.byType(MenuItemButton), matching: find.text('English')));
    expect(english.getSemanticsData().hasFlag(SemanticsFlag.isChecked), isTrue);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedName(), contains('Deutsch'));
    await _key(tester, LogicalKeyboardKey.enter);
    expect(v.value, 'de');
    handle.dispose();
  });

  testWidgets('NdDisclosure: a button that says whether it is open',
      (tester) async {
    final handle = tester.ensureSemantics();
    final v = await _pumpWith<bool>(
        tester,
        false,
        (open, set) => NdDisclosure(
            label: 'Relay and API server',
            open: open,
            onToggle: () => set(!open),
            child: const Text('Relay server')));
    var d = _sem(tester, find.text('Relay and API server'));
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.hasFlag(SemanticsFlag.hasExpandedState), isTrue);
    expect(d.hasFlag(SemanticsFlag.isExpanded), isFalse);
    await _tab(tester);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(v.value, isTrue);
    d = _sem(tester, find.text('Relay and API server'));
    expect(d.hasFlag(SemanticsFlag.isExpanded), isTrue);
    handle.dispose();
  });
}
