import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

String hex(Color c) =>
    '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

void main() {
  group('deriveAccent matches tools/colour.mjs', () {
    // input, light result, dark result (DESIGN.md, Server accent)
    const cases = [
      ['#3aa35c', '#00813c', '#3aa35c'],
      ['#ffd400', '#846d07', '#ffd400'],
      ['#e30613', '#d91e1e', '#fa473d'],
      ['#000000', '#000000', '#898989'],
      ['#ffffff', '#6f6f6f', '#ffffff'],
    ];
    for (final c in cases) {
      test('${c[0]}', () {
        final input = parseHexColor(c[0] as String)!;
        final l = deriveAccent(input, BdColors.light, Brightness.light);
        final d = deriveAccent(input, BdColors.dark, Brightness.dark);
        expect(hex(l.accent), c[1]);
        expect(hex(d.accent), c[2]);
        // Yellow and white carry the dark ink.
        if (c[0] == '#ffd400' || c[0] == '#ffffff') {
          expect(d.onAccent, const Color(0xFF0C1B1E));
        }
        for (final r in [l, d]) {
          expect(contrastRatio(r.accent, r.onAccent), greaterThanOrEqualTo(4.5));
          expect(contrastRatio(r.hover, r.onAccent), greaterThanOrEqualTo(4.5));
        }
      });
    }
  });

  test('a server accent replaces accent, hover and ink but nothing else', () {
    final branded = BdColors.light.withServerAccent('#e30613');
    expect(branded.accent, isNot(BdColors.light.accent));
    expect(branded.danger, BdColors.light.danger);
    expect(branded.logoSquare, BdColors.light.logoSquare);
    expect(branded.bg, BdColors.light.bg);
    expect(BdColors.light.withServerAccent('not a colour'), same(BdColors.light));
  });

  test('every token pair of the design reaches its contrast', () {
    for (final c in [BdColors.light, BdColors.dark]) {
      expect(contrastRatio(c.text, c.bg), greaterThanOrEqualTo(12));
      expect(contrastRatio(c.textMuted, c.hover), greaterThanOrEqualTo(4.5));
      for (final s in [c.bg, c.bgSubtle, c.bgFloat]) {
        expect(contrastRatio(c.accent, s), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.border, s), greaterThanOrEqualTo(3));
      }
      expect(contrastRatio(c.onAccent, c.accent), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(c.onDanger, c.danger), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('BdSwitch reports the flipped value and ignores taps when off',
      (tester) async {
    bool? got;
    await pumpScreen(
        tester,
        Center(child: BdSwitch(value: false, onChanged: (v) => got = v)),
        size: const Size(200, 100));
    await tester.tap(find.byType(BdSwitch));
    expect(got, isTrue);

    got = null;
    await pumpScreen(
        tester,
        const Center(child: BdSwitch(value: true, onChanged: null)),
        size: const Size(200, 100));
    await tester.tap(find.byType(BdSwitch), warnIfMissed: false);
    expect(got, isNull);
  });

  testWidgets('BdSwitch knob sits at the end when on', (tester) async {
    Future<double> knobX(bool v) async {
      await pumpScreen(
          tester,
          Center(child: BdSwitch(value: v, onChanged: (_) {})),
          size: const Size(200, 100));
      final track = tester.getRect(find.byType(BdSwitch));
      final knob = tester.getRect(find.descendant(
          of: find.byType(BdSwitch),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.constraints?.maxWidth == 12 &&
              w.constraints?.maxHeight == 12)));
      expect(track.size, const Size(36, 20));
      // The found box includes the knob's 3 px margin.
      return knob.left + 3 - track.left;
    }

    expect(await knobX(false), 4);
    expect(await knobX(true), 20);
  });

  testWidgets('BdSegmented selects the tapped choice only once',
      (tester) async {
    final picks = <String>[];
    await pumpScreen(
        tester,
        Center(
          child: BdSegmented<String>(
            segments: const [
              BdSegment('light', 'Light'),
              BdSegment('dark', 'Dark'),
              BdSegment('system', 'System'),
            ],
            value: 'system',
            onChanged: picks.add,
          ),
        ),
        size: const Size(400, 100));
    await tester.tap(find.text('Dark'));
    await tester.tap(find.text('System'));
    expect(picks, ['dark']);
    final h = tester.getSize(find.byType(BdSegmented<String>)).height;
    expect(h, 30);
  });

  testWidgets('primary buttons do not stretch in a column', (tester) async {
    await pumpScreen(
        tester,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BdButton.primary(label: 'Done', onPressed: () {}),
        ]),
        size: const Size(600, 200));
    expect(tester.getSize(find.byType(BdButton)).width, lessThan(120));
  });
}
