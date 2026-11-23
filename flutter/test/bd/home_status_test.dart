// The status line of Home says what the service and the server report
// about this computer: ready, waiting for approval, key refused, or that
// the server can't be reached, and nothing else for each.

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
