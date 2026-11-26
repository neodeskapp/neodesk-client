// The NeoDesk theme: the one place in lib/ where colour values live.
//
// Every other file reads colours from [NdColors] (context.nd, or ndColors
// where no BuildContext is at hand). tool/check_colours.py fails the build
// when a colour literal shows up anywhere else.
//
// Values follow .ui-rework/go/launch/design/DESIGN.md (Tokens).

import 'dart:math' as math;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Colour tokens
// ---------------------------------------------------------------------------

class NdColors extends ThemeExtension<NdColors> {
  const NdColors({
    required this.brightness,
    required this.bg,
    required this.bgSubtle,
    required this.hover,
    required this.bgFloat,
    required this.titlebar,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.rule,
    required this.accent,
    required this.accentHover,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.dangerHover,
    required this.onDanger,
    required this.info,
    required this.canvas,
    required this.onCanvas,
    required this.scrim,
    required this.shadowFar,
    required this.shadowNear,
    required this.logoSquare,
    required this.logoCircle,
    required this.logoOverlap,
    required this.osWindows,
    required this.osLinux,
    required this.osApple,
    required this.avatar1,
    required this.avatar2,
    required this.avatar3,
    required this.windowCloseHover,
    required this.onWindowCloseHover,
    required this.white,
    required this.black,
  });

  final Brightness brightness;
  final Color bg;
  final Color bgSubtle;
  final Color hover;
  final Color bgFloat;
  final Color titlebar;
  final Color text;
  final Color textMuted;
  final Color border;
  final Color rule;
  final Color accent;
  final Color accentHover;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color dangerHover;
  final Color onDanger;
  final Color info;

  /// Around the remote screen, the same in both themes.
  final Color canvas;

  /// Text on [canvas] (connection states in the session window).
  final Color onCanvas;
  final Color scrim;

  /// The two layers of shadow-float.
  final Color shadowFar;
  final Color shadowNear;
  final Color logoSquare;
  final Color logoCircle;
  final Color logoOverlap;
  final Color osWindows;
  final Color osLinux;
  final Color osApple;
  final Color avatar1;
  final Color avatar2;
  final Color avatar3;

  /// The window close button when hovered (Windows look).
  final Color windowCloseHover;
  final Color onWindowCloseHover;

  /// Plain white and black for the few places that need exactly that
  /// (QR codes, video surfaces, image masks). Not for text or surfaces.
  final Color white;
  final Color black;

  bool get isDark => brightness == Brightness.dark;

  /// The selected segment, pressed toolbar button, chosen menu item.
  Color get accentTint => accent.withOpacity(0.14);

  /// The 9 % tone background of a notice, over [bg].
  Color noticeBg(Color tone) => Color.alphaBlend(tone.withOpacity(0.09), bg);

  /// A tone at 16 % (avatar backgrounds).
  Color tint16(Color tone) => tone.withOpacity(0.16);

  List<BoxShadow> get shadowFloat => isDark
      ? [
          BoxShadow(color: shadowFar, offset: Offset(0, 8), blurRadius: 28),
          BoxShadow(color: shadowNear, offset: Offset(0, 1), blurRadius: 3),
        ]
      : [
          BoxShadow(color: shadowFar, offset: Offset(0, 6), blurRadius: 24),
          BoxShadow(color: shadowNear, offset: Offset(0, 1), blurRadius: 3),
        ];

  List<Color> get avatars => [avatar1, avatar2, avatar3];

  static const light = NdColors(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    bgSubtle: Color(0xFFF3F4F4),
    hover: Color(0xFFE8EBEB),
    bgFloat: Color(0xFFFFFFFF),
    titlebar: Color(0xFFF3F4F4),
    text: Color(0xFF1B1E1F),
    textMuted: Color(0xFF566064),
    border: Color(0xFF7E888B),
    rule: Color(0xFFDDE1E2),
    accent: Color(0xFF1B62CF),
    accentHover: Color(0xFF1854B3),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF1C7A3B),
    warning: Color(0xFF875B00),
    danger: Color(0xFFB3261E),
    dangerHover: Color(0xFF8C1D17),
    onDanger: Color(0xFFFFFFFF),
    info: Color(0xFF4A5A62),
    canvas: Color(0xFF0B0C0C),
    onCanvas: Color(0xFFE4E7E7),
    scrim: Color(0x731B1E1F),
    shadowFar: Color(0x24000000),
    shadowNear: Color(0x1A000000),
    logoSquare: Color(0xFF1F6FEB),
    logoCircle: Color(0xFF4D8F06),
    logoOverlap: Color(0xFF0F9E96),
    osWindows: Color(0xFF0067C0),
    osLinux: Color(0xFF8F6D00),
    osApple: Color(0xFF68717A),
    avatar1: Color(0xFF1858B8),
    avatar2: Color(0xFF974614),
    avatar3: Color(0xFF08655F),
    windowCloseHover: Color(0xFFC42B1C),
    onWindowCloseHover: Color(0xFFFFFFFF),
    white: Color(0xFFFFFFFF),
    black: Color(0xFF000000),
  );

  static const dark = NdColors(
    brightness: Brightness.dark,
    bg: Color(0xFF141616),
    bgSubtle: Color(0xFF1B1E1E),
    hover: Color(0xFF262A2A),
    bgFloat: Color(0xFF1F2323),
    titlebar: Color(0xFF1B1E1E),
    text: Color(0xFFE4E7E7),
    textMuted: Color(0xFFA3ABAD),
    border: Color(0xFF6A7474),
    rule: Color(0xFF2C3131),
    accent: Color(0xFF58A6FF),
    accentHover: Color(0xFF79B8FF),
    onAccent: Color(0xFF0C1B1E),
    success: Color(0xFF72C98C),
    warning: Color(0xFFE3B85A),
    danger: Color(0xFFFF8F80),
    dangerHover: Color(0xFFFFABA0),
    onDanger: Color(0xFF0C1B1E),
    info: Color(0xFFA9BCC4),
    canvas: Color(0xFF0B0C0C),
    onCanvas: Color(0xFFE4E7E7),
    scrim: Color(0x99000000),
    shadowFar: Color(0x80000000),
    shadowNear: Color(0x66000000),
    logoSquare: Color(0xFF58A6FF),
    logoCircle: Color(0xFFA3E635),
    logoOverlap: Color(0xFF3FD0C4),
    osWindows: Color(0xFF4CC2FF),
    osLinux: Color(0xFFD9AD3C),
    osApple: Color(0xFF9AA4A8),
    avatar1: Color(0xFF79B8FF),
    avatar2: Color(0xFFF0A070),
    avatar3: Color(0xFF4FD1C5),
    windowCloseHover: Color(0xFFC42B1C),
    onWindowCloseHover: Color(0xFFFFFFFF),
    white: Color(0xFFFFFFFF),
    black: Color(0xFF000000),
  );

  /// These tokens with a server's accent colour run through [deriveAccent].
  /// A null or unreadable [hex] keeps the brand blue.
  NdColors withServerAccent(String? hex) {
    final input = parseHexColor(hex ?? '');
    if (input == null) return this;
    final a = deriveAccent(input, this, brightness);
    return copyWith(accent: a.accent, accentHover: a.hover, onAccent: a.onAccent)
        as NdColors;
  }

  @override
  ThemeExtension<NdColors> copyWith({
    Color? accent,
    Color? accentHover,
    Color? onAccent,
  }) {
    return NdColors(
      brightness: brightness,
      bg: bg,
      bgSubtle: bgSubtle,
      hover: hover,
      bgFloat: bgFloat,
      titlebar: titlebar,
      text: text,
      textMuted: textMuted,
      border: border,
      rule: rule,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      onAccent: onAccent ?? this.onAccent,
      success: success,
      warning: warning,
      danger: danger,
      dangerHover: dangerHover,
      onDanger: onDanger,
      info: info,
      canvas: canvas,
      onCanvas: onCanvas,
      scrim: scrim,
      shadowFar: shadowFar,
      shadowNear: shadowNear,
      logoSquare: logoSquare,
      logoCircle: logoCircle,
      logoOverlap: logoOverlap,
      osWindows: osWindows,
      osLinux: osLinux,
      osApple: osApple,
      avatar1: avatar1,
      avatar2: avatar2,
      avatar3: avatar3,
      windowCloseHover: windowCloseHover,
      onWindowCloseHover: onWindowCloseHover,
      white: white,
      black: black,
    );
  }

  @override
  ThemeExtension<NdColors> lerp(ThemeExtension<NdColors>? other, double t) {
    // Theme changes are instant (no animated colour lerp).
    if (other is! NdColors) return this;
    return t < 0.5 ? this : other;
  }

  static NdColors of(BuildContext context) =>
      Theme.of(context).extension<NdColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
}

extension NdContext on BuildContext {
  NdColors get nd => NdColors.of(this);
  NdText get ndText => NdText.of(this);
}

/// `#RRGGBB` or `#AARRGGBB` (leading `#` optional), or null.
Color? parseHexColor(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(v);
}

/// The palette of the window being drawn, for code without a BuildContext.
/// The app's builder keeps it in step with the theme (see [NdTheme.track]).
NdColors get ndColors => NdTheme.current;

// ---------------------------------------------------------------------------
// Server accent rule (port of deriveAccent() in tools/colour.mjs)
// ---------------------------------------------------------------------------

class Oklch {
  final double l, c, h;
  const Oklch(this.l, this.c, this.h);
}

double _lin(int c) {
  final v = c / 255;
  return v <= 0.04045
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

double _gam(double v) =>
    (v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055) * 255;

double _cbrt(double x) =>
    x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

Oklch toOklch(Color c) {
  final r = _lin(c.red), g = _lin(c.green), b = _lin(c.blue);
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  final L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  final A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  final B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return Oklch(L, math.sqrt(A * A + B * B), math.atan2(B, A));
}

Color fromOklch(double L, double C, double H) {
  var c = C;
  for (var i = 0; i < 60; i++) {
    final a = c * math.cos(H), b = c * math.sin(H);
    final l = math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
    final m = math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
    final s = math.pow(L - 0.0894841775 * a - 1.291485548 * b, 3).toDouble();
    final rgb = [
      4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
    ];
    if (rgb.every((v) => v >= -0.0005 && v <= 1.0005) || c < 0.0005) {
      int ch(double v) => _gam(v.clamp(0.0, 1.0)).round().clamp(0, 255);
      return Color.fromARGB(255, ch(rgb[0]), ch(rgb[1]), ch(rgb[2]));
    }
    c *= 0.93;
  }
  return fromOklch(L, 0, H);
}

double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const _inkLight = Color(0xFFFFFFFF), _inkDark = Color(0xFF0C1B1E);

/// Turns a server's accent into accent, hover and ink for one theme, so it
/// reaches 4.5:1 as text on every surface and carries 4.5:1 ink.
({Color accent, Color hover, Color onAccent}) deriveAccent(
    Color input, NdColors t, Brightness mode) {
  final surfaces = [t.bg, t.bgSubtle, t.bgFloat];
  final dir = mode == Brightness.light ? -1 : 1;
  final o = toOklch(input);
  var L = o.l;
  late Color acc;
  Color ink(Color c) => contrastRatio(c, _inkLight) >= contrastRatio(c, _inkDark)
      ? _inkLight
      : _inkDark;
  for (var i = 0; i < 100; i++) {
    acc = fromOklch(L, o.c, o.h);
    final asText = surfaces.map((s) => contrastRatio(acc, s)).reduce(math.min);
    if (asText >= 4.5 && contrastRatio(acc, ink(acc)) >= 4.5) break;
    L = (L + dir * 0.01).clamp(0.0, 1.0);
  }
  final on = ink(acc);
  var hover = fromOklch((L + dir * 0.06).clamp(0.0, 1.0), o.c, o.h);
  if (hover == acc || contrastRatio(hover, on) < 4.5) {
    hover = fromOklch((L - dir * 0.06).clamp(0.0, 1.0), o.c, o.h);
  }
  if (contrastRatio(hover, on) < 4.5) hover = acc;
  return (accent: acc, hover: hover, onAccent: on);
}

// ---------------------------------------------------------------------------
// Type
// ---------------------------------------------------------------------------

const kNdFontSans = 'IBMPlexSans';
const kNdFontMono = 'IBMPlexMono';
const kNdFontDisplay = 'FunnelDisplay';
const kNdSansFallback = <String>['Segoe UI', 'Noto Sans', 'sans-serif'];
const kNdMonoFallback = <String>['Consolas', 'Menlo', 'monospace'];
const kNdDisplayFallback = <String>[kNdFontSans, 'Segoe UI', 'Noto Sans'];

class NdText extends ThemeExtension<NdText> {
  const NdText({
    required this.display,
    required this.title,
    required this.titleMd,
    required this.heading,
    required this.lead,
    required this.body,
    required this.label,
    required this.small,
    required this.caption,
    required this.id,
    required this.password,
    required this.mono,
  });

  final TextStyle display;
  final TextStyle title;
  final TextStyle titleMd;
  final TextStyle heading;
  final TextStyle lead;
  final TextStyle body;
  final TextStyle label;
  final TextStyle small;
  final TextStyle caption;
  final TextStyle id;
  final TextStyle password;
  final TextStyle mono;

  static TextStyle _s(double size, double line, FontWeight w, Color color,
          {String family = kNdFontSans,
          List<String> fallback = kNdSansFallback,
          double spacingEm = 0}) =>
      TextStyle(
        inherit: false,
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: line / size,
        fontWeight: w,
        letterSpacing: spacingEm * size,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
        textBaseline: TextBaseline.alphabetic,
        decoration: TextDecoration.none,
      );

  factory NdText.from(NdColors c) => NdText(
        display: _s(44, 48, FontWeight.w700, c.text,
            family: kNdFontDisplay,
            fallback: kNdDisplayFallback,
            spacingEm: -0.03),
        title: _s(28, 34, FontWeight.w700, c.text,
            family: kNdFontDisplay,
            fallback: kNdDisplayFallback,
            spacingEm: -0.02),
        titleMd: _s(22, 28, FontWeight.w700, c.text,
            family: kNdFontDisplay,
            fallback: kNdDisplayFallback,
            spacingEm: -0.015),
        heading: _s(16, 22, FontWeight.w600, c.text),
        lead: _s(16, 24, FontWeight.w400, c.textMuted),
        body: _s(14, 20, FontWeight.w400, c.text),
        label: _s(14, 20, FontWeight.w500, c.text),
        small: _s(13, 18, FontWeight.w400, c.textMuted),
        caption: _s(12, 16, FontWeight.w400, c.textMuted),
        id: _s(30, 36, FontWeight.w600, c.text,
            family: kNdFontMono, fallback: kNdMonoFallback, spacingEm: 0.02),
        password: _s(22, 28, FontWeight.w600, c.text,
            family: kNdFontMono, fallback: kNdMonoFallback, spacingEm: 0.06),
        mono: _s(13, 18, FontWeight.w400, c.text,
            family: kNdFontMono, fallback: kNdMonoFallback),
      );

  static NdText of(BuildContext context) =>
      Theme.of(context).extension<NdText>() ??
      NdText.from(NdColors.of(context));

  @override
  ThemeExtension<NdText> copyWith() => this;

  @override
  ThemeExtension<NdText> lerp(ThemeExtension<NdText>? other, double t) =>
      other is NdText && t >= 0.5 ? other : this;
}

// ---------------------------------------------------------------------------
// Sizes
// ---------------------------------------------------------------------------

class NdSize {
  NdSize._();
  static const double radius = 4;
  static const double radiusSm = 3;
  static const double controlSm = 30;
  static const double control = 36;
  static const double controlLg = 44;
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 24, s6 = 32;
  static const double s7 = 48, s8 = 64;
  static const Duration motion = Duration(milliseconds: 120);
  static const Duration dialogMotion = Duration(milliseconds: 150);
  static const BorderRadius r = BorderRadius.all(Radius.circular(radius));
}

// ---------------------------------------------------------------------------
// Material theme built from the tokens
// ---------------------------------------------------------------------------

class NdTheme {
  NdTheme._();

  static NdColors _light = NdColors.light;
  static NdColors _dark = NdColors.dark;
  static Brightness _brightness = Brightness.light;
  static String _accentHex = '';

  /// The palette of the current window, for code without a BuildContext.
  static NdColors get current =>
      _brightness == Brightness.dark ? _dark : _light;

  static NdColors get lightColors => _light;
  static NdColors get darkColors => _dark;

  /// Applies a server's accent (hex, empty for none) to both palettes.
  /// Returns true when it changed anything.
  static bool setServerAccent(String hex) {
    final h = hex.trim();
    if (h == _accentHex) return false;
    _accentHex = h;
    _light = NdColors.light.withServerAccent(h);
    _dark = NdColors.dark.withServerAccent(h);
    _cache.clear();
    return true;
  }

  /// Called from the app's builder so [current] follows the shown theme.
  static void track(BuildContext context) {
    _brightness = Theme.of(context).brightness;
  }

  @visibleForTesting
  static void setBrightnessForTest(Brightness b) => _brightness = b;

  static final Map<String, ThemeData> _cache = {};

  /// The light or dark ThemeData; [desktop] picks the flat desktop controls,
  /// [extra] adds theme extensions built from the same tokens.
  static ThemeData theme(Brightness brightness,
      {required bool desktop,
      List<ThemeExtension<dynamic>> Function(NdColors c)? extra}) {
    final key = '$brightness-$desktop-$_accentHex-${extra != null}';
    return _cache[key] ??= build(
        brightness == Brightness.dark ? _dark : _light,
        desktop: desktop,
        extra: extra);
  }

  static ThemeData build(NdColors c,
      {required bool desktop,
      List<ThemeExtension<dynamic>> Function(NdColors c)? extra}) {
    final t = NdText.from(c);
    final dark = c.isDark;
    final shape = RoundedRectangleBorder(borderRadius: NdSize.r);
    final fieldBorder = OutlineInputBorder(
      borderRadius: NdSize.r,
      borderSide: BorderSide(color: c.border, width: 1),
    );
    final scheme = (dark ? ColorScheme.dark() : ColorScheme.light()).copyWith(
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accent,
      onSecondary: c.onAccent,
      surface: c.bg,
      onSurface: c.text,
      error: c.danger,
      onError: c.onDanger,
      outline: c.border,
      outlineVariant: c.rule,
      surfaceContainerHighest: c.bgSubtle,
      onSurfaceVariant: c.textMuted,
      shadow: c.shadowFar,
      scrim: c.scrim,
    );
    TextStyle m(TextStyle s) => s.copyWith(inherit: true);
    final textTheme = TextTheme(
      displayLarge: m(t.display),
      displayMedium: m(t.display),
      displaySmall: m(t.title),
      headlineLarge: m(t.title),
      headlineMedium: m(t.titleMd),
      headlineSmall: m(t.titleMd),
      titleLarge: m(t.heading.copyWith(fontSize: 18, height: 24 / 18)),
      titleMedium: m(t.heading),
      titleSmall: m(t.label),
      bodyLarge: m(t.body.copyWith(fontSize: 15, height: 22 / 15)),
      bodyMedium: m(t.body),
      bodySmall: m(t.small.copyWith(color: c.textMuted)),
      labelLarge: m(t.label),
      labelMedium: m(t.small.copyWith(fontWeight: FontWeight.w500)),
      labelSmall: m(t.caption),
    );
    final noSplash = desktop ? NoSplash.splashFactory : null;
    // Keyboard focus on Material controls: a 2 px outline, as NdFocusRing
    // draws on the NeoDesk controls. The fills alone (focusColor, hover) are
    // under 3:1 against the surface. On an accent fill the outline is an
    // inner ring in the ink colour, which stands out from the fill.
    WidgetStateProperty<BorderSide?> focusSide(BorderSide? rest,
            {Color? color}) =>
        WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused)
            ? BorderSide(color: color ?? c.accent, width: 2)
            : rest);
    return ThemeData(
      useMaterial3: false,
      brightness: c.brightness,
      fontFamily: kNdFontSans,
      fontFamilyFallback: kNdSansFallback,
      colorScheme: scheme,
      primaryColor: c.accent,
      canvasColor: c.bg,
      scaffoldBackgroundColor: c.bg,
      dialogBackgroundColor: c.bgFloat,
      cardColor: c.bgSubtle,
      dividerColor: c.rule,
      hoverColor: c.hover,
      focusColor: c.accentTint,
      highlightColor: desktop ? Colors.transparent : null,
      splashColor: desktop ? Colors.transparent : null,
      splashFactory: noSplash,
      hintColor: c.textMuted,
      disabledColor: c.textMuted,
      unselectedWidgetColor: c.border,
      indicatorColor: c.accent,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: c.text, size: 20),
      primaryIconTheme: IconThemeData(color: c.onAccent, size: 20),
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: c.titlebar,
        foregroundColor: c.text,
        elevation: 0,
        shadowColor: Colors.transparent,
        iconTheme: IconThemeData(color: c.text),
        titleTextStyle: m(t.heading),
      ),
      dividerTheme: DividerThemeData(color: c.rule, thickness: 1),
      dialogTheme: DialogTheme(
        backgroundColor: c.bgFloat,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: NdSize.r, side: BorderSide(color: c.rule)),
        titleTextStyle: m(t.titleMd),
        contentTextStyle: m(t.body),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.bgFloat,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: c.shadowFar,
        textStyle: m(t.body),
        shape: RoundedRectangleBorder(
            borderRadius: NdSize.r, side: BorderSide(color: c.rule)),
      ),
      menuTheme: MenuThemeData(style: _menuStyle(c)),
      menuBarTheme: MenuBarThemeData(style: _menuStyle(c)),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12)),
          textStyle: WidgetStatePropertyAll(m(t.body)),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.disabled) ? c.textMuted : c.text),
          iconColor: WidgetStatePropertyAll(c.textMuted),
          overlayColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.hovered) ||
                      s.contains(WidgetState.focused)
                  ? c.hover
                  : null),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.hovered) ||
                      s.contains(WidgetState.focused)
                  ? c.hover
                  : Colors.transparent),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
          side: focusSide(null),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 800),
        textStyle: m(t.small.copyWith(color: c.bg)),
        decoration: BoxDecoration(color: c.text, borderRadius: NdSize.r),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        crossAxisMargin: 3,
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.dragged)) return c.text;
          if (s.contains(WidgetState.hovered)) return c.textMuted;
          return c.border.withOpacity(0.7);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: false,
        fillColor: c.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        hintStyle: m(t.body.copyWith(color: c.textMuted)),
        labelStyle: m(t.body.copyWith(color: c.textMuted)),
        floatingLabelStyle: m(t.small.copyWith(color: c.accent)),
        helperStyle: m(t.small),
        errorStyle: m(t.small.copyWith(color: c.danger)),
        prefixIconColor: c.textMuted,
        suffixIconColor: c.textMuted,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        disabledBorder: fieldBorder.copyWith(
            borderSide: BorderSide(color: c.border.withOpacity(0.45))),
        focusedBorder: fieldBorder.copyWith(
            borderSide: BorderSide(color: c.accent, width: 2)),
        errorBorder:
            fieldBorder.copyWith(borderSide: BorderSide(color: c.danger)),
        focusedErrorBorder: fieldBorder.copyWith(
            borderSide: BorderSide(color: c.danger, width: 2)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.text,
        selectionColor: c.accent.withOpacity(0.3),
        selectionHandleColor: c.accent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.accent.withOpacity(0.45),
          disabledForegroundColor: c.onAccent.withOpacity(0.8),
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(0, NdSize.control),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: m(t.label),
          shape: shape,
          splashFactory: noSplash,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) {
              return c.accent.withOpacity(0.45);
            }
            if (s.contains(WidgetState.hovered)) return c.accentHover;
            return c.accent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: focusSide(null, color: c.onAccent),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          disabledForegroundColor: c.text.withOpacity(0.45),
          backgroundColor: Colors.transparent,
          side: BorderSide(color: c.border),
          minimumSize: const Size(0, NdSize.control),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: m(t.label),
          shape: shape,
          splashFactory: noSplash,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.hovered) ? c.hover : Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: focusSide(BorderSide(color: c.border)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          disabledForegroundColor: c.textMuted,
          minimumSize: const Size(0, NdSize.control),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: m(t.label),
          shape: shape,
          splashFactory: noSplash,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.hovered) ? c.hover : Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: focusSide(null),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textMuted,
          hoverColor: c.hover,
          shape: shape,
          splashFactory: noSplash,
        ).copyWith(side: focusSide(null)),
      ),
      checkboxTheme: CheckboxThemeData(
        splashRadius: desktop ? 0 : kRadialReactionRadius,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NdSize.radiusSm)),
        side: WidgetStateBorderSide.resolveWith((s) =>
            s.contains(WidgetState.focused)
                ? BorderSide(color: c.text, width: 2)
                : BorderSide(color: c.border)),
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? c.accent : Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.onAccent),
      ),
      radioTheme: RadioThemeData(
        splashRadius: desktop ? 0 : kRadialReactionRadius,
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? c.accent : c.border),
      ),
      switchTheme: SwitchThemeData(
        splashRadius: desktop ? 0 : kRadialReactionRadius,
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? c.accent : c.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? c.accent.withOpacity(0.45)
                : c.rule),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accent,
        inactiveTrackColor: c.rule,
        thumbColor: c.accent,
        overlayColor: c.accentTint,
        valueIndicatorColor: c.text,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.rule,
        circularTrackColor: c.rule,
      ),
      tabBarTheme: TabBarTheme(
        labelColor: c.text,
        unselectedLabelColor: c.textMuted,
        labelStyle: m(t.label),
        unselectedLabelStyle: m(t.label),
        indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: c.accent, width: 2)),
        dividerColor: c.rule,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textMuted,
        textColor: c.text,
        selectedColor: c.text,
        selectedTileColor: c.hover,
        shape: shape,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.bgSubtle,
        labelStyle: m(t.small.copyWith(color: c.text)),
        side: BorderSide(color: c.rule),
        shape: shape,
      ),
      cardTheme: CardTheme(
        color: c.bgSubtle,
        elevation: 0,
        shape: shape,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.bgFloat,
        contentTextStyle: m(t.body),
        shape: RoundedRectangleBorder(
            borderRadius: NdSize.r, side: BorderSide(color: c.rule)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: c.bgFloat, modalBackgroundColor: c.bgFloat),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.bg,
        selectedItemColor: c.accent,
        unselectedItemColor: c.textMuted,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
      ),
      extensions: [c, t, ...(extra?.call(c) ?? const [])],
    );
  }

  static MenuStyle _menuStyle(NdColors c) => MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.bgFloat),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(c.shadowFar),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: NdSize.r, side: BorderSide(color: c.rule))),
      );
}

// ---------------------------------------------------------------------------
// Fixed colour sets that are data rather than theme roles
// ---------------------------------------------------------------------------

/// Chip colours of the old password rules list and the peer tag palette.
class NdPalette {
  NdPalette._();

  /// Tag colours offered when someone colours an address book tag.
  static const tagColors = <Color>[
    Color(0xFF1B62CF),
    Color(0xFF1C7A3B),
    Color(0xFF875B00),
    Color(0xFFB3261E),
    Color(0xFF6D3FB5),
    Color(0xFF08655F),
    Color(0xFF974614),
    Color(0xFF566064),
  ];

  /// Colours for tags named after a colour ("red", "teal", ...). Tags with
  /// other names get one of these, picked by a hash in this order. The values
  /// match what other RustDesk clients store in a shared address book.
  static const tagColorsByName = <String, Color>{
    'red': Color(0xFFF44336),
    'green': Color(0xFF4CAF50),
    'blue': Color(0xFF2196F3),
    'orange': Color(0xFFFF9800),
    'purple': Color(0xFF9C27B0),
    'grey': Color(0xFF9E9E9E),
    'cyan': Color(0xFF00BCD4),
    'lime': Color(0xFFCDDC39),
    'teal': Color(0xFF009688),
    'pink': Color(0xFFF48FB1),
    'indigo': Color(0xFF3F51B5),
    'brown': Color(0xFF795548),
  };

  /// A tag named "yellow". Not used for hashed names.
  static const tagYellow = Color(0xFFFFEB3B);

  /// Text and marks drawn over a data colour: a selected tag chip on its
  /// tag colour, an initial on an avatar's name colour (str2color).
  static const onDataColor = Color(0xFFFFFFFF);

  /// The xterm palette for the terminal: [0..15] ANSI colours, then
  /// foreground, background, cursor, selection.
  static const terminalDark = <Color>[
    Color(0xFF141616), Color(0xFFFF8F80), Color(0xFF72C98C), Color(0xFFE3B85A),
    Color(0xFF58A6FF), Color(0xFFC792EA), Color(0xFF3FD0C4), Color(0xFFE4E7E7),
    Color(0xFF6A7474), Color(0xFFFFABA0), Color(0xFF9BE0AE), Color(0xFFF2D08A),
    Color(0xFF79B8FF), Color(0xFFDDB6F2), Color(0xFF7FE3D8), Color(0xFFFFFFFF),
    Color(0xFFE4E7E7), Color(0xFF141616), Color(0xFFE4E7E7), Color(0x6658A6FF),
  ];

  static const terminalLight = <Color>[
    Color(0xFF1B1E1F), Color(0xFFB3261E), Color(0xFF1C7A3B), Color(0xFF875B00),
    Color(0xFF1B62CF), Color(0xFF6D3FB5), Color(0xFF08655F), Color(0xFFDDE1E2),
    Color(0xFF566064), Color(0xFF8C1D17), Color(0xFF15602E), Color(0xFF6B4800),
    Color(0xFF1854B3), Color(0xFF55308F), Color(0xFF064E49), Color(0xFFFFFFFF),
    Color(0xFF1B1E1F), Color(0xFFFFFFFF), Color(0xFF1B1E1F), Color(0x551B62CF),
  ];
}
