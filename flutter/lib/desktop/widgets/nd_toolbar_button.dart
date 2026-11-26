import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

/// A toolbar button: 36 high, 20 px icon and a 13 / 500 label.
class NdToolbarButton extends StatefulWidget {
  const NdToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.showLabel = true,
    this.danger = false,
    this.iconColor,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool showLabel;
  final bool danger;
  final Color? iconColor;
  final String? tooltip;

  @override
  State<NdToolbarButton> createState() => NdToolbarButtonState();
}

class NdToolbarButtonState extends State<NdToolbarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final enabled = widget.onPressed != null;
    final fg = widget.danger ? c.danger : c.text;
    Widget content = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(widget.icon, size: 20, color: widget.iconColor ?? fg),
      if (widget.showLabel) ...[
        const SizedBox(width: 8),
        Text(widget.label,
            style: t.label.copyWith(fontSize: 13, height: 18 / 13, color: fg)),
      ],
    ]);
    // A button to the keyboard and to assistive tech, named by its label
    // also when only the icon shows.
    return NdPressable(
      label: widget.label,
      hint: widget.showLabel ? widget.tooltip : null,
      onHover: (v) => setState(() => _hover = v),
      onPressed: widget.onPressed,
      child: Tooltip(
        message: widget.showLabel ? (widget.tooltip ?? '') : widget.label,
        excludeFromSemantics: true,
        child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Container(
              height: 36,
              padding: EdgeInsets.symmetric(
                  horizontal: widget.showLabel ? 10 : 8),
              margin: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 4),
              decoration: BoxDecoration(
                color: _hover && enabled ? c.hover : Colors.transparent,
                borderRadius: NdSize.r,
              ),
              child: content,
            ),
          ),
      ),
    );
  }
}

