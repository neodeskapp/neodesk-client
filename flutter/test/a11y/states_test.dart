// WCAG 1.3.1 and 4.1.2: states that are only drawn must also be said. The
// session toolbar's check and radio items say whether they are on, and a
// step of the install or join progress says whether it is done.
// (findings.md F25, F27)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/widgets/remote_toolbar.dart'
    show CkbMenuButton, RdoMenuButton;
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';

SemanticsData _sem(WidgetTester tester, String text) =>
    tester.getSemantics(find.text(text)).getSemanticsData();

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('toolbar check items say whether they are on', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CkbMenuButton(
                value: true,
                onChanged: (_) {},
                child: const Text('Show remote cursor')),
            CkbMenuButton(
                value: false,
                onChanged: (_) {},
                child: const Text('View only')),
          ]),
        ),
        size: const Size(400, 200));
    final on = _sem(tester, 'Show remote cursor');
    expect(on.hasFlag(SemanticsFlag.hasCheckedState), isTrue);
    expect(on.hasFlag(SemanticsFlag.isChecked), isTrue);
    expect(on.label, 'Show remote cursor');
    final off = _sem(tester, 'View only');
    expect(off.hasFlag(SemanticsFlag.hasCheckedState), isTrue);
    expect(off.hasFlag(SemanticsFlag.isChecked), isFalse);
    handle.dispose();
  });

  testWidgets('toolbar radio items say which one is chosen', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final q in ['Best', 'Balanced', 'Fast'])
              RdoMenuButton<String>(
                  value: q,
                  groupValue: 'Balanced',
                  onChanged: (_) {},
                  child: Text(q)),
          ]),
        ),
        size: const Size(400, 200));
    final chosen = _sem(tester, 'Balanced');
    expect(chosen.hasFlag(SemanticsFlag.isChecked), isTrue);
    expect(chosen.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
    expect(_sem(tester, 'Fast').hasFlag(SemanticsFlag.isChecked), isFalse);
    handle.dispose();
  });

  testWidgets('a progress step says its state', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        const Column(mainAxisSize: MainAxisSize.min, children: [
          NdStepRow(state: NdStepState.done, text: 'Copy files'),
          NdStepRow(state: NdStepState.running, text: 'Set up the service'),
          NdStepRow(state: NdStepState.todo, text: 'Start NeoDesk'),
        ]),
        size: const Size(400, 200));
    expect(find.bySemanticsLabel('Done: Copy files'), findsOneWidget);
    expect(find.bySemanticsLabel('In progress: Set up the service'),
        findsOneWidget);
    expect(find.bySemanticsLabel('To do: Start NeoDesk'), findsOneWidget);
    handle.dispose();
  });
}
