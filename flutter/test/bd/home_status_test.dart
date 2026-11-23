// The status line of Home says what the service and the server report
// about this computer: ready, waiting for approval, key refused, or that
// the server can't be reached, and nothing else for each.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_hbb/desktop/pages/home/home_status.dart';
import 'package:flutter_hbb/desktop/pages/home/home_widgets.dart';
import 'package:flutter_hbb/models/state_model.dart' show SvcStatus;
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _server = '10.10.10.74';
const _cantReach = "Can't reach 10.10.10.74.";
const _approval = 'Waiting for an administrator to approve this computer.';

HomeStatus _of(SvcStatus status,
        {String standing = '', String reason = 'offline'}) =>
    homeStatusOf(HomeStatusFacts(
        server: _server, status: status, standing: standing, reason: reason));

void main() {
  setUp(() => useLanguage('en'));

  test('a computer the signal server took is ready', () {
    final s = _of(SvcStatus.ready, reason: 'ready');
    expect(s.kind, BdStatusKind.good);
    expect(s.text, 'Ready. Connected to 10.10.10.74');
    // An enrollment answer from before the approval does not hide it.
    final late = _of(SvcStatus.ready,
        standing: '{"enrollment":"pending"}', reason: 'ready');
    expect(late.text, 'Ready. Connected to 10.10.10.74');
  });

  test('a refused key says so instead of "can\'t reach"', () {
    final s = _of(SvcStatus.notReady, standing: '{"signal":"refused"}');
    expect(s.kind, BdStatusKind.bad);
    expect(
        s.text,
        "10.10.10.74 does not accept this computer's new key. Ask your "
        'administrator to approve it or to delete the device in the console.');
    expect(s.linkLabel, isNull);
  });

  test('waiting for approval, whichever server part says it', () {
    for (final (standing, reason) in [
      ('{"signal":"pending"}', 'offline'),
      ('{"enrollment":"pending"}', 'offline'),
      ('', 'deployment_required'),
    ]) {
      final s = _of(SvcStatus.notReady, standing: standing, reason: reason);
      expect(s.kind, BdStatusKind.wait, reason: standing + reason);
      expect(s.text, _approval, reason: standing + reason);
    }
  });

  test('a service that does not answer is not the server', () {
    final s = _of(SvcStatus.notReady, reason: 'ipc_disconnected');
    expect(s.text, 'The NeoDesk service on this computer does not answer.');
  });

  test("only a server without any answer is \"can't reach\"", () {
    final s = _of(SvcStatus.notReady);
    expect(s.kind, BdStatusKind.bad);
    expect(s.text, _cantReach);
    expect(s.linkLabel, 'Try now');
    expect(_of(SvcStatus.connecting).text, 'Connecting to 10.10.10.74');
  });

  test('blocked and removed come before the rest', () {
    final banned = _of(SvcStatus.ready,
        standing: '{"banned":true,"signal":"refused"}', reason: 'ready');
    expect(banned.text, '10.10.10.74 has blocked this computer.');
    final removed = _of(SvcStatus.notReady,
        standing:
            '{"enrollment":"rejected","reason":"Device has been removed"}');
    expect(removed.text,
        'This computer was removed from 10.10.10.74. The server says: Device has been removed');
  });

  test('turned off and no server need no server answer', () {
    final off = homeStatusOf(const HomeStatusFacts(
        server: _server, status: SvcStatus.ready, serviceStopped: true));
    expect(off.kind, BdStatusKind.offline);
    expect(off.linkLabel, 'Turn on');
    final none = homeStatusOf(const HomeStatusFacts(
        server: '', status: SvcStatus.notReady, noServer: true));
    expect(none.text, 'No server is set up.');
  });

  test('the same cases as the tray menu', () {
    // home_status_cases.txt is shared with src/tray_model.rs, so Home and
    // the tray menu name the same state for the same facts.
    String withSaid(String text, String said) => said.isEmpty
        ? text
        : '$text ${tr('bd-home-status-server-says', [said])}';
    var count = 0;
    for (final raw in File('test/bd/home_status_cases.txt').readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split('=>');
      final facts = <String, String>{};
      for (final token in parts[0].trim().split(RegExp(r'\s+'))) {
        final i = token.indexOf('=');
        facts[token.substring(0, i)] = token.substring(i + 1);
      }
      final standing = <String, dynamic>{
        if (facts['banned'] == '1') 'banned': true,
        if ((facts['enrollment'] ?? '').isNotEmpty)
          'enrollment': facts['enrollment'],
        if ((facts['said'] ?? '').isNotEmpty) 'reason': facts['said'],
        if ((facts['signal'] ?? '').isNotEmpty) 'signal': facts['signal'],
      };
      final status = switch (facts['status']) {
        'ready' => SvcStatus.ready,
        'connecting' => SvcStatus.connecting,
        _ => SvcStatus.notReady,
      };
      final noServer = facts['noserver'] == '1';
      final server = noServer ? '' : _server;
      final said = facts['said'] ?? '';
      final want = switch (parts[1].trim()) {
        'off' => tr('bd-home-status-service-off'),
        'no-server' => tr('bd-home-status-no-server'),
        'banned' => withSaid(tr('bd-home-status-banned', [server]), said),
        'removed' => withSaid(tr('bd-home-status-removed', [server]), said),
        'key-refused' => tr('bd-home-status-key-refused', [server]),
        'ready' => tr('bd-home-status-ready', [server]),
        'approval' => tr('bd-home-status-approval'),
        'no-service' => tr('bd-home-status-no-service'),
        'connecting' => tr('bd-home-status-connecting', [server]),
        'offline' => tr('bd-home-status-offline', [server]),
        final other => fail('unknown state $other in $line'),
      };
      final got = homeStatusOf(HomeStatusFacts(
        server: server,
        status: status,
        reason: facts['reason'] ?? '',
        standing: standing.isEmpty ? '' : jsonEncode(standing),
        serviceStopped: facts['stopped'] == '1',
        noServer: noServer,
      ));
      expect(got.text, want, reason: line);
      count++;
    }
    expect(count, greaterThanOrEqualTo(10));
  });

  forBothThemes('home status, key refused', (tester, b) async {
    await pumpScreen(
        tester,
        Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
              width: 392,
              child: HomeStatusLine(
                  status: _of(SvcStatus.notReady,
                      standing: '{"signal":"refused"}'))),
        ),
        size: const Size(440, 140),
        brightness: b);
    await shot(tester, 'client-home-status-key-refused', b);
  });
}
