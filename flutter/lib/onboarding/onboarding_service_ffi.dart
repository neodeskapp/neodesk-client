// The onboarding service on top of the client core (src/onboard in Rust).
//
// The core runs the join and the quick support session and keeps their
// state; this service reads that state (often while something is going on,
// now and then otherwise) and passes the person's actions on.
//
// What the core reports and how it shows here:
// - error: the core's words for the error (with the server's reason when
//   it gave one); errorKind: the sentence the screen picks.
// - A bare code needs a server the computer already joined; otherwise the
//   screen asks for the server and passes https://<server>/join/<code>.
// - A link on plain HTTP (http://... or betterdesk://...?http=1) is redeemed
//   as it is; the screens warn before they pass one on.
// - In the quick support app, redeemSupport('') tries the link the app was
//   started with again (Try again on the offline screen).
// - At rest, a computer that has a server shows as joined (Home).

import 'dart:async';
import 'dart:convert';

import 'onboarding_service.dart';

/// The calls into the client core. The app uses the one in
/// onboarding_service_bind.dart; tests use a fake.
abstract class OnboardingNative {
  /// The state as JSON: phase, server, supporterName, company, error,
  /// errorText, joinStep, deviceId, deviceName, folderId, link, fileName,
  /// messages (fromSupporter, text, time in ms), inputActive, quickSupport,
  /// hasServer.
  String state();

  bool isQuickSupport();
  void redeemJoin(String text);
  void redeemSupport(String text);
  void consent(bool allow);
  void endSupport();
  void sendChat(String text);
}

const _activePhases = {
  OnboardingPhase.joining,
  OnboardingPhase.supportWaiting,
  OnboardingPhase.supportConsent,
  OnboardingPhase.supportConnecting,
  OnboardingPhase.supportInSession,
};

OnboardingPhase _phaseOf(Object? name) {
  for (final phase in OnboardingPhase.values) {
    if (phase.name == name) return phase;
  }
  return OnboardingPhase.notSetUp;
}

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

Map<String, dynamic> _decode(String json) {
  try {
    final value = jsonDecode(json);
    if (value is Map<String, dynamic>) return value;
  } catch (_) {}
  return const {};
}

List<OnboardingChatMessage> _messagesOf(Object? value) {
  if (value is! List) return const [];
  return [
    for (final line in value)
      if (line is Map && line['text'] is String)
        OnboardingChatMessage(
          fromSupporter: line['fromSupporter'] == true,
          text: line['text'] as String,
          time: DateTime.fromMillisecondsSinceEpoch(
              line['time'] is int ? line['time'] as int : 0),
        ),
  ];
}

bool _sameMessages(
    List<OnboardingChatMessage> a, List<OnboardingChatMessage> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].fromSupporter != b[i].fromSupporter ||
        a[i].text != b[i].text ||
        a[i].time != b[i].time) {
      return false;
    }
  }
  return true;
}

/// The sentence the screens pick for one of the core's error names.
OnboardingError? errorKindOf(String? code) {
  switch (code) {
    case null:
    case 'declined':
      return null;
    case 'not_a_link':
      return OnboardingError.notAnInvite;
    // The server does not tell expired, used up and revoked apart.
    case 'invalid_or_expired':
      return OnboardingError.expired;
    case 'unreachable':
      return OnboardingError.unreachable;
    case 'rate_limited':
      return OnboardingError.tooManyTries;
    default:
      return OnboardingError.other;
  }
}

/// Reads the core's state JSON. Anything it cannot read is notSetUp.
OnboardingState parseOnboardingState(String json) {
  final map = _decode(json);
  var phase = _phaseOf(map['phase']);
  if (phase == OnboardingPhase.notSetUp && map['hasServer'] == true) {
    phase = OnboardingPhase.joined;
  }
  final code = _text(map['error']);
  return OnboardingState(
    phase: phase,
    server: _text(map['server']),
    supporterName: _text(map['supporterName']),
    company: _text(map['company']),
    error: _text(map['errorText']),
    errorKind: errorKindOf(code),
    inputActive: map['inputActive'] == true,
    joinStep: map['joinStep'] is int ? map['joinStep'] as int : 0,
    deviceId: _text(map['deviceId']),
    deviceName: _text(map['deviceName']),
    link: _text(map['link']),
    fileName: _text(map['fileName']),
    declined: code == 'declined',
    messages: _messagesOf(map['messages']),
  );
}

bool _sameState(OnboardingState a, OnboardingState b) =>
    a.phase == b.phase &&
    a.server == b.server &&
    a.supporterName == b.supporterName &&
    a.company == b.company &&
    a.error == b.error &&
    a.errorKind == b.errorKind &&
    a.inputActive == b.inputActive &&
    a.joinStep == b.joinStep &&
    a.deviceId == b.deviceId &&
    a.deviceName == b.deviceName &&
    a.link == b.link &&
    a.fileName == b.fileName &&
    a.declined == b.declined &&
    _sameMessages(a.messages, b.messages);

class FfiOnboardingService extends OnboardingService {
  /// Reads the state every [interval] while a join or a session runs or a
  /// call was just made, and every [idleInterval] otherwise.
  FfiOnboardingService(
    this._native, {
    Duration interval = const Duration(milliseconds: 500),
    this.idleInterval = const Duration(seconds: 3),
  }) {
    _current = parseOnboardingState(_native.state());
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  final OnboardingNative _native;
  final Duration idleInterval;
  final _controller = StreamController<OnboardingState>.broadcast();
  late OnboardingState _current;
  Timer? _timer;
  DateTime _lastRead = DateTime.now();
  DateTime _busyUntil = DateTime.now();

  @override
  Stream<OnboardingState> get states => _controller.stream;

  @override
  OnboardingState get current => _current;

  @override
  bool get isQuickSupportBuild => _native.isQuickSupport();

  void _tick() {
    final now = DateTime.now();
    final active =
        _activePhases.contains(_current.phase) || now.isBefore(_busyUntil);
    if (active || now.difference(_lastRead) >= idleInterval) {
      refresh();
    }
  }

  /// Reads often for a while after a call, until the core has picked it up.
  void _called() {
    _busyUntil = DateTime.now().add(const Duration(seconds: 5));
    refresh();
  }

  /// Reads the state now and tells the listeners when it changed.
  void refresh() {
    _lastRead = DateTime.now();
    final next = parseOnboardingState(_native.state());
    if (_sameState(next, _current)) return;
    _current = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> redeemJoin(String linkOrCode) async {
    _native.redeemJoin(linkOrCode.trim());
    _called();
  }

  @override
  Future<void> redeemSupport(String linkOrCode) async {
    _native.redeemSupport(linkOrCode.trim());
    _called();
  }

  @override
  Future<void> consent(bool allow) async {
    _native.consent(allow);
    _called();
  }

  @override
  Future<void> endSupport() async {
    _native.endSupport();
    _called();
  }

  @override
  Future<void> sendChat(String text) async {
    if (text.trim().isEmpty) return;
    _native.sendChat(text);
    _called();
  }

  /// A betterdesk://join or betterdesk://support link the app received:
  /// joins, or starts quick support (in a quick support window of its own
  /// when this is the normal app).
  void handleLink(String link) {
    switch (InviteInput.parse(link).kind) {
      case InviteKind.supportLink:
        redeemSupport(link);
        break;
      case InviteKind.joinLink:
        redeemJoin(link);
        break;
      default:
        break;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }
}
