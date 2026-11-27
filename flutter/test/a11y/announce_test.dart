// WCAG 4.1.3 Status Messages: changes a screen reader user would miss are
// said. A notice is a live region, a new chat message from the helper is
// said, and quick support says when someone connects and when it ends.
// (findings.md F33, F35, F36)

import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/models/nd_chat_model.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/onboarding/quick_support_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nd/chat_fakes.dart';
import '../nd/fixtures.dart';
import '../nd/harness.dart';
import 'a11y_helpers.dart';

void main() {
  setUp(() => useLanguage('en'));

  testWidgets('NdNotice is a live region', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester,
        const NdNotice(tone: NdTone.danger, text: 'Wrong password'),
        size: const Size(400, 80));
    final d = tester.getSemantics(find.byType(NdNotice)).getSemanticsData();
    expect(d.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    expect(d.label, contains('Wrong password'));
    handle.dispose();
  });

  test('a new message from the helper is said, once, also in front', () {
    fakeAsync((async) {
      final said = <(String, String)>[];
      final server = Server();
      final m = NdChatModel(
        connect: server.connect,
        announce: (name, text) => said.add((name, text)),
        random: Random(1),
        now: () => t0,
      );
      m.start();
      async.flushMicrotasks();
      server.last.serve(welcome());
      server.last.serve(history([1]));
      server.last.serve({'type': 'helper', 'name': 'Anna Weber', 'state': 'open'});
      async.flushMicrotasks();
      expect(said, isEmpty, reason: 'history is not new');
      m.setFront(true);
      server.last.serve({
        'type': 'message.new',
        'message': msg(2, text: 'Can you open the printer settings?')
      });
      server.last.serve({'type': 'message.new', 'message': msg(2)});
      server.last.serve({
        'type': 'message.new',
        'message': msg(3, from: me, text: 'Done')
      });
      async.flushMicrotasks();
      expect(said, [('Anna Weber', 'Can you open the printer settings?')]);
      m.dispose();
    });
  });

  // The connection window's bar says who is connected (cm_screens_test);
  // the quick support window, hidden during the session, says the end.
  testWidgets('quick support says when the session ends', (tester) async {
    final said = recordAnnouncements(tester);
    final state = ValueNotifier(const OnboardingState(
      phase: OnboardingPhase.supportWaiting,
      server: fernServer,
      company: fernCompany,
      supporterName: 'Mara Jensen',
    ));
    await pumpScreen(
        tester,
        ValueListenableBuilder<OnboardingState>(
          valueListenable: state,
          builder: (_, s, __) => QuickSupportView(
            state: s,
            onAllow: (_) {},
            onDecline: () {},
            onCancel: () {},
            onClose: () {},
            onRetry: () {},
          ),
        ),
        size: const Size(480, 720));
    state.value = state.value.copyWith(phase: OnboardingPhase.supportInSession);
    await tester.pump();
    state.value = state.value.copyWith(phase: OnboardingPhase.supportEnded);
    await tester.pump();
    final lines = said.map((a) => a.message).toList();
    expect(lines.where((l) => l.contains('is viewing and controlling')),
        isEmpty);
    expect(lines.last, tr('nd-qs-ended-title'));
    expect(said.every((a) => a.assertive), isTrue);
  });
}
