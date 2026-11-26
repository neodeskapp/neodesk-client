// WCAG 2.4.7 Focus Visible and 1.4.11 Non-text Contrast: the keyboard
// focus on menu items and Material buttons is a 2 px outline with at least
// 3:1 against what is next to it, in light and dark. (findings.md F38)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/theme/nd_theme.dart';
import 'package:flutter_hbb/common/widgets/nd/nd_menu.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.red / 255) +
      0.7152 * ch(c.green / 255) +
      0.0722 * ch(c.blue / 255);
}

double _ratio(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

const _focused = {WidgetState.focused};

void main() {
  for (final b in Brightness.values) {
    testWidgets('focus outlines reach 3:1 (${b.name})', (tester) async {
      final theme = NdTheme.theme(b, desktop: true);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          })));
      final c = ctx.nd;

      void check(String what, ButtonStyle? style, List<Color> next) {
        final side = style?.side?.resolve(_focused);
        expect(side, isNotNull, reason: '$what: no focus outline');
        expect(side!.width, greaterThanOrEqualTo(2), reason: what);
        for (final n in next) {
          expect(_ratio(side.color, n), greaterThanOrEqualTo(3),
              reason: '$what: ${_ratio(side.color, n).toStringAsFixed(2)}:1');
        }
        // Not focused: no outline added.
        final rest = style!.side?.resolve(const {});
        expect(rest == null || rest.width <= 1, isTrue, reason: what);
      }

      check('menu item', ndMenuItemStyle(ctx), [c.bgFloat, c.hover]);
      check('menu button theme', theme.menuButtonTheme.style,
          [c.bgFloat, c.hover]);
      check('text button', theme.textButtonTheme.style, [c.bg, c.hover]);
      check('outlined button', theme.outlinedButtonTheme.style,
          [c.bg, c.hover]);
      check('icon button', theme.iconButtonTheme.style, [c.bg, c.hover]);
      // An inner ring on the accent fill: it is measured against the fill.
      check('elevated button', theme.elevatedButtonTheme.style,
          [c.accent, c.accentHover]);
    });
  }
}
