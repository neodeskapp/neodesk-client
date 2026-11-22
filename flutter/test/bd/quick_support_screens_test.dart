import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/onboarding/quick_support_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

const _qsSize = Size(480, 560);

const _base = OnboardingState(
  phase: OnboardingPhase.supportConsent,
  server: fernServer,
  company: fernCompany,
  supporterName: 'Mara Jensen',
  companyPhone: '+49 30 5550 1420',
  fileName: 'BetterDesk-QuickSupport-help.fernhill.example-R8TW3NPA.exe',
);

Widget _window(Widget child) => BdWindowFrame(
      titleBar: BdTitleBar(
        height: 36,
        brand: BdTitleBrand(title: tr('bd-qs-window-title')),
        controls: BdWindowControls(
            onMinimize: () {}, onClose: () {}, height: 36),
      ),
      child: child,
    );

Widget _qs(OnboardingState s, {List<String>? calls}) => _window(
      QuickSupportView(
        state: s,
        logo: fernLogo(),
        onAllow: () => calls?.add('allow'),
        onDecline: () => calls?.add('decline'),
        onCancel: () => calls?.add('cancel'),
        onClose: () => calls?.add('close'),
        onRetry: () => calls?.add('retry'),
      ),
    );

/// A plain desktop behind the session bar.
Widget _desktop(Widget child) => Builder(
      builder: (context) => Container(
        color: context.bd.isDark
            ? const Color(0xFF1E3442)
            : const Color(0xFF2F4A5C),
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 10),
        child: child,
      ),
    );

void main() {
  final states = {
    'connecting': _base.copyWith(phase: OnboardingPhase.supportConnecting),
    'consent': _base,
    'waiting': _base.copyWith(phase: OnboardingPhase.supportWaiting),
    'ended': _base.copyWith(phase: OnboardingPhase.supportEnded),
    'expired': _base.copyWith(phase: OnboardingPhase.supportExpired),
  };
  for (final e in states.entries) {
    forBothThemes('quick support ${e.key}', (tester, b) async {
      await pumpScreen(tester, _qs(e.value),
          size: _qsSize, brightness: b, accent: fernAccent);
      await shot(tester, 'client-quick-support-${e.key}', b);
    });
  }

  forBothThemes('session bar', (tester, b) async {
    await pumpScreen(
        tester,
        _desktop(SessionBar(state: _base, onChat: () {}, onStop: () {})),
        size: const Size(1100, 400),
        brightness: b,
        accent: fernAccent);
    await shot(tester, 'client-session-bar-default', b);
  });

  forBothThemes('session bar with chat', (tester, b) async {
    final s = _base.copyWith(inputActive: false, messages: [
      OnboardingChatMessage(
          fromSupporter: true,
          text:
              "I'm opening the printer settings now. Please don't move the mouse for a moment.",
          time: DateTime(2026, 11, 22, 10, 12)),
      OnboardingChatMessage(
          fromSupporter: false,
          text: "OK. It's the printer in the hallway.",
          time: DateTime(2026, 11, 22, 10, 13)),
    ]);
    await pumpScreen(
        tester,
        _desktop(Column(mainAxisSize: MainAxisSize.min, children: [
          SessionBar(state: s, onChat: () {}, onStop: () {}, chatOpen: true),
          const SizedBox(height: 8),
          SessionChatPanel(state: s, onSend: (_) {}, onClose: () {}),
        ])),
        size: const Size(1100, 400),
        brightness: b,
        accent: fernAccent);
    await shot(tester, 'client-session-bar-chat', b);
  });

  testWidgets('the bar says "is using your computer" while input arrives',
      (tester) async {
    await pumpScreen(
        tester,
        Center(
            child: SessionBar(
                state: _base.copyWith(inputActive: true),
                onChat: () {},
                onStop: () {})),
        size: const Size(800, 200));
    expect(find.textContaining('is using your computer', findRichText: true),
        findsOneWidget);
    await pumpScreen(
        tester,
        Center(
            child: SessionBar(state: _base, onChat: () {}, onStop: () {})),
        size: const Size(800, 200));
    expect(find.textContaining('is viewing your screen', findRichText: true),
        findsOneWidget);
  });

  testWidgets('Allow and Decline reach the service; the fake follows them',
      (tester) async {
    final calls = <String>[];
    await pumpScreen(tester, _qs(_base, calls: calls), size: _qsSize);
    await tester.tap(find.text('Allow'));
    await tester.tap(find.text('Decline'));
    expect(calls, ['allow', 'decline']);

    final svc = FakeOnboardingService(_base);
    await svc.consent(false);
    expect(svc.current.phase, OnboardingPhase.supportEnded);
    expect(svc.current.declined, isTrue);
  });

  testWidgets('consent names the supporter and company, and without a company only the supporter',
      (tester) async {
    await pumpScreen(tester, _qs(_base), size: _qsSize);
    expect(
        find.text(
            'Mara Jensen from Fernhill IT wants to see your screen to help you'),
        findsOneWidget);
    expect(find.text('If you allow it, Mara can:'), findsOneWidget);
    await pumpScreen(
        tester,
        _qs(const OnboardingState(
            phase: OnboardingPhase.supportConsent,
            supporterName: 'Mara Jensen')),
        size: _qsSize);
    expect(find.text('Mara Jensen wants to see your screen to help you'),
        findsOneWidget);
  });
}
