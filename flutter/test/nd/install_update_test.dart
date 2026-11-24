// L476: an exe started next to a NeoDesk installed from another file
// offered no update. Its install page now updates an older exe install and
// leaves a newer one, an MSI install and one of unknown version alone.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/install_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Future<void> _pump(WidgetTester tester, InstalledStanding standing,
    {VoidCallback? onUpdate,
    VoidCallback? onOpen,
    bool installing = false,
    String? error,
    String lang = 'en'}) async {
  useLanguage(lang);
  final path = TextEditingController(text: r'C:\Program Files\NeoDesk');
  addTearDown(path.dispose);
  await pumpScreen(
    tester,
    InstallView(
      lead: tr('nd-install-lead'),
      pathController: path,
      startMenu: true,
      desktopIcon: true,
      printer: false,
      onStartMenu: (_) {},
      onDesktopIcon: (_) {},
      onPrinter: (_) {},
      onInstall: () {},
      onChangePath: () {},
      onLicence: () {},
      onRunWithout: () {},
      onToggleOptions: () {},
      installing: installing,
      error: error,
      installed: standing,
      onUpdate: onUpdate ?? () {},
      onOpenInstalled: onOpen ?? () {},
    ),
    size: const Size(680, 560),
    lang: lang,
  );
}

void main() {
  test('the core\'s answer reads as a standing', () {
    final s = InstalledStanding.parse(
        '{"standing":"older","installed":"1.5.0-rc.6","this":"1.5.0-rc.7","msi":false}')!;
    expect(s.offersUpdate, isTrue);
    expect(s.installed, '1.5.0-rc.6');
    expect(s.version, '1.5.0-rc.7');
    expect(InstalledStanding.parse(''), isNull);
    expect(
        InstalledStanding.parse(
                '{"standing":"older","installed":"1.5.0-rc.6","this":"1.5.0-rc.7","msi":true}')!
            .offersUpdate,
        isFalse);
  });

  testWidgets('an older exe install is offered the update', (tester) async {
    var updated = 0;
    await _pump(
        tester,
        const InstalledStanding(
            standing: 'older', installed: '1.5.0-rc.6', version: '1.5.0-rc.7'),
        onUpdate: () => updated++);
    expect(find.text('Update NeoDesk'), findsOneWidget);
    expect(find.textContaining('NeoDesk 1.5.0-rc.6 is installed'),
        findsOneWidget);
    expect(find.textContaining('keeps its ID, key, password and settings'),
        findsOneWidget);
    expect(find.text('Install'), findsNothing);
    await tester.tap(find.text('Update NeoDesk to 1.5.0-rc.7'));
    expect(updated, 1);
  });

  testWidgets('a newer install is left alone and can be opened',
      (tester) async {
    var opened = 0;
    await _pump(
        tester,
        const InstalledStanding(
            standing: 'newer', installed: '1.5.0', version: '1.5.0-rc.7'),
        onOpen: () => opened++);
    expect(find.textContaining('A newer NeoDesk, 1.5.0, is installed'),
        findsOneWidget);
    expect(find.textContaining('Update NeoDesk to'), findsNothing);
    expect(find.text('Install'), findsNothing);
    await tester.tap(find.text('Open NeoDesk'));
    expect(opened, 1);
  });

  testWidgets('an MSI install is pointed to the MSI', (tester) async {
    await _pump(
        tester,
        const InstalledStanding(
            standing: 'older',
            installed: '1.5.0-rc.6',
            version: '1.5.0-rc.7',
            msi: true));
    expect(find.textContaining('with the MSI'), findsOneWidget);
    expect(find.textContaining('Update NeoDesk to'), findsNothing);
    expect(find.text('Install'), findsNothing);
  });

  testWidgets('an install of unknown version is left alone', (tester) async {
    await _pump(
        tester,
        const InstalledStanding(
            standing: 'unknown', installed: '', version: '1.5.0-rc.7'));
    expect(find.textContaining("version can't be read"), findsOneWidget);
    expect(find.textContaining('Update NeoDesk to'), findsNothing);
    expect(find.text('Install'), findsNothing);
  });

  testWidgets('the update shows its steps and a refused prompt',
      (tester) async {
    const older = InstalledStanding(
        standing: 'older', installed: '1.5.0-rc.6', version: '1.5.0-rc.7');
    await _pump(tester, older, installing: true);
    expect(find.text('Updating NeoDesk…'), findsOneWidget);
    expect(find.text('Asking Windows for permission'), findsOneWidget);
    await _pump(tester, older, error: tr('nd-update-cancelled'));
    expect(find.textContaining('nothing was updated'), findsOneWidget);
  });

  testWidgets('the update page is in German too', (tester) async {
    await _pump(
        tester,
        const InstalledStanding(
            standing: 'older', installed: '1.5.0-rc.6', version: '1.5.0-rc.7'),
        lang: 'de');
    expect(find.text('NeoDesk aktualisieren'), findsOneWidget);
    expect(find.text('NeoDesk auf 1.5.0-rc.7 aktualisieren'), findsOneWidget);
  });
}
