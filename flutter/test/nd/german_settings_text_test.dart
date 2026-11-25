// Settings texts that showed in English in the German client (L527): the
// Pair with code dialog and a Security switch whose label had no German.
// The dialog needs the client core to open, so this reads its code.

import 'dart:io';

import 'package:flutter_hbb/desktop/pages/settings/settings_index.dart';
import 'package:flutter_test/flutter_test.dart';

/// The keys de.rs has a German text for.
Set<String> _germanKeys() {
  final re = RegExp(r'^\s*\("((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)+)"\),',
      multiLine: true);
  return {
    for (final m in re.allMatches(File('../src/lang/de.rs').readAsStringSync()))
      m[1]!.replaceAll(r'\"', '"')
  };
}

/// Keys whose German is the English word, so de.rs leaves them out.
const _sameInGerman = {'Code', '2FA'};

void main() {
  final german = _germanKeys();

  test('the Pair with code dialog has German text', () {
    final page = File('lib/desktop/pages/desktop_setting_page.dart')
        .readAsStringSync();
    final start = page.indexOf('void showPairWithCodeDialog(');
    final end = page.indexOf('//#endregion', start);
    final keys = RegExp(r'''\b(?:translate|tr|dialogButton)\(\s*'([^'$]+)'\s*[,)]''')
        .allMatches(page.substring(start, end))
        .map((m) => m[1]!)
        .toSet();
    expect(keys, containsAll(['nd-set-pair-code', 'nd-pair-button']));
    expect(
        [
          for (final k in keys)
            if (!german.contains(k) && !_sameInGerman.contains(k)) k
        ],
        isEmpty);
  });

  test('every setting the search lists has German text', () {
    expect(
        {
          for (final e in kSettingsIndex)
            for (final k in [e.label, e.section])
              if (k.isNotEmpty &&
                  !german.contains(k) &&
                  !_sameInGerman.contains(k))
                k
        },
        isEmpty);
  });
}
