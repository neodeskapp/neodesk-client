// Shared helpers for the accessibility tests.

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Presses Tab (or Shift+Tab with [backwards]) up to [max] times and returns
/// the semantics name of every node that had the primary focus, in order.
/// Stops when focus comes back to the first one.
Future<List<String>> tabOrder(WidgetTester tester,
    {int max = 40, bool backwards = false}) async {
  final seen = <String>[];
  for (var i = 0; i < max; i++) {
    if (backwards) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (backwards) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.pump();
    final entry = focusedName();
    if (entry == null) continue;
    if (seen.isNotEmpty && seen.first == entry) break;
    seen.add(entry);
  }
  return seen;
}

/// The semantics name (label, tooltip, value) of the node with the primary
/// focus, or its widget type in angle brackets when it has none.
String? focusedName() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  var label = '';
  RenderObject? r = ctx.findRenderObject();
  while (r != null && label.isEmpty) {
    final s = r.debugSemantics;
    if (s != null) {
      final d = s.getSemanticsData();
      label = [d.label, d.tooltip, d.value]
          .where((x) => x.isNotEmpty)
          .join(' | ');
    }
    r = r.parent;
  }
  return label.isEmpty ? '<${ctx.widget.runtimeType}>' : label;
}

class Announcement {
  Announcement(this.message, this.assertive);
  final String message;
  final bool assertive;
  @override
  String toString() => '${assertive ? '!' : ''}$message';
}

/// Records what SemanticsService.announce sends to the screen reader.
List<Announcement> recordAnnouncements(WidgetTester tester) {
  final said = <Announcement>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility, (dynamic msg) async {
    final m = msg as Map;
    if (m['type'] == 'announce') {
      final d = m['data'] as Map;
      said.add(Announcement('${d['message']}', d['assertiveness'] == 1));
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility, null));
  return said;
}
