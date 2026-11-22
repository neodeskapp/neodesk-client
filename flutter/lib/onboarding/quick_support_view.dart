import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/bd/bd.dart';

import 'onboarding_service.dart';

/// The quick support window (480 x 560): connecting, consent, waiting,
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
    this.logo,
    this.waitedLong = false,
  });

  final OnboardingState state;
  final VoidCallback onAllow;
  final VoidCallback onDecline;

  /// Cancel while connecting or waiting: ends the session.
  final VoidCallback onCancel;

  /// Close after the end: quits the app.
  final VoidCallback onClose;
  final VoidCallback onRetry;
  final Widget? logo;

  /// Shows the "hasn't connected yet" line at once (screenshots).
  final bool waitedLong;

  @override
  State<QuickSupportView> createState() => _QuickSupportViewState();
}

class _QuickSupportViewState extends State<QuickSupportView> {
  Timer? _waitTimer;
  late bool _long = widget.waitedLong;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void didUpdateWidget(covariant QuickSupportView old) {
    super.didUpdateWidget(old);
    if (old.state.phase != widget.state.phase) _armTimer();
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
    final c = context.bd;
    final t = context.bdText;
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
        Text(tr('bd-qs-offline-title'), style: title),
        const SizedBox(height: 16),
        Text(tr('bd-qs-offline-lead', [companyOrServer]), style: lead),
      ]);
      primary = BdButton.primary(
          label: tr('bd-try-again'),
          size: BdButtonSize.lg,
          block: true,
          onPressed: widget.onRetry);
      secondary = BdButton(
          label: translate('Cancel'),
          size: BdButtonSize.lg,
          block: true,
          onPressed: widget.onCancel);
    } else {
      switch (s.phase) {
        case OnboardingPhase.supportConsent:
          body.addAll([
            Text(
                company.isNotEmpty
                    ? tr('bd-qs-consent-title', [full, company])
                    : tr('bd-qs-consent-title-nocompany', [full]),
                style: title),
            const SizedBox(height: 12),
            Text(tr('bd-qs-consent-intro', [short]), style: lead),
            const SizedBox(height: 10),
            _Can(icon: BdIcons.visibility, text: tr('bd-qs-can-see')),
            _Can(icon: BdIcons.mouse, text: tr('bd-qs-can-use')),
            const SizedBox(height: 10),
            Text(tr('bd-qs-consent-after'), style: lead),
            if ((s.server ?? '').isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(children: [
                Icon(BdIcons.lock, size: 16, color: c.textMuted),
                const SizedBox(width: 10),
                Text(tr('bd-qs-origin', [s.server]), style: t.small),
              ]),
            ],
          ]);
          primary = BdButton.primary(
              label: tr('bd-allow'),
              size: BdButtonSize.lg,
              block: true,
              onPressed: widget.onAllow);
          secondary = BdButton(
              label: translate('Decline'),
              size: BdButtonSize.lg,
              block: true,
              onPressed: widget.onDecline);
          under = Text(tr('bd-qs-not-expecting'),
              textAlign: TextAlign.center, style: t.small);
          break;
        case OnboardingPhase.supportWaiting:
        case OnboardingPhase.supportInSession:
          body.addAll([
            Text(tr('bd-qs-waiting-title', [short]), style: title),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.only(top: 3), child: BdSpinner()),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    _long
                        ? ((s.companyPhone ?? '').isNotEmpty
                            ? tr('bd-qs-waiting-long-phone',
                                [short, companyOrServer, s.companyPhone])
                            : tr('bd-qs-waiting-long', [short]))
                        : tr('bd-qs-waiting-line', [short]),
                    style: lead),
              ),
            ]),
          ]);
          secondary = BdButton(
              label: translate('Cancel'),
              size: BdButtonSize.lg,
              block: true,
              onPressed: widget.onCancel);
          break;
        case OnboardingPhase.supportEnded:
          if (s.declined) {
            body.addAll([
              Text(tr('bd-qs-ended-title'), style: title),
              const SizedBox(height: 16),
              Text(tr('bd-qs-declined', [full]), style: lead),
            ]);
          } else {
            body.addAll([
              Text(tr('bd-qs-ended-title'), style: title),
              const SizedBox(height: 16),
              Text(tr('bd-qs-ended-lead', [short, companyOrServer]),
                  style: lead),
              if ((s.fileName ?? '').isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(tr('bd-qs-ended-hint'), style: t.body.copyWith(
                    color: c.textMuted)),
                const SizedBox(height: 4),
                SelectableText(s.fileName!, style: t.mono.copyWith(
                    fontSize: 14, height: 20 / 14)),
              ],
            ]);
          }
          primary = BdButton.primary(
              label: translate('Close'),
              size: BdButtonSize.lg,
              block: true,
              onPressed: widget.onClose);
          break;
        case OnboardingPhase.supportExpired:
          body.addAll([
            Text(tr('bd-qs-expired-title'), style: title),
            const SizedBox(height: 16),
            Text(tr('bd-qs-expired-lead', [companyOrServer]), style: lead),
          ]);
          primary = BdButton.primary(
              label: translate('Close'),
              size: BdButtonSize.lg,
              block: true,
              onPressed: widget.onClose);
          break;
        default:
          body.addAll([
            Text(tr('bd-qs-connecting-title'), style: title),
            const SizedBox(height: 16),
            Row(children: [
              const BdSpinner(),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      tr('bd-qs-connecting-line', [s.server ?? '']),
                      style: lead)),
            ]),
          ]);
          secondary = BdButton(
              label: translate('Cancel'),
              size: BdButtonSize.lg,
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
    final t = context.bdText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 20, color: context.bd.success),
        const SizedBox(width: 12),
        Text(text, style: t.body.copyWith(fontSize: 15, height: 22 / 15)),
      ]),
    );
  }
}

/// The bar at the top of the screen while the supporter is connected:
/// "<name> is viewing your screen" (or "is using your computer" while their
/// input arrives), Chat and Stop.
class SessionBar extends StatelessWidget {
  const SessionBar({
    super.key,
    required this.state,
    required this.onChat,
    required this.onStop,
    this.chatOpen = false,
    this.onDrag,
  });

  final OnboardingState state;
  final VoidCallback onChat;
  final VoidCallback onStop;
  final bool chatOpen;

  /// Starts moving the window (the drag handle).
  final VoidCallback? onDrag;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final name = (state.supporterName ?? '').trim();
    final sentence = state.inputActive
        ? tr('bd-qs-bar-using', [name])
        : tr('bd-qs-bar-viewing', [name]);
    // Bold the name inside the translated sentence.
    final i = name.isEmpty ? -1 : sentence.indexOf(name);
    final style = t.body.copyWith(fontSize: 15, height: 22 / 15);
    final text = i < 0
        ? Text(sentence, style: style)
        : Text.rich(TextSpan(style: style, children: [
            TextSpan(text: sentence.substring(0, i)),
            TextSpan(
                text: name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: sentence.substring(i + name.length)),
          ]));
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 4, right: 6),
      decoration: BoxDecoration(
        color: c.bgFloat,
        borderRadius: BdSize.r,
        border: Border.all(color: c.rule),
        boxShadow: c.shadowFloat,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onPanStart: onDrag == null ? null : (_) => onDrag!(),
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(BdIcons.dragIndicator, size: 18, color: c.textMuted),
            ),
          ),
        ),
        const SizedBox(width: 4),
        const BdLogoMark(size: 18),
        const SizedBox(width: 10),
        text,
        const SizedBox(width: 14),
        BdButton(
            label: translate('Chat'),
            size: BdButtonSize.sm,
            onPressed: onChat),
        const SizedBox(width: 8),
        BdButton(
            label: tr('bd-stop'),
            size: BdButtonSize.sm,
            kind: BdButtonKind.danger,
            onPressed: onStop),
      ]),
    );
  }
}

/// The chat panel under the session bar.
class SessionChatPanel extends StatefulWidget {
  const SessionChatPanel({
    super.key,
    required this.state,
    required this.onSend,
    required this.onClose,
    this.timeFormat,
  });

  final OnboardingState state;
  final ValueChanged<String> onSend;
  final VoidCallback onClose;
  final String Function(DateTime)? timeFormat;

  @override
  State<SessionChatPanel> createState() => _SessionChatPanelState();
}

class _SessionChatPanelState extends State<SessionChatPanel> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  String _time(DateTime d) =>
      widget.timeFormat?.call(d) ??
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final name = (widget.state.supporterName ?? '').trim();
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: c.bgFloat,
        borderRadius: BdSize.r,
        border: Border.all(color: c.rule),
        boxShadow: c.shadowFloat,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            Expanded(
                child: Text(tr('bd-qs-chat-with', [name]), style: t.heading)),
            BdIconButton(
                icon: BdIcons.close,
                tooltip: translate('Close'),
                color: c.text,
                iconSize: 20,
                onPressed: widget.onClose),
          ]),
        ),
        const BdRule(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            children: [
              for (final m in widget.state.messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: m.fromSupporter
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.end,
                    children: [
                      Text(
                          '${m.fromSupporter ? name : tr('bd-qs-you')}, ${_time(m.time)}',
                          style: t.small),
                      const SizedBox(height: 2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(m.text,
                            textAlign: m.fromSupporter
                                ? TextAlign.start
                                : TextAlign.end,
                            style: t.body
                                .copyWith(fontSize: 15, height: 22 / 15)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          child: Row(children: [
            Expanded(
              child: BdField(
                controller: _controller,
                placeholder: tr('bd-qs-chat-field'),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            BdButton.primary(label: translate('Send'), onPressed: _send),
          ]),
        ),
      ]),
    );
  }
}
