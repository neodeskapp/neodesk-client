// WCAG 1.3.1, 3.3.1, 3.3.2 and 4.1.2 for text fields: the label drawn above
// a field is its name, the error under it is read with it and said when it
// appears, and a field without a drawn label still has a name.
// (findings.md F21, F22, F23)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart' show DialogTextField;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';
import 'a11y_helpers.dart';

SemanticsData _field(WidgetTester tester) =>
    tester.getSemantics(find.byType(EditableText).first).getSemanticsData();

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('NdField is named by its label and describes its error',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        const Padding(
            padding: EdgeInsets.all(20),
            child: NdField(
                label: 'New ID',
                hint: '6 to 16 letters or digits',
                error: 'This ID is taken')),
        size: const Size(400, 160));
    final d = _field(tester);
    expect(d.hasFlag(SemanticsFlag.isTextField), isTrue);
    expect(d.label, 'New ID');
    expect(d.hint, 'This ID is taken');
    expect(find.bySemanticsLabel('New ID'), findsOneWidget,
        reason: 'the label is not a second, separate node');
    handle.dispose();
  });

  testWidgets('NdField without an error describes itself with its hint',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        const Padding(
            padding: EdgeInsets.all(20),
            child:
                NdField(label: 'New ID', hint: '6 to 16 letters or digits')),
        size: const Size(400, 160));
    expect(_field(tester).hint, '6 to 16 letters or digits');
    handle.dispose();
  });

  testWidgets('a new error is said at once', (tester) async {
    final said = recordAnnouncements(tester);
    final error = ValueNotifier<String?>(null);
    await pumpScreen(
        tester,
        Padding(
            padding: const EdgeInsets.all(20),
            child: ValueListenableBuilder<String?>(
                valueListenable: error,
                builder: (_, e, __) => NdField(label: 'Code', error: e))),
        size: const Size(400, 160));
    error.value = 'Code not valid';
    await tester.pump();
    expect(said.map((a) => a.message), ['Code not valid']);
    expect(said.single.assertive, isTrue);
  });

  testWidgets('a field without a drawn label keeps a name while focused',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        const Padding(
            padding: EdgeInsets.all(20),
            child: NdField(semanticLabel: 'Remote ID')),
        size: const Size(400, 120));
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    expect(_field(tester).label, 'Remote ID');
    handle.dispose();
  });

  testWidgets('DialogTextField reads its error with the field',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        Material(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: DialogTextField(
                  title: 'Password',
                  errorText: 'Wrong password',
                  controller: TextEditingController())),
        ),
        size: const Size(400, 200));
    final d = _field(tester);
    expect('${d.label} ${d.hint}', contains('Password'));
    expect(d.hint, contains('Wrong password'));
    handle.dispose();
  });
}
