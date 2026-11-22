// Shared setup for the NeoDesk widget tests and screenshots.
//
// - Loads the fonts pubspec.yaml declares (Plex, Funnel Display, the icon
//   fonts) so text and icons render as in the app.
// - Translates with src/lang/en.rs or de.rs, the same tables the Rust side
//   uses, falling back to English and then to the key.
// - shot() pumps a screen at a window size in light or dark and, when
//   BD_SHOTS_DIR is set, writes it there as <name>-<theme>.png at 2x.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' show translateForTest;
import 'package:flutter_hbb/common/theme/bd_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// The font families of pubspec.yaml with their asset files.
Map<String, List<String>> _pubspecFonts() {
  final families = <String, List<String>>{};
  String? family;
  for (final line in File('pubspec.yaml').readAsLinesSync()) {
    final f = RegExp(r'^\s*- family:\s*(\S+)').firstMatch(line);
    final a = RegExp(r'^\s*- asset:\s*(\S+\.(?:ttf|otf))').firstMatch(line);
    if (f != null) {
      family = f.group(1)!;
      families[family] = [];
    } else if (a != null && family != null) {
      families[family]!.add(a.group(1)!);
    }
  }
  return families;
}

bool _fontsLoaded = false;

Future<void> loadBdFonts() async {
  if (_fontsLoaded) return;
  for (final e in _pubspecFonts().entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
  // Material Icons, for widgets that still use Icons.*.
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final f = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (f.existsSync()) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(
          Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await loader.load();
    }
  }
  _fontsLoaded = true;
}

Map<String, String> _readLang(String code) {
  final f = File('../src/lang/$code.rs');
  if (!f.existsSync()) return {};
  final text = f.readAsStringSync();
  final re = RegExp(r'^\s*\("((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\),',
      multiLine: true);
  final m = <String, String>{};
  for (final x in re.allMatches(text)) {
    String un(String s) => s
        .replaceAll(r'\"', '"')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\\', '\\');
    final v = un(x.group(2)!);
    if (v.isNotEmpty) m[un(x.group(1)!)] = v;
  }
  return m;
}

final _en = _readLang('en');
final _de = _readLang('de');

/// Translates like the Rust side for [lang] ('en' or 'de').
void useLanguage(String lang) {
  final table = lang == 'de' ? _de : const <String, String>{};
  translateForTest = (k) => table[k] ?? _en[k] ?? k;
}

String? get shotsDir => Platform.environment['BD_SHOTS_DIR'];

/// Builds [screen] in a window of [size] with the theme of [brightness]
/// (and an optional server [accent]) and keeps time still. [extra] adds
/// theme extensions, as the app does for its older widgets.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required Size size,
  Brightness brightness = Brightness.light,
  String? accent,
  String lang = 'en',
  Key? rootKey,
  List<ThemeExtension<dynamic>> Function(BdColors c)? extra,
}) async {
  await loadBdFonts();
  useLanguage(lang);
  BdTheme.setServerAccent(accent ?? '');
  BdTheme.setBrightnessForTest(brightness);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    BdTheme.setServerAccent('');
  });
  // The boundary holds the whole app, so menus and dialogs in the
  // overlay are in the picture too.
  await tester.pumpWidget(
    RepaintBoundary(
      key: rootKey ?? const ValueKey('bd-shot'),
      child: MediaQuery(
        data: MediaQueryData(
            size: size, devicePixelRatio: 2, disableAnimations: true),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: BdTheme.theme(brightness, desktop: true, extra: extra),
          home: Material(type: MaterialType.transparency, child: screen),
        ),
      ),
    ),
  );
  // SVG pictures and images decode outside the fake clock.
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
}

/// Writes the current frame as <name>-<light|dark>.png (2x) into
/// BD_SHOTS_DIR when it is set.
Future<void> shot(WidgetTester tester, String name, Brightness b,
    {Key? rootKey}) async {
  final dir = shotsDir;
  if (dir == null) return;
  final theme = b == Brightness.dark ? 'dark' : 'light';
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(rootKey ?? const ValueKey('bd-shot')));
  // Tests draw shadows hard; draw the real soft ones for the picture.
  debugDisableShadows = false;
  try {
    // Not awaited: it waits for a frame that only pump() produces here.
    // ignore: unawaited_futures
    tester.binding.reassembleApplication();
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name-$theme.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  } finally {
    debugDisableShadows = true;
  }
}

/// Runs [body] once in light and once in dark.
void forBothThemes(
    String description, Future<void> Function(WidgetTester, Brightness) body) {
  for (final b in Brightness.values) {
    testWidgets('$description (${b.name})', (tester) {
      useLanguage('en');
      BdTheme.setBrightnessForTest(b);
      return body(tester, b);
    });
  }
}
