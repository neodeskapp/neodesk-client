// Home's list header keeps every tab label whole: when the tabs and the
// search with its buttons don't fit on one row, the search moves to a row
// of its own above the tabs. The buttons look like NdIconButton. Signed
// out, Address book and Devices say what signing in shows, and the
// sign-in dialog is an NdDialog.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fixtures.dart';
import 'harness.dart';

const _tabKeys = [
  'nd-tab-recent',
  'nd-tab-favourites',
  'nd-tab-network',
  'nd-tab-address-book',
  'nd-tab-devices',
];

final _tagsHidden = false.obs;

/// Home as ConnectionPage lays it out, on Address book with the buttons
/// that tab shows: refresh, select, view, sort and tags (on).
Widget _home({Widget? list}) => Builder(builder: (context) {
      final left = ThisComputerColumn(
        id: '418205739',
        password: 'k7m2qx9w',
        status: HomeStatus(
            NdStatusKind.good, tr('nd-home-status-ready', [fernServer])),
        onNewPassword: () async {},
      );
      final right = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConnectHeader(
            field: const NdField(large: true, mono: true),
            onConnect: () {},
            moreWays: [(tr('nd-home-files-only'), () {})],
          ),
          const SizedBox(height: 22),
          PeerListHeader<int>(
            key: const ValueKey('header'),
            tabs: [
              for (var i = 0; i < _tabKeys.length; i++)
                NdTab(i, tr(_tabKeys[i])),
            ],
            value: 3,
            onChanged: (_) {},
            search: NdSearchField(
                key: const ValueKey('search'),
                placeholder: tr('nd-search'),
                width: 170,
                height: 30),
            actions: [
              RefreshWidget(
                  onPressed: () {},
                  child: Icon(NdIcons.refresh,
                      size: 18, color: context.nd.textMuted)),
              PeerListAction(
                  key: const ValueKey('select'),
                  tooltip: 'Select',
                  onTap: () {},
                  child: Icon(NdIcons.checkBox)),
              PeerListAction(
                  tooltip: 'Change view',
                  onTap: () {},
                  child: Icon(NdIcons.viewList)),
              PeerListAction(
                  tooltip: 'Sort by', onTap: () {}, child: Icon(NdIcons.sort)),
              PeerListAction(
                  key: const ValueKey('tags'),
                  tooltip: 'Toggle Tags',
                  onTap: () {},
                  on: _tagsHidden,
                  child: Icon(NdIcons.tags)),
            ],
          ),
          Expanded(child: list ?? peersSignIn('nd-home-sign-in-ab')),
        ],
      );
      return mainWindow(HomeLayout(left: left, right: right));
    });

/// Every tab label is whole: inside the header and clear of the search
/// field and the buttons. Returns the labels' rects.
List<Rect> _expectTabsWhole(WidgetTester tester) {
  final header = tester.getRect(find.byKey(const ValueKey('header')));
  final others = [
    tester.getRect(find.byKey(const ValueKey('search'))),
    for (final e in find.byType(PeerListAction).evaluate())
      tester.getRect(find.byWidget(e.widget)),
  ];
  final rects = <Rect>[];
  for (final k in _tabKeys) {
    final r = tester.getRect(find.text(translate(k)));
    expect(r.left, greaterThanOrEqualTo(header.left), reason: k);
    expect(r.right, lessThanOrEqualTo(header.right), reason: k);
    for (final o in others) {
      expect(r.overlaps(o), isFalse, reason: '$k is under $o');
    }
    // On the rule: the underline sits right under the label.
    expect(header.bottom - r.bottom, lessThan(14), reason: k);
    rects.add(r);
  }
  return rects;
}

/// [f] inside the dialog only; the page behind has a Sign in button too.
Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(NdDialog), matching: f);

void main() {
  for (final lang in ['en', 'de']) {
    forBothThemes('narrow home keeps the tabs whole ($lang)',
        (tester, b) async {
      await pumpScreen(tester, _home(),
          size: mainSize, brightness: b, lang: lang);
      _expectTabsWhole(tester);
      final search = tester.getRect(find.byKey(const ValueKey('search')));
      final first = tester.getRect(find.text(translate(_tabKeys.first)));
      // Doesn't fit next to the tabs at this size: the search went up.
      expect(search.bottom, lessThanOrEqualTo(first.top));
      await shot(tester, 'client-home-tabs-narrow-$lang', b);
    });
  }

  testWidgets('a wide home keeps tabs and search on one row', (tester) async {
    await pumpScreen(tester, _home(), size: const Size(1700, 720), lang: 'de');
    _expectTabsWhole(tester);
    final search = tester.getRect(find.byKey(const ValueKey('search')));
    final first = tester.getRect(find.text(translate(_tabKeys.first)));
    expect(search.top, lessThan(first.bottom));
    expect(search.bottom, greaterThan(first.top));
    final header = tester.getRect(find.byKey(const ValueKey('header')));
    expect(header.height, lessThan(50));
  });

  testWidgets('the buttons are drawn like NdIconButton', (tester) async {
    _tagsHidden.value = false;
    await pumpScreen(tester, _home(), size: mainSize);
    final c = NdColors.light;
    BoxDecoration boxOf(Finder f) => tester
        .widget<Container>(
            find.descendant(of: f, matching: find.byType(Container)).first)
        .decoration as BoxDecoration;
    IconThemeData iconOf(Finder f) => IconTheme.of(
        tester.element(find.descendant(of: f, matching: find.byType(Icon))));

    final select = find.byKey(const ValueKey('select'));
    expect(tester.getSize(select), const Size(30, 30));
    expect(iconOf(select).size, 18);
    expect(iconOf(select).color, c.textMuted);
    expect(boxOf(select).color, Colors.transparent);

    // Hover highlights show in the desktop's mouse mode, as in the app.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(select));
    await tester.pump();
    expect(boxOf(select).color, c.hover);

    // The tags panel shows: the toggle is on, in the accent.
    final tags = find.byKey(const ValueKey('tags'));
    expect(boxOf(tags).color, c.accentTint);
    expect(iconOf(tags).color, c.accent);
    _tagsHidden.value = true;
    await tester.pump();
    expect(boxOf(tags).color, Colors.transparent);
    expect(iconOf(tags).color, c.textMuted);
  });

  forBothThemes('signed out, the address book says to sign in',
      (tester, b) async {
    await pumpScreen(tester, _home(),
        size: mainSize, brightness: b, lang: 'de');
    final empty = find.byType(PeerListEmpty);
    expect(empty, findsOneWidget);
    final muted =
        (b == Brightness.dark ? NdColors.dark : NdColors.light).textMuted;
    final text =
        tester.widget<Text>(find.text(translate('nd-home-sign-in-ab')));
    expect(text.style?.color, muted);
    final button = find.descendant(of: empty, matching: find.byType(NdButton));
    expect(tester.widget<NdButton>(button).kind, NdButtonKind.primary);
    expect(tester.widget<NdButton>(button).label, 'Anmelden');
  });

  test('both signed-out lists have their sentence in en and de', () {
    for (final lang in ['en', 'de']) {
      useLanguage(lang);
      for (final k in [
        'nd-home-sign-in-ab',
        'nd-home-sign-in-devices',
        'nd-show-password',
        'nd-hide-password',
      ]) {
        expect(translate(k), isNot(k), reason: '$lang $k');
      }
    }
  });

  group('sign-in dialog', () {
    late TextEditingController user, pass;
    late int signIns, cancels;

    Widget dialog({bool busy = false, String? passwordError}) =>
        Builder(builder: (context) {
          return withDialog(
            context,
            _home(),
            NdLoginDialog(
              username: user,
              password: pass,
              busy: busy,
              passwordError: passwordError,
              onSignIn: () => signIns++,
              onCancel: () => cancels++,
            ),
          );
        });

    setUp(() {
      user = TextEditingController(text: 'lena');
      pass = TextEditingController();
      signIns = 0;
      cancels = 0;
    });

    for (final lang in ['en', 'de']) {
      forBothThemes('looks like the other dialogs ($lang)', (tester, b) async {
        await pumpScreen(tester, dialog(),
            size: mainSize, brightness: b, lang: lang);
        expect(find.byType(NdDialog), findsOneWidget);
        expect(_inDialog(find.byType(NdField)), findsNWidgets(2));
        // Labels above the fields, not floating Material labels.
        expect(
            _inDialog(find.byType(InputDecorator)).evaluate().every((e) {
              final d = (e.widget as InputDecorator).decoration;
              return d.labelText == null && d.label == null;
            }),
            isTrue);
        expect(_inDialog(find.text(translate('Username'))), findsOneWidget);
        expect(_inDialog(find.text(translate('Password'))), findsOneWidget);
        await shot(tester, 'client-sign-in-$lang', b);
      });
    }

    testWidgets('Enter in Password signs in, Sign in too, Cancel cancels',
        (tester) async {
      await pumpScreen(tester, dialog(), size: mainSize);
      final passField = find.descendant(
          of: find.widgetWithText(NdField, 'Password'),
          matching: find.byType(EditableText));
      await tester.enterText(passField, 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(signIns, 1);
      await tester.tap(_inDialog(find.widgetWithText(NdButton, 'Sign in')));
      await tester.pump();
      expect(signIns, 2);
      await tester.tap(_inDialog(find.widgetWithText(NdButton, 'Cancel')));
      await tester.pump();
      expect(cancels, 1);
    });

    testWidgets('the eye shows and hides the password', (tester) async {
      await pumpScreen(tester, dialog(), size: mainSize);
      bool hidden() => tester
          .widget<EditableText>(find.descendant(
              of: find.widgetWithText(NdField, 'Password'),
              matching: find.byType(EditableText)))
          .obscureText;
      expect(hidden(), isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(hidden(), isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(hidden(), isTrue);
    });

    testWidgets('while signing in, Sign in is off and Enter does nothing',
        (tester) async {
      await pumpScreen(tester, dialog(busy: true), size: mainSize);
      expect(
          tester
              .widget<NdButton>(
                  _inDialog(find.widgetWithText(NdButton, 'Sign in')))
              .onPressed,
          isNull);
      await tester.enterText(
          find.descendant(
              of: find.widgetWithText(NdField, 'Password'),
              matching: find.byType(EditableText)),
          'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(signIns, 0);
    });

    testWidgets('a wrong password shows under Password', (tester) async {
      await pumpScreen(tester, dialog(passwordError: 'Wrong credentials'),
          size: mainSize);
      final field = find.widgetWithText(NdField, 'Password');
      expect(tester.widget<NdField>(field).error, 'Wrong credentials');
      expect(find.text('Wrong credentials'), findsOneWidget);
    });
  });
}
