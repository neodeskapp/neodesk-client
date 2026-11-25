// An empty peer list says so in one muted sentence and says what to do on a
// second line, as the console's empty states do: no icon (L481). Here on
// Home with no recent sessions, as the app lays it out (ConnectionPage:
// ConnectHeader, PeerTabPage's header, then the list).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

const _lists = [
  LoadEvent.recent,
  LoadEvent.favorite,
  LoadEvent.lan,
  LoadEvent.addressBook,
  LoadEvent.group,
];

Widget _homeEmpty() => Builder(builder: (context) {
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
            tabs: [
              NdTab(0, tr('nd-tab-recent')),
              NdTab(1, tr('nd-tab-favourites')),
              NdTab(2, tr('nd-tab-network')),
              NdTab(3, tr('nd-tab-address-book')),
            ],
            value: 0,
            onChanged: (_) {},
            search: NdSearchField(
                placeholder: tr('nd-search'), width: 170, height: 30),
          ),
          Expanded(child: peersEmpty(LoadEvent.recent)),
        ],
      );
      return mainWindow(HomeLayout(left: left, right: right));
    });

void main() {
  test('every list has its own sentence and what-to-do line', () {
    for (final lang in ['en', 'de']) {
      useLanguage(lang);
      final seen = <String>{};
      for (final list in _lists) {
        final keys = peersEmptyTexts[list];
        expect(keys, isNotNull, reason: list);
        for (final key in [keys!.$1, keys.$2]) {
          final text = translate(key);
          expect(text, isNot(key), reason: '$lang $key');
          expect(text, isNot(contains('\n')), reason: '$lang $key');
          expect(seen.add(text), isTrue, reason: '$lang $key repeats');
        }
      }
    }
  });

  test('the texts use the words of the tab and the menu', () {
    useLanguage('en');
    final tab = translate('nd-tab-favourites').toLowerCase();
    expect(translate('Add to Favorites').toLowerCase(), contains(tab));
    expect(translate('nd-home-empty-favourites').toLowerCase(), contains(tab));
    useLanguage('de');
    // The Recent tab ("Zuletzt") lists past sessions, not current ones.
    expect(translate('nd-home-empty-recent'), 'Noch keine Sitzungen.');
    // Menu items and buttons named mid-sentence are quoted.
    expect(translate('nd-home-empty-favourites-hint'),
        contains('„${translate('Add to Favorites')}“'));
    expect(translate('nd-home-empty-address-book-hint'),
        contains('„${translate('Add to address book')}“'));
    expect(translate('nd-home-empty-recent-hint'),
        contains('„${translate('Connect')}“'));
  });

  test('the old cheerful texts are gone from every language file', () {
    final old = RegExp(r'"empty_(recent|favorite|lan|address_book)_tip"');
    final files = Directory('../src/lang')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.rs'))
        .toList();
    expect(files, hasLength(greaterThan(40)));
    for (final f in files) {
      expect(old.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  for (final lang in ['en', 'de']) {
    forBothThemes('home without recent sessions ($lang)', (tester, b) async {
      await pumpScreen(tester, _homeEmpty(),
          size: mainSize, brightness: b, lang: lang);
      final empty = find.byType(PeerListEmpty);
      expect(empty, findsOneWidget);
      expect(find.descendant(of: empty, matching: find.byType(Icon)),
          findsNothing);
      final muted =
          (b == Brightness.dark ? NdColors.dark : NdColors.light).textMuted;
      for (final key in [
        peersEmptyTexts[LoadEvent.recent]!.$1,
        peersEmptyTexts[LoadEvent.recent]!.$2,
      ]) {
        final text = tester.widget<Text>(find.text(translate(key)));
        expect(text.style?.color, muted, reason: key);
      }
      await shot(tester, 'client-home-no-recent-$lang', b);
    });
  }
}
