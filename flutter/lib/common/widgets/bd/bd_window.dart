import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;

import '../../theme/bd_theme.dart';
import 'bd_icons.dart';
import 'bd_misc.dart';

/// translate() with {} placeholders filled from [args] in order.
String tr(String key, [List<Object?> args = const []]) {
  var s = translate(key);
  for (final a in args) {
    s = s.replaceFirst('{}', '${a ?? ''}');
  }
  return s;
}

class BdWindowTab {
  const BdWindowTab({
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
class BdWindowControls extends StatelessWidget {
  const BdWindowControls({
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
        BdWinButton(
            glyph: BdWinGlyph.minimize,
            tooltip: translate('Minimize'),
            onTap: onMinimize,
            height: height),
      if (onMaximize != null)
        BdWinButton(
            glyph: maximized ? BdWinGlyph.restore : BdWinGlyph.maximize,
            tooltip: translate(maximized ? 'Restore' : 'Maximize'),
            onTap: onMaximize,
            height: height),
      if (onClose != null)
        BdWinButton(
            glyph: BdWinGlyph.close,
            tooltip: translate('Close'),
            onTap: onClose,
            height: height,
            isClose: true),
    ]);
  }
}

enum BdWinGlyph { minimize, maximize, restore, close }

/// The window buttons' glyphs: 10 px with a 1 px line, as Windows draws
/// its own, so the four have the same size and weight. Icon fonts draw a
/// short heavy dash, a large thin square and a mid-size cross.
class BdWinGlyphPainter extends CustomPainter {
  const BdWinGlyphPainter(this.glyph, this.color);
  final BdWinGlyph glyph;
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
      case BdWinGlyph.minimize:
        canvas.drawLine(const Offset(0, 4.5), const Offset(10, 4.5), p);
      case BdWinGlyph.maximize:
        canvas.drawRect(const Rect.fromLTRB(0.5, 0.5, 9.5, 9.5), p);
      case BdWinGlyph.restore:
        canvas.drawRect(const Rect.fromLTRB(0.5, 2.5, 7.5, 9.5), p);
        canvas.drawPath(
            Path()
              ..moveTo(2.5, 2.5)
              ..lineTo(2.5, 0.5)
              ..lineTo(9.5, 0.5)
              ..lineTo(9.5, 7.5)
              ..lineTo(7.5, 7.5),
            p);
      case BdWinGlyph.close:
        p.isAntiAlias = true;
        canvas.drawLine(Offset.zero, const Offset(10, 10), p);
        canvas.drawLine(const Offset(10, 0), const Offset(0, 10), p);
    }
  }

  @override
  bool shouldRepaint(BdWinGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

/// One window button, 46 x [height]; the close button hovers red.
class BdWinButton extends StatefulWidget {
  const BdWinButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onTap,
    required this.height,
    this.isClose = false,
  });

  final BdWinGlyph glyph;
  final String tooltip;
  final VoidCallback? onTap;
  final double height;
  final bool isClose;

  @override
  State<BdWinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<BdWinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final bg = _hover
        ? (widget.isClose ? c.windowCloseHover : c.hover)
        : Colors.transparent;
    final fg = widget.onTap == null
        ? c.textMuted
        : (_hover && widget.isClose ? c.onWindowCloseHover : c.text);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.tooltip,
          waitDuration: const Duration(seconds: 1),
          child: Container(
            width: 46,
            height: widget.height,
            color: bg,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size.square(BdWinGlyphPainter.size),
              painter: BdWinGlyphPainter(widget.glyph, fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 40 px title bar: brand at the start, tabs when more than one page is
/// open, then [actions] and the window controls.
class BdTitleBar extends StatelessWidget {
  const BdTitleBar({
    super.key,
    required this.brand,
    this.tabs = const [],
    this.actions = const [],
    this.controls,
    this.height = 40,
  });

  final Widget brand;
  final List<BdWindowTab> tabs;
  final List<Widget> actions;
  final Widget? controls;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
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
  final BdWindowTab tab;
  final bool first;

  @override
  State<_TitleTab> createState() => _TitleTabState();
}

class _TitleTabState extends State<_TitleTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final tab = widget.tab;
    final sel = tab.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tab.onTap,
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
                Text(tab.label,
                    style: t.label.copyWith(
                        fontSize: 13,
                        height: 18 / 13,
                        color: sel ? c.text : c.textMuted)),
                if (tab.onClose != null) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: tab.onClose,
                    child: Tooltip(
                      message: translate('Close'),
                      child: Icon(BdIcons.close, size: 16, color: c.textMuted),
                    ),
                  ),
                ] else
                  const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A text button in the title bar (Settings, Back).
class BdTitleBarText extends StatefulWidget {
  const BdTitleBarText(
      {super.key, required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<BdTitleBarText> createState() => _BdTitleBarTextState();
}

class _BdTitleBarTextState extends State<BdTitleBarText> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    return Center(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? c.hover : Colors.transparent,
              borderRadius: BdSize.r,
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
      ),
    );
  }
}

/// The brand at the start of the title bar: the server's logo and name
/// when the branding has them, otherwise the BetterDesk mark (and wordmark
/// when [wordmark]).
class BdTitleBrand extends StatelessWidget {
  const BdTitleBrand({
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
    final t = context.bdText;
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
        const BdLogoMark(size: 18),
        const SizedBox(width: 8),
        Text(title!, style: t.label.copyWith(fontWeight: FontWeight.w500)),
      ]);
    }
    return wordmark ? const BdWordmark(height: 18) : const BdLogoMark(size: 18);
  }
}

/// A window drawn by the app: title bar on top, page below on bg.
class BdWindowFrame extends StatelessWidget {
  const BdWindowFrame({super.key, required this.titleBar, required this.child});
  final Widget titleBar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.bd.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [titleBar, Expanded(child: child)],
      ),
    );
  }
}
