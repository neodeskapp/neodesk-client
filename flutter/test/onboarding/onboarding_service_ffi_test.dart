import 'dart:async';
import 'dart:convert';

import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/onboarding/onboarding_service_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// The client core, as far as the service sees it: a state the test sets and
/// the calls the service made.
class FakeNative implements OnboardingNative {
  Map<String, dynamic> stateMap = {'phase': 'notSetUp'};
  bool quickSupport = false;
  int stateReads = 0;
  final calls = <String>[];

  /// What the core does when it is called; by default nothing.
  void Function(String call)? onCall;

  @override
  String state() {
    stateReads++;
    return jsonEncode(stateMap);
  }

  @override
  bool isQuickSupport() => quickSupport;

  void _call(String call) {
    calls.add(call);
    onCall?.call(call);
  }

  @override
  void redeemJoin(String text) => _call('join $text');

  @override
  void redeemSupport(String text) => _call('support $text');

  @override
  void consent(bool allow) => _call('consent $allow');

  @override
  void endSupport() => _call('end');

  @override
  void sendChat(String text) => _call('chat $text');
}

FfiOnboardingService serviceOf(FakeNative native,
    {Duration interval = const Duration(hours: 1),
    Duration idle = const Duration(seconds: 3)}) {
  final service =
      FfiOnboardingService(native, interval: interval, idleInterval: idle);
  addTearDown(service.dispose);
  return service;
}

void main() {
  test('reads every field of the core state', () {
    final state = parseOnboardingState(jsonEncode({
      'phase': 'supportInSession',
      'server': 'help.fernhill.example',
      'supporterName': 'Mara Jensen',
      'company': 'Fernhill IT',
      'error': null,
      'errorText': null,
      'inputActive': true,
      'link': 'neodesk://support/help.fernhill.example/7KQ4M2XD',
      'fileName': 'NeoDesk-QuickSupport-help.fernhill.example-7KQ4M2XD.exe',
      'quickSupport': true,
    }));
    expect(state.phase, OnboardingPhase.supportInSession);
    expect(state.server, 'help.fernhill.example');
    expect(state.supporterName, 'Mara Jensen');
    expect(state.company, 'Fernhill IT');
    expect(state.error, isNull);
    expect(state.errorKind, isNull);
    expect(state.inputActive, isTrue);
    expect(state.link, 'neodesk://support/help.fernhill.example/7KQ4M2XD');
    expect(state.fileName,
        'NeoDesk-QuickSupport-help.fernhill.example-7KQ4M2XD.exe');
    expect(state.declined, isFalse);
  });

  test('a finished join shows the facts of the invite', () {
    final state = parseOnboardingState(jsonEncode({
      'phase': 'joined',
      'joinStep': 2,
      'deviceId': '123456789',
      'deviceName': 'Reception PC',
      'folderId': 7,
    }));
    expect(state.phase, OnboardingPhase.joined);
    expect(state.joinStep, 2);
    expect(state.deviceId, '123456789');
    expect(state.deviceName, 'Reception PC');
    // The join answer names the folder only by id.
    expect(state.folder, isNull);
  });

  test('every phase name of the core is known', () {
    for (final phase in OnboardingPhase.values) {
      expect(parseOnboardingState(jsonEncode({'phase': phase.name})).phase,
          phase);
    }
  });

  test('a computer with a server is joined at rest, one without is not', () {
    expect(
        parseOnboardingState('{"phase":"notSetUp","hasServer":true}').phase,
        OnboardingPhase.joined);
    expect(
        parseOnboardingState('{"phase":"notSetUp","hasServer":false}').phase,
        OnboardingPhase.notSetUp);
    expect(
        parseOnboardingState('{"phase":"joinFailed","hasServer":true}').phase,
        OnboardingPhase.joinFailed);
  });

  test('a state it cannot read is not set up', () {
    expect(parseOnboardingState('not json').phase, OnboardingPhase.notSetUp);
    expect(parseOnboardingState('{"phase":"somethingNew"}').phase,
        OnboardingPhase.notSetUp);
  });

  test('error names pick the sentence and keep the core\'s words', () {
    final failed = parseOnboardingState(jsonEncode({
      'phase': 'joinFailed',
      'error': 'invalid_or_expired',
      'errorText':
          'This link has expired or was already used. Ask the person who sent it for a new one.',
    }));
    expect(failed.errorKind, OnboardingError.expired);
    expect(failed.error, startsWith('This link has expired'));

    expect(errorKindOf('not_a_link'), OnboardingError.notAnInvite);
    expect(errorKindOf('unreachable'), OnboardingError.unreachable);
    expect(errorKindOf('rate_limited'), OnboardingError.tooManyTries);
    expect(errorKindOf('certificate'), OnboardingError.other);
    expect(errorKindOf('refused'), OnboardingError.other);
    expect(errorKindOf(null), isNull);

    final declined = parseOnboardingState(
        '{"phase":"supportEnded","error":"declined","errorText":null}');
    expect(declined.declined, isTrue);
    expect(declined.errorKind, isNull);
    expect(declined.error, isNull);
  });

  test('redeemJoin passes the trimmed link on and shows the new state',
      () async {
    final native = FakeNative();
    native.onCall = (call) => native.stateMap = {
          'phase': 'joining',
          'joinStep': 0,
          'server': 'help.fernhill.example',
        };
    final service = serviceOf(native);
    final seen = <OnboardingPhase>[];
    service.states.listen((s) => seen.add(s.phase));

    await service.redeemJoin('  https://help.fernhill.example/join/7KQ4M2XD \n');
    await Future<void>.delayed(Duration.zero);

    expect(native.calls, ['join https://help.fernhill.example/join/7KQ4M2XD']);
    expect(service.current.phase, OnboardingPhase.joining);
    expect(service.current.server, 'help.fernhill.example');
    expect(seen, [OnboardingPhase.joining]);
  });

  test('consent and Stop reach the core', () async {
    final native = FakeNative()..stateMap = {'phase': 'supportConsent'};
    final service = serviceOf(native);
    await service.consent(true);
    await service.consent(false);
    await service.endSupport();
    await service.redeemSupport(' neodesk://support/desk.lan/7KQ4M2XD ');
    expect(native.calls, [
      'consent true',
      'consent false',
      'end',
      'support neodesk://support/desk.lan/7KQ4M2XD',
    ]);
  });

  test('polling tells listeners only about changes', () async {
    final native = FakeNative()..stateMap = {'phase': 'supportConnecting'};
    final service =
        serviceOf(native, interval: const Duration(milliseconds: 5));
    final seen = <OnboardingState>[];
    service.states.listen(seen.add);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(seen, isEmpty);
    expect(native.stateReads, greaterThan(2));

    native.stateMap = {
      'phase': 'supportConsent',
      'supporterName': 'Mara Jensen',
    };
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(seen.map((s) => s.phase), [OnboardingPhase.supportConsent]);
    expect(seen.single.supporterName, 'Mara Jensen');

    native.stateMap = {
      'phase': 'supportInSession',
      'supporterName': 'Mara Jensen',
      'inputActive': true,
    };
    await Future<void>.delayed(const Duration(milliseconds: 40));
    native.stateMap = {
      'phase': 'supportInSession',
      'supporterName': 'Mara Jensen',
      'inputActive': false,
    };
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(seen.map((s) => s.inputActive), [false, true, false]);
  });

  test('at rest the state is read only now and then', () async {
    final native = FakeNative()..stateMap = {'phase': 'joined'};
    final service = serviceOf(native,
        interval: const Duration(milliseconds: 5),
        idle: const Duration(hours: 1));
    final readsAtStart = native.stateReads;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(native.stateReads, readsAtStart);
    expect(service.current.phase, OnboardingPhase.joined);
  });

  test('a call makes it read often until the core has picked it up',
      () async {
    final native = FakeNative()..stateMap = {'phase': 'notSetUp'};
    final service = serviceOf(native,
        interval: const Duration(milliseconds: 5),
        idle: const Duration(hours: 1));
    final done = Completer<void>();
    service.states.listen((s) {
      if (s.phase == OnboardingPhase.joined && !done.isCompleted) {
        done.complete();
      }
    });
    await service.redeemJoin('https://desk.lan/join/7KQ4M2XD');
    // The core finishes later, on its own thread.
    native.stateMap = {'phase': 'joined', 'deviceName': 'Reception PC'};
    await done.future.timeout(const Duration(seconds: 2));
    expect(service.current.deviceName, 'Reception PC');
  });

  test('links are sorted into join and quick support', () {
    final native = FakeNative();
    final service = serviceOf(native);
    service.handleLink('neodesk://support/desk.lan/7KQ4M2XD');
    service.handleLink('neodesk://join/desk.lan:5000/7KQ4M2XD?http=1');
    service.handleLink('neodesk://join/not-a-link');
    expect(native.calls, [
      'support neodesk://support/desk.lan/7KQ4M2XD',
      'join neodesk://join/desk.lan:5000/7KQ4M2XD?http=1',
    ]);
  });

  test('chat lines come from the core and go to it', () async {
    final native = FakeNative()
      ..stateMap = {
        'phase': 'supportInSession',
        'messages': [
          {'fromSupporter': true, 'text': 'Which printer?', 'time': 1000},
        ],
      };
    final service = serviceOf(native);
    expect(service.current.messages.single.fromSupporter, isTrue);
    expect(service.current.messages.single.text, 'Which printer?');
    expect(service.current.messages.single.time,
        DateTime.fromMillisecondsSinceEpoch(1000));

    native.onCall = (call) => native.stateMap = {
          'phase': 'supportInSession',
          'messages': [
            {'fromSupporter': true, 'text': 'Which printer?', 'time': 1000},
            {'fromSupporter': false, 'text': 'The one upstairs', 'time': 2000},
          ],
        };
    final seen = <OnboardingState>[];
    service.states.listen(seen.add);
    await service.sendChat('   ');
    await service.sendChat('The one upstairs');
    await Future<void>.delayed(Duration.zero);

    expect(native.calls, ['chat The one upstairs']);
    expect(seen.single.messages.map((m) => m.text),
        ['Which printer?', 'The one upstairs']);
    expect(seen.single.messages.last.fromSupporter, isFalse);
  });

  test('the quick support build comes from the core', () {
    final native = FakeNative()..quickSupport = true;
    expect(serviceOf(native).isQuickSupportBuild, isTrue);
  });
}
