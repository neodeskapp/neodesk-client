import 'package:flutter/material.dart';

import '../../theme/nd_theme.dart';
import 'nd_button.dart';
import 'nd_icons.dart';
import 'nd_pressable.dart';

Duration _motion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations ? Duration.zero : NdSize.motion;

/// The square switch: 36 x 20 track with 4 px corners and a 12 px knob.
/// For settings that apply at once. A null [onChanged] shows it disabled.
class NdSwitch extends StatefulWidget {
  const NdSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  State<NdSwitch> createState() => _NdSwitchState();
}

class _NdSwitchState extends State<NdSwitch> {
  bool _focus = false;

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final on = widget.value;
    final enabled = widget.onChanged != null;
    Widget track = AnimatedContainer(
      duration: _motion(context),
      curve: Curves.easeOut,
      width: 36,
      height: 20,
      decoration: BoxDecoration(
        color: on ? c.accent : Colors.transparent,
        borderRadius: NdSize.r,
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
    if (_focus) track = NdFocusRing(child: track);
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
class NdCheckbox extends StatelessWidget {
  const NdCheckbox({
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
    final c = context.nd;
    final t = context.ndText;
    final enabled = onChanged != null;
    return NdPressable(
      button: false,
      checked: value,
      label: label,
      hint: hint,
      onPressed: enabled ? () => onChanged!(!value) : null,
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
                borderRadius: BorderRadius.circular(NdSize.radiusSm),
                border: Border.all(color: value ? c.accent : c.border),
              ),
              child: value
                  ? Icon(NdIcons.check, size: 14, color: c.onAccent)
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
    );
  }
}

/// A round 16 px radio mark (menus draw their own 14 px variant).
class NdRadioMark extends StatelessWidget {
  const NdRadioMark({super.key, required this.selected, this.size = 16});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
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

class NdSegment<T> {
  const NdSegment(this.value, this.label);
  final T value;
  final String label;
}

/// Two to four short choices that apply at once. 30 high; the chosen one
/// has the accent tint and a 2 px accent line at the bottom.
///
/// To the keyboard it is one stop in the Tab order: the chosen segment.
/// The arrow keys choose the neighbour. Each segment is a button with a
/// selected state, in a group of which only one can be chosen.
class NdSegmented<T> extends StatefulWidget {
  const NdSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<NdSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  /// The name of the whole group (usually the settings row's label).
  final String? semanticLabel;

  /// These segments, named [name].
  NdSegmented<T> withSemanticLabel(String name) => NdSegmented<T>(
        key: key,
        segments: segments,
        value: value,
        onChanged: onChanged,
        semanticLabel: name,
      );

  @override
  State<NdSegmented<T>> createState() => _NdSegmentedState<T>();
}

class _NdSegmentedState<T> extends State<NdSegmented<T>> {
  final _group = NdRovingGroup();

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final segments = widget.segments;
    final enabled = widget.onChanged != null;
    final selected = segments.indexWhere((s) => s.value == widget.value);
    final nodes = _group.nodes(segments.length, selected);
    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final on = i == selected;
      children.add(NdPressable(
        focusNode: nodes[i],
        selected: on,
        inMutuallyExclusiveGroup: true,
        label: s.label,
        // Inside the segment: the group clips its rounded corners.
        ringOutset: 0,
        onPressed: enabled
            ? () {
                if (!on) widget.onChanged!(s.value);
              }
            : null,
        keys: enabled
            ? _group.keys(i, segments.length,
                (k) => widget.onChanged!(segments[k].value))
            : const {},
        child: Container(
          constraints: const BoxConstraints(minHeight: 28),
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
      ));
    }
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      explicitChildNodes: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: NdSize.r,
            border: Border.all(color: c.border, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NdSize.radius - 1),
            child: IntrinsicHeight(
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children),
            ),
          ),
        ),
      ),
    );
  }
}

class NdTab<T> {
  const NdTab(this.value, this.label);
  final T value;
  final String label;
}

/// Text tabs with a 2 px accent underline on the chosen one and a rule
/// under the row. [trailing] sits at the end of the row (search field);
/// when the tabs and [trailing] don't fit side by side, [trailing] moves to
/// a row of its own above the tabs, so no tab label gets cut off.
///
/// To the keyboard the row is one stop in the Tab order: the chosen tab.
/// Left / Right choose the neighbour, Home / End the first and last. Each
/// tab is a button with a selected state.
class NdTabs<T> extends StatefulWidget {
  const NdTabs({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.trailing,
    this.gap = 20,
  });

  final List<NdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;
  final Widget? trailing;
  final double gap;

  @override
  State<NdTabs<T>> createState() => _NdTabsState<T>();
}

class _NdTabsState<T> extends State<NdTabs<T>> {
  final _group = NdRovingGroup();

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final tabs = widget.tabs;
    final selected = tabs.indexWhere((x) => x.value == widget.value);
    final nodes = _group.nodes(tabs.length, selected);
    final row = <Widget>[];
    for (var i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      final on = i == selected;
      if (row.isNotEmpty) row.add(SizedBox(width: widget.gap));
      row.add(NdPressable(
        focusNode: nodes[i],
        selected: on,
        label: tab.label,
        onPressed: () => widget.onChanged(tab.value),
        keys: _group.keys(
            i, tabs.length, (k) => widget.onChanged(tabs[k].value)),
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
      ));
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule, width: 1)),
      ),
      // Runs stack upwards, so the tabs stay on the rule and [trailing]
      // wraps above them. Upwards also flips the cross axis: start is the
      // bottom of a run.
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          verticalDirection: VerticalDirection.up,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: 16,
          children: [
            // Scrolls only when the tabs alone are wider than the row.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // The focus ring is drawn just outside the tab.
              clipBehavior: Clip.none,
              child: Row(mainAxisSize: MainAxisSize.min, children: row),
            ),
            if (widget.trailing != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: widget.trailing!),
          ],
        ),
      ),
    );
  }
}
