// Check for updates in About, the update notice on the home screen, and how
// the core's answer to a check is read.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_widgets.dart';
import 'package:flutter_hbb/desktop/widgets/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _url =
    'https://github.com/neodeskapp/neodesk-client/releases/tag/desktop-v1.5.0-rc.9';

Widget _about({
  String? result,
  String? actionLabel,
  VoidCallback? onAction,
  VoidCallback? onCheck,
  bool checking = false,
}) =>
    AboutView(
      facts: const AboutFacts(
          version: '1.5.0-rc.8',
          buildDate: '2026-11-26 00:36',
          id: '987654321',
          fingerprint: 'ed94 ebd5 2908 b6c6'),
      onViewLicence: () {},
      onSource: () {},
      onUpstream: () {},
      onCheckUpdates: onCheck ?? () {},
      checking: checking,
      updateResult: result,
      updateActionLabel: actionLabel,
      onUpdateAction: onAction,
    );

/// [child] on the page background, as the settings page and home show it.
Widget _page(Widget child) =>
    Builder(builder: (c) => ColoredBox(color: c.nd.bg, child: child));

void main() {
  group('the answer of a check', () {
    setUp(() => useLanguage('en'));

    test('a newer release gives its version, page and Update', () {
      final r = UpdateCheckResult.parse(
          '{"version":"1.5.0-rc.9","url":"$_url"}');
      expect(r.hasUpdate, isTrue);
      expect(r.version, '1.5.0-rc.9');
      expect(r.url, _url);
      expect(r.message(), 'Version 1.5.0-rc.9 is out.');
      expect(r.actionLabel(canInstall: true), 'Update to 1.5.0-rc.9');
      expect(r.actionLabel(canInstall: false), 'Download 1.5.0-rc.9');
    });

    test('an empty answer is the latest version, with no button', () {
      final r = UpdateCheckResult.parse('');
      expect(r.hasUpdate, isFalse);
      expect(r.message(), 'You have the latest version.');
      expect(r.actionLabel(canInstall: true), isNull);
    });

    test('a failed check says why', () {
      final r = UpdateCheckResult.parse(
          'error:Failed to read the release list: 403 Forbidden');
      expect(r.hasUpdate, isFalse);
      expect(r.message(),
          "Couldn't check for updates: Failed to read the release list: 403 Forbidden");
      expect(r.actionLabel(canInstall: true), isNull);
    });

    test('an answer that is not the expected JSON is an error', () {
      for (final answer in ['{"version":""}', '[1]', 'nonsense']) {
        final r = UpdateCheckResult.parse(answer);
        expect(r.hasUpdate, isFalse, reason: answer);
        expect(r.error, isNotNull, reason: answer);
      }
    });

    test('German', () {
      useLanguage('de');
      final r = UpdateCheckResult.parse(
          '{"version":"1.5.0-rc.9","url":"$_url"}');
      expect(r.message(), 'Version 1.5.0-rc.9 ist erschienen.');
      expect(r.actionLabel(canInstall: true), 'Auf 1.5.0-rc.9 aktualisieren');
    });
  });

  test('the version of a release page', () {
    expect(versionOfReleaseUrl(_url), '1.5.0-rc.9');
    expect(versionOfReleaseUrl('$_url/'), '1.5.0-rc.9');
    expect(versionOfReleaseUrl(''), '');
  });

  for (final lang in ['en', 'de']) {
    testWidgets('About offers the update it found ($lang)', (tester) async {
      var taken = 0;
      final r = UpdateCheckResult.parse(
          '{"version":"1.5.0-rc.9","url":"$_url"}');
      await pumpScreen(tester, _about(), size: const Size(900, 700), lang: lang);
      final label = r.actionLabel(canInstall: true)!;
      await pumpScreen(
          tester,
          _about(
              result: r.message(),
              actionLabel: label,
              onAction: () => taken++),
          size: const Size(900, 700),
          lang: lang);
      expect(find.text(r.message()), findsOneWidget);
      final update = find.widgetWithText(NdButton, label);
      expect(update, findsOneWidget);
      expect(tester.widget<NdButton>(update).kind, NdButtonKind.primary);
      await tester.tap(update);
      expect(taken, 1);
    });
  }

  testWidgets('About shows no update button without a newer release',
      (tester) async {
    useLanguage('en');
    await pumpScreen(tester, _about(result: tr('nd-about-latest')),
        size: const Size(900, 700));
    expect(find.text('You have the latest version.'), findsOneWidget);
    expect(find.widgetWithText(NdButton, 'Check for updates'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is NdButton && w.kind == NdButtonKind.primary),
        findsNothing);
  });

  testWidgets('Check for updates waits while a check runs', (tester) async {
    var checks = 0;
    await pumpScreen(
        tester,
        _about(
            result: tr('nd-about-checking'),
            checking: true,
            onCheck: () => checks++),
        size: const Size(900, 700));
    final check = find.widgetWithText(NdButton, tr('nd-about-check'));
    expect(tester.widget<NdButton>(check).onPressed, isNull);
    await tester.tap(check, warnIfMissed: false);
    expect(checks, 0);
  });

  for (final (canInstall, button) in [(true, 'Update'), (false, 'Download')]) {
    testWidgets('the home notice names the version and offers $button',
        (tester) async {
      var acted = 0, notes = 0, closed = 0;
      await pumpScreen(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 560,
              child: UpdateNotice(
                version: '1.5.0-rc.9',
                canInstall: canInstall,
                onAction: () => acted++,
                onWhatsNew: () => notes++,
                onClose: () => closed++,
              ),
            ),
          ),
          size: const Size(700, 300));
      expect(find.text('NeoDesk 1.5.0-rc.9 is out.'), findsOneWidget);
      await tester.tap(find.widgetWithText(NdButton, button));
      await tester.tap(find.widgetWithText(NdButton, "What's new"));
      await tester.tap(find.byType(NdIconButton));
      expect((acted, notes, closed), (1, 1, 1));
    });
  }

  // Pictures for the pull request (ND_SHOTS_DIR): About after a check found
  // a release, and the home notice, in the reporter's German.
  for (final b in Brightness.values) {
    testWidgets('pictures of About and the notice (${b.name})', (tester) async {
      useLanguage('de');
      final r = UpdateCheckResult.parse(
          '{"version":"1.5.0-rc.9","url":"$_url"}');
      await pumpScreen(
          tester,
          _page(_about(
              result: r.message(),
              actionLabel: r.actionLabel(canInstall: true),
              onAction: () {})),
          size: const Size(720, 640),
          brightness: b,
          lang: 'de');
      await shot(tester, 'client-about-update', b);
      await pumpScreen(
          tester,
          _page(Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 520,
                child: UpdateNotice(
                    version: '1.5.0-rc.9',
                    canInstall: true,
                    onAction: () {},
                    onWhatsNew: () {},
                    onClose: () {}),
              ),
            ),
          )),
          size: const Size(552, 120),
          brightness: b,
          lang: 'de');
      await shot(tester, 'client-update-notice', b);
    });
  }
}
