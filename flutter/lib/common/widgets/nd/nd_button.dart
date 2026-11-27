import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/nd_theme.dart';
import 'nd_pressable.dart';

enum NdButtonKind { primary, plain, danger, dangerQuiet, ghost, link }

enum NdButtonSize { sm, md, lg }

/// The one button of the design: primary, plain, danger, danger-quiet,
/// ghost (no border) and link, in three heights (30, 36, 44).
class NdButton extends StatefulWidget {
  const NdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = NdButtonKind.plain,
    this.size = NdButtonSize.md,
    this.icon,
    this.leading,
    this.trailingIcon,
    this.block = false,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
    this.labelColor,
  });

  const NdButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = NdButtonSize.md,
    this.icon,
    this.leading,
    this.trailingIcon,
    this.block = false,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  })  : kind = NdButtonKind.primary,
        labelColor = null;

  const NdButton.link({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = NdButtonSize.md,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  })  : kind = NdButtonKind.link,
        icon = null,
        leading = null,
        trailingIcon = null,
        block = false,
        labelColor = null;

  final String label;
  final VoidCallback? onPressed;
  final NdButtonKind kind;
  final NdButtonSize size;
  final IconData? icon;

  /// A picture before the label where an icon glyph won't do, such as the
  /// NeoDesk mark in its own colours. Takes the place of [icon].
  final Widget? leading;
  final IconData? trailingIcon;
  final bool block;
  final String? tooltip;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Overrides the label colour of plain and ghost buttons (toolbar End).
  final Color? labelColor;

  @override
  State<NdButton> createState() => _NdButtonState();
}

class _NdButtonState extends State<NdButton> {
  bool _hover = false;
  bool _focus = false;
  bool _pressed = false;
  bool _hasFocus = false;

  bool get _enabled => widget.onPressed != null;

  double get _height => switch (widget.size) {
        NdButtonSize.sm => NdSize.controlSm,
        NdButtonSize.md => NdSize.control,
        NdButtonSize.lg => NdSize.controlLg,
      };

  double get _padX => switch (widget.size) {
        NdButtonSize.sm => 10,
        NdButtonSize.md => 14,
        NdButtonSize.lg => 20,
      };

  double get _fontSize => switch (widget.size) {
        NdButtonSize.sm => 13,
        NdButtonSize.md => 14,
        NdButtonSize.lg => 15,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final isLink = widget.kind == NdButtonKind.link;

    Color fill = Colors.transparent;
    Color borderColor = c.border;
    Color fg = widget.labelColor ?? c.text;
    switch (widget.kind) {
      case NdButtonKind.primary:
        fill = _hover && _enabled ? c.accentHover : c.accent;
        borderColor = fill;
        fg = c.onAccent;
        break;
      case NdButtonKind.danger:
        fill = _hover && _enabled ? c.dangerHover : c.danger;
        borderColor = fill;
        fg = c.onDanger;
        break;
      case NdButtonKind.dangerQuiet:
        fg = c.danger;
        fill = _hover && _enabled ? c.hover : Colors.transparent;
        break;
      case NdButtonKind.plain:
        fill = _pressed
            ? c.accentTint
            : (_hover && _enabled ? c.hover : Colors.transparent);
        break;
      case NdButtonKind.ghost:
        borderColor = Colors.transparent;
        fill = _pressed
            ? c.accentTint
            : (_hover && _enabled ? c.hover : Colors.transparent);
        break;
      case NdButtonKind.link:
        fg = c.accent;
        break;
    }

    final style = (isLink ? t.body : t.label).copyWith(
      fontSize: isLink ? null : _fontSize,
      height: isLink ? null : 20 / _fontSize,
      color: fg,
      decoration: isLink ? TextDecoration.underline : null,
      decorationColor: fg,
      decorationThickness: 1,
    );

    // Two lines at most when the text is scaled up; the box grows with it.
    Widget content = Text(widget.label,
        style: style,
        maxLines: isLink ? null : 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center);
    if (!isLink &&
        (widget.icon != null ||
            widget.leading != null ||
            widget.trailingIcon != null)) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 8),
          ] else if (widget.icon != null) ...[
            Icon(widget.icon, size: 18, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(child: content),
          if (widget.trailingIcon != null) ...[
            const SizedBox(width: 6),
            Icon(widget.trailingIcon, size: 18, color: fg),
          ],
        ],
      );
    }

    Widget box = isLink
        ? content
        : AnimatedContainer(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : NdSize.motion,
            curve: Curves.easeOut,
            constraints: BoxConstraints(minHeight: _height),
            width: widget.block ? double.infinity : null,
            padding: EdgeInsets.symmetric(horizontal: _padX),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: NdSize.r,
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Center(widthFactor: 1, heightFactor: 1, child: content),
          );

    if (_focus) box = NdFocusRing(child: box);

    Widget result = FocusableActionDetector(
      enabled: _enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor:
          _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      onFocusChange: (f) => setState(() => _hasFocus = f),
      includeFocusSemantics: false,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onPressed?.call()),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: Opacity(opacity: _enabled ? 1 : 0.45, child: box),
      ),
    );
    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      result = Tooltip(
          message: widget.tooltip!, excludeFromSemantics: true, child: result);
    }
    // The label is the name; the Text inside would say it a second time.
    return Semantics(
        container: true,
        button: true,
        enabled: _enabled,
        label: widget.label,
        hint: widget.tooltip,
        excludeSemantics: true,
        focusable: _enabled,
        focused: _hasFocus,
        onTap: widget.onPressed,
        child: result);
  }
}

/// The 2 px accent ring, 2 px outside the control, drawn without changing
/// the control's size.
class NdFocusRing extends StatelessWidget {
  const NdFocusRing(
      {super.key, required this.child, this.color, this.outset = 4});

  final Widget child;
  final Color? color;

  /// How far outside the control the ring's outer edge sits; 0 draws it on
  /// the control's own edge, for controls whose parent clips.
  final double outset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: -outset,
          top: -outset,
          right: -outset,
          bottom: -outset,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(NdSize.radius + outset - 1),
                border: Border.all(color: color ?? context.nd.accent, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An icon-only button (close, row menu, disclosure). Always has a tooltip.
class NdIconButton extends StatefulWidget {
  const NdIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 30,
    this.iconSize = 18,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  State<NdIconButton> createState() => _NdIconButtonState();
}

class _NdIconButtonState extends State<NdIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    // The tooltip is for the mouse; the name comes from the label, which
    // Windows reads reliably (a tooltip alone is not the name there).
    return NdPressable(
      label: widget.tooltip,
      onHover: (v) => setState(() => _hover = v),
      onPressed: widget.onPressed,
      child: Tooltip(
        message: widget.tooltip,
        excludeFromSemantics: true,
        child: Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? c.hover : Colors.transparent,
            borderRadius: NdSize.r,
          ),
          child: Icon(widget.icon,
              size: widget.iconSize, color: widget.color ?? c.textMuted),
        ),
      ),
    );
  }
}
