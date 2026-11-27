import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/consts.dart' show kCommConfKeyLang;
import 'package:flutter_hbb/models/platform_model.dart' show bind, localeName;

import '../../theme/nd_theme.dart';
import 'nd_button.dart';
import 'nd_pressable.dart';
import 'nd_icons.dart';
import 'nd_misc.dart';

/// translate() with {} placeholders filled from [args] in order.
String tr(String key, [List<Object?> args = const []]) {
  var s = translate(key);
  for (final a in args) {
    s = s.replaceFirst('{}', '${a ?? ''}');
  }
  return s;
}

/// A page of the NeoDesk docs at neode.sk, in German when the app speaks German.
String ndDocsUrl(String path) {
  var lang = bind.mainGetLocalOption(key: kCommConfKeyLang);
  if (lang.isEmpty || lang == 'default') lang = localeName;
  final prefix = lang.toLowerCase().startsWith('de') ? '/de' : '';
  return 'https://docs.neode.sk$prefix/$path';
}

class NdWindowTab {
  const NdWindowTab({
    required this.label,
    this.icon,
    this.leading,
    this.selected = false,
    this.onTap,
    this.onClose,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
}

/// The window's three buttons (Windows layout, also used on Linux when the
/// window manager draws none). 46 x 40, close hovers red.
class NdWindowControls extends StatelessWidget {
  const NdWindowControls({
    super.key,
    this.onMinimize,
    this.onMaximize,
    this.onClose,
    this.maximized = false,
    this.height = 40,
  });

  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final VoidCallback? onClose;
  final bool maximized;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (onMinimize != null)
        NdWinButton(
            glyph: NdWinGlyph.minimize,
            tooltip: translate('Minimize'),
            onTap: onMinimize,
            height: height),
      if (onMaximize != null)
        NdWinButton(
            glyph: maximized ? NdWinGlyph.restore : NdWinGlyph.maximize,
            tooltip: translate(maximized ? 'Restore' : 'Maximize'),
            onTap: onMaximize,
            height: height),
      if (onClose != null)
        NdWinButton(
            glyph: NdWinGlyph.close,
            tooltip: translate('Close'),
            onTap: onClose,
            height: height,
            isClose: true),
    ]);
  }
}

enum NdWinGlyph { minimize, maximize, restore, close }

/// The window buttons' glyphs: 10 px with a 1 px line, as Windows draws
/// its own, so the four have the same size and weight. Icon fonts draw a
/// short heavy dash, a large thin square and a mid-size cross.
class NdWinGlyphPainter extends CustomPainter {
  const NdWinGlyphPainter(this.glyph, this.color);
  final NdWinGlyph glyph;
  final Color color;

  static const double size = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Straight lines sit on half pixels so they cover whole pixels.
    switch (glyph) {
      case NdWinGlyph.minimize:
        canvas.drawLine(const Offset(0, 4.5), const Offset(10, 4.5), p);
      case NdWinGlyph.maximize:
        canvas.drawRect(const Rect.fromLTRB(0.5, 0.5, 9.5, 9.5), p);
      case NdWinGlyph.restore:
        canvas.drawRect(const Rect.fromLTRB(0.5, 2.5, 7.5, 9.5), p);
        canvas.drawPath(
            Path()
              ..moveTo(2.5, 2.5)
              ..lineTo(2.5, 0.5)
              ..lineTo(9.5, 0.5)
              ..lineTo(9.5, 7.5)
              ..lineTo(7.5, 7.5),
            p);
      case NdWinGlyph.close:
        p.isAntiAlias = true;
        canvas.drawLine(Offset.zero, const Offset(10, 10), p);
        canvas.drawLine(const Offset(10, 0), const Offset(0, 10), p);
    }
  }

  @override
  bool shouldRepaint(NdWinGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

/// One window button, 46 x [height]; the close button hovers red.
class NdWinButton extends StatefulWidget {
  const NdWinButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onTap,
    required this.height,
    this.isClose = false,
  });

  final NdWinGlyph glyph;
  final String tooltip;
  final VoidCallback? onTap;
  final double height;
  final bool isClose;

  @override
  State<NdWinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<NdWinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final bg = _hover
        ? (widget.isClose ? c.windowCloseHover : c.hover)
        : Colors.transparent;
    final fg = widget.onTap == null
        ? c.textMuted
        : (_hover && widget.isClose ? c.onWindowCloseHover : c.text);
    return NdPressable(
      label: widget.tooltip,
      ringOutset: 0,
      onHover: (v) => setState(() => _hover = v),
      onPressed: widget.onTap,
      child: Tooltip(
        message: widget.tooltip,
        excludeFromSemantics: true,
        waitDuration: const Duration(seconds: 1),
        child: Container(
          width: 46,
          height: widget.height,
          color: bg,
          alignment: Alignment.center,
          child: CustomPaint(
            size: const Size.square(NdWinGlyphPainter.size),
            painter: NdWinGlyphPainter(widget.glyph, fg),
          ),
        ),
      ),
    );
  }
}

/// The free part of a custom title bar. All of it moves the window, also
/// where nothing is drawn (the gap between the brand and the buttons, and
/// above and below the brand: it takes the bar's full height), and takes
/// taps for a double click to maximise. Widgets inside it that handle taps
/// themselves (tabs) keep them. Needs a bar of bounded height.
class NdTitleDragArea extends StatelessWidget {
  const NdTitleDragArea({
    super.key,
    required this.onDragStart,
    this.onTap,
    this.onDragCancel,
    this.onDragEnd,
    required this.child,
  });

  final VoidCallback onDragStart;
  final VoidCallback? onTap;
  final VoidCallback? onDragCancel;
  final VoidCallback? onDragEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: (_) => onDragStart(),
      onPanCancel: onDragCancel,
      onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
      child: SizedBox(height: double.infinity, child: child),
    );
  }
}

/// The 40 px title bar: brand at the start, tabs when more than one page is
/// open, then [actions] and the window controls.
class NdTitleBar extends StatelessWidget {
  const NdTitleBar({
    super.key,
    required this.brand,
    this.tabs = const [],
    this.actions = const [],
    this.controls,
    this.height = 40,
  });

  final Widget brand;
  final List<NdWindowTab> tabs;
  final List<Widget> actions;
  final Widget? controls;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.titlebar,
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 12),
            child: Center(child: brand),
          ),
          for (var i = 0; i < tabs.length; i++)
            _TitleTab(tab: tabs[i], first: i == 0),
          const Spacer(),
          ...actions,
          if (actions.isNotEmpty) const SizedBox(width: 8),
          if (controls != null) controls!,
        ],
      ),
    );
  }
}

class _TitleTab extends StatefulWidget {
  const _TitleTab({required this.tab, required this.first});
  final NdWindowTab tab;
  final bool first;

  @override
  State<_TitleTab> createState() => _TitleTabState();
}

class _TitleTabState extends State<_TitleTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final tab = widget.tab;
    final sel = tab.selected;
    void move(TraversalDirection d) =>
        FocusManager.instance.primaryFocus?.focusInDirection(d);
    // A page tab: Tab or Left / Right to reach it, Enter to open it,
    // Ctrl+W to close it.
    return NdPressable(
      label: tab.label,
      keepChildSemantics: true,
      selected: sel,
      ringOutset: 0,
      onHover: (v) => setState(() => _hover = v),
      onPressed: tab.onTap,
      keys: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            move(TraversalDirection.right),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            move(TraversalDirection.left),
        if (tab.onClose != null)
          const SingleActivator(LogicalKeyboardKey.keyW, control: true):
              tab.onClose!,
      },
      child: Transform.translate(
          offset: Offset(0, sel ? 1 : 0),
          child: Container(
            constraints: const BoxConstraints(minWidth: 120),
            padding: const EdgeInsets.only(left: 14, right: 10),
            decoration: BoxDecoration(
              color: sel ? c.bg : (_hover ? c.hover : Colors.transparent),
              border: Border(
                left: widget.first
                    ? BorderSide(color: c.rule)
                    : BorderSide.none,
                right: BorderSide(color: c.rule),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tab.leading != null)
                  tab.leading!
                else if (tab.icon != null)
                  Icon(tab.icon, size: 16, color: c.textMuted),
                if (tab.leading != null || tab.icon != null)
                  const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Text(tab.label,
                      style: t.label.copyWith(
                          fontSize: 13,
                          height: 18 / 13,
                          color: sel ? c.text : c.textMuted)),
                ),
                if (tab.onClose != null) ...[
                  const SizedBox(width: 6),
                  NdIconButton(
                    icon: NdIcons.close,
                    tooltip: '${translate('Close')} ${tab.label}',
                    size: 24,
                    iconSize: 16,
                    onPressed: tab.onClose,
                  ),
                ] else
                  const SizedBox(width: 4),
              ],
            ),
          ),
        ),
    );
  }
}

/// A text button in the title bar (Settings, Back).
class NdTitleBarText extends StatefulWidget {
  const NdTitleBarText(
      {super.key, required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<NdTitleBarText> createState() => _NdTitleBarTextState();
}

class _NdTitleBarTextState extends State<NdTitleBarText> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Center(
      child: NdPressable(
        label: widget.label,
        onHover: (v) => setState(() => _hover = v),
        onPressed: widget.onTap,
        child: Container(
            constraints: const BoxConstraints(minHeight: 30),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? c.hover : Colors.transparent,
              borderRadius: NdSize.r,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: c.text),
                const SizedBox(width: 6),
              ],
              Text(widget.label,
                  style: t.label.copyWith(fontSize: 13, height: 18 / 13)),
            ]),
          ),
      ),
    );
  }
}

/// The brand at the start of the title bar: the server's logo and name
/// when the branding has them, otherwise the NeoDesk mark (and wordmark
/// when [wordmark]).
class NdTitleBrand extends StatelessWidget {
  const NdTitleBrand({
    super.key,
    this.wordmark = true,
    this.serverLogo,
    this.serverName,
    this.title,
  });

  final bool wordmark;
  final Widget? serverLogo;
  final String? serverName;

  /// Small windows show their name after the mark (Quick Support).
  final String? title;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    if (serverName != null && serverName!.isNotEmpty) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        if (serverLogo != null) ...[
          SizedBox(height: 18, width: 18, child: serverLogo),
          const SizedBox(width: 8),
        ],
        Text(serverName!,
            style: t.label.copyWith(fontWeight: FontWeight.w600)),
      ]);
    }
    if (title != null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const NdLogoMark(size: 18),
        const SizedBox(width: 8),
        Text(title!, style: t.label.copyWith(fontWeight: FontWeight.w500)),
      ]);
    }
    return wordmark ? const NdWordmark(height: 18) : const NdLogoMark(size: 18);
  }
}

/// A window drawn by the app: title bar on top, page below on bg.
class NdWindowFrame extends StatelessWidget {
  const NdWindowFrame({super.key, required this.titleBar, required this.child});
  final Widget titleBar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.nd.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [titleBar, Expanded(child: child)],
      ),
    );
  }
}
