// "Sign in with NeoDesk": when the server offers the sign-in through the
// web console, the sign-in dialog puts it first, then "or", then Username
// and Password, then the other providers. Older servers without it keep
// the dialog as it was. While it waits, the dialog says it waits for the
// Allow in the browser and has a Cancel.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fixtures.dart';
import 'harness.dart';

Finder _neodeskButton() => find.byType(NdNeoDeskSignInButton);

/// A line of text, also when it is selectable.
Finder _line(String text) => find.byWidgetPredicate((w) =>
    (w is Text && w.data == text) || (w is SelectableText && w.data == text));

void main() {
  group('login options', () {
    test('NeoDesk goes apart, the other providers keep their order', () {
      final split = splitLoginOptions([
        {'name': 'GitHub'},
        {'name': 'NeoDesk', 'icon': '<svg/>'},
        {'name': 'Okta'},
      ]);
      expect(split.neodesk?.op, 'NeoDesk');
      expect(split.neodesk?.icon, '<svg/>');
      expect(split.others.map((e) => e.op), ['GitHub', 'Okta']);
    });

    test('only the exact name NeoDesk is the console sign-in', () {
      final split = splitLoginOptions([
        {'name': 'neodesk'},
        {'name': 'NeoDesk SSO'},
      ]);
      expect(split.neodesk, isNull);
      expect(split.others.map((e) => e.op), ['neodesk', 'NeoDesk SSO']);
    });

    test('an older server without NeoDesk keeps its providers', () {
      final split = splitLoginOptions([
        {'name': 'Keycloak'},
        {'icon': 'no name'},
        'not a map',
      ]);
      expect(split.neodesk, isNull);
      expect(split.others.map((e) => e.op), ['Keycloak']);
    });

    test('the waiting line names the browser for NeoDesk only', () {
      expect(oidcStateMessageKey('NeoDesk', 'Waiting account auth'),
          'nd-sign-in-browser-waiting');
      expect(oidcStateMessageKey('NeoDesk', 'Requesting account auth'),
          'nd-sign-in-browser-waiting');
      expect(oidcStateMessageKey('GitHub', 'Waiting account auth'),
          'Waiting account auth');
    });

    test('the new texts have English and German', () {
      for (final lang in ['en', 'de']) {
        useLanguage(lang);
        for (final k in [
          'nd-sign-in-with-neodesk',
          'nd-sign-in-browser-waiting',
        ]) {
          expect(translate(k), isNot(k), reason: '$lang $k');
        }
      }
      useLanguage('de');
      expect(translate('nd-sign-in-with-neodesk'), 'Mit NeoDesk anmelden');
      expect(translate('Sign-in was declined in the browser'),
          isNot('Sign-in was declined in the browser'));
    });
  });

  group('sign-in dialog', () {
    late TextEditingController user, pass;
    late RxString curOP;
    late int starts, cancels;

    Widget neodeskOp() => WidgetOP(
          config: ConfigOP(op: kNeoDeskOp, icon: null),
          curOP: curOP,
          cbLogin: (_) {},
          // The backend's wait is not started here: the dialog shows the
          // waiting state as soon as the op is the current one.
          startAuth: (op) async {
            starts++;
            curOP.value = op;
            return false;
          },
          cancelAuth: (op) async {
            cancels++;
            return true;
          },
          canStartAuth: () => true,
        );

    Widget dialog({Widget? above}) => Builder(
          builder: (context) => withDialog(
            context,
            ColoredBox(color: context.nd.bg),
            NdLoginDialog(
              username: user,
              password: pass,
              onSignIn: () {},
              onCancel: () {},
              above: above,
            ),
          ),
        );

    setUp(() {
      user = TextEditingController(text: 'lena');
      pass = TextEditingController();
      curOP = ''.obs;
      starts = 0;
      cancels = 0;
    });

    for (final lang in ['en', 'de']) {
      forBothThemes('Sign in with NeoDesk comes first ($lang)',
          (tester, b) async {
        await pumpScreen(tester, dialog(above: neodeskOp()),
            size: mainSize, brightness: b, lang: lang);
        final button = _neodeskButton();
        expect(button, findsOneWidget);
        expect(
            find.descendant(
                of: button,
                matching: find.text(translate('nd-sign-in-with-neodesk'))),
            findsOneWidget);
        expect(
            find.descendant(
                of: button,
                matching: find.byKey(const ValueKey('nd-neodesk-mark'))),
            findsOneWidget);
        final or = find.byKey(const ValueKey('nd-sign-in-or'));
        final username = find.widgetWithText(NdField, translate('Username'));
        expect(or, findsOneWidget);
        final buttonBottom = tester.getBottomLeft(button).dy;
        expect(tester.getTopLeft(or).dy, greaterThan(buttonBottom));
        expect(tester.getTopLeft(username).dy,
            greaterThan(tester.getBottomLeft(or).dy));
        // Full width: as wide as the Username field.
        expect(tester.getSize(button).width,
            moreOrLessEquals(tester.getSize(username).width, epsilon: 1));
        await shot(tester, 'client-sign-in-neodesk-$lang', b);
      });
    }

    testWidgets('without NeoDesk the dialog starts with Username',
        (tester) async {
      await pumpScreen(tester, dialog(), size: mainSize);
      expect(_neodeskButton(), findsNothing);
      expect(find.byKey(const ValueKey('nd-sign-in-or')), findsNothing);
      expect(find.widgetWithText(NdField, 'Username'), findsOneWidget);
    });

    for (final lang in ['en', 'de']) {
      forBothThemes('waiting for the browser, with Cancel ($lang)',
          (tester, b) async {
        await pumpScreen(tester, dialog(above: neodeskOp()),
            size: mainSize, brightness: b, lang: lang);
        final waiting = translate('nd-sign-in-browser-waiting');
        expect(_line(waiting), findsNothing);
        await tester.tap(_neodeskButton());
        await tester.pump();
        expect(starts, 1);
        expect(_line(waiting), findsOneWidget);
        // The generic line of the other providers is not shown.
        expect(_line(translate('Waiting account auth')), findsNothing);
        final cancel = find.byKey(const ValueKey('nd-sign-in-browser-cancel'));
        expect(cancel, findsOneWidget);
        expect(tester.getTopLeft(cancel).dy,
            lessThan(tester.getTopLeft(find.byType(NdField).first).dy));
        await shot(tester, 'client-sign-in-neodesk-waiting-$lang', b);

        await tester.tap(cancel);
        await tester.pump();
        await tester.pump();
        expect(cancels, 1);
        expect(curOP.value, '');
        expect(_line(waiting), findsNothing);
        expect(cancel, findsNothing);
      });
    }
  });
}
