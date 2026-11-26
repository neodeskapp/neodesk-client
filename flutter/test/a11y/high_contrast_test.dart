// EN 301 549 11.7 User Preferences, WCAG 1.4.11: when the system asks for
// high contrast (Windows contrast themes, GNOME high contrast), muted text
// and every control border are drawn in the text colour. (findings.md F41)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show MyTheme;
import 'package:flutter_hbb/common/theme/nd_theme.dart';
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

Future<NdColors> _colors(WidgetTester tester,
    {required bool highContrast, required ThemeMode mode}) async {
  late NdColors c;
  // As the system reports it (Windows contrast theme, GNOME high contrast).
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(highContrast: highContrast);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(MaterialApp(
      theme: MyTheme.lightTheme,
      darkTheme: MyTheme.darkTheme,
      highContrastTheme: MyTheme.highContrastLightTheme,
      highContrastDarkTheme: MyTheme.highContrastDarkTheme,
      themeMode: mode,
      home: Builder(builder: (context) {
        NdTheme.track(context);
        c = context.nd;
        return const SizedBox();
      }),
  ));
  // The app animates between themes; wait for the end.
  await tester.pumpAndSettle();
  return c;
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('high contrast strengthens muted text and borders '
        '(${mode.name})', (tester) async {
      final normal = await _colors(tester, highContrast: false, mode: mode);
      final hc = await _colors(tester, highContrast: true, mode: mode);
      expect(normal.textMuted, isNot(normal.text),
          reason: 'the normal theme keeps its muted tone');
      expect(hc.textMuted, hc.text);
      expect(hc.border, hc.text);
      for (final surface in [hc.bg, hc.bgSubtle, hc.bgFloat, hc.titlebar]) {
        expect(_ratio(hc.border, surface), greaterThanOrEqualTo(7),
            reason: 'borders on $surface');
        expect(_ratio(hc.textMuted, surface), greaterThanOrEqualTo(7));
      }
      expect(ndColors.border, hc.border,
          reason: 'code without a context follows it too');
    });
  }
}
