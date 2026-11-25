// The labels of About stay on one line in every language: a longer word
// ("Fingerabdruck") widens the label column instead of breaking (L527).

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Widget _about() => AboutView(
      facts: const AboutFacts(
          version: '1.5.0',
          buildDate: '20 Nov 2026',
          id: '418205739',
          fingerprint: '8f3a 61c2 d09b 4e77'),
      onViewLicence: () {},
      onSource: () {},
      onUpstream: () {},
      onCheckUpdates: () {},
      onCommunity: () {},
    );

void main() {
  for (final lang in ['en', 'de']) {
    testWidgets('About keeps every label on one line ($lang)', (tester) async {
      await pumpScreen(tester, _about(),
          size: const Size(900, 700), lang: lang);
      final line = tester.getSize(find.text(tr('nd-about-version'))).height;
      for (final key in [
        'nd-about-build',
        'nd-fact-id',
        'nd-about-fingerprint',
        'nd-about-licence',
        'nd-about-source',
        'nd-about-based-on',
        'nd-about-help',
      ]) {
        expect(tester.getSize(find.text(tr(key))).height, line,
            reason: '${tr(key)} breaks');
      }
    });
  }
}
