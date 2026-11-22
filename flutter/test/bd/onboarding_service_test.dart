import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InviteInput.parse', () {
    test('a join link gives host and code', () {
      final i = InviteInput.parse(' https://help.fernhill.example/join/7KQ4-M2XD ');
      expect(i.kind, InviteKind.joinLink);
      expect(i.host, 'help.fernhill.example');
      expect(i.code, '7KQ4M2XD');
      expect(i.displayCode, '7KQ4-M2XD');
      expect(i.isPlainHttp, isFalse);
    });

    test('a port stays with the host', () {
      final i = InviteInput.parse('https://10.0.0.5:5000/join/7kq4m2xd');
      expect(i.host, '10.0.0.5:5000');
      expect(i.code, '7KQ4M2XD');
    });

    test('plain HTTP is flagged by scheme and by ?http=1', () {
      expect(InviteInput.parse('http://h.example/join/7KQ4-M2XD').isPlainHttp,
          isTrue);
      expect(
          InviteInput.parse('https://h.example/join/7KQ4-M2XD?http=1')
              .isPlainHttp,
          isTrue);
      expect(
          InviteInput.parse('betterdesk://join/h.example/7KQ4-M2XD?http=1')
              .isPlainHttp,
          isTrue);
      expect(
          InviteInput.parse('https://h.example/join/7KQ4-M2XD?http=0')
              .isPlainHttp,
          isFalse);
    });

    test('deep links for join and support', () {
      final j = InviteInput.parse('betterdesk://join/help.fernhill.example/7KQ4-M2XD');
      expect(j.kind, InviteKind.joinLink);
      expect(j.host, 'help.fernhill.example');
      final s = InviteInput.parse('betterdesk://support/help.fernhill.example/R8TW-3NPA');
      expect(s.kind, InviteKind.supportLink);
      expect(s.code, 'R8TW3NPA');
      expect(InviteInput.parse('https://h.example/s/R8TW3NPA').kind,
          InviteKind.supportLink);
    });

    test('a bare code needs a server', () {
      final i = InviteInput.parse('7kq4m2xd');
      expect(i.kind, InviteKind.code);
      expect(i.needsServer, isTrue);
      expect(i.code, '7KQ4M2XD');
    });

    test('anything else is not an invite', () {
      for (final s in ['hello', 'https://h.example/other/7KQ4M2XD', '7KQ4-M2X', 'ftp://h/join/7KQ4M2XD']) {
        expect(InviteInput.parse(s).kind, InviteKind.invalid, reason: s);
      }
      expect(InviteInput.parse('  ').kind, InviteKind.empty);
    });
  });

  test('the fake walks a join through its steps and reports a failure',
      () async {
    final svc = FakeOnboardingService()..stepDelay = Duration.zero;
    final phases = <OnboardingPhase>[];
    svc.states.listen((s) => phases.add(s.phase));
    await svc.redeemJoin('https://h.example/join/7KQ4-M2XD');
    expect(svc.current.phase, OnboardingPhase.joined);
    expect(svc.current.server, 'h.example');
    svc.nextJoinError = OnboardingError.usedUp;
    await svc.redeemJoin('7KQ4-M2XD');
    expect(svc.current.phase, OnboardingPhase.joinFailed);
    expect(svc.current.errorKind, OnboardingError.usedUp);
    await svc.redeemJoin('not an invite');
    expect(svc.current.errorKind, OnboardingError.notAnInvite);
    await Future<void>.delayed(Duration.zero);
    expect(phases, contains(OnboardingPhase.joining));
  });

  test('pairing fallback joins through the pair call and maps its errors',
      () async {
    String? got;
    final ok = PairingOnboardingService(
      hasServer: () => false,
      pair: (server, code) async {
        got = '$server $code';
        return '{"ok":true,"status":"approved","message":""}';
      },
    );
    expect(ok.current.phase, OnboardingPhase.notSetUp);
    await ok.redeemJoin('https://h.example/join/7KQ4-M2XD?http=1');
    expect(got, 'http://h.example 7KQ4M2XD');
    expect(ok.current.phase, OnboardingPhase.joined);

    final used = PairingOnboardingService(
      hasServer: () => false,
      pair: (_, __) async =>
          '{"ok":false,"status":"","message":"The code is wrong or has been used"}',
    );
    await used.redeemJoin('https://h.example/join/7KQ4-M2XD');
    expect(used.current.phase, OnboardingPhase.joinFailed);
    expect(used.current.errorKind, OnboardingError.usedUp);
  });
}
