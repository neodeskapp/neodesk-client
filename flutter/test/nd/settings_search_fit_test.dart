// The settings search field's placeholder fits the navigation column in
// every language the client is checked in (the German one was cut).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  for (final lang in ['en', 'de']) {
    testWidgets('the search placeholder is not cut ($lang)', (tester) async {
      // tr() below runs before pumpScreen sets the language.
      useLanguage(lang);
      await pumpScreen(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 400,
              child: SettingsNav<String>(
                items: [SettingsNavItem('general', tr('nd-set-general'))],
                value: 'general',
                onChanged: (_) {},
                // As desktop_setting_page.dart builds it.
                search: NdSearchField(
                    placeholder: tr('nd-set-search'), height: 32),
              ),
            ),
          ),
          size: const Size(800, 500),
          lang: lang);
      final hint =
          tester.renderObject<RenderParagraph>(find.text(tr('nd-set-search')));
      expect(hint.didExceedMaxLines, isFalse, reason: tr('nd-set-search'));
      expect(hint.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(hint.size.width + 0.5),
          reason: '${tr('nd-set-search')} needs more room');
    });
  }
}
