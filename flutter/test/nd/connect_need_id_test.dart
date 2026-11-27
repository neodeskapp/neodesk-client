// Connect and More ways to connect with no ID entered: the hint under the
// field gives way to a red line that says the ID is missing, instead of
// nothing happening.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Widget _header({String? error, VoidCallback? onFiles}) =>
    Builder(builder: (context) {
      return ColoredBox(
        color: context.nd.bg,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConnectHeader(
            field: const NdField(large: true, mono: true),
            onConnect: () {},
            error: error,
            moreWays: [
              (tr('nd-home-files-only'), onFiles ?? () {}),
              (tr('nd-home-terminal'), () {}),
            ],
          ),
        ),
      );
    });

void main() {
  for (final lang in ['en', 'de']) {
    forBothThemes('missing ID replaces the hint ($lang)', (tester, b) async {
      useLanguage(lang);
      final error = tr('nd-home-connect-need-id');
      expect(error, isNot('nd-home-connect-need-id'));
      await pumpScreen(tester, _header(error: error),
          size: const Size(640, 260), brightness: b, lang: lang);
      expect(find.text(tr('nd-home-connect-hint')), findsNothing);
      final text = tester.widget<Text>(find.text(error));
      final danger =
          (b == Brightness.dark ? NdColors.dark : NdColors.light).danger;
      expect(text.style?.color, danger);
      await shot(tester, 'client-home-connect-need-id-$lang', b);
    });
  }

  testWidgets('without an error the hint shows', (tester) async {
    await pumpScreen(tester, _header(), size: const Size(640, 260));
    expect(find.text(tr('nd-home-connect-hint')), findsOneWidget);
    expect(find.text(tr('nd-home-connect-need-id')), findsNothing);
  });

  testWidgets('a way to connect runs its action', (tester) async {
    var files = 0;
    await pumpScreen(tester, _header(onFiles: () => files++),
        size: const Size(640, 360));
    await tester.tap(find.text(tr('nd-home-more-ways')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('nd-home-files-only')));
    await tester.pumpAndSettle();
    expect(files, 1);
  });
}
