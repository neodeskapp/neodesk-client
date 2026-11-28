// A support session in the installed receiver (receiver plan, step 5): the
// service runs it with the computer's own ID, the home window shows its
// screens instead of a second app, hides for the bar while the supporter is
// connected and goes back to its home after Close.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart' show tr;
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/receiver/receiver_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

const _consent = OnboardingState(
  phase: OnboardingPhase.supportConsent,
  server: fernServer,
  company: fernCompany,
  supporterName: 'Mara Jensen',
);

void main() {
  setUpAll(loadNdFonts);

  testWidgets('a session of the receiver shows in its own window and ends at home',
      (tester) async {
    final service =
        FakeOnboardingService(const OnboardingState(phase: OnboardingPhase.joined));
    final window = <String>[];
    await pumpScreen(
      tester,
      ReceiverSession(
        service: service,
        home: const Text('home', key: ValueKey('rcv-home')),
        window: ReceiverWindowActions(
          toFront: () async => window.add('front'),
          hide: () async => window.add('hide'),
          show: () async => window.add('show'),
        ),
      ),
      size: const Size(960, 660),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('rcv-home')), findsOneWidget);
    expect(window, isEmpty);

    // The link of the receiver's server: consent in this window, which
    // comes to the front
    service.emit(_consent);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('rcv-home')), findsNothing);
    expect(find.text(tr('nd-qs-consent-title', ['Mara Jensen', fernCompany])),
        findsOneWidget);
    expect(window, ['front']);
    await tester.tap(find.text(tr('nd-allow')));
    await tester.pump();
    await tester.pump();
    expect(service.calls, contains('consent:true'));

    // The supporter is connected: the bar takes over
    window.clear();
    service.emit(_consent.copyWith(phase: OnboardingPhase.supportInSession));
    await tester.pump();
    await tester.pump();
    expect(window, ['hide']);

    // The end comes back in this window; Close goes home
    window.clear();
    service.emit(_consent.copyWith(phase: OnboardingPhase.supportEnded));
    await tester.pump();
    await tester.pump();
    expect(window, containsAll(['show', 'front']));
    expect(find.text(tr('nd-qs-ended-title')), findsOneWidget);
    await tester.tap(find.text(translate('Close')));
    await tester.pump();
    await tester.pump();
    expect(service.calls, contains('dismissSupport'));
    expect(find.byKey(const ValueKey('rcv-home')), findsOneWidget);
  });
}
