// The empty peer lists show their tab's glyph (L481), here on Home with no
// recent sessions, as the app lays it out (ConnectionPage: ConnectHeader,
// PeerTabPage's header, then the list).

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

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
          Expanded(
            child: PeersEmpty(
              icon: peersEmptyIcons[LoadEvent.recent]!,
              text: translate('empty_recent_tip'),
            ),
          ),
        ],
      );
      return mainWindow(HomeLayout(left: left, right: right));
    });

void main() {
  test('each empty list shows the glyph of its tab', () {
    final events = [
      LoadEvent.recent,
      LoadEvent.favorite,
      LoadEvent.lan,
      LoadEvent.addressBook,
      LoadEvent.group,
    ];
    for (var i = 0; i < events.length; i++) {
      expect(peersEmptyIcons[events[i]], PeerTabModel.icons[i],
          reason: events[i]);
    }
  });

  for (final lang in ['en', 'de']) {
    forBothThemes('home without recent sessions ($lang)', (tester, b) async {
      await pumpScreen(tester, _homeEmpty(),
          size: mainSize, brightness: b, lang: lang);
      final empty = find.descendant(
          of: find.byType(PeersEmpty), matching: find.byType(Icon));
      final icon = tester.widget<Icon>(empty);
      expect(icon.icon, NdIcons.history);
      expect(icon.color,
          (b == Brightness.dark ? NdColors.dark : NdColors.light).textMuted);
      await shot(tester, 'client-home-no-recent-$lang', b);
    });
  }
}
