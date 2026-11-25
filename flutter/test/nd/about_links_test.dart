// About links the NeoDesk community on Discord next to the licence and the
// source code.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Widget _about({VoidCallback? onCommunity}) => AboutView(
      facts: const AboutFacts(
          version: '1.5.0',
          buildDate: '20 Nov 2026',
          id: '418205739',
          fingerprint: '8f3a 61c2 d09b 4e77'),
      onViewLicence: () {},
      onSource: () {},
      onUpstream: () {},
      onCheckUpdates: () {},
      onCommunity: onCommunity,
    );

void main() {
  test('the Discord invite is the NeoDesk one', () {
    expect(kNeoDeskDiscordUrl, 'https://discord.gg/nwERSawufr');
  });

  for (final lang in ['en', 'de']) {
    testWidgets('About opens the Discord from its link ($lang)',
        (tester) async {
      var opened = 0;
      await pumpScreen(tester, _about(onCommunity: () => opened++),
          size: const Size(900, 700), lang: lang);
      final link = find.widgetWithText(NdButton, tr('nd-about-community'));
      expect(link, findsOneWidget);
      expect(tr('nd-about-community'), contains('Discord'));
      expect(find.byIcon(NdIcons.forum), findsOneWidget);
      await tester.tap(link);
      expect(opened, 1);
    });
  }

  testWidgets('About without a community link shows none', (tester) async {
    await pumpScreen(tester, _about(), size: const Size(900, 700));
    expect(find.text(tr('nd-about-community')), findsNothing);
    expect(find.byIcon(NdIcons.forum), findsNothing);
  });
}
