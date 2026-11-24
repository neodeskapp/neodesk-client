import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

const _rows = [
  ('Accounting laptop', '702118446', 'Windows 11', 'Today, 09:41', true, true),
  ('Workshop PC', '315880902', 'Windows 10', 'Yesterday', true, false),
  ("Mara's MacBook", '884120377', 'macOS 15', '18 Nov', false, true),
  ('Build server', '120455908', 'Ubuntu 24.04', '12 Nov', true, false),
  ('Home office', '557301264', 'Windows 11', '2 Nov', false, false),
];

void _noop() {}

Widget _home({
  bool branded = false,
  bool empty = false,
  bool offline = false,
}) {
  return Builder(builder: (context) {
    final status = offline
        ? HomeStatus(NdStatusKind.bad,
            tr('nd-home-status-offline', [fernServer]),
            linkLabel: tr('nd-home-try-now'), onLink: () {})
        : HomeStatus(
            NdStatusKind.good, tr('nd-home-status-ready', [fernServer]));
    final left = ThisComputerColumn(
      id: '418205739',
      password: 'k7m2qx9w',
      status: status,
      onNewPassword: () async {},
      support: branded
          ? HomeSupportContact(
              company: fernCompany,
              phone: '+49 30 5550 1420',
              email: 'help@fernhill.example',
              website: 'fernhill.example',
              onEmail: _noop,
              onWebsite: _noop)
          : null,
    );
    final list = empty
        ? PeerListEmpty(text: tr('nd-home-empty-recent'))
        : Column(children: [
            for (var i = 0; i < _rows.length; i++)
              NdPeerRow(
                name: _rows[i].$1,
                id: _rows[i].$2,
                platform: _rows[i].$3,
                lastSeen: _rows[i].$4,
                online: _rows[i].$5,
                favourite: _rows[i].$6,
                showStatus: !offline,
                forceHover: i == 0 && !offline,
                onConnect: () {},
                onMenu: (_) {},
              ),
          ]);
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
        if (offline) ...[
          const SizedBox(height: 12),
          Text(tr('nd-home-offline-note'), style: context.ndText.small),
        ],
        list,
      ],
    );
    return mainWindow(HomeLayout(left: left, right: right), branded: branded);
  });
}

void main() {
  forBothThemes('home', (tester, b) async {
    await pumpScreen(tester, _home(), size: mainSize, brightness: b);
    expect(find.text('418 205 739'), findsOneWidget);
    await shot(tester, 'client-home-default', b);
  });

  forBothThemes('home branded', (tester, b) async {
    await pumpScreen(tester, _home(branded: true),
        size: mainSize, brightness: b, accent: fernAccent);
    await shot(tester, 'client-home-branded', b);
  });

  forBothThemes('home empty', (tester, b) async {
    await pumpScreen(tester, _home(empty: true), size: mainSize, brightness: b);
    await shot(tester, 'client-home-empty', b);
  });

  forBothThemes('home offline', (tester, b) async {
    await pumpScreen(tester, _home(offline: true),
        size: mainSize, brightness: b);
    await shot(tester, 'client-home-offline', b);
  });

  testWidgets('Copy puts the ID without spaces on the clipboard',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    await pumpScreen(
        tester,
        ThisComputerColumn(
          id: '418205739',
          password: 'k7m2qx9w',
          status: const HomeStatus(NdStatusKind.good, 'Ready'),
        ),
        size: const Size(392, 600));
    await tester.tap(find.text('Copy').first);
    await tester.pump();
    expect(copied, '418205739');
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('the password shows only after Show and the row hides for Only Allow',
      (tester) async {
    await pumpScreen(
        tester,
        ThisComputerColumn(
          id: '418205739',
          password: 'k7m2qx9w',
          status: const HomeStatus(NdStatusKind.good, 'Ready'),
        ),
        size: const Size(392, 600));
    expect(find.text('k7m2qx9w'), findsNothing);
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('k7m2qx9w'), findsOneWidget);

    await pumpScreen(
        tester,
        ThisComputerColumn(
          id: '418205739',
          password: 'k7m2qx9w',
          onlyClick: true,
          status: const HomeStatus(NdStatusKind.good, 'Ready'),
        ),
        size: const Size(392, 600));
    expect(find.text('Show'), findsNothing);
    expect(find.textContaining('You decide each time'), findsOneWidget);
  });
}
