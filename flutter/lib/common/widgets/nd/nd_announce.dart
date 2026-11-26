import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Reads [text] out through the screen reader, without moving focus.
///
/// Use it for status changes a screen reader user would otherwise miss:
/// connection state, an incoming request, a chat message, an error. Polite
/// waits for the reader to finish; [assertive] interrupts it.
void ndAnnounce(BuildContext? context, String text, {bool assertive = false}) {
  if (text.trim().isEmpty) return;
  final dir = (context == null ? null : Directionality.maybeOf(context)) ??
      TextDirection.ltr;
  SemanticsService.announce(text, dir,
      assertiveness:
          assertive ? Assertiveness.assertive : Assertiveness.polite);
}
