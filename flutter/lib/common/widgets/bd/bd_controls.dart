import 'package:flutter/material.dart';

import '../../theme/bd_theme.dart';
import 'bd_button.dart';
import 'bd_icons.dart';

Duration _motion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations ? Duration.zero : BdSize.motion;

/// The square switch: 36 x 20 track with 4 px corners and a 12 px knob.
/// For settings that apply at once. A null [onChanged] shows it disabled.
class BdSwitch extends StatefulWidget {
  const BdSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  State<BdSwitch> createState() => _BdSwitchState();
}

class _BdSwitchState extends State<BdSwitch> {
  bool _focus = false;

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final on = widget.value;
    final enabled = widget.onChanged != null;
    Widget track = AnimatedContainer(
      duration: _motion(context),
      curve: Curves.easeOut,
      width: 36,
      height: 20,
      decoration: BoxDecoration(
        color: on ? c.accent : Colors.transparent,
        borderRadius: BdSize.r,
        border: Border.all(color: on ? c.accent : c.border, width: 1),
      ),
      child: AnimatedAlign(
        duration: _motion(context),
        curve: Curves.easeOut,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: on ? c.onAccent : c.textMuted,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
    if (_focus) track = BdFocusRing(child: track);
    return Semantics(
      toggled: on,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent:
              CallbackAction<ActivateIntent>(onInvoke: (_) => _toggle()),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _toggle : null,
          child: Opacity(opacity: enabled ? 1 : 0.45, child: track),
        ),
      ),
    );
  }
}

/// A 16 px checkbox with 3 px corners, for forms that are submitted.
class BdCheckbox extends StatelessWidget {
  const BdCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.hint,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final enabled = onChanged != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: value ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(BdSize.radiusSm),
                  border: Border.all(color: value ? c.accent : c.border),
                ),
                child: value
                    ? Icon(BdIcons.check, size: 14, color: c.onAccent)
                    : null,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: t.body),
                    if (hint != null) Text(hint!, style: t.small),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round 16 px radio mark (menus draw their own 14 px variant).
class BdRadioMark extends StatelessWidget {
  const BdRadioMark({super.key, required this.selected, this.size = 16});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? c.accent : c.border),
      ),
      child: selected
          ? Container(
              width: size / 2,
              height: size / 2,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: c.accent),
            )
          : null,
    );
  }
}

class BdSegment<T> {
  const BdSegment(this.value, this.label);
  final T value;
  final String label;
}

/// Two to four short choices that apply at once. 30 high; the chosen one
/// has the accent tint and a 2 px accent line at the bottom.
class BdSegmented<T> extends StatelessWidget {
  const BdSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<BdSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final enabled = onChanged != null;
    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final on = s.value == value;
      children.add(MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled && !on ? () => onChanged!(s.value) : null,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.accentTint : Colors.transparent,
              border: Border(
                left: i == 0
                    ? BorderSide.none
                    : BorderSide(color: c.border, width: 1),
                bottom: on
                    ? BorderSide(color: c.accent, width: 2)
                    : const BorderSide(color: Colors.transparent, width: 2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(s.label,
                  style: t.label.copyWith(fontSize: 13, height: 18 / 13)),
            ),
          ),
        ),
      ));
    }
    return Semantics(
      container: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BdSize.r,
            border: Border.all(color: c.border, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(BdSize.radius - 1),
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

class BdTab<T> {
  const BdTab(this.value, this.label);
  final T value;
  final String label;
}

/// Text tabs with a 2 px accent underline on the chosen one and a rule
/// under the row. [trailing] sits at the end of the row (search field).
class BdTabs<T> extends StatelessWidget {
  const BdTabs({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.trailing,
    this.gap = 20,
  });

  final List<BdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;
  final Widget? trailing;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final row = <Widget>[];
    for (final tab in tabs) {
      final on = tab.value == value;
      if (row.isNotEmpty) row.add(SizedBox(width: gap));
      row.add(MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(tab.value),
          child: Container(
            padding: const EdgeInsets.only(top: 8, bottom: 7),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: on ? c.accent : Colors.transparent, width: 2),
              ),
            ),
            child: Text(tab.label,
                style: t.label.copyWith(color: on ? c.text : c.textMuted)),
          ),
        ),
      ));
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: row),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 16),
            Padding(padding: const EdgeInsets.only(bottom: 8), child: trailing!),
          ],
        ],
      ),
    );
  }
}
