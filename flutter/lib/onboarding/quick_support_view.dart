import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

import 'onboarding_service.dart';
import 'session_feedback.dart';

/// The quick support window (480 x 720): connecting, consent, waiting,
/// ended, declined, expired and offline (DESIGN.md, Quick support app).
class QuickSupportView extends StatefulWidget {
  const QuickSupportView({
    super.key,
    required this.state,
    required this.onAllow,
    required this.onDecline,
    required this.onCancel,
    required this.onClose,
    required this.onRetry,
    this.onFeedback,
    this.onInstallReceiver,
    this.logo,
    this.waitedLong = false,
  });

  final OnboardingState state;

  /// Allow, with the choices the person ticked.
  final ValueChanged<QuickSupportGrants> onAllow;
  final VoidCallback onDecline;

  /// Cancel while connecting or waiting: ends the session.
  final VoidCallback onCancel;

  /// Close after the end: quits the app.
  final VoidCallback onClose;
  final VoidCallback onRetry;

  /// Send on the end screen, with the answers by question id.
  final ValueChanged<Map<String, Object>>? onFeedback;

  /// Install on the offer to keep the app after the session (A277).
  final VoidCallback? onInstallReceiver;
  final Widget? logo;

  /// Shows the "hasn't connected yet" line at once (screenshots).
  final bool waitedLong;

  @override
  State<QuickSupportView> createState() => _QuickSupportViewState();
}

class _QuickSupportViewState extends State<QuickSupportView> {
  Timer? _waitTimer;
  late bool _long = widget.waitedLong;

  /// The consent screen's choices; both start off.
  bool _clipboard = false;
  bool _files = false;

  /// The end screen's feedback answers until Send.
  Map<String, Object> _answers = const {};

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void didUpdateWidget(covariant QuickSupportView old) {
    super.didUpdateWidget(old);
    if (old.state.phase != widget.state.phase) {
      _armTimer();
      // The person being helped must hear when someone is on their
      // computer, and when that ends.
      final line = _phaseLine(widget.state);
      if (line != null) ndAnnounce(context, line, assertive: true);
    }
  }

  String? _phaseLine(OnboardingState s) {
    final company = (s.company ?? '').trim();
    final full = (s.supporterName ?? '').trim();
    final short = s.supporterShortName.isNotEmpty ? s.supporterShortName : full;
    return switch (s.phase) {
      OnboardingPhase.supportConsent => company.isNotEmpty
          ? tr('nd-qs-consent-title', [full, company])
          : tr('nd-qs-consent-title-nocompany', [full]),
      OnboardingPhase.supportConnecting => tr('nd-qs-connecting-title'),
      OnboardingPhase.supportWaiting => tr('nd-qs-waiting-title', [short]),
      OnboardingPhase.supportEnded => tr('nd-qs-ended-title'),
      OnboardingPhase.supportExpired => tr('nd-qs-expired-title'),
      _ => null,
    };
  }

  void _armTimer() {
    _waitTimer?.cancel();
    if (widget.state.phase == OnboardingPhase.supportWaiting && !_long) {
      _waitTimer = Timer(const Duration(minutes: 2), () {
        if (mounted) setState(() => _long = true);
      });
    }
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final s = widget.state;
    final company = (s.company ?? '').trim();
    final full = (s.supporterName ?? '').trim();
    final short = s.supporterShortName.isNotEmpty ? s.supporterShortName : full;
    final companyOrServer = company.isNotEmpty ? company : (s.server ?? '');
    final lead = t.body.copyWith(fontSize: 15, height: 22 / 15, color: c.text);
    final title = t.titleMd.copyWith(fontSize: 26, height: 32 / 26);

    final body = <Widget>[];
    Widget? primary;
    Widget? secondary;
    Widget? under;

    final offline = s.errorKind == OnboardingError.unreachable &&
        (s.phase == OnboardingPhase.supportConnecting ||
            s.phase == OnboardingPhase.supportWaiting);

    if (offline) {
      body.addAll([
        Text(tr('nd-qs-offline-title'), style: title),
        const SizedBox(height: 16),
        Text(tr('nd-qs-offline-lead', [companyOrServer]), style: lead),
      ]);
      primary = NdButton.primary(
          label: tr('nd-try-again'),
          size: NdButtonSize.lg,
          block: true,
          onPressed: widget.onRetry);
      secondary = NdButton(
          label: translate('Cancel'),
          size: NdButtonSize.lg,
          block: true,
          onPressed: widget.onCancel);
    } else {
      switch (s.phase) {
        case OnboardingPhase.supportConsent:
          body.addAll([
            Text(
                company.isNotEmpty
                    ? tr('nd-qs-consent-title', [full, company])
                    : tr('nd-qs-consent-title-nocompany', [full]),
                style: title),
            const SizedBox(height: 12),
            Text(tr('nd-qs-consent-intro', [short]), style: lead),
            const SizedBox(height: 10),
            _Can(icon: NdIcons.view, text: tr('nd-qs-can-see')),
            _Can(icon: NdIcons.mouse, text: tr('nd-qs-can-use')),
            const SizedBox(height: 16),
            Text(tr('nd-qs-consent-also', [short]), style: lead),
            const SizedBox(height: 10),
            NdCheckbox(
                value: _clipboard,
                label: tr('nd-qs-allow-clipboard'),
                hint: tr('nd-qs-allow-clipboard-hint'),
                onChanged: (v) => setState(() => _clipboard = v)),
            const SizedBox(height: 10),
            NdCheckbox(
                value: _files,
                label: tr('nd-qs-allow-files'),
                hint: tr('nd-qs-allow-files-hint', [short]),
                onChanged: (v) => setState(() => _files = v)),
            const SizedBox(height: 16),
            Text(tr('nd-qs-consent-after'), style: lead),
            if ((s.server ?? '').isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(children: [
                Icon(NdIcons.lock, size: 16, color: c.textMuted),
                const SizedBox(width: 10),
                Text(tr('nd-qs-origin', [s.server]), style: t.small),
              ]),
            ],
          ]);
          primary = NdButton.primary(
              label: tr('nd-allow'),
              size: NdButtonSize.lg,
              block: true,
              onPressed: () => widget.onAllow(QuickSupportGrants(
                  clipboard: _clipboard, fileTransfer: _files)));
          secondary = NdButton(
              label: translate('Decline'),
              size: NdButtonSize.lg,
              block: true,
              onPressed: widget.onDecline);
          under = Text(tr('nd-qs-not-expecting'),
              textAlign: TextAlign.center, style: t.small);
          break;
        case OnboardingPhase.supportWaiting:
        case OnboardingPhase.supportInSession:
          if (s.phase == OnboardingPhase.supportWaiting &&
              (s.asking ?? '').isNotEmpty) {
            // The supporter's connection waits for the person in the other
            // window (the connection manager): send them there (L553)
            body.addAll([
              Text(tr('nd-qs-asking-title', [s.asking]), style: title),
              const SizedBox(height: 16),
              Text(tr('nd-qs-asking-line'), style: lead),
            ]);
            secondary = NdButton(
                label: translate('Cancel'),
                size: NdButtonSize.lg,
                block: true,
                onPressed: widget.onCancel);
            break;
          }
          body.addAll([
            Text(tr('nd-qs-waiting-title', [short]), style: title),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.only(top: 3), child: NdSpinner()),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    _long
                        ? ((s.companyPhone ?? '').isNotEmpty
                            ? tr('nd-qs-waiting-long-phone',
                                [short, companyOrServer, s.companyPhone])
                            : tr('nd-qs-waiting-long', [short]))
                        : tr('nd-qs-waiting-line', [short]),
                    style: lead),
              ),
            ]),
          ]);
          secondary = NdButton(
              label: translate('Cancel'),
              size: NdButtonSize.lg,
              block: true,
              onPressed: widget.onCancel);
          break;
        case OnboardingPhase.supportEnded:
          if (s.errorKind == OnboardingError.refused &&
              (s.reason ?? '').trim().isNotEmpty) {
            // The server refused this computer: its reason in the app's
            // words, with what to do (L550)
            body.addAll([
              Text(tr('nd-qs-refused-title'), style: title),
              const SizedBox(height: 16),
              Text(s.reason!.trim(), style: lead),
            ]);
          } else if (s.declined) {
            body.addAll([
              Text(tr('nd-qs-ended-title'), style: title),
              const SizedBox(height: 16),
              Text(tr('nd-qs-declined', [full]), style: lead),
            ]);
          } else if (s.offerReceiver &&
              widget.onInstallReceiver != null &&
              (s.feedback.isEmpty || s.feedbackState == FeedbackState.sent)) {
            // After the feedback: keep the app on this computer (A277)
            final installing = s.receiverInstalling;
            body.addAll([
              Text(
                  company.isNotEmpty
                      ? tr('nd-qs-keep-title', [company])
                      : tr('nd-qs-keep-title-nocompany'),
                  style: title),
              const SizedBox(height: 16),
              Text(tr('nd-qs-keep-lead'), style: lead),
            ]);
            primary = NdButton.primary(
                key: const ValueKey('qs-keep-install'),
                label: tr('nd-qs-keep-install'),
                size: NdButtonSize.lg,
                block: true,
                leading: installing ? const NdSpinner() : null,
                onPressed: installing ? null : widget.onInstallReceiver);
            secondary = NdButton(
                key: const ValueKey('qs-keep-no'),
                label: tr('nd-qs-keep-no'),
                size: NdButtonSize.lg,
                block: true,
                onPressed: installing ? null : widget.onClose);
            break;
          } else {
            final asks = s.feedback.isNotEmpty &&
                s.feedbackState != FeedbackState.sent;
            final sending = s.feedbackState == FeedbackState.sending;
            body.addAll([
              Text(tr('nd-qs-ended-title'), style: title),
              const SizedBox(height: 16),
              Text(tr('nd-qs-ended-lead', [short, companyOrServer]),
                  style: lead),
              if (s.sessionLength != null) ...[
                const SizedBox(height: 20),
                SessionSummary(state: s),
              ],
              if (asks) ...[
                const SizedBox(height: 32),
                Text(tr('nd-qs-feedback-title'),
                    style: t.heading.copyWith(fontSize: 17)),
                const SizedBox(height: 16),
                SessionFeedbackForm(
                  questions: s.feedback,
                  enabled: !sending,
                  onChanged: (a) => setState(() => _answers = a),
                ),
                if (s.feedbackState == FeedbackState.failed) ...[
                  const SizedBox(height: 16),
                  NdNotice(
                      text: tr('nd-qs-feedback-failed'), tone: NdTone.danger),
                ],
              ],
              if (s.feedbackState == FeedbackState.sent) ...[
                const SizedBox(height: 24),
                Row(children: [
                  Icon(NdIcons.checkCircle, size: 20, color: c.success),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(tr('nd-qs-feedback-thanks'), style: lead)),
                ]),
              ],
              if ((s.fileName ?? '').isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(tr('nd-qs-ended-hint'), style: t.small),
                const SizedBox(height: 4),
                SelectableText(s.fileName!, style: t.mono.copyWith(
                    fontSize: 13, height: 18 / 13, color: c.textMuted)),
              ],
            ]);
            if (asks) {
              primary = NdButton.primary(
                  label: tr('nd-qs-feedback-send'),
                  size: NdButtonSize.lg,
                  block: true,
                  onPressed: !sending &&
                          widget.onFeedback != null &&
                          feedbackComplete(s.feedback, _answers)
                      ? () => widget.onFeedback!(Map.of(_answers))
                      : null);
              secondary = NdButton(
                  label: translate('Close'),
                  size: NdButtonSize.lg,
                  block: true,
                  onPressed: widget.onClose);
              break;
            }
          }
          primary = NdButton.primary(
              label: translate('Close'),
              size: NdButtonSize.lg,
              block: true,
              onPressed: widget.onClose);
          break;
        case OnboardingPhase.supportExpired:
          body.addAll([
            Text(tr('nd-qs-expired-title'), style: title),
            const SizedBox(height: 16),
            Text(tr('nd-qs-expired-lead', [companyOrServer]), style: lead),
          ]);
          primary = NdButton.primary(
              label: translate('Close'),
              size: NdButtonSize.lg,
              block: true,
              onPressed: widget.onClose);
          break;
        default:
          body.addAll([
            Text(tr('nd-qs-connecting-title'), style: title),
            const SizedBox(height: 16),
            Row(children: [
              const NdSpinner(),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      tr('nd-qs-connecting-line', [s.server ?? '']),
                      style: lead)),
            ]),
          ]);
          secondary = NdButton(
              label: translate('Cancel'),
              size: NdButtonSize.lg,
              block: true,
              onPressed: widget.onCancel);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (company.isNotEmpty) ...[
            Row(children: [
              if (widget.logo != null) ...[
                SizedBox(width: 26, height: 26, child: widget.logo),
                const SizedBox(width: 8),
              ],
              Text(company,
                  style: t.label.copyWith(
                      fontSize: 17, height: 1, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 24),
          ],
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: body),
            ),
          ),
          const SizedBox(height: 16),
          if (primary != null) primary,
          if (primary != null && secondary != null) const SizedBox(height: 10),
          if (secondary != null) secondary,
          if (under != null) ...[const SizedBox(height: 16), under],
          if (under == null) const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Can extends StatelessWidget {
  const _Can({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 20, color: context.nd.success),
        const SizedBox(width: 12),
        // Wraps when the text is scaled up instead of running off the edge.
        Flexible(
          child: Text(text,
              style: t.body.copyWith(fontSize: 15, height: 22 / 15)),
        ),
      ]),
    );
  }
}
