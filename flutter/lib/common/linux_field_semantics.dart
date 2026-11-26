// Whether text fields hide from assistive tech on Linux.
//
// On some Cinnamon desktops (Linux Mint) a broken AT-SPI setup makes every
// accessibility call from the GTK embedder block for 25 seconds, and the app
// freezes when a text field gets focus (flutter/flutter#153560). Hiding the
// field from assistive tech avoids the calls, but it also hides the field
// from Orca. So fields hide only on Cinnamon, and only while no screen reader
// runs: a screen reader needs a working AT-SPI anyway.

import 'linux_field_semantics_detect.dart'
    if (dart.library.html) 'linux_field_semantics_detect_web.dart' as detect;

/// The rule, apart from how the facts are found. [desktop] is
/// XDG_CURRENT_DESKTOP and DESKTOP_SESSION joined.
bool hideFieldSemanticsOnLinux({
  required bool linux,
  required String desktop,
  required bool screenReaderOn,
}) =>
    linux && desktop.toLowerCase().contains('cinnamon') && !screenReaderOn;

/// Tests set this to skip the detection.
bool? hideLinuxFieldSemanticsForTest;

bool? _hide;

/// Decided once per process: on Linux it asks gsettings and looks for an
/// Orca process. Orca started after NeoDesk is seen after a restart.
bool get hideLinuxFieldSemantics =>
    hideLinuxFieldSemanticsForTest ??
    (_hide ??= detect.detect(hideFieldSemanticsOnLinux));
