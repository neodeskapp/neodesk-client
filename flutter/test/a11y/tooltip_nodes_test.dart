// Windows tree (root-cause.md, cause 3): the Flutter 3.24 bridge stops
// updating the accessibility tree after one rejected update, and Tooltip
// semantics in lists and overlays are a known trigger. The shared buttons
// give their name through a label, so their tooltips stay out of the
// semantics tree. (findings.md F01, F18, F19)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common.dart' show ColorThemeExtension;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/widgets/nd_toolbar_button.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart'
    show ActionIcon, TabbarTheme;
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';

List<String> _tooltips(WidgetTester tester) {
  final out = <String>[];
  void visit(SemanticsNode n) {
    final t = n.getSemanticsData().tooltip;
    if (t.isNotEmpty) out.add(t);
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return out;
}

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('the shared buttons put no tooltip nodes in the tree',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        Material(
          child: Center(
            child: Wrap(spacing: 8, children: [
              NdIconButton(
                  icon: NdIcons.close, tooltip: 'Close', onPressed: () {}),
              NdButton(
                  label: 'Copy', tooltip: 'Copy the ID', onPressed: () {}),
              NdToolbarButton(
                  icon: NdIcons.chat,
                  label: 'Chat',
                  showLabel: false,
                  onPressed: () {}),
              ActionIcon(message: 'Close', icon: NdIcons.close, onTap: () {}),
              NdWindowControls(
                  onMinimize: () {}, onMaximize: () {}, onClose: () {}),
            ]),
          ),
        ),
        size: const Size(800, 200),
        extra: (c) => [ColorThemeExtension.from(c), TabbarTheme.from(c)]);
    expect(_tooltips(tester), isEmpty);
    // The names are still there, as labels.
    for (final name in ['Close', 'Copy', 'Chat', 'Minimize', 'Maximize']) {
      expect(find.bySemanticsLabel(name), findsWidgets, reason: name);
    }
    handle.dispose();
  });
}
