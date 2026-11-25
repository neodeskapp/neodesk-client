// L466: after a join from Settings, the Server page kept "Not connected to"
// the server while Home and the tray said Ready, until Settings was opened
// again. The page now reads the connection again while it shows, from the
// same connect status Home reads.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/settings/server_status.dart';
import 'package:flutter_hbb/desktop/pages/settings/settings_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('connected is what Home calls Ready', () {
    expect(connectedOf({'status_num': 1}), isTrue);
    expect(connectedOf({'status_num': 0}), isFalse);
    expect(connectedOf({'status_num': -1}), isFalse);
    expect(connectedOf({}), isFalse);
  });

  testWidgets('the Server page follows a join while it shows', (tester) async {
    var server = '10.10.10.74';
    var connected = false;
    var reads = 0;
    await pumpScreen(
      tester,
      LiveServerReading(
        read: () async {
          reads++;
          return ServerReading(
              options: {'custom-rendezvous-server': server},
              connected: connected);
        },
        builder: (context, r) => ServerSummary(
          connected: r.connected,
          server: '${r.options['custom-rendezvous-server'] ?? ''}',
          relay: '',
          api: '',
          keyText: '',
          actions: const [],
        ),
      ),
      size: const Size(800, 400),
    );
    expect(find.text('Not connected to 10.10.10.74'), findsOneWidget);

    // The join from Settings goes through, to another server.
    server = '10.10.10.75';
    connected = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Connected to 10.10.10.75'), findsOneWidget);
    expect(reads, greaterThan(1));

    // The page stops reading once it is gone.
    await tester.pumpWidget(const SizedBox());
    final after = reads;
    await tester.pump(const Duration(seconds: 3));
    expect(reads, after);
  });

  // L529: the window used about a tenth of a core on the Server page while
  // nothing changed: the page was rebuilt (and the window redrawn) every
  // second. It still reads every second, and builds again only on a change.
  testWidgets('the Server page draws again only when its reading changes',
      (tester) async {
    var connected = true;
    var reads = 0;
    var builds = 0;
    await pumpScreen(
      tester,
      LiveServerReading(
        read: () async {
          reads++;
          return ServerReading(
              options: {'custom-rendezvous-server': '10.10.10.74'},
              connected: connected);
        },
        builder: (context, r) {
          builds++;
          return Text(r.connected ? 'on' : 'off');
        },
      ),
      size: const Size(800, 400),
    );
    final first = builds;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(reads, greaterThan(10));
    expect(builds, first);

    connected = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(builds, first + 1);
    expect(find.text('off'), findsOneWidget);
  });
}
