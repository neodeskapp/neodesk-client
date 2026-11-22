// Every icon the desktop app draws comes from BdIcons (Material Symbols,
// DESIGN.md Icons). This test reads the sources the desktop app is built
// from (lib/ without lib/mobile and lib/web) and fails on any other icon
// source:
//
// - Material Icons (Icons.*), Cupertino icons, RustDesk's IconFont,
// - IconData made outside bd_icons.dart (icon fonts of their own),
// - SVG or PNG assets other than the kept pictures listed below,
// - the retired icon fonts in pubspec.yaml or in assets/.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Asset paths the app may still name, with the reason they stay.
const _keptAssets = <String, String>{
  'assets/bd-logo-': 'the NeoDesk logo',
  'assets/bd-os-': 'operating system marks (Phosphor, as in the console)',
  'assets/flags/': 'language flags (Twemoji)',
  r'assets/auth-$svgFile.svg': 'logos of the sign-in providers',
  'assets/icon.svg': 'the app icon',
  'assets/icon.png': 'the app icon',
  'assets/logo': 'the logo a custom build brings',
  r'assets/${_kKBLayoutImageMap': 'pictures of the keyboard layouts',
};

/// Files that pass a variable to SvgPicture.asset, with the reason.
const _variableSvgFiles = <String, String>{
  'lib/common/widgets/bd/bd_misc.dart': 'logo and OS marks',
};

const _retiredFonts = [
  'tabbar.ttf',
  'more.ttf',
  'address_book.ttf',
  'device_group.ttf',
  'peer_searchbar.ttf',
];

final _generated = RegExp(
    r'(generated_bridge.*|.*\.g|.*\.freezed|generated_plugin_registrant)\.dart$');

/// The Dart files under [base]/lib that the desktop app uses, with their
/// paths relative to [base].
Iterable<(String, File)> _desktopSources(Directory base) sync* {
  final lib = Directory('${base.path}/lib');
  for (final e in lib.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final rel = e.path.substring(lib.path.length + 1).replaceAll(r'\', '/');
    final p = 'lib/$rel';
    if (p.startsWith('lib/mobile/') || p.startsWith('lib/web/')) continue;
    if (_generated.hasMatch(p)) continue;
    yield (p, e);
  }
}

/// The line without a // comment (not counting // inside a string).
String _code(String line) {
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quote != null) {
      if (ch == r'\') {
        i++;
      } else if (ch == quote) {
        quote = null;
      }
    } else if (ch == "'" || ch == '"') {
      quote = ch;
    } else if (ch == '/' && i + 1 < line.length && line[i + 1] == '/') {
      return line.substring(0, i);
    }
  }
  return line;
}

const _ownFont = 'an icon font of its own';
final _forbidden = <RegExp, String>{
  RegExp(r'\bIcons\.'): 'Material Icons',
  RegExp(r'\bCupertinoIcons\.'): 'Cupertino icons',
  RegExp(r'\bIconFont\b'): 'the old IconFont',
  RegExp(r'\bIconData\('): _ownFont,
};
final _assetLiteral = RegExp(r'''['"](assets/[^'"]*\.(?:svg|png))['"]''');
final _svgAsset = RegExp(r'SvgPicture\.asset\(\s*(\S)');

/// Every use of another icon source in the desktop sources under [base]
/// (the package folder by default), as path:line: what.
List<String> scanSources([Directory? base]) {
  final findings = <String>[];
  for (final (path, f) in _desktopSources(base ?? Directory.current)) {
    final code = f.readAsLinesSync().map(_code).toList();
    for (var i = 0; i < code.length; i++) {
      final line = code[i];
      for (final e in _forbidden.entries) {
        if (e.value == _ownFont &&
            path == 'lib/common/widgets/bd/bd_icons.dart') {
          continue;
        }
        if (e.key.hasMatch(line)) {
          findings.add('$path:${i + 1}: ${e.value}: ${line.trim()}');
        }
      }
      for (final m in _assetLiteral.allMatches(line)) {
        final asset = m.group(1)!;
        if (!_keptAssets.keys.any(asset.startsWith)) {
          findings.add('$path:${i + 1}: asset $asset');
        }
      }
    }
    final text = code.join('\n');
    for (final m in _svgAsset.allMatches(text)) {
      final first = m.group(1)!;
      if (first == "'" || first == '"') continue;
      if (_variableSvgFiles.containsKey(path)) continue;
      final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
      findings.add('$path:$line: SvgPicture.asset with a path from a variable');
    }
  }
  return findings;
}

List<String> scanFonts() {
  final findings = <String>[];
  final pubspec = File('pubspec.yaml').readAsStringSync();
  for (final font in _retiredFonts) {
    if (pubspec.contains('assets/$font')) {
      findings.add('pubspec.yaml: declares assets/$font');
    }
    if (File('assets/$font').existsSync()) {
      findings.add('assets/$font: still in the app');
    }
  }
  return findings;
}

void main() {
  test('the desktop sources draw icons only from BdIcons', () {
    final findings = scanSources();
    expect(findings, isEmpty, reason: findings.join('\n'));
  });

  test('the retired icon fonts are gone', () {
    final findings = scanFonts();
    expect(findings, isEmpty, reason: findings.join('\n'));
  });

  test('the scan finds icons from other sources', () {
    final base = Directory.systemTemp.createTempSync('icon-scan');
    addTearDown(() => base.deleteSync(recursive: true));
    Directory('${base.path}/lib/mobile').createSync(recursive: true);
    File('${base.path}/lib/mobile/page.dart')
        .writeAsStringSync('final a = Icon(Icons.close);\n');
    File('${base.path}/lib/page.dart').writeAsStringSync('''
// Icons.close in a comment does not count.
final a = Icon(Icons.close);
final b = SvgPicture.asset('assets/close.svg');
final c = SvgPicture.asset(name);
final d = Image.asset('assets/icon.png');
''');
    expect(scanSources(base), [
      'lib/page.dart:2: Material Icons: final a = Icon(Icons.close);',
      'lib/page.dart:3: asset assets/close.svg',
      'lib/page.dart:4: SvgPicture.asset with a path from a variable',
    ]);
  });
}
