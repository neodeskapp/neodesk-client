// The Devices tab after a failed pull (L507): without the NeoDesk service the
// tab says so in a sentence instead of the raw error.

import 'package:flutter_hbb/models/group_pull.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUp(() => useLanguage('en'));

  test('without the service the Devices tab says what to do', () {
    final text = groupPullErrorText('neodesk_service_unavailable');
    expect(
        text,
        "The NeoDesk service isn't running on this computer, so the device "
        "list can't load. Start the service, then click Retry.");
    expect(text, isNot(contains('neodesk_service_unavailable')));
    expect(text, isNot(contains('Failed to parse response')));
  });

  test('the sentence in German', () {
    useLanguage('de');
    expect(
        groupPullErrorText('neodesk_service_unavailable'),
        'Der NeoDesk-Dienst läuft auf diesem Computer nicht, darum lädt die '
        'Geräteliste nicht. Starte den Dienst und klick dann auf Erneut '
        'versuchen.');
  });

  test('other errors keep the old banner', () {
    expect(groupPullErrorText('Admin required!'), isNull);
    expect(groupPullErrorText(''), isNull);
  });
}
