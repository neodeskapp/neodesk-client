// Settings, Server, Join a server with a bare code (L524): the address the
// dialog only prefilled from the earlier join is not the person's choice.
// The code then goes as a bare code, so the client tries the console's new
// port when the old one does not answer, as --join CODE does. An address
// the person changed goes with the code, to that address only.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show globalKey;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/onboarding/first_start_view.dart';
import 'package:flutter_hbb/onboarding/onboarding_flow.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'fixtures.dart';
import 'harness.dart';

const _known = 'http://10.10.10.74:5000';

Future<FakeOnboardingService> _join(WidgetTester tester,
    {String? serverTypedOver}) async {
  useLanguage('en');
  await loadNdFonts();
  tester.view.physicalSize = mainSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final svc = FakeOnboardingService(
      const OnboardingState(phase: OnboardingPhase.joined))
    ..stepDelay = const Duration(milliseconds: 10);
  await tester.pumpWidget(GetMaterialApp(
    navigatorKey: globalKey,
    theme: NdTheme.theme(Brightness.light, desktop: true),
    home: Scaffold(
      body: Center(
        child: NdButton(
            label: 'Join a server',
            onPressed: () => showJoinServerDialog(svc,
                currentServer: '10.10.10.74', knownConsole: _known)),
      ),
    ),
  ));
  await tester.tap(find.text('Join a server'));
  await tester.pumpAndSettle();
  final fields = find.descendant(
      of: find.byType(NdDialog), matching: find.byType(EditableText));
  await tester.enterText(fields.first, 'K7Q4-M2XD');
  await tester.pump();
  // The server address field shows the prefilled console
  expect(find.text(_known), findsOneWidget);
  if (serverTypedOver != null) {
    await tester.enterText(fields.at(1), serverTypedOver);
    await tester.pump();
  }
  await tester.tap(find.text('Continue'));
  await tester.pump();
  // Plain HTTP: the dialog warns first (L468)
  await tester.tap(find.text('Continue anyway'));
  await tester.pumpAndSettle();
  return svc;
}

void main() {
  testWidgets('a prefilled address leaves the code bare', (tester) async {
    final svc = await _join(tester);
    expect(svc.calls, contains('redeemJoin:K7Q4-M2XD'));
  });

  testWidgets('an address the person typed goes with the code', (tester) async {
    final svc =
        await _join(tester, serverTypedOver: 'http://10.10.10.74:5000/');
    expect(svc.calls,
        contains('redeemJoin:http://10.10.10.74:5000/join/K7Q4-M2XD'));
  });

  test('what the dialog hands to the join', () {
    expect(joinRequestFor('K7Q4M2XD', _known, _known), 'K7Q4-M2XD');
    expect(joinRequestFor('K7Q4-M2XD', ' $_known ', _known), 'K7Q4-M2XD');
    expect(joinRequestFor('K7Q4-M2XD', 'http://10.10.10.74:3375', _known),
        'http://10.10.10.74:3375/join/K7Q4-M2XD');
    expect(joinRequestFor('K7Q4-M2XD', '', ''), isNull);
    // A link keeps its own console
    expect(
        joinRequestFor(
            'http://10.10.10.74:3375/join/K7Q4-M2XD', _known, _known),
        'http://10.10.10.74:3375/join/K7Q4-M2XD');
  });
}
