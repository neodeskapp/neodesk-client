// WCAG 4.1.2 on Linux: text fields must stay visible to Orca. The freeze
// workaround (flutter/flutter#153560) hides them only on Cinnamon while no
// screen reader runs. (findings.md F43)
//
// The widget test runs on Linux, so isLinux is true here, as for a user.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common.dart' show WorkaroundFreezeLinuxMint;
import 'package:flutter_hbb/common/linux_field_semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/harness.dart';

Widget _field() => const Padding(
      padding: EdgeInsets.all(20),
      child: TextField(
          decoration: InputDecoration(labelText: 'Remote ID')),
    ).workaroundFreezeLinuxMint();

void main() {
  tearDown(() => hideLinuxFieldSemanticsForTest = null);

  test('fields hide only on Cinnamon without a screen reader', () {
    bool hide(String desktop, bool sr, {bool linux = true}) =>
        hideFieldSemanticsOnLinux(
            linux: linux, desktop: desktop, screenReaderOn: sr);
    expect(hide('X-Cinnamon:cinnamon', false), isTrue);
    expect(hide('X-Cinnamon:cinnamon', true), isFalse,
        reason: 'Orca needs the fields');
    expect(hide('ubuntu:GNOME:ubuntu', false), isFalse);
    expect(hide('KDE:plasma', false), isFalse);
    expect(hide(':', false), isFalse);
    expect(hide('X-Cinnamon:cinnamon', false, linux: false), isFalse);
  });

  testWidgets('a field outside Cinnamon is a named text field',
      (tester) async {
    final handle = tester.ensureSemantics();
    // No override: the real detection runs, in a session without Cinnamon.
    await pumpScreen(tester, _field(), size: const Size(400, 120));
    final d = tester.getSemantics(find.byType(EditableText)).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isTextField), isTrue);
    expect(d.label, contains('Remote ID'));
    handle.dispose();
  });

  testWidgets('with a screen reader on Cinnamon the field stays visible',
      (tester) async {
    final handle = tester.ensureSemantics();
    hideLinuxFieldSemanticsForTest = hideFieldSemanticsOnLinux(
        linux: true, desktop: 'X-Cinnamon:cinnamon', screenReaderOn: true);
    await pumpScreen(tester, _field(), size: const Size(400, 120));
    final d = tester.getSemantics(find.byType(EditableText)).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isTextField), isTrue);
    handle.dispose();
  });

  testWidgets('on Cinnamon without a screen reader the workaround still holds',
      (tester) async {
    final handle = tester.ensureSemantics();
    hideLinuxFieldSemanticsForTest = true;
    await pumpScreen(tester, _field(), size: const Size(400, 120));
    expect(find.bySemanticsLabel(RegExp('Remote ID')), findsNothing);
    handle.dispose();
  });
}
