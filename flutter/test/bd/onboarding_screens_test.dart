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
