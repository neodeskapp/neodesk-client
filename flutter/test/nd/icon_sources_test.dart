// Every icon the client draws comes from NdIcons (Material Symbols,
// DESIGN.md Icons, the set of the console). This test reads the client's
// Dart sources (lib/, desktop, mobile and web) and fails on any other icon
// source:
//
// - Material Icons (Icons.*), Cupertino icons, RustDesk's IconFont,
// - IconData made outside nd_icons.dart (icon fonts of their own),
// - SVG or PNG assets other than the kept pictures listed below,
// - the retired icon fonts in pubspec.yaml or in assets/,
// - icons in tool/nd_symbols.txt that no source uses (the font holds only
//   the client's icons).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Asset paths the app may still name, with the reason they stay.
const _keptAssets = <String, String>{
  'assets/nd-logo-': 'the NeoDesk logo',
  'assets/nd-os-': 'operating system marks (Phosphor, as in the console)',
  'assets/flags/': 'language flags (Twemoji)',
  r'assets/auth-$svgFile.svg': 'logos of the sign-in providers',
  'assets/icon.svg': 'the app icon',
  'assets/icon.png': 'the app icon',
  'assets/logo': 'the logo a custom build brings',
  r'assets/${_kKBLayoutImageMap': 'pictures of the keyboard layouts',
  'assets/scam.png': 'the "SCAM" stamp picture of the mobile scam warning',
};

/// Files that pass a variable to SvgPicture.asset, with the reason.
const _variableSvgFiles = <String, String>{
  'lib/common/widgets/nd/nd_misc.dart': 'logo and OS marks',
};

const _retiredFonts = [
  'tabbar.ttf',
  'more.ttf',
  'address_book.ttf',
  'device_group.ttf',
  'peer_searchbar.ttf',
  'gestures.ttf',
];

final _generated = RegExp(
    r'(generated_bridge.*|.*\.g|.*\.freezed|generated_plugin_registrant)\.dart$');

/// The Dart files under [base]/lib, with their paths relative to [base].
Iterable<(String, File)> _sources(Directory base) sync* {
  final lib = Directory('${base.path}/lib');
  for (final e in lib.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final rel = e.path.substring(lib.path.length + 1).replaceAll(r'\', '/');
    final p = 'lib/$rel';
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

/// Every use of another icon source in the sources under [base]
/// (the package folder by default), as path:line: what.
List<String> scanSources([Directory? base]) {
  final findings = <String>[];
  for (final (path, f) in _sources(base ?? Directory.current)) {
    final code = f.readAsLinesSync().map(_code).toList();
    for (var i = 0; i < code.length; i++) {
      final line = code[i];
      for (final e in _forbidden.entries) {
        if (e.value == _ownFont &&
            path == 'lib/common/widgets/nd/nd_icons.dart') {
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

/// The `<first> <second>` pairs of a list in tool/ (# starts a comment).
Map<String, String> _pairs(String path) => {
      for (final line in File(path).readAsLinesSync())
        if (line.split('#').first.trim().split(RegExp(r'\s+'))
            case [final a, final b, ...])
          a: b,
    };

String _camel(String snake) => snake.replaceAllMapped(
    RegExp(r'_([a-z0-9])'), (m) => m.group(1)!.toUpperCase());

/// Icons of [symbols] (dart name to glyph) named after a meaning of
/// [console] (meaning to glyph) that use another glyph than the console.
List<String> meaningMismatches(
    Map<String, String> symbols, Map<String, String> console) {
  final byDart = {for (final e in console.entries) _camel(e.key): e};
  return [
    for (final e in symbols.entries)
      if (byDart[e.key] case final c? when c.value != e.value)
        'NdIcons.${e.key} is ${e.value}, the console shows ${c.key} as ${c.value}',
  ];
}

/// Icons of tool/nd_symbols.txt that no source under lib/ names.
List<String> unusedIcons() {
  final used = <String>{};
  for (final (path, f) in _sources(Directory.current)) {
    if (path == 'lib/common/widgets/nd/nd_icons.dart') continue;
    used.addAll(RegExp(r'\bNdIcons\.(\w+)')
        .allMatches(f.readAsStringSync())
        .map((m) => m.group(1)!));
  }
  return [
    for (final name in _pairs('tool/nd_symbols.txt').keys)
      if (!used.contains(name)) '$name: in tool/nd_symbols.txt, not used',
  ];
}

void main() {
  test('icons named after a console meaning use the console glyph', () {
    final symbols = _pairs('tool/nd_symbols.txt');
    final console = _pairs('tool/console_icons.txt');
    expect(console, hasLength(greaterThan(50)));
    final findings = meaningMismatches(symbols, console);
    expect(findings, isEmpty, reason: findings.join('\n'));
    expect(
        meaningMismatches({'password': 'password', 'tags': 'sell'}, console),
        ['NdIcons.password is password, the console shows password as key']);
  });

  test('the font holds only icons the client uses', () {
    final findings = unusedIcons();
    expect(findings, isEmpty, reason: findings.join('\n'));
  });

  test('the sources draw icons only from NdIcons', () {
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
    expect(scanSources(base), unorderedEquals([
      'lib/mobile/page.dart:1: Material Icons: final a = Icon(Icons.close);',
      'lib/page.dart:2: Material Icons: final a = Icon(Icons.close);',
      'lib/page.dart:3: asset assets/close.svg',
      'lib/page.dart:4: SvgPicture.asset with a path from a variable',
    ]));
  });
}
