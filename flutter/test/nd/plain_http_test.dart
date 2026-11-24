// L468: Join a server and Set up by hand took a typed http:// address
// without a word. Both now show the invite installer's warning (the console
// doesn't use a secure connection) and join or save only after Continue
// anyway.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show globalKey;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/common/widgets/nd/nd_dialog_host.dart';
import 'package:flutter_hbb/onboarding/onboarding_flow.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/onboarding/setup_by_hand.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fixtures.dart';
import 'harness.dart';

const _insecure = "doesn't use a secure connection";

Future<void> _app(WidgetTester tester, Widget Function() open,
    {String lang = 'en'}) async {
  useLanguage(lang);
  await loadNdFonts();
  tester.view.physicalSize = mainSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(GetMaterialApp(
    navigatorKey: globalKey,
    theme: NdTheme.theme(Brightness.light, desktop: true),
    home: Scaffold(body: Center(child: open())),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Lets the fake join run to its end.
Future<void> _finishJoin(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

Finder _fields() => find.descendant(
    of: find.byType(NdDialog), matching: find.byType(EditableText));

Future<FakeOnboardingService> _openJoin(WidgetTester tester,
    {String lang = 'en'}) async {
  final svc = FakeOnboardingService(
      const OnboardingState(phase: OnboardingPhase.joined));
  await _app(
      tester,
      () => NdButton(
          label: 'Open',
          onPressed: () => showJoinServerDialog(svc, currentServer: '')),
      lang: lang);
  return svc;
}

void main() {
  testWidgets('Join a server warns before joining over http://',
      (tester) async {
    const link = 'http://10.10.10.74:5000/join/K7Q4-M2XD';
    final svc = await _openJoin(tester);
    await tester.enterText(_fields().first, link);
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(svc.calls, isEmpty);
    expect(find.textContaining('10.10.10.74:5000 $_insecure'), findsOneWidget);
    await tester.tap(find.text('Continue anyway'));
    await tester.pump();
    expect(svc.calls, ['redeemJoin:$link']);
    await _finishJoin(tester);
  });

  testWidgets('a code with a typed http:// server address warns too',
      (tester) async {
    final svc = await _openJoin(tester);
    await tester.enterText(_fields().first, 'K7Q4-M2XD');
    await tester.pump();
    await tester.enterText(_fields().at(1), 'http://10.10.10.74:5000');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(svc.calls, isEmpty);
    expect(find.textContaining(_insecure), findsOneWidget);
    // Changing the address asks again.
    await tester.enterText(_fields().at(1), 'https://10.10.10.74:5000');
    await tester.pump();
    expect(find.textContaining(_insecure), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(svc.calls, ['redeemJoin:https://10.10.10.74:5000/join/K7Q4-M2XD']);
    await _finishJoin(tester);
  });

  testWidgets('an https invite joins without the warning', (tester) async {
    const link = 'https://help.fernhill.example/join/K7Q4-M2XD';
    final svc = await _openJoin(tester);
    await tester.enterText(_fields().first, link);
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.textContaining(_insecure), findsNothing);
    expect(svc.calls, ['redeemJoin:$link']);
    await _finishJoin(tester);
  });

  testWidgets('the warning is in German too', (tester) async {
    final svc = await _openJoin(tester, lang: 'de');
    await tester.enterText(
        _fields().first, 'http://10.10.10.74:5000/join/K7Q4-M2XD');
    await tester.pump();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(svc.calls, isEmpty);
    expect(find.textContaining('nutzt keine sichere Verbindung'),
        findsOneWidget);
    expect(find.text('Trotzdem fortfahren'), findsOneWidget);
  });

  testWidgets('Set up by hand warns before saving a typed http:// address',
      (tester) async {
    final saved = <HandSetup>[];
    await _app(
        tester,
        () => NdButton(
            label: 'Open',
            onPressed: () => showNdDialog<void>((close, _) => SetupByHandDialog(
                  initial: const HandSetup(
                      idServer: '10.10.10.74', key: 'abc=', apiServer: ''),
                  onCancel: close,
                  onSave: (h) async {
                    saved.add(h);
                    close();
                    return const HandSetupErrors();
                  },
                ))));
    await tester.tap(find.text('Relay and API server'));
    await tester.pumpAndSettle();
    // Server, key, relay, API server.
    await tester.enterText(_fields().at(3), 'http://10.10.10.74:21114');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.textContaining('10.10.10.74:21114 $_insecure'), findsOneWidget);
    await tester.tap(find.text('Continue anyway'));
    await tester.pumpAndSettle();
    expect(saved.single.apiServer, 'http://10.10.10.74:21114');
  });

  testWidgets('Set up by hand saves an address it already had without asking',
      (tester) async {
    final saved = <HandSetup>[];
    await _app(
        tester,
        () => NdButton(
            label: 'Open',
            onPressed: () => showNdDialog<void>((close, _) => SetupByHandDialog(
                  initial: const HandSetup(
                      idServer: '10.10.10.74',
                      key: 'abc=',
                      apiServer: 'http://10.10.10.74:21114'),
                  onCancel: close,
                  onSave: (h) async {
                    saved.add(h);
                    close();
                    return const HandSetupErrors();
                  },
                ))));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining(_insecure), findsNothing);
    expect(saved, hasLength(1));
  });
}
