import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' show globalKey;

import '../../theme/nd_theme.dart';

/// Shows an NdDialog (or any widget) centred over the window with the scrim
/// and a 150 ms fade. Escape closes it; focus returns to what opened it.
Future<T?> showNdDialog<T>(
  Widget Function(void Function([T? result]) close, StateSetter setState)
      builder, {
  BuildContext? context,
}) {
  final ctx = context ?? globalKey.currentContext;
  if (ctx == null) return Future.value(null);
  final reduce = MediaQuery.maybeOf(ctx)?.disableAnimations ?? false;
  return showGeneralDialog<T>(
    context: ctx,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(ctx).modalBarrierDismissLabel,
    barrierColor: ctx.nd.scrim,
    transitionDuration: reduce ? Duration.zero : NdSize.dialogMotion,
    transitionBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (dialogContext, _, __) {
      void close([T? r]) => Navigator.of(dialogContext).pop(r);
      return Center(
        // A scope of its own, so that the autofocus of a field inside
        // applies. A plain Focus would take the dialog's first focus itself
        // and leave a freshly opened dialog with no field to type into.
        child: FocusScope(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              close();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: StatefulBuilder(
              builder: (context, setState) => builder(close, setState)),
        ),
      );
    },
  );
}
