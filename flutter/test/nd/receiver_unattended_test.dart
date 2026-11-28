// The receiver's line about unattended access under Get help (A279):
// whether the company's support can connect without asking, and when, in
// the words the owner chose; no line when they can't.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/receiver/get_help_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _office = UnattendedAccess(
    schedule: UnattendedSchedule(
        days: ['mon', 'tue', 'wed', 'thu', 'fri'], start: '8:00', end: '18:00'));

Future<FakeOnboardingService> _pump(WidgetTester tester, UnattendedAccess? access,
    {String lang = 'en'}) async {
  final service = FakeOnboardingService(
      OnboardingState(phase: OnboardingPhase.joined, unattended: access));
  await pumpScreen(
      tester,
      GetHelpView(
          service: service, onMessages: () {}, company: 'Fernhill Dental'),
      size: const Size(720, 560),
      lang: lang);
  return service;
}

String? _line(WidgetTester tester) {
  final found = find.byKey(const ValueKey('rcv-help-unattended'));
  if (found.evaluate().isEmpty) return null;
  return tester.widget<Text>(found).data;
}

void main() {
  testWidgets('with a schedule the line names the days and times', (tester) async {
    await _pump(tester, _office);
    expect(_line(tester),
        "Your company's support can connect to this computer without asking you, Mon to Fri 8:00 to 18:00.");
  });

  testWidgets('without a schedule the line has no time part', (tester) async {
    await _pump(tester, const UnattendedAccess());
    expect(_line(tester),
        "Your company's support can connect to this computer without asking you.");
  });

  testWidgets('with the line the lead no longer says they see the screen only after Allow',
      (tester) async {
    await _pump(tester, _office);
    final lead = tester.widget<Text>(find.byKey(const ValueKey('rcv-help-lead'))).data!;
    expect(lead, 'Did someone from Fernhill Dental give you a code or a link? Enter it here.');
    expect(lead, isNot(contains('allow')));
  });

  testWidgets('without the line the lead keeps the Allow sentence', (tester) async {
    await _pump(tester, null);
    final lead = tester.widget<Text>(find.byKey(const ValueKey('rcv-help-lead'))).data!;
    expect(lead, contains('They can see your screen only after you allow it.'));
  });

  testWidgets('no line when the company\'s support can\'t connect without asking',
      (tester) async {
    await _pump(tester, null);
    expect(_line(tester), isNull);
  });

  testWidgets('the line follows the policy while the window is open',
      (tester) async {
    final service = await _pump(tester, null);
    service.emit(service.current.copyWith(unattended: _office));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    expect(_line(tester), contains('Mon to Fri 8:00 to 18:00'));
  });

  testWidgets('the line in German', (tester) async {
    await _pump(tester, _office, lang: 'de');
    expect(_line(tester),
        'Der Support deiner Firma kann sich ohne Nachfrage mit diesem Computer verbinden, Mo bis Fr 8:00 bis 18:00.');
  });

  test('days read as a range only for three or more days in a row', () {
    useLanguage('en');
    expect(unattendedDaysText(['mon', 'tue', 'wed', 'thu', 'fri']), 'Mon to Fri');
    expect(unattendedDaysText(['sun', 'mon', 'sat', 'tue', 'wed', 'thu', 'fri']),
        'Mon to Sun');
    expect(unattendedDaysText(['mon', 'wed', 'fri']), 'Mon, Wed, Fri');
    expect(unattendedDaysText(['sat', 'sun']), 'Sat, Sun');
    expect(unattendedDaysText(['wed']), 'Wed');
    expect(
        unattendedLineText(const UnattendedAccess(
            schedule: UnattendedSchedule(
                days: ['sat', 'sun'], start: '0:00', end: '0:00', allDay: true))),
        "Your company's support can connect to this computer without asking you, Sat, Sun.");
    expect(
        unattendedLineText(const UnattendedAccess(
            schedule:
                UnattendedSchedule(days: ['fri'], start: '22:00', end: '6:00'))),
        "Your company's support can connect to this computer without asking you, Fri 22:00 to 6:00.");
  });
}
