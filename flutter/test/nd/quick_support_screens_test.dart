import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/onboarding/quick_support_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'harness.dart';

const _qsSize = Size(480, 720);

const _base = OnboardingState(
  phase: OnboardingPhase.supportConsent,
  server: fernServer,
  company: fernCompany,
  supporterName: 'Mara Jensen',
  companyPhone: '+49 30 5550 1420',
  fileName: 'NeoDesk-QuickSupport-help.fernhill.example-R8TW3NPA.exe',
);

Widget _window(Widget child) => NdWindowFrame(
      titleBar: NdTitleBar(
        height: 36,
        brand: NdTitleBrand(title: tr('nd-qs-window-title')),
        controls: NdWindowControls(
            onMinimize: () {}, onClose: () {}, height: 36),
      ),
      child: child,
    );

Widget _qs(OnboardingState s, {List<String>? calls}) => _window(
      QuickSupportView(
        state: s,
        logo: fernLogo(),
        onAllow: (grants) => calls?.add(
            ['allow', ...grants.names].join(' ')),
        onDecline: () => calls?.add('decline'),
        onCancel: () => calls?.add('cancel'),
        onClose: () => calls?.add('close'),
        onRetry: () => calls?.add('retry'),
      ),
    );

/// A plain desktop behind the session bar.
Widget _desktop(Widget child) => Builder(
      builder: (context) => Container(
        color: context.nd.isDark
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
    expect(
        find.textContaining('is viewing and controlling your computer',
            findRichText: true),
        findsOneWidget);
  });

  testWidgets('consent lists exactly what is given; text and files only when ticked',
      (tester) async {
    final calls = <String>[];
    await pumpScreen(tester, _qs(_base, calls: calls), size: _qsSize);
    expect(find.text('See your screen'), findsOneWidget);
    expect(find.text('Use your mouse and keyboard'), findsOneWidget);
    expect(find.text('Only if you tick it, Mara can also:'), findsOneWidget);
    // Nothing ticked: Allow gives the screen, the mouse and the keyboard.
    await tester.tap(find.text('Allow'));
    await tester.tap(find.text('Copy text between the two computers'));
    await tester.pump();
    await tester.tap(find.text('Allow'));
    await tester.tap(find.text('Send and receive files'));
    await tester.pump();
    await tester.tap(find.text('Allow'));
    await tester.tap(find.text('Copy text between the two computers'));
    await tester.pump();
    await tester.tap(find.text('Allow'));
    expect(calls, [
      'allow',
      'allow clipboard',
      'allow clipboard file_transfer',
      'allow file_transfer',
    ]);

    final svc = FakeOnboardingService(_base);
    await svc.consent(true, const QuickSupportGrants(fileTransfer: true));
    expect(svc.grants, const QuickSupportGrants(fileTransfer: true));
    expect(svc.calls.last, 'consent:true:file_transfer');
  });

  final withFiles = _base.copyWith(
    phase: OnboardingPhase.supportInSession,
    filesOpen: true,
    files: [
      OnboardingFileLine(
          toThisComputer: true,
          path: r'C:\Users\tester',
          name: 'to-win.txt',
          size: 36,
          time: DateTime(2026, 11, 23, 8, 41)),
      OnboardingFileLine(
          toThisComputer: false,
          path: r'C:\Users\tester\Desktop\from-win.txt',
          name: 'from-win.txt',
          size: 31,
          time: DateTime(2026, 11, 23, 8, 42)),
    ],
  );

  forBothThemes('session bar with files', (tester, b) async {
    var opened = 0;
    await pumpScreen(
        tester,
        _desktop(Column(mainAxisSize: MainAxisSize.min, children: [
          SessionBar(
              state: withFiles,
              onChat: () {},
              onStop: () {},
              onFiles: () => opened++),
          const SizedBox(height: 8),
          SessionFilesPanel(state: withFiles, onClose: () {}),
        ])),
        size: const Size(1100, 460),
        brightness: b,
        accent: fernAccent);
    expect(find.text('Files (2)'), findsOneWidget);
    expect(find.text('Mara Jensen has your files open.'), findsOneWidget);
    expect(find.text(r'To this computer: C:\Users\tester'), findsOneWidget);
    expect(
        find.text(r'From this computer: C:\Users\tester\Desktop\from-win.txt'),
        findsOneWidget);
    expect(find.text('36 B'), findsOneWidget);
    // Newest first.
    expect(
        tester.getTopLeft(find.text('from-win.txt')).dy <
            tester.getTopLeft(find.text('to-win.txt')).dy,
        isTrue);
    await tester.tap(find.text('Files (2)'));
    expect(opened, 1);
    await shot(tester, 'client-session-bar-files', b);
  });

  testWidgets('the bar has no Files button before files move', (tester) async {
    await pumpScreen(
        tester,
        Center(
            child: SessionBar(
                state: _base.copyWith(phase: OnboardingPhase.supportInSession),
                onChat: () {},
                onStop: () {},
                onFiles: () {})),
        size: const Size(800, 200));
    expect(find.text('Files'), findsNothing);
    expect(sessionFileSize(4718592), '4.5 MB');
    expect(sessionFileSize(1536), '1.5 KB');
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
