// WCAG 2.1.1 and 4.1.2 for the session toolbar and the small icon actions:
// a toolbar button takes focus and is a button named by its label, also
// when only its icon shows; an icon action is named by its message, not
// only by a tooltip. (findings.md F17, F19, F20)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' show ColorThemeExtension;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/widgets/nd_toolbar_button.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart'
    show ActionIcon, TabbarTheme;
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';
import 'a11y_helpers.dart';

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('an icon-only toolbar button is a named, focusable button',
      (tester) async {
    final handle = tester.ensureSemantics();
    var pressed = 0;
    await pumpScreen(
        tester,
        Center(
            child: NdToolbarButton(
                icon: NdIcons.chat,
                label: 'Chat',
                showLabel: false,
                onPressed: () => pressed++)),
        size: const Size(200, 100));
    final d =
        tester.getSemantics(find.byType(NdToolbarButton)).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.label, 'Chat');
    final order = await tabOrder(tester);
    expect(order, ['Chat']);
    expect(find.byType(NdFocusRing), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(pressed, 1);
    handle.dispose();
  });

  testWidgets('an icon action is a button named by its message',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        Material(
          child: Center(
              child: ActionIcon(
                  message: 'Close', icon: NdIcons.close, onTap: () {})),
        ),
        size: const Size(200, 100),
        extra: (c) => [ColorThemeExtension.from(c), TabbarTheme.from(c)]);
    final d = tester.getSemantics(find.byType(ActionIcon)).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(d.label, 'Close');
    expect(d.tooltip, isEmpty);
    handle.dispose();
  });
}
