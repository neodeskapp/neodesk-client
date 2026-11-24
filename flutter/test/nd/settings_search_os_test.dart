// L465: the settings search ignored the index's os field, so Linux listed
// Windows-only settings such as Share Windows remote desktop sessions and
// the NeoDesk printer, and the hit Set permanent password always said
// "Not set.".

import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/desktop/pages/settings/settings_index.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

SettingsIndexEntry _entry(String label) =>
    kSettingsIndex.firstWhere((e) => e.label == label);

Set<String> _labels(SettingsSystem system) => {
      for (final e in kSettingsIndex)
        if (settingsEntryShows(e, system)) e.label
    };

const _windowsOnly = [
  'Enable RDP session sharing',
  'Enable remote printer',
  'Enable blocking user input',
  'Enable privacy mode',
  'nd-set-row-neodesk-printer',
  'nd-set-row-print-jobs-from-other-computers',
];

void main() {
  test('Linux lists none of the Windows-only settings', () {
    final linux = _labels(const SettingsSystem(os: 'linux', installed: true));
    expect([for (final l in _windowsOnly) if (linux.contains(l)) l], isEmpty);
    expect(linux, contains('Enable clipboard'));
    expect(linux, contains('Unlock with PIN'));
  });

  test('an installed Windows client lists them', () {
    final windows =
        _labels(const SettingsSystem(os: 'windows', installed: true));
    expect([for (final l in _windowsOnly) if (!windows.contains(l)) l],
        isEmpty);
    expect(windows, contains('Auto update'));
  });

  test('settings for installed clients stay out of a portable one', () {
    final portable = _labels(const SettingsSystem(os: 'windows'));
    expect(portable, isNot(contains('Enable RDP session sharing')));
    expect(portable, isNot(contains('Unlock with PIN')));
    expect(portable, isNot(contains('Auto update')));
    expect(portable, contains('Enable remote printer'));
  });

  test('the Wayland resets show only on Linux with Wayland', () {
    const reset = 'nd-set-row-choose-the-shared-screen-again';
    expect(_labels(const SettingsSystem(os: 'linux', wayland: true)),
        contains(reset));
    expect(_labels(const SettingsSystem(os: 'linux')), isNot(contains(reset)));
    expect(_labels(const SettingsSystem(os: 'windows', installed: true)),
        isNot(contains(reset)));
  });

  test('macOS keeps auto update and privacy mode', () {
    final mac = _labels(const SettingsSystem(os: 'macos', installed: true));
    expect(mac, contains('Auto update'));
    expect(mac, contains('Enable privacy mode'));
    expect(mac, isNot(contains('Enable remote printer')));
  });

  test('every os value of the index names systems the search knows', () {
    for (final e in kSettingsIndex) {
      if (e.os.isEmpty) continue;
      final shown = [
        for (final os in ['windows', 'macos', 'linux'])
          for (final installed in [false, true])
            for (final wayland in [false, true])
              if (settingsEntryShows(
                  e,
                  SettingsSystem(
                      os: os, installed: installed, wayland: wayland)))
                1
      ];
      expect(shown, isNotEmpty, reason: '${e.label}: ${e.os}');
      expect(shown.length, lessThan(12), reason: '${e.label}: ${e.os}');
    }
  });

  test('Set permanent password says whether one is set', () {
    final e = _entry('Set permanent password');
    useLanguage('en');
    expect(translate(settingsEntryDesc(e, permanentPasswordSet: true)),
        'Permanent password is set (hidden).');
    expect(translate(settingsEntryDesc(e, permanentPasswordSet: false)),
        'Not set.');
    useLanguage('de');
    expect(translate(settingsEntryDesc(e, permanentPasswordSet: true)),
        'Ein permanentes Passwort wurde festgelegt (ausgeblendet).');
    expect(settingsEntryDesc(_entry('Enable clipboard'),
            permanentPasswordSet: true),
        'nd-desc:Enable clipboard');
  });
}
