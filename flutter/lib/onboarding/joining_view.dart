import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';

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
    final t = context.bdText;
    final c = context.bd;
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
          _title(tr('bd-join-done-title', [_company]), t.title),
          const SizedBox(height: 12),
          Text(tr('bd-join-done-lead', [_company]), style: t.lead),
          const SizedBox(height: 32),
          SizedBox(
            width: 436,
            child: BdFacts(facts: [
              if ((state.deviceName ?? '').isNotEmpty)
                BdFact(tr('bd-fact-name'), state.deviceName!),
              if ((state.folder ?? '').isNotEmpty)
                BdFact(tr('bd-fact-folder'), state.folder!),
              if (id.isNotEmpty) BdFact(tr('bd-fact-id'), formatBdId(id), mono: true),
              if ((state.server ?? '').isNotEmpty)
                BdFact(tr('bd-fact-server'), state.server!),
            ]),
          ),
          const SizedBox(height: 24),
          BdButton.primary(
              label: tr('bd-done'), size: BdButtonSize.lg, onPressed: onDone),
        ]);
        break;
      case OnboardingPhase.joinFailed:
        final kind = state.errorKind ?? OnboardingError.other;
        final refused = kind == OnboardingError.refused;
        final reason = (state.reason ?? '').trim();
        // The server's own words for a refusal; for the rest the core's
        // sentence with the server's answer in it.
        final answer =
            (refused && reason.isNotEmpty ? reason : (state.error ?? ''))
                .trim();
        final tryAgain = refused ? onTryAgain : null;
        children.addAll([
          _title(tr('bd-join-failed-title'), t.title),
          const SizedBox(height: 12),
          Text(_failedLead(kind), style: t.lead),
          const SizedBox(height: 24),
          BdNotice(
            tone: BdTone.danger,
            text: kind == OnboardingError.unreachable
                ? onboardingFailedReach(state.server)
                : tr('bd-join-failed-answer', [
                    state.server ?? '',
                    _withoutFinalStop(
                        answer.isNotEmpty ? answer : _shortReason(kind))
                  ]),
          ),
          const SizedBox(height: 24),
          Text(
              tr(refused
                  ? 'bd-join-failed-next-refused'
                  : 'bd-join-failed-next'),
              style: t.body.copyWith(fontSize: 15, height: 22 / 15)),
          const SizedBox(height: 24),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (tryAgain != null)
              BdButton.primary(
                  label: tr('bd-try-again'),
                  size: BdButtonSize.lg,
                  onPressed: tryAgain),
            tryAgain != null
                ? BdButton(
                    label: tr('bd-try-another-code'),
                    size: BdButtonSize.lg,
                    onPressed: onTryAnother)
                : BdButton.primary(
                    label: tr('bd-try-another-code'),
                    size: BdButtonSize.lg,
                    onPressed: onTryAnother),
            BdButton(
                label: tr('bd-set-up-by-hand'),
                size: BdButtonSize.lg,
                onPressed: onSetUpByHand),
          ]),
        ]);
        break;
      default:
        final step = state.joinStep.clamp(0, 3);
        BdStepState st(int i) => step > i
            ? BdStepState.done
            : (step == i ? BdStepState.running : BdStepState.todo);
        children.addAll([
          _title(tr('bd-join-progress-title', [_company]), t.title),
          const SizedBox(height: 24),
          BdStepRow(
              state: st(0),
              text: step > 0
                  ? tr('bd-join-step-checked')
                  : tr('bd-join-step-checking')),
          BdStepRow(
              state: st(1),
              text: tr('bd-join-step-settings', [state.server ?? ''])),
          BdStepRow(state: st(2), text: tr('bd-join-step-adding', [_company])),
          const SizedBox(height: 24),
          Text(tr('bd-join-progress-hint'), style: t.small),
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
        OnboardingError.usedUp => tr('bd-join-failed-lead-used'),
        OnboardingError.expired => tr('bd-join-failed-lead-expired'),
        OnboardingError.unreachable => tr('bd-join-failed-lead-unreachable'),
        OnboardingError.tooManyTries => tr('bd-invite-error-too-many'),
        OnboardingError.refused => tr('bd-join-failed-lead-refused'),
        _ => tr('bd-join-failed-lead-other'),
      };

  /// The notice ends the sentence itself.
  static String _withoutFinalStop(String text) =>
      text.endsWith('.') ? text.substring(0, text.length - 1) : text;

  String _shortReason(OnboardingError kind) => switch (kind) {
        OnboardingError.usedUp => tr('bd-reason-used'),
        OnboardingError.expired => tr('bd-reason-expired'),
        OnboardingError.tooManyTries => tr('bd-reason-too-many'),
        _ => tr('bd-reason-other'),
      };
}

String onboardingFailedReach(String? server) =>
    tr('bd-invite-error-unreachable', [server ?? '']);

/// An ID grouped in threes with spaces: 418 205 739.
String formatBdId(String id) {
  final digits = id.replaceAll(' ', '');
  if (!RegExp(r'^\d+$').hasMatch(digits)) return id;
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
    b.write(digits[i]);
  }
  return b.toString();
}
