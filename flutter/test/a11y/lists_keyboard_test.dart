// WCAG 2.1.1 and 4.1.2 for the Settings navigation, the settings search
// hits and the computer rows on Home. (findings.md F07, F08, F09)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';
import 'a11y_helpers.dart';

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('Settings navigation: Tab and arrows reach every page',
      (tester) async {
    final handle = tester.ensureSemantics();
    final page = ValueNotifier<int>(0);
    await pumpScreen(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 240,
            child: ValueListenableBuilder<int>(
              valueListenable: page,
              builder: (_, v, __) => SettingsNav<int>(
                items: const [
                  SettingsNavItem(0, 'General'),
                  SettingsNavItem(1, 'Security'),
                  SettingsNavItem(2, 'Network'),
                  SettingsNavItem(3, 'About', dividerBefore: true),
                ],
                value: v,
                onChanged: (x) => page.value = x,
                search: NdSearchField(placeholder: tr('nd-search')),
              ),
            ),
          ),
        ),
        size: const Size(300, 400));
    final order = await tabOrder(tester);
    for (final want in ['General', 'Security', 'Network', 'About']) {
      expect(order.any((s) => s.contains(want)), isTrue,
          reason: '$want is not reachable with Tab');
    }
    final general = tester.getSemantics(find.text('General')).getSemanticsData();
    expect(general.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(general.hasFlag(SemanticsFlag.isSelected), isTrue);

    // Down from General goes to Security; Enter opens it.
    while (!(focusedName() ?? '').contains('General')) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedName(), 'Security');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(page.value, 1);
    handle.dispose();
  });

  testWidgets('a settings search hit is a button that opens the setting',
      (tester) async {
    final handle = tester.ensureSemantics();
    var opened = 0;
    await pumpScreen(
        tester,
        SettingsSearchResults(query: 'theme', hits: [
          SettingsSearchHit(
              label: 'Theme',
              path: 'General',
              description: 'Light, dark or as the system.',
              onTap: () => opened++),
        ]),
        size: const Size(800, 300));
    final order = await tabOrder(tester);
    expect(order, ['Theme']);
    final d = tester.getSemantics(find.text('Theme')).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.hint, 'General. Light, dark or as the system.');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, 1);
    handle.dispose();
  });

  testWidgets('a computer row: one name, Enter connects, Shift+F10 opens the '
      'menu, Connect and the menu are reachable', (tester) async {
    final handle = tester.ensureSemantics();
    var connects = 0;
    Offset? menuAt;
    await pumpScreen(
        tester,
        Center(
          child: SizedBox(
            width: 700,
            child: NdPeerRow(
              name: 'Accounting laptop',
              id: '702118446',
              platform: 'Windows 11',
              online: true,
              lastSeen: 'Today, 09:41',
              onConnect: () => connects++,
              onTap: () {},
              onMenu: (p) => menuAt = p,
            ),
          ),
        ),
        size: const Size(800, 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusedName(),
        'Accounting laptop, 702 118 446, Windows 11, Online, Today, 09:41');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(connects, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(menuAt, isNotNull);

    // With focus in the row, Connect shows and Tab reaches it and the menu.
    await tester.pump();
    final order = await tabOrder(tester);
    expect(order.any((s) => s.contains('Connect')), isTrue);
    expect(order.any((s) => s.contains(tr('nd-row-menu'))), isTrue);
    handle.dispose();
  });
}
