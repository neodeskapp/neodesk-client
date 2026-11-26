// WCAG 4.1.2, 1.3.1 and 2.5.3 Label in Name: the control in a settings row
// is named by the row's visible label. (findings.md F24)

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('a switch, a choice and a select are named by their row',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(
        tester,
        SingleChildScrollView(
          child: Column(children: [
            SettingsRow(
                label: 'Allow connections',
                control: NdSwitch(value: true, onChanged: (_) {})),
            SettingsRow(
              label: 'Theme',
              control: NdSegmented<int>(
                  segments: const [NdSegment(0, 'Light'), NdSegment(1, 'Dark')],
                  value: 0,
                  onChanged: (_) {}),
            ),
            SettingsRow(
              label: 'Language',
              control: NdSelect<String>(
                  options: const [NdOption('en', 'English')],
                  value: 'en',
                  onChanged: (_) {}),
            ),
          ]),
        ),
        size: const Size(800, 400));
    final sw = tester.getSemantics(find.byType(NdSwitch)).getSemanticsData();
    expect(sw.hasFlag(SemanticsFlag.hasToggledState), isTrue);
    expect(sw.label, 'Allow connections');
    final group = tester
        .getSemantics(find.byType(NdSegmented<int>))
        .getSemanticsData();
    expect(group.label, 'Theme', reason: 'the choice group is named');
    final select =
        tester.getSemantics(find.byType(NdPressable).last).getSemanticsData();
    expect(select.label, 'Language');
    expect(select.value, 'English');
    handle.dispose();
  });
}
