// The settings search lists the settings of the Security page under the
// names and in the sections the page shows (L450). The page needs the client
// core to build, so this reads its code: the _Safety class in
// desktop_setting_page.dart. Keys are compared, so the texts agree in every
// language.

import 'dart:io';

import 'package:flutter_hbb/desktop/pages/settings/settings_index.dart';
import 'package:flutter_test/flutter_test.dart';

String _securityPageCode() {
  final s = File('lib/desktop/pages/desktop_setting_page.dart')
      .readAsStringSync();
  return s.substring(
      s.indexOf('class _Safety extends'), s.indexOf('class _Network extends'));
}

/// The string literals of [code], comments left out.
Set<String> _literals(String code) {
  final out = <String>{};
  var i = 0;
  while (i < code.length) {
    if (code.startsWith('//', i)) {
      final end = code.indexOf('\n', i);
      if (end < 0) break;
      i = end;
      continue;
    }
    final c = code[i];
    if (c == "'" || c == '"') {
      final b = StringBuffer();
      var j = i + 1;
      while (j < code.length && code[j] != c) {
        if (code[j] == r'\') {
          b.write(code[j + 1]);
          j += 2;
          continue;
        }
        b.write(code[j]);
        j++;
      }
      out.add(b.toString());
      i = j + 1;
      continue;
    }
    i++;
  }
  return out;
}

void main() {
  final code = _securityPageCode();
  final security = kSettingsIndex.where((e) => e.group == 'security').toList();

  test('search names only what the Security page shows', () {
    final names = _literals(code);
    final sections = RegExp(r'''_Card\(\s*title:\s*['"]([^'"]+)['"]''')
        .allMatches(code)
        .map((m) => m[1]!)
        .toSet();
    expect([
      for (final e in security)
        if (!names.contains(e.label)) e.label,
    ], isEmpty, reason: 'names the page does not have');
    expect([
      for (final e in security)
        if (!sections.contains(e.section)) '${e.label} in ${e.section}',
    ], isEmpty, reason: 'sections the page does not have');
  });

  test('search finds every switch of the Security page there', () {
    final switches = RegExp(r'''_OptionCheckBox\(\s*context,\s*['"]([^'"]+)['"]''')
        .allMatches(code)
        .map((m) => m[1]!);
    final indexed = {for (final e in security) e.label};
    expect([
      for (final s in switches)
        if (!indexed.contains(s)) s,
    ], isEmpty);
  });
}
