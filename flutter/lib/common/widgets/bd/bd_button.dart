import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/bd_theme.dart';

enum BdButtonKind { primary, plain, danger, dangerQuiet, ghost, link }

enum BdButtonSize { sm, md, lg }

/// The one button of the design: primary, plain, danger, danger-quiet,
/// ghost (no border) and link, in three heights (30, 36, 44).
class BdButton extends StatefulWidget {
  const BdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = BdButtonKind.plain,
    this.size = BdButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.block = false,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
    this.labelColor,
  });

  const BdButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = BdButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.block = false,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  })  : kind = BdButtonKind.primary,
        labelColor = null;

  const BdButton.link({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = BdButtonSize.md,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  })  : kind = BdButtonKind.link,
        icon = null,
        trailingIcon = null,
        block = false,
        labelColor = null;

  final String label;
  final VoidCallback? onPressed;
  final BdButtonKind kind;
  final BdButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool block;
  final String? tooltip;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Overrides the label colour of plain and ghost buttons (toolbar End).
  final Color? labelColor;

  @override
  State<BdButton> createState() => _BdButtonState();
}

class _BdButtonState extends State<BdButton> {
  bool _hover = false;
  bool _focus = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  double get _height => switch (widget.size) {
        BdButtonSize.sm => BdSize.controlSm,
        BdButtonSize.md => BdSize.control,
        BdButtonSize.lg => BdSize.controlLg,
      };

  double get _padX => switch (widget.size) {
        BdButtonSize.sm => 10,
        BdButtonSize.md => 14,
        BdButtonSize.lg => 20,
      };

  double get _fontSize => switch (widget.size) {
        BdButtonSize.sm => 13,
        BdButtonSize.md => 14,
        BdButtonSize.lg => 15,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final isLink = widget.kind == BdButtonKind.link;

    Color fill = Colors.transparent;
    Color borderColor = c.border;
    Color fg = widget.labelColor ?? c.text;
    switch (widget.kind) {
      case BdButtonKind.primary:
        fill = _hover && _enabled ? c.accentHover : c.accent;
        borderColor = fill;
        fg = c.onAccent;
        break;
      case BdButtonKind.danger:
        fill = _hover && _enabled ? c.dangerHover : c.danger;
        borderColor = fill;
        fg = c.onDanger;
        break;
      case BdButtonKind.dangerQuiet:
        fg = c.danger;
        fill = _hover && _enabled ? c.hover : Colors.transparent;
        break;
      case BdButtonKind.plain:
        fill = _pressed
            ? c.accentTint
            : (_hover && _enabled ? c.hover : Colors.transparent);
        break;
      case BdButtonKind.ghost:
        borderColor = Colors.transparent;
        fill = _pressed
            ? c.accentTint
            : (_hover && _enabled ? c.hover : Colors.transparent);
        break;
      case BdButtonKind.link:
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

    Widget content = Text(widget.label,
        style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (!isLink && (widget.icon != null || widget.trailingIcon != null)) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
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
                : BdSize.motion,
            curve: Curves.easeOut,
            height: _height,
            width: widget.block ? double.infinity : null,
            padding: EdgeInsets.symmetric(horizontal: _padX),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BdSize.r,
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Center(widthFactor: 1, child: content),
          );

    if (_focus) box = BdFocusRing(child: box);

    Widget result = FocusableActionDetector(
      enabled: _enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor:
          _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
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
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return Semantics(
        button: true, enabled: _enabled, label: widget.label, child: result);
  }
}

/// The 2 px accent ring, 2 px outside the control, drawn without changing
/// the control's size.
class BdFocusRing extends StatelessWidget {
  const BdFocusRing({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: -4,
          top: -4,
          right: -4,
          bottom: -4,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(BdSize.radius + 3),
                border: Border.all(color: color ?? context.bd.accent, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An icon-only button (close, row menu, disclosure). Always has a tooltip.
class BdIconButton extends StatefulWidget {
  const BdIconButton({
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
  State<BdIconButton> createState() => _BdIconButtonState();
}

class _BdIconButtonState extends State<BdIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    return Tooltip(
      message: widget.tooltip,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => widget.onPressed?.call()),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? c.hover : Colors.transparent,
              borderRadius: BdSize.r,
            ),
            child: Icon(widget.icon,
                size: widget.iconSize, color: widget.color ?? c.textMuted),
          ),
        ),
      ),
    );
  }
}
