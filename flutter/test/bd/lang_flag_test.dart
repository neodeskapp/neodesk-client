import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

// Languages spoken without one country of their own: no flag.
const _noFlag = {'ca', 'eo', 'eu', 'sc'};

List<String> _clientLanguages() {
  final src = File('../src/lang.rs').readAsStringSync();
  final block = src.substring(src.indexOf('pub const LANGS'));
  return RegExp(r'\("([a-z-]+)",')
      .allMatches(block.substring(0, block.indexOf('];')))
      .map((m) => m.group(1)!)
      .toList();
}

void main() {
  setUpAll(loadBdFonts);

  test('every client language has a flag file or is one without a country', () {
    final langs = _clientLanguages();
    expect(langs, contains('de'));
    for (final code in langs) {
      if (_noFlag.contains(code)) {
        expect(kBdLangFlags, isNot(contains(code)), reason: code);
        continue;
      }
      expect(kBdLangFlags, contains(code), reason: code);
      expect(File('assets/flags/$code.svg').existsSync(), isTrue,
          reason: 'assets/flags/$code.svg');
    }
  });

  for (final b in Brightness.values) {
    testWidgets(
        'the language select shows flags in the field and the menu ($b)',
        (tester) async {
      await pumpScreen(
        tester,
        size: const Size(420, 360),
        brightness: b,
        Align(
          alignment: Alignment.topCenter,
          child: BdSelect<String>(
            width: 240,
            options: [
              for (final o in const [
                ['default', 'Default'],
                ['de', 'Deutsch'],
                ['eo', 'Esperanto'],
                ['fr', 'Français'],
              ])
                BdOption(o[0], o[1], prefix: BdLangFlag(o[0])),
            ],
            value: 'de',
            onChanged: (_) {},
          ),
        ),
      );
      // The closed field: the chosen language's flag before its name
      expect(find.byType(SvgPicture), findsOneWidget);
      final flag = tester.getTopLeft(find.byType(SvgPicture));
      final name = tester.getTopLeft(find.text('Deutsch'));
      expect(flag.dx, lessThan(name.dx));

      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await shot(tester, 'language-flags', b);
      // The menu: de and fr have flags; Default and Esperanto keep an empty
      // 20 px slot, so all names start at the same x
      expect(find.byType(SvgPicture), findsNWidgets(3));
      final xs = {
        for (final n in ['Default', 'Esperanto', 'Français'])
          tester.getTopLeft(find.text(n)).dx,
      };
      expect(xs, hasLength(1));
    });
  }
}
