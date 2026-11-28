// The offer after quick support (receiver plan, A277 point 4): once the
// feedback is done, and only when the console allowed it, the end screen
// asks whether to keep the company's support on this computer. Install
// goes to the core, which installs the receiver with the session's
// admission (src/onboard/mod.rs install_receiver); No thanks closes as
// before. With ND_SHOTS_DIR set it writes the screenshots of the pull
// request.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/onboarding/quick_support_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

const _size = Size(480, 720);

final _ended = OnboardingState(
  phase: OnboardingPhase.supportEnded,
  server: fernServer,
  company: fernCompany,
  supporterName: 'Mara Jensen',
  sessionStarted: DateTime(2026, 11, 28, 10, 0),
  sessionEnded: DateTime(2026, 11, 28, 10, 12),
);

const _form = [
  FeedbackQuestion(
      id: 'q1',
      kind: FeedbackKind.rating,
      label: 'How happy are you with the help?',
      required: true),
];

Widget _screen(OnboardingState s, List<String> calls, {bool canInstall = true}) =>
    NdWindowFrame(
      titleBar: NdTitleBar(
        height: 36,
        brand: NdTitleBrand(title: tr('nd-qs-window-title')),
        controls:
            NdWindowControls(onMinimize: () {}, onClose: () {}, height: 36),
      ),
      child: QuickSupportView(
        state: s,
        logo: fernLogo(),
        onAllow: (_) {},
        onDecline: () {},
        onCancel: () {},
        onRetry: () {},
        onClose: () => calls.add('close'),
        onFeedback: (_) => calls.add('feedback'),
        onInstallReceiver: canInstall ? () => calls.add('install') : null,
      ),
    );

String get _title => tr('nd-qs-keep-title', [fernCompany]);

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('the offer shows only when the console allowed it', (tester) async {
    final calls = <String>[];
    await pumpScreen(tester, _screen(_ended, calls), size: _size);
    expect(find.text(_title), findsNothing);
    expect(find.text(tr('nd-qs-ended-title')), findsOneWidget);
    await tester.tap(find.text(translate('Close')));
    expect(calls, ['close']);

    // Allowed, but the feedback comes first
    await pumpScreen(
        tester, _screen(_ended.copyWith(offerReceiver: true, feedback: _form), calls),
        size: _size);
    expect(find.text(_title), findsNothing);
    expect(find.text(tr('nd-qs-feedback-title')), findsOneWidget);

    // An app that can't install (the installed receiver's own session)
    // never offers it
    await pumpScreen(
        tester, _screen(_ended.copyWith(offerReceiver: true), calls, canInstall: false),
        size: _size);
    expect(find.text(_title), findsNothing);
  });

  testWidgets('after the feedback the offer asks, Install goes to the core and No thanks closes',
      (tester) async {
    final calls = <String>[];
    final offered = _ended.copyWith(
        offerReceiver: true, feedback: _form, feedbackState: FeedbackState.sent);
    await pumpScreen(tester, _screen(offered, calls), size: _size);
    expect(find.text(_title), findsOneWidget);
    expect(find.text(tr('nd-qs-keep-lead')), findsOneWidget);
    // One primary action and a plain way out, nothing else
    expect(find.byType(NdButton), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('qs-keep-install')));
    expect(calls, ['install']);
    await tester.tap(find.byKey(const ValueKey('qs-keep-no')));
    expect(calls, ['install', 'close']);

    // While it installs, nothing more can be pressed
    calls.clear();
    await pumpScreen(
        tester, _screen(offered.copyWith(receiverInstalling: true), calls),
        size: _size);
    await tester.tap(find.byKey(const ValueKey('qs-keep-install')));
    await tester.tap(find.byKey(const ValueKey('qs-keep-no')));
    expect(calls, isEmpty);

    // Without a company name the question names the support
    await pumpScreen(
        tester,
        _screen(
            OnboardingState(phase: OnboardingPhase.supportEnded, offerReceiver: true),
            calls),
        size: _size);
    expect(find.text(tr('nd-qs-keep-title-nocompany')), findsOneWidget);
  });

  testWidgets('the service passes Install to the core', (tester) async {
    final service = FakeOnboardingService(_ended.copyWith(offerReceiver: true), true);
    service.installReceiver();
    expect(service.calls, ['installReceiver']);
    expect(service.current.receiverInstalling, isTrue);
  });

  forBothThemes('offer to keep the app', (tester, b) async {
    await pumpScreen(
        tester, _screen(_ended.copyWith(offerReceiver: true), <String>[]),
        size: _size, brightness: b, accent: fernAccent);
    await shot(tester, 'client-quick-support-keep', b);
  });
}
