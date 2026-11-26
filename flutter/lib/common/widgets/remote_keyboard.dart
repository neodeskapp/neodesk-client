// ignore_for_file: deprecated_member_use
// The keyboard in a remote session: who has it, and how to get it back.
//
// While the remote screen has focus, every key goes to the remote computer,
// Tab included. One key combination always gives the keyboard back to this
// computer: Ctrl+Alt+Shift+G on Windows and Linux, Command+Option+Shift+G
// on macOS. The Rust grab loop (src/keyboard_release.rs) catches it while
// the system keyboard hook runs; RemoteKeyboardScope catches it when the
// keys come through Flutter. The same combination gives the keyboard back
// to the remote computer.

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common.dart' show isMacOS;
import 'package:flutter_hbb/common/widgets/nd/nd_announce.dart';
import 'package:flutter_hbb/common/widgets/nd/nd_window.dart' show tr;

/// Whether the combination uses Command (macOS) instead of Ctrl. Tests set it.
bool? releaseChordUsesCommandForTest;

bool get _useCommand => releaseChordUsesCommandForTest ?? isMacOS;

/// The combination as the user reads it, in the UI language.
String releaseKeyboardChordLabel() =>
    tr(_useCommand ? 'nd-key-release-chord-mac' : 'nd-key-release-chord');

bool _isG(LogicalKeyboardKey l, PhysicalKeyboardKey p) =>
    l == LogicalKeyboardKey.keyG || p == PhysicalKeyboardKey.keyG;

/// True for the key down of G while the other keys of the combination are
/// held. Repeats do not count.
bool isReleaseKeyboardChord(KeyEvent e) {
  if (e is! KeyDownEvent || !_isG(e.logicalKey, e.physicalKey)) return false;
  final k = HardwareKeyboard.instance;
  return k.isShiftPressed &&
      k.isAltPressed &&
      (_useCommand ? k.isMetaPressed : k.isControlPressed);
}

/// The same for the raw key events Linux still uses.
// ignore: deprecated_member_use
bool isReleaseKeyboardRawChord(RawKeyEvent e) {
  // ignore: deprecated_member_use
  if (e is! RawKeyDownEvent || e.repeat) return false;
  if (!_isG(e.logicalKey, e.physicalKey)) return false;
  return e.isShiftPressed &&
      e.isAltPressed &&
      (_useCommand ? e.isMetaPressed : e.isControlPressed);
}

/// Moves the keyboard between the remote screen and the session toolbar.
///
/// [screenNode] is the focus node of the remote screen. Wrap the toolbar in
/// a FocusScope with [toolbarScope] so release() has somewhere to put focus.
class RemoteKeyboardController {
  RemoteKeyboardController({required this.screenNode});

  final FocusNode screenNode;
  final FocusScopeNode toolbarScope =
      FocusScopeNode(debugLabel: 'remote toolbar');

  /// True after the combination released the keyboard, until the user gives
  /// it back (the combination, a click on the screen or the mouse entering
  /// it). While true, the page must not hand the keyboard to the remote
  /// computer on its own, for example when the window gets focus again.
  bool releasedByKey = false;

  /// Takes the keyboard from the remote computer.
  ///
  /// [leaveRemote] stops sending keys (unfocus, end the grab). [showToolbar]
  /// brings back a hidden or collapsed toolbar. Focus then goes to the first
  /// control of the toolbar, and the screen reader says how to give the
  /// keyboard back.
  void release(BuildContext context,
      {required VoidCallback leaveRemote, VoidCallback? showToolbar}) {
    releasedByKey = true;
    leaveRemote();
    if (screenNode.hasFocus) screenNode.unfocus();
    showToolbar?.call();
    // Focus the scope at once, so no key reaches the screen in between; the
    // toolbar's first control may only exist after the next frame.
    toolbarScope.requestFocus();
    SchedulerBinding.instance.addPostFrameCallback((_) => focusToolbar());
    ndAnnounce(
        context, tr('nd-keyboard-released', [releaseKeyboardChordLabel()]));
  }

  /// Puts focus on the first control of the toolbar, or on the toolbar
  /// itself when it has none.
  void focusToolbar() {
    // The keyboard went back to the remote computer in the meantime.
    if (!releasedByKey || screenNode.hasFocus) return;
    final first = ReadingOrderTraversalPolicy()
        .findFirstFocus(toolbarScope, ignoreCurrentFocus: true);
    if (first != null && first != toolbarScope) {
      first.requestFocus();
    } else {
      toolbarScope.requestFocus();
    }
  }

  /// Gives the keyboard back to the remote computer. [enterRemote] focuses
  /// the screen and starts the grab the way the platform needs it.
  void take({required VoidCallback enterRemote}) {
    releasedByKey = false;
    enterRemote();
  }

  void dispose() {
    toolbarScope.dispose();
  }
}

/// The remote screen: takes the keys, names itself for assistive tech and
/// lets the release combination through to [onReleaseKeyboard].
///
/// Every other key goes to [onKeyEvent] (or [onRawKeyEvent] when
/// [useRawKeyEvents]), which sends it to the remote computer.
class RemoteKeyboardScope extends StatelessWidget {
  const RemoteKeyboardScope({
    super.key,
    this.focusNode,
    this.onFocusChange,
    required this.useRawKeyEvents,
    required this.onKeyEvent,
    // ignore: deprecated_member_use
    required this.onRawKeyEvent,
    this.peerName,
    this.onReleaseKeyboard,
    required this.child,
  });

  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final bool useRawKeyEvents;
  final KeyEventResult Function(KeyEvent e) onKeyEvent;
  // ignore: deprecated_member_use
  final KeyEventResult Function(RawKeyEvent e) onRawKeyEvent;

  /// The name of the remote computer, for the screen's label. Without it the
  /// screen has no name (mobile).
  final String? peerName;

  /// Called for the release combination instead of [onKeyEvent].
  final VoidCallback? onReleaseKeyboard;
  final Widget child;

  void _focusChanged(BuildContext context, bool focused) {
    onFocusChange?.call(focused);
    final name = peerName;
    if (focused && name != null && onReleaseKeyboard != null) {
      ndAnnounce(context,
          tr('nd-keyboard-taken', [name, releaseKeyboardChordLabel()]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = onReleaseKeyboard;
    Widget scope = FocusScope(
        autofocus: true,
        child: Focus(
            autofocus: true,
            canRequestFocus: true,
            focusNode: focusNode,
            onFocusChange: (f) => _focusChanged(context, f),
            onKey: useRawKeyEvents
                ? (FocusNode data, RawKeyEvent event) {
                    if (release != null && isReleaseKeyboardRawChord(event)) {
                      release();
                      return KeyEventResult.handled;
                    }
                    return onRawKeyEvent(event);
                  }
                : null,
            onKeyEvent: useRawKeyEvents
                ? null
                : (FocusNode node, KeyEvent event) {
                    if (release != null && isReleaseKeyboardChord(event)) {
                      release();
                      return KeyEventResult.handled;
                    }
                    return onKeyEvent(event);
                  },
            child: child));
    final name = peerName;
    if (name == null) return scope;
    final chord = releaseKeyboardChordLabel();
    return Semantics(
      container: true,
      label: tr('nd-remote-screen-label', [name]),
      hint: tr('nd-remote-screen-hint', [name, chord]),
      child: scope,
    );
  }
}

/// Gives the keyboard back to the remote computer on the release
/// combination while focus is anywhere else in the session window, for
/// example on the toolbar after a release.
class RemoteKeyboardTakeBack extends StatelessWidget {
  const RemoteKeyboardTakeBack(
      {super.key, required this.onTake, required this.child});

  final VoidCallback onTake;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: (node, e) {
        if (!isReleaseKeyboardChord(e)) return KeyEventResult.ignored;
        onTake();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
