// WCAG 1.3.1, 2.1.1, 2.4.3 and 4.1.2 for dialogs: a dialog is a named,
// modal dialog to assistive tech, the page under it drops out, Shift+Tab
// goes backwards, Enter on a button presses that button, and focus goes
// back to what opened the dialog. (findings.md F28 to F32)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart'
    show CustomAlertDialog, OverlayDialogManager, OverlayKeyState;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';
import 'a11y_helpers.dart';

class _Page {
  final keyState = OverlayKeyState();
  final manager = OverlayDialogManager();
  final opener = FocusNode(debugLabel: 'opener');
  final log = <String>[];

  Widget build() => Overlay(key: keyState.key, initialEntries: [
        OverlayEntry(
            builder: (_) => Material(
                  child: Center(
                    child: ElevatedButton(
                        focusNode: opener,
                        onPressed: () {},
                        child: const Text('Open details')),
                  ),
                )),
      ]);

  Future<void> show() {
    manager.setOverlayState(keyState);
    return manager.show((setState, close, context) => CustomAlertDialog(
          semanticLabel: 'Connection error',
          content: const Text('ID does not exist'),
          actions: [
            TextButton(
                onPressed: () {
                  log.add('cancel');
                  close();
                },
                child: const Text('Cancel')),
            TextButton(
                onPressed: () {
                  log.add('ok');
                  close();
                },
                child: const Text('OK')),
          ],
          onSubmit: () {
            log.add('submit');
            close();
          },
          onCancel: close,
        ));
  }
}

/// Every label in the semantics tree that assistive tech gets.
List<String> _treeLabels(WidgetTester tester) {
  final out = <String>[];
  void visit(SemanticsNode n) {
    final l = n.getSemanticsData().label;
    if (l.isNotEmpty) out.add(l);
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

  testWidgets('NdDialog is a dialog named by its title', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        Center(
          child: NdDialog(
              title: 'Change ID',
              onClose: () {},
              children: const [Text('Your ID is 418 205 739.')],
              actions: [NdButton(label: 'Save', onPressed: () {})]),
        ),
        size: const Size(700, 400));
    final d = tester.getSemantics(find.byType(NdDialog)).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.scopesRoute), isTrue);
    expect(d.hasFlag(SemanticsFlag.namesRoute), isTrue);
    expect(d.label, 'Change ID');
    final title = tester.getSemantics(find.text('Change ID')).getSemanticsData();
    expect(title.hasFlag(SemanticsFlag.isHeader), isTrue);
    handle.dispose();
  });

  testWidgets('an overlay dialog hides the page, is named and modal',
      (tester) async {
    final handle = tester.ensureSemantics();
    final p = _Page();
    await pumpScreen(tester, p.build(), size: const Size(700, 500));
    expect(_treeLabels(tester), contains('Open details'));
    p.show();
    await tester.pumpAndSettle();
    expect(_treeLabels(tester), isNot(contains('Open details')),
        reason: 'the page under the dialog must leave the tree');
    expect(find.bySemanticsLabel('Connection error'), findsOneWidget);
    final named = tester
        .getSemantics(find.bySemanticsLabel('Connection error'))
        .getSemanticsData();
    expect(named.hasFlag(SemanticsFlag.namesRoute), isTrue);
    handle.dispose();
  });

  testWidgets('Shift+Tab goes backwards and Enter presses the focused button',
      (tester) async {
    final p = _Page();
    await pumpScreen(tester, p.build(), size: const Size(700, 500));
    p.show();
    await tester.pumpAndSettle();
    final forward = await tabOrder(tester, max: 2);
    expect(forward, ['Cancel', 'OK']);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(focusedName(), 'Cancel');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(p.log, ['cancel'], reason: 'Enter on Cancel must not submit');
  });

  testWidgets('focus goes back to what opened the dialog', (tester) async {
    final p = _Page();
    await pumpScreen(tester, p.build(), size: const Size(700, 500));
    p.opener.requestFocus();
    await tester.pump();
    p.show();
    await tester.pumpAndSettle();
    expect(p.opener.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(p.opener.hasPrimaryFocus, isTrue);
  });
}
