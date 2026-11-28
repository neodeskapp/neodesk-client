// Get help in the receiver's home window: the person enters the code or
// the link their support person gave them, and quick support starts with it
// in a window of its own (src/onboard/mod.rs redeem_support), the same as
// the link from the console's quick support. During the session the
// connection window is the bar at the top of the screen (step 1).
//
// Under the title one line says whether the company's support may connect
// without asking, and when (A279); there is no switch for it here, the
// admin decides in the policy.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/onboarding/first_start_view.dart'
    show onboardingErrorText;
import 'package:flutter_hbb/onboarding/onboarding_service.dart';

const _days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

/// The days of a schedule as the home window says them: a run of three or
/// more days as "Mon to Fri", anything else listed ("Mon, Wed").
String unattendedDaysText(List<String> days) {
  final picked = [
    for (var i = 0; i < _days.length; i++)
      if (days.contains(_days[i])) i
  ];
  String name(int i) => tr('nd-day-${_days[i]}');
  if (picked.length >= 3 && picked.last - picked.first == picked.length - 1) {
    return tr('nd-rcv-range', [name(picked.first), name(picked.last)]);
  }
  return picked.map(name).join(', ');
}

/// The line under Get help (A279): "Your company's support can connect to
/// this computer without asking you, Mon to Fri 8:00 to 18:00."
String unattendedLineText(UnattendedAccess access) {
  final schedule = access.schedule;
  if (schedule == null) return tr('nd-rcv-unattended');
  final days = unattendedDaysText(schedule.days);
  final when = schedule.allDay
      ? days
      : '$days ${tr('nd-rcv-range', [schedule.start, schedule.end])}';
  return tr('nd-rcv-unattended-when', [when]);
}

class GetHelpView extends StatefulWidget {
  const GetHelpView({
    super.key,
    required this.service,
    required this.onMessages,
    this.company = '',
  });

  final OnboardingService service;

  /// Opens Messages.
  final VoidCallback onMessages;
  final String company;

  @override
  State<GetHelpView> createState() => _GetHelpViewState();
}

class _GetHelpViewState extends State<GetHelpView> {
  final _input = TextEditingController();
  StreamSubscription<OnboardingState>? _sub;
  String? _error;
  bool _started = false;
  Timer? _startedTimer;
  UnattendedAccess? _unattended;

  @override
  void initState() {
    super.initState();
    _unattended = widget.service.current.unattended;
    _input.addListener(() {
      if (_error != null) setState(() => _error = null);
      setState(() {});
    });
    _sub = widget.service.states.listen((s) {
      if (!mounted) return;
      if (s.unattended != _unattended) {
        setState(() => _unattended = s.unattended);
      }
      if (!_started) return;
      final kind = s.errorKind;
      if (kind == null && (s.error ?? '').isEmpty) return;
      setState(() {
        _started = false;
        _error = kind != null && kind != OnboardingError.other
            ? onboardingErrorText(kind, s.server)
            : ((s.error ?? '').isNotEmpty
                ? s.error
                : onboardingErrorText(OnboardingError.other, s.server));
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _startedTimer?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final text = _input.text.trim();
    final p = InviteInput.parse(text);
    if (p.kind != InviteKind.code && p.kind != InviteKind.supportLink) {
      setState(() => _error = tr('nd-invite-error-not-invite'));
      return;
    }
    setState(() {
      _error = null;
      _started = true;
    });
    await widget.service.redeemSupport(text);
    // The quick support window takes over; the line goes after a while
    _startedTimer?.cancel();
    _startedTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _started = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final company = widget.company.trim();
    final lead = t.body.copyWith(fontSize: 15, height: 22 / 15, color: c.text);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 36, 40, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(tr('nd-rcv-help-title'),
                  style: t.titleMd.copyWith(fontSize: 26, height: 32 / 26)),
            ),
            const SizedBox(height: 12),
            Text(
                company.isNotEmpty
                    ? tr('nd-rcv-help-lead', [company])
                    : tr('nd-rcv-help-lead-nocompany'),
                style: lead),
            if (_unattended != null) ...[
              const SizedBox(height: 12),
              Text(unattendedLineText(_unattended!),
                  key: const ValueKey('rcv-help-unattended'),
                  style: t.body.copyWith(color: c.textMuted)),
            ],
            const SizedBox(height: 24),
            NdField(
              key: const ValueKey('rcv-help-code'),
              label: tr('nd-rcv-help-field'),
              controller: _input,
              large: true,
              mono: true,
              placeholder: '7KQ4-M2XD',
              error: _error,
              onSubmitted: (_) => _start(),
            ),
            const SizedBox(height: 16),
            NdButton.primary(
              key: const ValueKey('rcv-help-start'),
              label: tr('nd-rcv-help-start'),
              size: NdButtonSize.lg,
              onPressed: _input.text.trim().isEmpty || _started ? null : _start,
            ),
            if (_started) ...[
              const SizedBox(height: 16),
              Row(children: [
                const NdSpinner(),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('nd-rcv-help-starting'), style: lead)),
              ]),
            ],
            const SizedBox(height: 40),
            Container(height: 1, color: c.rule),
            const SizedBox(height: 20),
            Text(tr('nd-rcv-help-no-code'), style: lead),
            const SizedBox(height: 8),
            NdButton.link(
                label: tr('nd-rcv-help-write'), onPressed: widget.onMessages),
          ],
        ),
      ),
    );
  }
}
