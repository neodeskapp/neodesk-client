import 'package:flutter/material.dart';
import 'package:flutter_hbb/onboarding/first_start_view.dart';
import 'package:flutter_hbb/onboarding/joining_view.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/onboarding/setup_by_hand.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

void main() {
  forBothThemes('first start', (tester, b) async {
    final svc = FakeOnboardingService();
    await pumpScreen(
        tester,
        mainWindow(FirstStartView(
            service: svc, onSetUpByHand: () {}, initialText: '')),
        size: mainSize,
        brightness: b);
    expect(find.text('Set up NeoDesk'), findsOneWidget);
    await shot(tester, 'client-first-start-default', b);
  });

  forBothThemes('first start with an expired invite', (tester, b) async {
    final svc = FakeOnboardingService(const OnboardingState(
        phase: OnboardingPhase.notSetUp, errorKind: OnboardingError.expired));
    await pumpScreen(
        tester,
        mainWindow(FirstStartView(
            service: svc, onSetUpByHand: () {}, initialText: '7KQ4-M2XD')),
        size: mainSize,
        brightness: b);
    await shot(tester, 'client-first-start-error', b);
  });

  forBothThemes('set up by hand', (tester, b) async {
    final svc = FakeOnboardingService();
    await pumpScreen(
        tester,
        Builder(
          builder: (context) => withDialog(
            context,
            mainWindow(FirstStartView(
                service: svc, onSetUpByHand: () {}, initialText: '')),
            SetupByHandDialog(
              initial: const HandSetup(
                  idServer: fernServer,
                  key: '0eVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw='),
              onSave: (_) async => const HandSetupErrors(),
              onCancel: () {},
            ),
          ),
        ),
        size: mainSize,
        brightness: b);
    await shot(tester, 'client-setup-by-hand', b);
  });

  const progress = OnboardingState(
      phase: OnboardingPhase.joining,
      joinStep: 1,
      server: fernServer,
      company: fernCompany);

  forBothThemes('joining progress', (tester, b) async {
    await pumpScreen(
        tester,
        mainWindow(JoiningView(
            state: progress,
            logo: fernLogo(),
            onDone: () {},
            onTryAnother: () {},
            onSetUpByHand: () {})),
        size: mainSize,
        brightness: b,
        accent: fernAccent);
    await shot(tester, 'client-joining-progress', b);
  });

  forBothThemes('joining done', (tester, b) async {
    await pumpScreen(
        tester,
        mainWindow(JoiningView(
            state: progress.copyWith(
                phase: OnboardingPhase.joined,
                deviceName: 'Reception PC',
                folder: 'Front desk',
                deviceId: '418205739'),
            logo: fernLogo(),
            onDone: () {},
            onTryAnother: () {},
            onSetUpByHand: () {})),
        size: mainSize,
        brightness: b,
        accent: fernAccent);
    expect(find.text('418 205 739'), findsOneWidget);
    await shot(tester, 'client-joining-done', b);
  });

  const keyRefusal =
      "This computer's ID is already enrolled with another key. Ask your "
      'administrator to approve the new key or to delete the device in the '
      'console.';
  const refused = OnboardingState(
      phase: OnboardingPhase.joinFailed,
      server: '10.10.10.74',
      errorKind: OnboardingError.refused,
      error: '10.10.10.74 did not accept this computer: $keyRefusal',
      reason: keyRefusal,
      link: 'http://10.10.10.74:5000/join/2EQ9AJ3X');

  forBothThemes('a join refused for its key says what the server said',
      (tester, b) async {
    var triedAgain = 0;
    await pumpScreen(
        tester,
        mainWindow(JoiningView(
            state: refused,
            onDone: () {},
            onTryAnother: () {},
            onSetUpByHand: () {},
            onTryAgain: () => triedAgain++)),
        size: mainSize,
        brightness: b);
    expect(find.text('10.10.10.74 answered: $keyRefusal'), findsOneWidget);
    expect(find.textContaining('did not accept this computer:'), findsNothing);
    expect(find.textContaining('for a new one'), findsNothing);
    expect(find.text('The server did not accept this computer.'),
        findsOneWidget);
    expect(find.textContaining('try the same invite again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(triedAgain, 1);
    await shot(tester, 'client-joining-refused', b);
  });

  testWidgets('an invite the server did not take still asks for a new one',
      (tester) async {
    await pumpScreen(
        tester,
        mainWindow(JoiningView(
            state: const OnboardingState(
                phase: OnboardingPhase.joinFailed,
                server: fernServer,
                errorKind: OnboardingError.usedUp),
            onDone: () {},
            onTryAnother: () {},
            onSetUpByHand: () {},
            onTryAgain: () {})),
        size: mainSize);
    expect(find.textContaining('for a new one'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  forBothThemes('joining failed', (tester, b) async {
    await pumpScreen(
        tester,
        mainWindow(JoiningView(
            state: const OnboardingState(
                phase: OnboardingPhase.joinFailed,
                server: fernServer,
                errorKind: OnboardingError.usedUp),
            onDone: () {},
            onTryAnother: () {},
            onSetUpByHand: () {})),
        size: mainSize,
        brightness: b);
    await shot(tester, 'client-joining-failed', b);
  });
}
