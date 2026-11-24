// Settings, Server, Join a server: the dialog stays open until the join
// ends and shows a refusal itself (L458).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show globalKey;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/onboarding/joining_view.dart';
import 'package:flutter_hbb/onboarding/onboarding_flow.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fixtures.dart';
import 'harness.dart';

const _reason =
    "This computer's ID is already enrolled with another key. Ask your administrator to approve the new key or to delete the device in the console.";
const _link = 'http://10.10.10.74:5000/join/K7Q4-M2XD';

const _refused = OnboardingState(
  phase: OnboardingPhase.joinFailed,
  server: '10.10.10.74',
  link: _link,
  errorKind: OnboardingError.refused,
  error: '10.10.10.74 refused this computer',
  reason: _reason,
);

/// Joins as the client core does: redeemJoin returns while the join runs,
/// and the result comes later as a state.
class _CoreLikeService extends FakeOnboardingService {
  _CoreLikeService(this.result)
      : super(const OnboardingState(phase: OnboardingPhase.joined));
  final OnboardingState result;

  @override
  Future<void> redeemJoin(String linkOrCode) async {
    calls.add('redeemJoin:$linkOrCode');
    emit(current.copyWith(
        phase: OnboardingPhase.joining,
        joinStep: 0,
        link: linkOrCode,
        clearError: true));
    Timer(const Duration(milliseconds: 400), () => emit(result));
  }
}

Future<void> _openJoin(WidgetTester tester, OnboardingService svc) async {
  useLanguage('en');
  await loadNdFonts();
  tester.view.physicalSize = mainSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(GetMaterialApp(
    navigatorKey: globalKey,
    theme: NdTheme.theme(Brightness.light, desktop: true),
    home: Scaffold(
      body: Center(
        child: NdButton(
            label: 'Join a server',
            onPressed: () => showJoinServerDialog(svc, currentServer: '')),
      ),
    ),
  ));
  await tester.tap(find.text('Join a server'));
  await tester.pumpAndSettle();
  await tester.enterText(
      find.descendant(
          of: find.byType(NdDialog), matching: find.byType(EditableText)),
      _link);
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pump();
  // The lab's console runs on plain HTTP: the dialog warns first (L468).
  await tester.tap(find.text('Continue anyway'));
  await tester.pump();
}

void main() {
  testWidgets('a refused join keeps the dialog open with the server\'s words',
      (tester) async {
    final svc = _CoreLikeService(_refused);
    await _openJoin(tester, svc);
    expect(svc.calls, ['redeemJoin:$_link']);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final dialog = find.byType(NdDialog);
    expect(dialog, findsOneWidget);
    expect(
        find.descendant(
            of: dialog, matching: find.text('10.10.10.74 answered: $_reason')),
        findsOneWidget);
    expect(
        find.descendant(
            of: dialog,
            matching: find.text(
                'When your administrator has done that, try the same invite again. It still works.')),
        findsOneWidget);
    // The invite stays in the field for the next try.
    expect(find.descendant(of: dialog, matching: find.text(_link)),
        findsOneWidget);
  });

  testWidgets('Home shows the same words for the refusal', (tester) async {
    useLanguage('en');
    await pumpScreen(
        tester,
        JoiningView(
          state: _refused,
          onDone: () {},
          onTryAnother: () {},
          onSetUpByHand: () {},
        ),
        size: mainSize);
    expect(find.text('10.10.10.74 answered: $_reason'), findsOneWidget);
  });

  testWidgets('a join that works closes the dialog', (tester) async {
    final svc = _CoreLikeService(const OnboardingState(
        phase: OnboardingPhase.joined, server: '10.10.10.74'));
    await _openJoin(tester, svc);
    // While the join runs the dialog stays and says so.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(NdDialog), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byType(NdDialog), findsNothing);
  });
}
