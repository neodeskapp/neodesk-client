import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/bd_theme.dart';
import 'bd_icons.dart';
import 'bd_menu.dart';

/// A text field with the label above, a hint or an error below.
/// Large fields (44 high) are for onboarding, the connect field and quick
/// support; they can hold a button at the end ([trailing], e.g. Paste).
class BdField extends StatefulWidget {
  const BdField({
    super.key,
    this.label,
    this.hint,
    this.error,
    this.controller,
    this.focusNode,
    this.large = false,
    this.mono = false,
    this.placeholder,
    this.trailing,
    this.prefixIcon,
    this.autofocus = false,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.inputFormatters,
    this.width,
    this.height,
    this.textAlignVertical,
  });

  final String? label;
  final String? hint;
  final String? error;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool large;
  final bool mono;

  /// Example text inside the empty field (never instructions).
  final String? placeholder;
  final Widget? trailing;
  final IconData? prefixIcon;
  final bool autofocus;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final double? width;
  final double? height;
  final TextAlignVertical? textAlignVertical;

  @override
  State<BdField> createState() => _BdFieldState();
}

class _BdFieldState extends State<BdField> {
  FocusNode? _own;
  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant BdField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _own)?.removeListener(_onFocus);
      _node.addListener(_onFocus);
    }
  }

  void _onFocus() {
    if (mounted && _focused != _node.hasFocus) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final invalid = widget.error != null && widget.error!.isNotEmpty;
    final h = widget.height ??
        (widget.large ? BdSize.controlLg : BdSize.control);
    final fontSize = widget.large ? 16.0 : 14.0;
    final base = widget.mono ? t.mono : t.body;
    final style = base.copyWith(
        fontSize: widget.mono && !widget.large ? 14 : fontSize,
        height: 1.25,
        color: widget.enabled ? c.text : c.textMuted);
    final borderColor = invalid ? c.danger : (_focused ? c.accent : c.border);

    Widget box = Container(
      height: h,
      width: widget.width,
      padding: EdgeInsets.only(
          left: widget.large ? 12 : 10,
          right: widget.trailing != null ? 4 : (widget.large ? 12 : 10)),
      decoration: BoxDecoration(
        color: widget.enabled ? c.bg : c.bgSubtle,
        borderRadius: BdSize.r,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          if (widget.prefixIcon != null) ...[
            Icon(widget.prefixIcon, size: 18, color: c.textMuted),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              autofocus: widget.autofocus,
              obscureText: widget.obscureText,
              enabled: widget.enabled,
              readOnly: widget.readOnly,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              keyboardType: widget.keyboardType,
              inputFormatters: widget.inputFormatters,
              style: style,
              cursorColor: c.text,
              cursorWidth: 1,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                hintText: widget.placeholder,
                hintStyle: style.copyWith(color: c.textMuted),
              ),
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 8),
            widget.trailing!,
          ],
        ],
      ),
    );
    if (_focused) {
      box = Stack(clipBehavior: Clip.none, children: [
        box,
        Positioned(
          left: -3,
          top: -3,
          right: -3,
          bottom: -3,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(BdSize.radius + 2),
                border: Border.all(
                    color: invalid ? c.danger : c.accent, width: 2),
              ),
            ),
          ),
        ),
      ]);
    }

    final below = invalid
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(BdIcons.error, size: 16, color: c.danger),
              ),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(widget.error!,
                      style: t.small.copyWith(color: c.danger))),
            ],
          )
        : (widget.hint != null && widget.hint!.isNotEmpty
            ? Text(widget.hint!, style: t.small)
            : null);

    if (widget.label == null && below == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: t.label),
          const SizedBox(height: 6),
        ],
        box,
        if (below != null) ...[const SizedBox(height: 6), below],
      ],
    );
  }
}

/// The search field of the computer list and the settings navigation.
class BdSearchField extends StatelessWidget {
  const BdSearchField({
    super.key,
    required this.placeholder,
    this.controller,
    this.onChanged,
    this.width,
    this.height = BdSize.control,
    this.focusNode,
  });

  final String placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final double? width;
  final double height;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => BdField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        prefixIcon: BdIcons.search,
        onChanged: onChanged,
        width: width,
        height: height,
      );
}

class BdOption<T> {
  const BdOption(this.value, this.label, {this.prefix});
  final T value;
  final String label;

  /// Shown before the label in the menu and in the closed field, such as a
  /// language's flag.
  final Widget? prefix;
}

/// A field with expand_more that opens a menu of choices.
class BdSelect<T> extends StatefulWidget {
  const BdSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.width = 220,
    this.placeholder,
  });

  final List<BdOption<T>> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final double width;
  final String? placeholder;

  @override
  State<BdSelect<T>> createState() => _BdSelectState<T>();
}

class _BdSelectState<T> extends State<BdSelect<T>> {
  final _controller = MenuController();
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final enabled = widget.onChanged != null;
    String label = widget.placeholder ?? '';
    Widget? prefix;
    for (final o in widget.options) {
      if (o.value == widget.value) {
        label = o.label;
        prefix = o.prefix;
      }
    }
    return MenuAnchor(
      controller: _controller,
      style: bdMenuStyle(context, minWidth: widget.width),
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final o in widget.options)
          BdMenuItem(
            label: o.label,
            prefix: o.prefix,
            leading: o.value == widget.value
                ? BdMenuLead.check
                : BdMenuLead.none,
            onPressed: () => widget.onChanged?.call(o.value),
          ),
      ],
      builder: (context, controller, _) => MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Container(
              width: widget.width,
              height: BdSize.control,
              padding: const EdgeInsets.only(left: 10, right: 8),
              decoration: BoxDecoration(
                color: _hover && enabled ? c.bgSubtle : c.bg,
                borderRadius: BdSize.r,
                border: Border.all(
                    color: controller.isOpen ? c.accent : c.border),
              ),
              child: Row(
                children: [
                  if (prefix != null) ...[prefix, const SizedBox(width: 8)],
                  Expanded(
                    child: Text(label,
                        style: t.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Icon(BdIcons.expandMore, size: 18, color: c.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
