// A support session in the installed receiver: the service runs it with
// the computer's own ID (src/onboard/receiver.rs), and the home window
// shows its screens, the same as the quick support app's: consent, waiting,
// the end with the feedback. While the supporter is connected the
// connection window is the bar at the top of the screen and this window
// hides, as quick support's does.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/onboarding/onboarding_service.dart';
import 'package:flutter_hbb/onboarding/quick_support_view.dart';

/// The phases in which the window shows the session instead of its home.
const kReceiverSessionPhases = {
  OnboardingPhase.supportConnecting,
  OnboardingPhase.supportConsent,
  OnboardingPhase.supportWaiting,
  OnboardingPhase.supportInSession,
  OnboardingPhase.supportEnded,
  OnboardingPhase.supportExpired,
};

/// What the window does for a session.
class ReceiverWindowActions {
  const ReceiverWindowActions({
    required this.toFront,
    required this.hide,
    required this.show,
  });

  /// The session asks the person something: the window comes up.
  final Future<void> Function() toFront;

  /// The supporter is connected: the bar takes over.
  final Future<void> Function() hide;
  final Future<void> Function() show;
}

class ReceiverSession extends StatefulWidget {
  const ReceiverSession({
    super.key,
    required this.service,
    required this.home,
    required this.window,
    this.logo,
  });

  final OnboardingService service;

  /// The home window's areas, shown when no session runs.
  final Widget home;
  final ReceiverWindowActions window;
  final Widget? logo;

  @override
  State<ReceiverSession> createState() => _ReceiverSessionState();
}

class _ReceiverSessionState extends State<ReceiverSession> {
  StreamSubscription<OnboardingState>? _sub;
  OnboardingState? _session;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.states.listen(_onState);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _onState(widget.service.current));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onState(OnboardingState s) {
    if (!mounted) return;
    final shows = kReceiverSessionPhases.contains(s.phase);
    final before = _session;
    setState(() => _session = shows ? s : null);
    if (shows &&
        s.phase != OnboardingPhase.supportInSession &&
        before?.phase != s.phase) {
      unawaited(widget.window.toFront());
    }
    final hide = s.phase == OnboardingPhase.supportInSession;
    if (hide != _hidden) {
      _hidden = hide;
      unawaited(hide ? widget.window.hide() : widget.window.show());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) return widget.home;
    final service = widget.service;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 480,
        child: QuickSupportView(
          key: const ValueKey('rcv-session'),
          state: s,
          logo: widget.logo,
          onAllow: (grants) => service.consent(true, grants),
          onDecline: () => service.consent(false),
          onCancel: () => service.endSupport(),
          onClose: service.dismissSupport,
          onFeedback: service.sendFeedback,
          onRetry: () {
            final link = s.link;
            if (link != null) service.redeemSupport(link);
          },
        ),
      ),
    );
  }
}
