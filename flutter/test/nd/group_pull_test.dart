// The Devices tab after a failed pull (L500, L507): a refused envelope keeps
// a fresh sign-in, and without the NeoDesk service the tab says so in a
// sentence instead of the raw error.

import 'package:flutter_hbb/models/group_pull.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUp(() => useLanguage('en'));

  test('a refused envelope keeps the account signed in', () {
    expect(groupPullSignsOut(401, 'secure_envelope_rejected'), isFalse);
  });

  test('an expired token still signs out', () {
    expect(groupPullSignsOut(401, ''), isTrue);
    expect(groupPullSignsOut(401, 'Invalid token'), isTrue);
    expect(groupPullSignsOut(200, ''), isFalse);
    expect(groupPullSignsOut(503, 'neodesk_service_unavailable'), isFalse);
  });

  test('without the service the Devices tab says what to do', () {
    final text = groupPullErrorText('neodesk_service_unavailable');
    expect(
        text,
        "The NeoDesk service isn't running on this computer, so the device "
        "list can't load. Start the service, then click Retry.");
    expect(text, isNot(contains('neodesk_service_unavailable')));
    expect(text, isNot(contains('Failed to parse response')));
  });

  test('a refused envelope is explained, not shown raw', () {
    expect(
        groupPullErrorText('secure_envelope_rejected'),
        "The server didn't take this computer's signed request for the device "
        "list. You're still signed in. Click Retry in a moment.");
  });

  test('both sentences in German', () {
    useLanguage('de');
    expect(
        groupPullErrorText('neodesk_service_unavailable'),
        'Der NeoDesk-Dienst läuft auf diesem Computer nicht, darum lädt die '
        'Geräteliste nicht. Starte den Dienst und klick dann auf Erneut '
        'versuchen.');
    expect(
        groupPullErrorText('secure_envelope_rejected'),
        'Der Server hat die signierte Anfrage dieses Computers für die '
        'Geräteliste nicht angenommen. Du bist weiter angemeldet. Klick gleich '
        'auf Erneut versuchen.');
  });

  test('other errors keep the old banner', () {
    expect(groupPullErrorText('Admin required!'), isNull);
    expect(groupPullErrorText(''), isNull);
  });
}
