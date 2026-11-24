import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

import 'onboarding_service.dart';

/// Joining a server: progress, done and failed, on the first-start column.
class JoiningView extends StatelessWidget {
  const JoiningView({
    super.key,
    required this.state,
    required this.onDone,
    required this.onTryAnother,
    required this.onSetUpByHand,
    this.onTryAgain,
    this.logo,
    this.deviceId,
  });

  final OnboardingState state;
  final VoidCallback onDone;
  final VoidCallback onTryAnother;
  final VoidCallback onSetUpByHand;

  /// Redeems the same invite again (a refusal leaves it unused).
  final VoidCallback? onTryAgain;

  /// The server's logo from the branding, when it has one.
  final Widget? logo;

  /// This computer's ID (falls back to the state's).
  final String? deviceId;

  String get _company {
    final c = (state.company ?? '').trim();
    return c.isNotEmpty ? c : (state.server ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    final c = context.nd;
    final children = <Widget>[];
    final company = (state.company ?? '').trim();
    if (company.isNotEmpty && state.phase != OnboardingPhase.joinFailed) {
      children.addAll([
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (logo != null) ...[
            SizedBox(width: 34, height: 34, child: logo),
            const SizedBox(width: 10),
          ],
          Text(company,
              style: t.heading.copyWith(
                  fontSize: 22, height: 1, letterSpacing: -0.2)),
        ]),
        const SizedBox(height: 32),
      ]);
    }

    switch (state.phase) {
      case OnboardingPhase.joined:
        final id = deviceId ?? state.deviceId ?? '';
        children.addAll([
          _title(tr('nd-join-done-title', [_company]), t.title),
          const SizedBox(height: 12),
          Text(tr('nd-join-done-lead', [_company]), style: t.lead),
          const SizedBox(height: 32),
          SizedBox(
            width: 436,
            child: NdFacts(facts: [
              if ((state.deviceName ?? '').isNotEmpty)
                NdFact(tr('nd-fact-name'), state.deviceName!),
              if ((state.folder ?? '').isNotEmpty)
                NdFact(tr('nd-fact-folder'), state.folder!),
              if (id.isNotEmpty) NdFact(tr('nd-fact-id'), formatNdId(id), mono: true),
              if ((state.server ?? '').isNotEmpty)
                NdFact(tr('nd-fact-server'), state.server!),
            ]),
          ),
          const SizedBox(height: 24),
          NdButton.primary(
              label: tr('nd-done'), size: NdButtonSize.lg, onPressed: onDone),
        ]);
        break;
      case OnboardingPhase.joinFailed:
        final kind = state.errorKind ?? OnboardingError.other;
        final refused = kind == OnboardingError.refused;
        final tryAgain = refused ? onTryAgain : null;
        children.addAll([
          _title(tr('nd-join-failed-title'), t.title),
          const SizedBox(height: 12),
          Text(_failedLead(kind), style: t.lead),
          const SizedBox(height: 24),
          NdNotice(tone: NdTone.danger, text: joinFailedNotice(state)),
          const SizedBox(height: 24),
          Text(joinFailedNext(state),
              style: t.body.copyWith(fontSize: 15, height: 22 / 15)),
          const SizedBox(height: 24),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (tryAgain != null)
              NdButton.primary(
                  label: tr('nd-try-again'),
                  size: NdButtonSize.lg,
                  onPressed: tryAgain),
            tryAgain != null
                ? NdButton(
                    label: tr('nd-try-another-code'),
                    size: NdButtonSize.lg,
                    onPressed: onTryAnother)
                : NdButton.primary(
                    label: tr('nd-try-another-code'),
                    size: NdButtonSize.lg,
                    onPressed: onTryAnother),
            NdButton(
                label: tr('nd-set-up-by-hand'),
                size: NdButtonSize.lg,
                onPressed: onSetUpByHand),
          ]),
        ]);
        break;
      default:
        final step = state.joinStep.clamp(0, 3);
        NdStepState st(int i) => step > i
            ? NdStepState.done
            : (step == i ? NdStepState.running : NdStepState.todo);
        children.addAll([
          _title(tr('nd-join-progress-title', [_company]), t.title),
          const SizedBox(height: 24),
          NdStepRow(
              state: st(0),
              text: step > 0
                  ? tr('nd-join-step-checked')
                  : tr('nd-join-step-checking')),
          NdStepRow(
              state: st(1),
              text: tr('nd-join-step-settings', [state.server ?? ''])),
          NdStepRow(state: st(2), text: tr('nd-join-step-adding', [_company])),
          const SizedBox(height: 24),
          Text(tr('nd-join-progress-hint'), style: t.small),
        ]);
    }

    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(72, 40, 32, 40),
            child: Align(
              alignment: const Alignment(-1, -0.1),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: DefaultTextStyle(
                  style: t.body.copyWith(color: c.text),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(String text, TextStyle style) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Text(text, style: style));

  String _failedLead(OnboardingError kind) => switch (kind) {
        OnboardingError.usedUp => tr('nd-join-failed-lead-used'),
        OnboardingError.expired => tr('nd-join-failed-lead-expired'),
        OnboardingError.unreachable => tr('nd-join-failed-lead-unreachable'),
        OnboardingError.tooManyTries => tr('nd-invite-error-too-many'),
        OnboardingError.refused => tr('nd-join-failed-lead-refused'),
        _ => tr('nd-join-failed-lead-other'),
      };

}

/// The notice of a failed join, the same on Home and in Settings, Join a
/// server: the server's own words for a refusal, for the rest the core's
/// sentence with the server's answer in it.
String joinFailedNotice(OnboardingState state) {
  final kind = state.errorKind ?? OnboardingError.other;
  if (kind == OnboardingError.unreachable) {
    return onboardingFailedReach(state.server);
  }
  final reason = (state.reason ?? '').trim();
  final answer = (kind == OnboardingError.refused && reason.isNotEmpty
          ? reason
          : (state.error ?? ''))
      .trim();
  return tr('nd-join-failed-answer', [
    state.server ?? '',
    _withoutFinalStop(answer.isNotEmpty ? answer : _shortReason(kind))
  ]);
}

/// What to do after a failed join, under its notice.
String joinFailedNext(OnboardingState state) =>
    tr(state.errorKind == OnboardingError.refused
        ? 'nd-join-failed-next-refused'
        : 'nd-join-failed-next');

/// The notice ends the sentence itself.
String _withoutFinalStop(String text) =>
    text.endsWith('.') ? text.substring(0, text.length - 1) : text;

String _shortReason(OnboardingError kind) => switch (kind) {
      OnboardingError.usedUp => tr('nd-reason-used'),
      OnboardingError.expired => tr('nd-reason-expired'),
      OnboardingError.tooManyTries => tr('nd-reason-too-many'),
      _ => tr('nd-reason-other'),
    };

String onboardingFailedReach(String? server) =>
    tr('nd-invite-error-unreachable', [server ?? '']);

/// An ID grouped in threes with spaces: 418 205 739.
String formatNdId(String id) {
  final digits = id.replaceAll(' ', '');
  if (!RegExp(r'^\d+$').hasMatch(digits)) return id;
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
    b.write(digits[i]);
  }
  return b.toString();
}
