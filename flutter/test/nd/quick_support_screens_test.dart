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
        onKeep: () => calls?.add('keep'),
        onRemove: () => calls?.add('remove'),
      ),
    );

/// A normal end in a downloaded quick support file on Windows.
final _endedKeep =
    _base.copyWith(phase: OnboardingPhase.supportEnded, canKeep: true);

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
  states['ended-keep'] = _endedKeep;
  states['ready'] = const OnboardingState(
      phase: OnboardingPhase.joined, server: fernServer, kept: true);
  for (final e in states.entries) {
    forBothThemes('quick support ${e.key}', (tester, b) async {
      await pumpScreen(tester, _qs(e.value),
          size: _qsSize, brightness: b, accent: fernAccent);
      await shot(tester, 'client-quick-support-${e.key}', b);
    });
  }

  // While the supporter's connection waits in the connection manager, this
  // window sends the person there instead of saying the supporter has not
  // connected (L553)
  for (final lang in ['en', 'de']) {
    testWidgets('a waiting request sends the person to the other window ($lang)',
        (tester) async {
      await pumpScreen(
          tester,
          _qs(_base.copyWith(
              phase: OnboardingPhase.supportWaiting, asking: 'Mara Jensen')),
          size: _qsSize,
          lang: lang);
      expect(find.text(tr('nd-qs-asking-title', ['Mara Jensen'])), findsOneWidget);
      expect(find.text(tr('nd-qs-asking-line')), findsOneWidget);
      expect(find.text(tr('nd-qs-waiting-title', ['Mara'])), findsNothing);
      if (lang == 'de') {
        expect(find.text('Mara Jensen möchte sich verbinden'), findsOneWidget);
      }
    });
  }

  // The server refused this computer (a revoked ID, L550): the window says
  // why and what to do, in the app's words, not only "the session ended"
  testWidgets('a refused computer says why the session ended', (tester) async {
    useLanguage('de');
    const words =
        'Dieser Computer wurde auf diesem Server widerrufen. Bitte die Person, die dir den Link geschickt hat, ihn in der Konsole zu entsperren, und öffne den Link dann noch einmal.';
    await pumpScreen(
        tester,
        _qs(_base.copyWith(
            phase: OnboardingPhase.supportEnded,
            errorKind: OnboardingError.refused,
            reason: words)),
        size: _qsSize,
        lang: 'de');
    expect(find.text(tr('nd-qs-refused-title')), findsOneWidget);
    expect(find.text(words), findsOneWidget);
    expect(find.text(tr('nd-qs-ended-title')), findsNothing);
  });

  // After the session the person keeps quick support on the computer or
  // removes it
  for (final lang in ['en', 'de']) {
    testWidgets('the end of a session asks to keep or remove ($lang)',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(tester, _qs(_endedKeep, calls: calls),
          size: _qsSize, lang: lang);
      expect(find.text(tr('nd-qs-keep-title')), findsOneWidget);
      expect(find.text(tr('nd-qs-keep-line')), findsOneWidget);
      // The file goes either way, so the old hint about deleting it is gone
      expect(find.text(tr('nd-qs-ended-hint')), findsNothing);
      expect(find.text(tr('Close')), findsNothing);
      await tester.tap(find.text(tr('nd-qs-keep')));
      await tester.tap(find.text(tr('nd-qs-remove')));
      expect(calls, ['keep', 'remove']);
      if (lang == 'de') {
        expect(find.text('Auf diesem Computer behalten'), findsOneWidget);
        expect(find.text('Von diesem Computer entfernen'), findsOneWidget);
      }
    });
  }

  testWidgets('without a way to keep it the end stays as it was',
      (tester) async {
    final calls = <String>[];
    await pumpScreen(
        tester, _qs(_endedKeep.copyWith(canKeep: false), calls: calls),
        size: _qsSize);
    expect(find.text(tr('nd-qs-keep-title')), findsNothing);
    expect(find.text(tr('nd-qs-remove')), findsNothing);
    expect(find.text(tr('nd-qs-ended-hint')), findsOneWidget);
    await tester.tap(find.text('Close'));
    expect(calls, ['close']);
  });

  testWidgets('a declined session offers no keeping', (tester) async {
    await pumpScreen(tester, _qs(_endedKeep.copyWith(declined: true)),
        size: _qsSize);
    expect(find.text(tr('nd-qs-keep-title')), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('the kept app says it stays and offers Remove', (tester) async {
    final calls = <String>[];
    await pumpScreen(
        tester, _qs(_endedKeep.copyWith(kept: true), calls: calls),
        size: _qsSize);
    expect(find.text(tr('nd-qs-kept-line')), findsOneWidget);
    expect(find.text(tr('nd-qs-keep-title')), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.tap(find.text(tr('nd-qs-remove')));
    expect(calls, ['close', 'remove']);
  });

  testWidgets('keeping that failed says so and offers only Close',
      (tester) async {
    await pumpScreen(tester, _qs(_endedKeep.copyWith(keepFailed: true)),
        size: _qsSize);
    expect(find.text(tr('nd-qs-keep-failed')), findsOneWidget);
    expect(find.text(tr('nd-qs-keep')), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  for (final phase in [OnboardingPhase.notSetUp, OnboardingPhase.joined]) {
    testWidgets('the kept app opened without a link is ready (${phase.name})',
        (tester) async {
      final calls = <String>[];
      await pumpScreen(
          tester, _qs(OnboardingState(phase: phase, kept: true), calls: calls),
          size: _qsSize, lang: 'de');
      expect(find.text('NeoDesk Schnellhilfe ist bereit'), findsOneWidget);
      expect(find.text(tr('nd-qs-connecting-title')), findsNothing);
      await tester.tap(find.text(tr('nd-qs-remove')));
      expect(calls, ['remove']);
    });
  }

  test('closing after the session removes, and the kept app stays', () {
    QuickSupportClose close(OnboardingState s) => quickSupportCloseOf(s);
    expect(close(_endedKeep), QuickSupportClose.remove);
    expect(close(_endedKeep.copyWith(declined: true)), QuickSupportClose.remove);
    expect(close(_endedKeep.copyWith(phase: OnboardingPhase.supportExpired)),
        QuickSupportClose.remove);
    // Not over yet: closing quits as before and the file stays
    expect(close(_endedKeep.copyWith(phase: OnboardingPhase.supportConnecting)),
        QuickSupportClose.quit);
    expect(close(_endedKeep.copyWith(phase: OnboardingPhase.supportConsent)),
        QuickSupportClose.quit);
    // macOS, Linux, or no file to keep
    expect(close(_endedKeep.copyWith(canKeep: false)), QuickSupportClose.quit);
    // The person chose Keep and it did not work
    expect(close(_endedKeep.copyWith(keepFailed: true)), QuickSupportClose.quit);
    for (final phase in OnboardingPhase.values) {
      expect(close(OnboardingState(phase: phase, kept: true)),
          QuickSupportClose.rest);
    }
  });

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
