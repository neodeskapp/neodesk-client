import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nd_button.dart';

/// Makes a drawn control usable by keyboard and assistive tech.
///
/// It takes focus with Tab, runs [onPressed] on a click, Enter or Space, draws
/// the 2 px accent focus ring (NdFocusRing) while focused from the keyboard,
/// and gives the control one semantics node with its role ([button]), name
/// ([label], read instead of the child's text when given) and state
/// ([checked], [selected], [toggled], [expanded]). A null [onPressed] shows
/// it disabled and takes it out of the Tab order.
///
/// [keys] adds key bindings while it has focus (arrows in a group).
class NdPressable extends StatefulWidget {
  const NdPressable({
    super.key,
    required this.child,
    required this.onPressed,
    this.label,
    this.hint,
    this.value,
    this.button = true,
    this.checked,
    this.selected,
    this.toggled,
    this.expanded,
    this.inMutuallyExclusiveGroup = false,
    this.focusNode,
    this.autofocus = false,
    this.onHover,
    this.onFocusChange,
    this.keys = const {},
    this.ring = true,
    this.ringColor,
    this.ringOutset = 4,
    this.onSecondaryTapUp,
    this.onDoubleTap,
    this.keepChildSemantics = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? label;
  final String? hint;
  final String? value;
  final bool button;
  final bool? checked;
  final bool? selected;
  final bool? toggled;
  final bool? expanded;
  final bool inMutuallyExclusiveGroup;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final Map<ShortcutActivator, VoidCallback> keys;

  /// False when the child draws its own focused state.
  final bool ring;
  final Color? ringColor;
  final double ringOutset;
  final GestureTapUpCallback? onSecondaryTapUp;
  final VoidCallback? onDoubleTap;

  /// With a [label], the child's semantics are dropped so the name is not
  /// read twice. True keeps them, for a row that holds its own buttons; the
  /// row then hides its texts itself.
  final bool keepChildSemantics;

  @override
  State<NdPressable> createState() => NdPressableState();
}

class NdPressableState extends State<NdPressable> {
  bool _focusShown = false;

  /// True while the control shows keyboard focus.
  bool get focusShown => _focusShown;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Widget content = widget.child;
    if (_focusShown && widget.ring) {
      content = NdFocusRing(
          color: widget.ringColor, outset: widget.ringOutset, child: content);
    }
    final bindings = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
      const SingleActivator(LogicalKeyboardKey.numpadEnter):
          const ActivateIntent(),
      const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
    };
    final callbacks = <int, VoidCallback>{};
    for (final e in widget.keys.entries) {
      final id = callbacks.length;
      bindings[e.key] = _KeyIntent(id);
      callbacks[id] = e.value;
    }
    return Semantics(
      container: true,
      button: widget.button ? true : null,
      enabled: enabled,
      checked: widget.checked,
      selected: widget.selected,
      toggled: widget.toggled,
      expanded: widget.expanded,
      inMutuallyExclusiveGroup:
          widget.inMutuallyExclusiveGroup ? true : null,
      label: widget.label,
      hint: widget.hint,
      value: widget.value,
      excludeSemantics: widget.label != null && !widget.keepChildSemantics,
      onTap: widget.onPressed,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        includeFocusSemantics: true,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowHoverHighlight: widget.onHover,
        onShowFocusHighlight: (v) => setState(() => _focusShown = v),
        onFocusChange: widget.onFocusChange,
        shortcuts: bindings,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => widget.onPressed?.call()),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
              onInvoke: (_) => widget.onPressed?.call()),
          if (callbacks.isNotEmpty) _KeyIntent: _KeyAction(callbacks),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onPressed,
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapUp: widget.onSecondaryTapUp,
          child: content,
        ),
      ),
    );
  }
}

class _KeyIntent extends Intent {
  const _KeyIntent(this.id);
  final int id;
}

class _KeyAction extends Action<_KeyIntent> {
  _KeyAction(this.callbacks);
  final Map<int, VoidCallback> callbacks;
  @override
  Object? invoke(_KeyIntent intent) {
    callbacks[intent.id]?.call();
    return null;
  }
}

/// Moves selection and focus within a row of choices with the arrow keys,
/// like a tab list or a radio group: only the chosen item is in the Tab
/// order, Left / Right (and Up / Down) choose the neighbour and Home / End
/// the first and last.
class NdRovingGroup {
  NdRovingGroup();

  final List<FocusNode> _nodes = [];

  /// Returns the focus nodes for [count] items, with only [selected] in the
  /// Tab order (the first when none is selected).
  List<FocusNode> nodes(int count, int selected) {
    while (_nodes.length < count) {
      _nodes.add(FocusNode(debugLabel: 'roving ${_nodes.length}'));
    }
    while (_nodes.length > count) {
      _nodes.removeLast().dispose();
    }
    final tabStop = selected < 0 ? 0 : selected;
    for (var i = 0; i < count; i++) {
      _nodes[i].skipTraversal = i != tabStop;
    }
    return _nodes;
  }

  /// Key bindings for item [i]: [choose] selects an item by index.
  Map<ShortcutActivator, VoidCallback> keys(
      int i, int count, ValueChanged<int> choose) {
    void go(int j) {
      if (count == 0) return;
      final k = (j + count) % count;
      choose(k);
      if (k < _nodes.length) _nodes[k].requestFocus();
    }

    return {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => go(i - 1),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => go(i - 1),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => go(i + 1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => go(i + 1),
      const SingleActivator(LogicalKeyboardKey.home): () => go(0),
      const SingleActivator(LogicalKeyboardKey.end): () => go(count - 1),
    };
  }

  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    _nodes.clear();
  }
}
