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
// - A link on plain HTTP (http://... or neodesk://...?http=1) is redeemed
//   as it is; the screens warn before they pass one on.
// - In the quick support app, redeemSupport('') tries the link the app was
//   started with again (Try again on the offline screen).
// - At rest, a computer that has a server shows as joined (Home).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;

import 'onboarding_service.dart';

/// The calls into the client core. The app uses the one in
/// onboarding_service_bind.dart; tests use a fake.
abstract class OnboardingNative {
  /// The state as JSON: phase, server, supporterName, company, error,
  /// errorText, errorReason, joinStep, deviceId, deviceName, folderId, link,
  /// fileName, messages (fromSupporter, text, time in ms), files
  /// (toThisComputer, path, name, count, size, time), inputActive,
  /// filesOpen, quickSupport, hasServer, sessionStarted and sessionEnded
  /// (ms), feedback (id, kind, label, required, long, options),
  /// feedbackState, unattended (null, or schedule: null or days, start,
  /// end, allDay).
  String state();

  bool isQuickSupport();
  void redeemJoin(String text);
  void redeemSupport(String text);
  void consent(bool allow, bool clipboard, bool fileTransfer);
  void dismissFailedJoin();
  void endSupport();
  void sendChat(String text);

  /// The feedback answers as a JSON object by question id.
  void sendFeedback(String answers);

  /// Leaves the installed receiver's ended session.
  void dismissSupport();

  /// Install on the offer after quick support.
  void installReceiver();
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

List<OnboardingFileLine> _filesOf(Object? value) {
  if (value is! List) return const [];
  int number(Object? v) => v is int ? v : 0;
  return [
    for (final line in value)
      if (line is Map && line['path'] is String)
        OnboardingFileLine(
          toThisComputer: line['toThisComputer'] == true,
          path: line['path'] as String,
          name: line['name'] is String ? line['name'] as String : '',
          count: number(line['count']),
          size: number(line['size']),
          time: DateTime.fromMillisecondsSinceEpoch(number(line['time'])),
        ),
  ];
}

DateTime? _timeOf(Object? value) =>
    value is int && value > 0 ? DateTime.fromMillisecondsSinceEpoch(value) : null;

List<FeedbackQuestion> _feedbackOf(Object? value) {
  if (value is! List) return const [];
  FeedbackKind? kindOf(Object? name) {
    for (final kind in FeedbackKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  return [
    for (final q in value)
      if (q is Map &&
          q['id'] is String &&
          q['label'] is String &&
          kindOf(q['kind']) != null)
        FeedbackQuestion(
          id: q['id'] as String,
          kind: kindOf(q['kind'])!,
          label: q['label'] as String,
          required: q['required'] == true,
          long: q['long'] == true,
          options: [
            if (q['options'] is List)
              for (final o in q['options'] as List)
                if (o is String) o,
          ],
        ),
  ];
}

/// The receiver's unattended access line (A279): null for none.
UnattendedAccess? _unattendedOf(Object? value) {
  if (value is! Map) return null;
  final schedule = value['schedule'];
  if (schedule is! Map) return const UnattendedAccess();
  const order = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final listed = schedule['days'] is List ? schedule['days'] as List : const [];
  final days = [
    for (final day in order)
      if (listed.contains(day)) day
  ];
  final start = schedule['start'];
  final end = schedule['end'];
  // A schedule that doesn't read says nothing: no line rather than a wrong one
  if (days.isEmpty || start is! String || end is! String) return null;
  return UnattendedAccess(
      schedule: UnattendedSchedule(
          days: days,
          start: start,
          end: end,
          allDay: schedule['allDay'] == true));
}

FeedbackState _feedbackStateOf(Object? value) => switch (value) {
      'sending' => FeedbackState.sending,
      'sent' => FeedbackState.sent,
      'failed' => FeedbackState.failed,
      _ => FeedbackState.none,
    };

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
    case 'refused':
      return OnboardingError.refused;
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
    reason: _text(map['errorReason']),
    errorKind: errorKindOf(code),
    inputActive: map['inputActive'] == true,
    joinStep: map['joinStep'] is int ? map['joinStep'] as int : 0,
    deviceId: _text(map['deviceId']),
    deviceName: _text(map['deviceName']),
    link: _text(map['link']),
    fileName: _text(map['fileName']),
    declined: code == 'declined',
    messages: _messagesOf(map['messages']),
    files: _filesOf(map['files']),
    filesOpen: map['filesOpen'] == true,
    asking: _text(map['asking']),
    sessionStarted: _timeOf(map['sessionStarted']),
    sessionEnded: _timeOf(map['sessionEnded']),
    feedback: _feedbackOf(map['feedback']),
    feedbackState: _feedbackStateOf(map['feedbackState']),
    offerReceiver: map['offerReceiver'] == true,
    receiverInstalling: map['receiverInstalling'] == true,
    unattended: _unattendedOf(map['unattended']),
  );
}

bool _sameState(OnboardingState a, OnboardingState b) =>
    a.phase == b.phase &&
    a.server == b.server &&
    a.supporterName == b.supporterName &&
    a.company == b.company &&
    a.error == b.error &&
    a.reason == b.reason &&
    a.errorKind == b.errorKind &&
    a.inputActive == b.inputActive &&
    a.joinStep == b.joinStep &&
    a.deviceId == b.deviceId &&
    a.deviceName == b.deviceName &&
    a.link == b.link &&
    a.fileName == b.fileName &&
    a.declined == b.declined &&
    a.filesOpen == b.filesOpen &&
    a.asking == b.asking &&
    a.sessionStarted == b.sessionStarted &&
    a.sessionEnded == b.sessionEnded &&
    a.feedbackState == b.feedbackState &&
    a.offerReceiver == b.offerReceiver &&
    a.receiverInstalling == b.receiverInstalling &&
    a.unattended == b.unattended &&
    listEquals(a.feedback, b.feedback) &&
    listEquals(a.files, b.files) &&
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
  Future<void> consent(bool allow,
      [QuickSupportGrants grants = const QuickSupportGrants()]) async {
    _native.consent(allow, grants.clipboard, grants.fileTransfer);
    _called();
  }

  @override
  Future<void> endSupport() async {
    _native.endSupport();
    _called();
  }

  @override
  void dismissFailedJoin() {
    _native.dismissFailedJoin();
    _called();
  }

  @override
  void dismissSupport() {
    _native.dismissSupport();
    _called();
  }

  @override
  void installReceiver() {
    _native.installReceiver();
    _called();
  }

  @override
  Future<void> sendChat(String text) async {
    if (text.trim().isEmpty) return;
    _native.sendChat(text);
    _called();
  }

  @override
  Future<void> sendFeedback(Map<String, Object> answers) async {
    if (answers.isEmpty) return;
    _native.sendFeedback(jsonEncode(answers));
    _called();
  }

  /// A neodesk://join or neodesk://support link the app received:
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
