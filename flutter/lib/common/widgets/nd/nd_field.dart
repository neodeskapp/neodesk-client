import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/nd_theme.dart';
import 'nd_icons.dart';
import 'nd_menu.dart';
import 'nd_pressable.dart';

/// A text field with the label above, a hint or an error below.
/// Large fields (44 high) are for onboarding, the connect field and quick
/// support; they can hold a button at the end ([trailing], e.g. Paste).
class NdField extends StatefulWidget {
  const NdField({
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
  State<NdField> createState() => _NdFieldState();
}

class _NdFieldState extends State<NdField> {
  FocusNode? _own;
  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant NdField old) {
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
    final c = context.nd;
    final t = context.ndText;
    final invalid = widget.error != null && widget.error!.isNotEmpty;
    final h = widget.height ??
        (widget.large ? NdSize.controlLg : NdSize.control);
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
        borderRadius: NdSize.r,
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
    // The box keeps its place in the tree whether the ring shows or not: a
    // TextField that moves is built anew and drops its text input
    // connection while it keeps the focus, and typed keys get lost.
    box = Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
      box,
      if (_focused)
        Positioned(
          left: -3,
          top: -3,
          right: -3,
          bottom: -3,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NdSize.radius + 2),
                border: Border.all(
                    color: invalid ? c.danger : c.accent, width: 2),
              ),
            ),
          ),
        ),
    ]);

    final below = invalid
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(NdIcons.error, size: 16, color: c.danger),
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
class NdSearchField extends StatelessWidget {
  const NdSearchField({
    super.key,
    required this.placeholder,
    this.controller,
    this.onChanged,
    this.width,
    this.height = NdSize.control,
    this.focusNode,
  });

  final String placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final double? width;
  final double height;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => NdField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        prefixIcon: NdIcons.search,
        onChanged: onChanged,
        width: width,
        height: height,
      );
}

class NdOption<T> {
  const NdOption(this.value, this.label, {this.prefix});
  final T value;
  final String label;

  /// Shown before the label in the menu and in the closed field, such as a
  /// language's flag.
  final Widget? prefix;
}

/// A field with expand_more that opens a menu of choices.
class NdSelect<T> extends StatefulWidget {
  const NdSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.width = 220,
    this.placeholder,
    this.semanticLabel,
  });

  final List<NdOption<T>> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final double width;
  final String? placeholder;

  /// What is chosen here, usually the settings row's label. The screen
  /// reader says it with the current choice.
  final String? semanticLabel;

  @override
  State<NdSelect<T>> createState() => _NdSelectState<T>();
}

class _NdSelectState<T> extends State<NdSelect<T>> {
  final _controller = MenuController();
  bool _hover = false;
  final _optionNodes = <FocusNode>[];

  List<FocusNode> _nodes() {
    while (_optionNodes.length < widget.options.length) {
      _optionNodes.add(FocusNode(debugLabel: 'option ${_optionNodes.length}'));
    }
    return _optionNodes;
  }

  /// Opens the menu and puts focus on the chosen option, so the arrow keys
  /// move from there and Enter picks one.
  void _openFromKeyboard() {
    if (widget.onChanged == null) return;
    _controller.open();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isOpen) return;
      final i = widget.options.indexWhere((o) => o.value == widget.value);
      final nodes = _nodes();
      if (nodes.isNotEmpty) nodes[i < 0 ? 0 : i].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final n in _optionNodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final enabled = widget.onChanged != null;
    String label = widget.placeholder ?? '';
    Widget? prefix;
    for (final o in widget.options) {
      if (o.value == widget.value) {
        label = o.label;
        prefix = o.prefix;
      }
    }
    final nodes = _nodes();
    return MenuAnchor(
      controller: _controller,
      style: ndMenuStyle(context, minWidth: widget.width),
      alignmentOffset: const Offset(0, 4),
      onOpen: () => setState(() {}),
      onClose: () => setState(() {}),
      menuChildren: [
        for (var i = 0; i < widget.options.length; i++)
          NdMenuItem(
            focusNode: nodes[i],
            label: widget.options[i].label,
            prefix: widget.options[i].prefix,
            leading: widget.options[i].value == widget.value
                ? NdMenuLead.check
                : NdMenuLead.none,
            onPressed: () => widget.onChanged?.call(widget.options[i].value),
          ),
      ],
      builder: (context, controller, _) => NdPressable(
        label: widget.semanticLabel ?? label,
        value: widget.semanticLabel == null ? null : label,
        expanded: controller.isOpen,
        onHover: (v) => setState(() => _hover = v),
        onPressed: enabled
            ? () => controller.isOpen ? controller.close() : _openFromKeyboard()
            : null,
        keys: {
          const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
              _openFromKeyboard,
          const SingleActivator(LogicalKeyboardKey.arrowDown):
              _openFromKeyboard,
        },
        child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Container(
              width: widget.width,
              height: NdSize.control,
              padding: const EdgeInsets.only(left: 10, right: 8),
              decoration: BoxDecoration(
                color: _hover && enabled ? c.bgSubtle : c.bg,
                borderRadius: NdSize.r,
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
                  Icon(NdIcons.expandMore, size: 18, color: c.textMuted),
                ],
              ),
            ),
          ),
      ),
    );
  }
}
