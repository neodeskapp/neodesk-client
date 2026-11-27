// The contract between the onboarding screens (redesign) and the code that
// joins servers and runs quick support (onboard-client, in
// onboarding_service_ffi.dart).
//
// Additions to the contract of 22 Nov, made for the screens:
// - OnboardingState: errorKind, joinStep, deviceName, folder, deviceId,
//   companyPhone, accentHex, link, fileName, declined, messages.
// - OnboardingService: sendChat() and dismissJoined(), with default bodies,
//   so an implementation that `extends OnboardingService` compiles without
//   them. An implementation that `implements` it must add both.
// - InviteInput: parses what people paste (link, neodesk:// link, code).
// - OnboardingService.registered: main.dart sets the real implementation
//   here at start. Without one, PairingOnboardingService below joins through
//   the existing pair-with-code call.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

enum OnboardingPhase {
  notSetUp,
  joining,
  joined,
  joinFailed,
  supportWaiting,
  supportConsent,
  supportConnecting,
  supportInSession,
  supportEnded,
  supportExpired,
}

/// Why a join or a support session failed; picks the sentence on screen.
enum OnboardingError {
  /// The text is not a link or code.
  notAnInvite,
  expired,
  usedUp,

  /// The server did not answer (no network, wrong address).
  unreachable,

  /// The console uses plain HTTP; the person must confirm to go on.
  insecureHttp,
  tooManyTries,

  /// The server keeps this computer out (a new key for a known ID, a
  /// blocked device). The invite is not used up.
  refused,
  other,
}

class OnboardingChatMessage {
  const OnboardingChatMessage({
    required this.fromSupporter,
    required this.text,
    required this.time,
  });

  final bool fromSupporter;
  final String text;
  final DateTime time;
}

/// What the person allows on the quick support consent screen besides the
/// screen, the mouse and the keyboard. Both stay off until ticked.
@immutable
class QuickSupportGrants {
  const QuickSupportGrants({this.clipboard = false, this.fileTransfer = false});

  /// Copying text between the two computers.
  final bool clipboard;

  /// Opening folders and sending files both ways.
  final bool fileTransfer;

  /// The names the consent request sends.
  List<String> get names => [
        if (clipboard) 'clipboard',
        if (fileTransfer) 'file_transfer',
      ];

  @override
  bool operator ==(Object other) =>
      other is QuickSupportGrants &&
      other.clipboard == clipboard &&
      other.fileTransfer == fileTransfer;

  @override
  int get hashCode => Object.hash(clipboard, fileTransfer);
}

/// A file transfer of a quick support session, as it started.
@immutable
class OnboardingFileLine {
  const OnboardingFileLine({
    required this.toThisComputer,
    required this.path,
    required this.time,
    this.name = '',
    this.count = 1,
    this.size = 0,
  });

  /// The supporter sent it to this computer; otherwise they took it.
  final bool toThisComputer;

  /// The file or folder on this computer.
  final String path;

  /// The file's name when it is one file, else empty.
  final String name;
  final int count;

  /// Bytes in all.
  final int size;
  final DateTime time;

  @override
  bool operator ==(Object other) =>
      other is OnboardingFileLine &&
      other.toThisComputer == toThisComputer &&
      other.path == path &&
      other.name == name &&
      other.count == count &&
      other.size == size &&
      other.time == time;

  @override
  int get hashCode =>
      Object.hash(toThisComputer, path, name, count, size, time);
}

@immutable
class OnboardingState {
  const OnboardingState({
    required this.phase,
    this.server,
    this.supporterName,
    this.company,
    this.error,
    this.reason,
    this.inputActive = false,
    this.errorKind,
    this.joinStep = 0,
    this.deviceName,
    this.folder,
    this.deviceId,
    this.companyPhone,
    this.accentHex,
    this.link,
    this.fileName,
    this.declined = false,
    this.messages = const [],
    this.files = const [],
    this.filesOpen = false,
    this.asking,
    this.canKeep = false,
    this.kept = false,
    this.startHidden = false,
    this.keepFailed = false,
  });

  final OnboardingPhase phase;

  /// The console's host name, e.g. help.fernhill.example.
  final String? server;
  final String? supporterName;
  final String? company;

  /// The server's answer as text, shown in the failed notice.
  final String? error;

  /// The server's own words when it refused this computer.
  final String? reason;

  /// True while the supporter's mouse or keyboard input arrives.
  final bool inputActive;

  final OnboardingError? errorKind;

  /// Joining progress: 0 checks the invite, 1 gets the settings, 2 adds this
  /// computer to the server.
  final int joinStep;

  /// What the invite set (left out on screen when null).
  final String? deviceName;
  final String? folder;

  /// This computer's ID after joining.
  final String? deviceId;

  /// The branding's phone number (quick support waiting too long).
  final String? companyPhone;

  /// The branding's accent colour from the redeem, as hex.
  final String? accentHex;

  /// The link or code that was redeemed (Try again).
  final String? link;

  /// The quick support file the person downloaded.
  final String? fileName;

  /// The person clicked Decline (supportEnded).
  final bool declined;

  /// Chat during a quick support session, oldest first.
  final List<OnboardingChatMessage> messages;

  /// Files the supporter sent or took in a quick support session, oldest
  /// first.
  final List<OnboardingFileLine> files;

  /// True while the supporter has this computer's files open.
  final bool filesOpen;

  /// While a connection waits for the person to accept in the connection
  /// manager: the name it gave (supportWaiting).
  final String? asking;

  /// The ended screen offers to keep quick support on this computer
  /// (Windows, a downloaded quick support file, no full NeoDesk).
  final bool canKeep;

  /// This is the quick support app kept on this computer: Close sends it to
  /// the background, and it offers Remove.
  final bool kept;

  /// The kept app started at sign-in: the window stays hidden until a link
  /// comes or the tray's Open.
  final bool startHidden;

  /// Keep did not work.
  final bool keepFailed;

  OnboardingState copyWith({
    OnboardingPhase? phase,
    String? server,
    String? supporterName,
    String? company,
    String? error,
    String? reason,
    bool? inputActive,
    OnboardingError? errorKind,
    bool clearError = false,
    int? joinStep,
    String? deviceName,
    String? folder,
    String? deviceId,
    String? companyPhone,
    String? accentHex,
    String? link,
    String? fileName,
    bool? declined,
    List<OnboardingChatMessage>? messages,
    List<OnboardingFileLine>? files,
    bool? filesOpen,
    String? asking,
    bool? canKeep,
    bool? kept,
    bool? startHidden,
    bool? keepFailed,
  }) =>
      OnboardingState(
        phase: phase ?? this.phase,
        server: server ?? this.server,
        supporterName: supporterName ?? this.supporterName,
        company: company ?? this.company,
        error: clearError ? null : (error ?? this.error),
        reason: clearError ? null : (reason ?? this.reason),
        inputActive: inputActive ?? this.inputActive,
        errorKind: clearError ? null : (errorKind ?? this.errorKind),
        joinStep: joinStep ?? this.joinStep,
        deviceName: deviceName ?? this.deviceName,
        folder: folder ?? this.folder,
        deviceId: deviceId ?? this.deviceId,
        companyPhone: companyPhone ?? this.companyPhone,
        accentHex: accentHex ?? this.accentHex,
        link: link ?? this.link,
        fileName: fileName ?? this.fileName,
        declined: declined ?? this.declined,
        messages: messages ?? this.messages,
        files: files ?? this.files,
        filesOpen: filesOpen ?? this.filesOpen,
        asking: asking ?? this.asking,
        canKeep: canKeep ?? this.canKeep,
        kept: kept ?? this.kept,
        startHidden: startHidden ?? this.startHidden,
        keepFailed: keepFailed ?? this.keepFailed,
      );

  /// The supporter's first name for the short lines; the full name when the
  /// account has only one word.
  String get supporterShortName {
    final n = (supporterName ?? '').trim();
    if (n.isEmpty) return '';
    final first = n.split(RegExp(r'\s+')).first;
    return first;
  }
}

abstract class OnboardingService {
  /// The implementation main.dart chose at start.
  static OnboardingService? registered;

  static OnboardingService? _fallback;

  /// The service the screens use.
  static OnboardingService get instance =>
      registered ?? (_fallback ??= PairingOnboardingService());

  Stream<OnboardingState> get states;
  OnboardingState get current;

  /// A link, a short code, or a neodesk:// link.
  Future<void> redeemJoin(String linkOrCode);
  Future<void> redeemSupport(String linkOrCode);
  /// The answer on the consent screen, with what the person ticked.
  Future<void> consent(bool allow,
      [QuickSupportGrants grants = const QuickSupportGrants()]);
  Future<void> endSupport();

  /// Started from a QuickSupport file name or link.
  bool get isQuickSupportBuild;

  /// Sends a chat line to the supporter during quick support.
  Future<void> sendChat(String text) async {}

  /// Done on the joined screen: the app goes to Home.
  void dismissJoined() {}

  /// Set up by hand after a failed join: the failure is left behind.
  void dismissFailedJoin() {}

  /// Keep on the ended screen: quick support stays on this computer and
  /// waits in the background. False when it could not.
  Future<bool> keepQuickSupport() async => false;

  /// Remove: the downloaded file goes, and the kept app with it. The app
  /// quits after it.
  Future<void> removeQuickSupport() async {}

  /// Close in the kept app: it waits in the background for the next link.
  Future<void> restQuickSupport() async {}

  /// Reads the state now (the kept app's window was asked to show).
  void refresh() {}
}

/// What people paste into the invite field.
class InviteInput {
  const InviteInput._(this.kind, this.host, this.code,
      [this.isPlainHttp = false]);

  final InviteKind kind;

  /// The link uses http:// or carries ?http=1 (the console runs on plain
  /// HTTP); the screen warns first.
  final bool isPlainHttp;

  /// The console host (with port), when the text names one.
  final String? host;

  /// The code without dash, upper case.
  final String? code;

  static final _code = RegExp(r'^[A-Za-z0-9]{4}-?[A-Za-z0-9]{4}$');

  /// Accepts https://<host>/join/<code>, http://..., neodesk://join/<host>/<code>,
  /// the same for support (/s/<code>, neodesk://support/...), and a bare
  /// code with or without the dash.
  static InviteInput parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return const InviteInput._(InviteKind.empty, null, null);
    if (_code.hasMatch(s)) {
      return InviteInput._(
          InviteKind.code, null, s.replaceAll('-', '').toUpperCase());
    }
    final uri = Uri.tryParse(s);
    if (uri != null && uri.scheme.isNotEmpty) {
      // The console adds ?http=1 when it is served over plain HTTP.
      final httpFlag = uri.queryParameters['http'] == '1';
      final segs = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (uri.scheme == 'neodesk') {
        // neodesk://join/<host>/<code>: the host part is "join".
        final kind = uri.host == 'join'
            ? InviteKind.joinLink
            : (uri.host == 'support' ? InviteKind.supportLink : null);
        if (kind != null && segs.length >= 2 && _code.hasMatch(segs[1])) {
          return InviteInput._(kind, segs[0],
              segs[1].replaceAll('-', '').toUpperCase(), httpFlag);
        }
      } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty &&
          segs.length >= 2) {
        final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
        final kind = segs[segs.length - 2] == 'join'
            ? InviteKind.joinLink
            : (segs[segs.length - 2] == 's' ? InviteKind.supportLink : null);
        final code = segs.last;
        if (kind != null && _code.hasMatch(code)) {
          return InviteInput._(kind, host,
              code.replaceAll('-', '').toUpperCase(),
              uri.scheme == 'http' || httpFlag);
        }
      }
    }
    return InviteInput._(InviteKind.invalid, null, null);
  }

  bool get needsServer => kind == InviteKind.code;

  /// The code as people read it: 7KQ4-M2XD.
  String? get displayCode => code == null || code!.length != 8
      ? code
      : '${code!.substring(0, 4)}-${code!.substring(4)}';
}

enum InviteKind { empty, invalid, code, joinLink, supportLink }

/// The host of a server address as the settings and invites write it
/// (`host`, `host:port`, `[v6]:port`, with or without a scheme), lower case
/// and without its port.
String serverHostOf(String address) {
  var s = address.trim().toLowerCase();
  final scheme = s.indexOf('://');
  if (scheme >= 0) s = s.substring(scheme + 3);
  final slash = s.indexOf('/');
  if (slash >= 0) s = s.substring(0, slash);
  if (s.startsWith('[')) {
    final end = s.indexOf(']');
    return end > 0 ? s.substring(1, end) : s;
  }
  // One colon is a port; more is an IPv6 address without brackets
  final colon = s.indexOf(':');
  if (colon >= 0 && colon == s.lastIndexOf(':')) s = s.substring(0, colon);
  return s;
}

/// Whether an invite's console [inviteHost] belongs to the server this
/// computer uses, [currentServer] (its ID server). The console, the ID
/// server and the API run on one host on their own ports, and a console
/// moves to another port with an update, so the host decides (L508).
bool isSameServer(String currentServer, String inviteHost) =>
    serverHostOf(currentServer) == serverHostOf(inviteHost);

/// The screens' test double, and the demo for screenshots: every phase can
/// be set by hand, redeemJoin walks through the three steps.
class FakeOnboardingService extends OnboardingService {
  FakeOnboardingService([OnboardingState? start, this.quickSupport = false])
      : _state = start ?? const OnboardingState(phase: OnboardingPhase.notSetUp);

  final bool quickSupport;
  OnboardingState _state;
  final _ctrl = StreamController<OnboardingState>.broadcast();
  final List<String> calls = [];

  /// What the next redeemJoin ends in; null joins.
  OnboardingError? nextJoinError;
  Duration stepDelay = const Duration(milliseconds: 600);

  @override
  Stream<OnboardingState> get states => _ctrl.stream;

  @override
  OnboardingState get current => _state;

  void emit(OnboardingState s) {
    _state = s;
    _ctrl.add(s);
  }

  @override
  bool get isQuickSupportBuild => quickSupport;

  @override
  Future<void> redeemJoin(String linkOrCode) async {
    calls.add('redeemJoin:$linkOrCode');
    final input = InviteInput.parse(linkOrCode);
    if (input.kind == InviteKind.invalid || input.kind == InviteKind.empty) {
      emit(_state.copyWith(
          phase: OnboardingPhase.notSetUp,
          errorKind: OnboardingError.notAnInvite));
      return;
    }
    emit(_state.copyWith(
        phase: OnboardingPhase.joining,
        joinStep: 0,
        server: input.host ?? _state.server,
        link: linkOrCode,
        clearError: true));
    for (var i = 1; i <= 2; i++) {
      await Future.delayed(stepDelay);
      emit(_state.copyWith(joinStep: i));
    }
    await Future.delayed(stepDelay);
    if (nextJoinError != null) {
      emit(_state.copyWith(
          phase: OnboardingPhase.joinFailed, errorKind: nextJoinError));
    } else {
      emit(_state.copyWith(phase: OnboardingPhase.joined));
    }
  }

  @override
  Future<void> redeemSupport(String linkOrCode) async {
    calls.add('redeemSupport:$linkOrCode');
    emit(_state.copyWith(
        phase: OnboardingPhase.supportConnecting,
        link: linkOrCode,
        clearError: true));
  }

  /// The grants of the last Allow.
  QuickSupportGrants? grants;

  @override
  Future<void> consent(bool allow,
      [QuickSupportGrants grants = const QuickSupportGrants()]) async {
    final names = grants.names;
    calls.add('consent:$allow${names.isEmpty ? '' : ':${names.join(',')}'}');
    if (allow) this.grants = grants;
    emit(_state.copyWith(
        phase: allow
            ? OnboardingPhase.supportWaiting
            : OnboardingPhase.supportEnded,
        declined: !allow));
  }

  @override
  Future<void> endSupport() async {
    calls.add('endSupport');
    emit(_state.copyWith(phase: OnboardingPhase.supportEnded, declined: false));
  }

  @override
  Future<void> sendChat(String text) async {
    calls.add('sendChat:$text');
    emit(_state.copyWith(messages: [
      ..._state.messages,
      OnboardingChatMessage(
          fromSupporter: false, text: text, time: DateTime.now()),
    ]));
  }

  @override
  void dismissJoined() {
    calls.add('dismissJoined');
  }

  @override
  void dismissFailedJoin() {
    calls.add('dismissFailedJoin');
    if (_state.phase == OnboardingPhase.joinFailed) {
      emit(_state.copyWith(phase: OnboardingPhase.notSetUp, clearError: true));
    }
  }

  /// Whether the next Keep works.
  bool keepWorks = true;

  @override
  Future<bool> keepQuickSupport() async {
    calls.add('keepQuickSupport');
    if (!keepWorks) {
      emit(_state.copyWith(keepFailed: true));
      return false;
    }
    emit(OnboardingState(
        phase: OnboardingPhase.notSetUp, kept: true, canKeep: _state.canKeep));
    return true;
  }

  @override
  Future<void> removeQuickSupport() async {
    calls.add('removeQuickSupport');
  }

  @override
  Future<void> restQuickSupport() async {
    calls.add('restQuickSupport');
    emit(OnboardingState(
        phase: OnboardingPhase.notSetUp, kept: _state.kept, canKeep: _state.canKeep));
  }
}

/// Joins through today's pair-with-code call (server address and code)
/// until the real implementation is registered. Quick support needs the
/// real implementation; here it reports the link as expired.
class PairingOnboardingService extends OnboardingService {
  PairingOnboardingService({this.pair, this.hasServer});

  /// bind.mainPairWithCode, as JSON {"ok","status","message"}.
  final Future<String> Function(String server, String code)? pair;

  /// Whether this computer already has a server.
  final bool Function()? hasServer;

  final _ctrl = StreamController<OnboardingState>.broadcast();
  OnboardingState? _state;

  @override
  Stream<OnboardingState> get states => _ctrl.stream;

  @override
  OnboardingState get current => _state ??= OnboardingState(
      phase: (hasServer?.call() ?? true)
          ? OnboardingPhase.joined
          : OnboardingPhase.notSetUp);

  void _emit(OnboardingState s) {
    _state = s;
    _ctrl.add(s);
  }

  @override
  bool get isQuickSupportBuild => false;

  @override
  Future<void> redeemJoin(String linkOrCode) async {
    final input = InviteInput.parse(linkOrCode);
    if (input.host == null || input.code == null || pair == null) {
      _emit(current.copyWith(
          phase: OnboardingPhase.notSetUp,
          errorKind: OnboardingError.notAnInvite));
      return;
    }
    final scheme = input.isPlainHttp ? 'http' : 'https';
    _emit(current.copyWith(
        phase: OnboardingPhase.joining,
        joinStep: 1,
        server: input.host,
        link: linkOrCode,
        clearError: true));
    Map<String, dynamic> res = {};
    try {
      res = jsonDecode(await pair!('$scheme://${input.host}', input.code!));
    } catch (_) {}
    if (res['ok'] == true) {
      _emit(current.copyWith(phase: OnboardingPhase.joined, joinStep: 2));
    } else {
      final msg = (res['message'] ?? '').toString();
      final lower = msg.toLowerCase();
      _emit(current.copyWith(
        phase: OnboardingPhase.joinFailed,
        error: msg,
        errorKind: lower.contains('expired')
            ? OnboardingError.expired
            : lower.contains('used')
                ? OnboardingError.usedUp
                : lower.contains('too many') || lower.contains('429')
                    ? OnboardingError.tooManyTries
                    : msg.isEmpty
                        ? OnboardingError.unreachable
                        : OnboardingError.other,
      ));
    }
  }

  @override
  Future<void> redeemSupport(String linkOrCode) async {
    _emit(current.copyWith(phase: OnboardingPhase.supportExpired));
  }

  @override
  Future<void> consent(bool allow,
      [QuickSupportGrants grants = const QuickSupportGrants()]) async {}

  @override
  Future<void> endSupport() async {
    _emit(current.copyWith(phase: OnboardingPhase.supportEnded));
  }
}
