import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

import 'onboarding_service.dart';

/// What closing the quick support window does.
enum QuickSupportClose {
  /// Quit, as before: the session was not over, or nothing can be kept.
  quit,

  /// Quit and delete the downloaded file: the session is over and the
  /// person did not keep quick support.
  remove,

  /// The kept app goes to the background and waits for the next link.
  rest,
}

/// What closing the window in state [s] does. Closing without a choice
/// after the session counts as Remove.
QuickSupportClose quickSupportCloseOf(OnboardingState s) {
  if (s.kept) return QuickSupportClose.rest;
  final over = s.phase == OnboardingPhase.supportEnded ||
      s.phase == OnboardingPhase.supportExpired;
  if (over && s.canKeep && !s.keepFailed) return QuickSupportClose.remove;
  return QuickSupportClose.quit;
}

/// The quick support window (480 x 720): connecting, consent, waiting,
/// ended, declined, expired and offline (DESIGN.md, Quick support app).
/// After a session it offers to keep quick support on the computer, and
/// the kept app shows that it is ready when it opens without a link.
class QuickSupportView extends StatefulWidget {
  const QuickSupportView({
    super.key,
    required this.state,
    required this.onAllow,
    required this.onDecline,
    required this.onCancel,
    required this.onClose,
    required this.onRetry,
    this.onKeep,
    this.onRemove,
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

  /// Keep on this computer, on the ended screen.
  final VoidCallback? onKeep;

  /// Remove from this computer, on the ended screen and in the kept app.
  final VoidCallback? onRemove;
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
      OnboardingPhase.supportInSession => tr('nd-qs-bar-viewing', [short]),
      OnboardingPhase.supportEnded => tr('nd-qs-ended-title'),
      OnboardingPhase.supportExpired => tr('nd-qs-expired-title'),
      OnboardingPhase.notSetUp ||
      OnboardingPhase.joined when s.kept =>
        tr('nd-qs-ready-title'),
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
          } else {
            final offerKeep = s.canKeep && !s.kept && !s.keepFailed;
            body.addAll([
              Text(tr('nd-qs-ended-title'), style: title),
              const SizedBox(height: 16),
              Text(tr('nd-qs-ended-lead', [short, companyOrServer]),
                  style: lead),
              if (s.kept) ...[
                const SizedBox(height: 16),
                Text(tr('nd-qs-kept-line'), style: lead),
              ] else if (offerKeep) ...[
                const SizedBox(height: 28),
                Text(tr('nd-qs-keep-title'), style: t.heading),
                const SizedBox(height: 8),
                Text(tr('nd-qs-keep-line'), style: lead),
              ] else if (s.keepFailed) ...[
                const SizedBox(height: 16),
                Text(tr('nd-qs-keep-failed'), style: lead),
              ] else if ((s.fileName ?? '').isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(tr('nd-qs-ended-hint'), style: t.body.copyWith(
                    color: c.textMuted)),
                const SizedBox(height: 4),
                SelectableText(s.fileName!, style: t.mono.copyWith(
                    fontSize: 14, height: 20 / 14)),
              ],
            ]);
            if (offerKeep && widget.onKeep != null) {
              // Closing the window without a choice removes it too
              primary = NdButton.primary(
                  label: tr('nd-qs-keep'),
                  size: NdButtonSize.lg,
                  block: true,
                  onPressed: widget.onKeep);
              secondary = NdButton(
                  label: tr('nd-qs-remove'),
                  size: NdButtonSize.lg,
                  block: true,
                  onPressed: widget.onRemove ?? widget.onClose);
              break;
            }
          }
          primary = NdButton.primary(
              label: translate('Close'),
              size: NdButtonSize.lg,
              block: true,
              onPressed: widget.onClose);
          if (s.kept && widget.onRemove != null) {
            secondary = NdButton(
                label: tr('nd-qs-remove'),
                size: NdButtonSize.lg,
                block: true,
                onPressed: widget.onRemove);
          }
          break;
        case OnboardingPhase.notSetUp:
        case OnboardingPhase.joined:
          if (!s.kept) continue connecting;
          // The kept app opened without a link: it waits for one
          body.addAll([
            Text(tr('nd-qs-ready-title'), style: title),
            const SizedBox(height: 16),
            Text(tr('nd-qs-ready-line'), style: lead),
          ]);
          primary = NdButton.primary(
              label: translate('Close'),
              size: NdButtonSize.lg,
              block: true,
              onPressed: widget.onClose);
          if (widget.onRemove != null) {
            secondary = NdButton(
                label: tr('nd-qs-remove'),
                size: NdButtonSize.lg,
                block: true,
                onPressed: widget.onRemove);
          }
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
        connecting:
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

/// The bar at the top of the screen while the supporter is connected:
/// "<name> is viewing and controlling your computer" (or "is using your
/// computer" while their input arrives), Files once files move, Chat and
/// Stop.
class SessionBar extends StatelessWidget {
  const SessionBar({
    super.key,
    required this.state,
    required this.onChat,
    required this.onStop,
    this.onFiles,
    this.chatOpen = false,
    this.onDrag,
  });

  final OnboardingState state;
  final VoidCallback onChat;
  final VoidCallback onStop;

  /// Opens the list of files; the button shows once the supporter has the
  /// files open or sent or took one.
  final VoidCallback? onFiles;
  final bool chatOpen;

  /// Starts moving the window (the drag handle).
  final VoidCallback? onDrag;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final name = (state.supporterName ?? '').trim();
    final sentence = state.inputActive
        ? tr('nd-qs-bar-using', [name])
        : tr('nd-qs-bar-viewing', [name]);
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
        borderRadius: NdSize.r,
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
              child: Icon(NdIcons.dragIndicator, size: 18, color: c.textMuted),
            ),
          ),
        ),
        const SizedBox(width: 4),
        const NdLogoMark(size: 18),
        const SizedBox(width: 10),
        text,
        const SizedBox(width: 14),
        if (onFiles != null && (state.filesOpen || state.files.isNotEmpty)) ...[
          NdButton(
              label: state.files.isEmpty
                  ? tr('nd-qs-files')
                  : tr('nd-qs-files-count', [state.files.length]),
              icon: state.filesOpen ? NdIcons.folderOpen : NdIcons.folder,
              size: NdButtonSize.sm,
              onPressed: onFiles),
          const SizedBox(width: 8),
        ],
        NdButton(
            label: translate('Chat'),
            size: NdButtonSize.sm,
            onPressed: onChat),
        const SizedBox(width: 8),
        NdButton(
            label: tr('nd-stop'),
            size: NdButtonSize.sm,
            kind: NdButtonKind.danger,
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
    final c = context.nd;
    final t = context.ndText;
    final name = (widget.state.supporterName ?? '').trim();
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: c.bgFloat,
        borderRadius: NdSize.r,
        border: Border.all(color: c.rule),
        boxShadow: c.shadowFloat,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            Expanded(
                child: Text(tr('nd-qs-chat-with', [name]), style: t.heading)),
            NdIconButton(
                icon: NdIcons.close,
                tooltip: translate('Close'),
                color: c.text,
                iconSize: 20,
                onPressed: widget.onClose),
          ]),
        ),
        const NdRule(),
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
                          '${m.fromSupporter ? name : tr('nd-qs-you')}, ${_time(m.time)}',
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
              child: NdField(
                controller: _controller,
                placeholder: tr('nd-qs-chat-field'),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            NdButton.primary(label: translate('Send'), onPressed: _send),
          ]),
        ),
      ]),
    );
  }
}

/// A file size as people read it: 36 B, 4.5 KB, 12.3 MB.
String sessionFileSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final number = unit == 0 || size >= 100
      ? size.round().toString()
      : size.toStringAsFixed(1);
  return '$number ${units[unit]}';
}

/// The files panel under the session bar: whether the supporter has the
/// files open, and each file they sent to this computer or took from it, as
/// it happens. Newest first.
class SessionFilesPanel extends StatelessWidget {
  const SessionFilesPanel({
    super.key,
    required this.state,
    required this.onClose,
    this.timeFormat,
  });

  final OnboardingState state;
  final VoidCallback onClose;
  final String Function(DateTime)? timeFormat;

  String _time(DateTime d) =>
      timeFormat?.call(d) ??
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final name = (state.supporterName ?? '').trim();
    final lines = state.files.reversed.toList();
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: c.bgFloat,
        borderRadius: NdSize.r,
        border: Border.all(color: c.rule),
        boxShadow: c.shadowFloat,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            Expanded(child: Text(tr('nd-qs-files'), style: t.heading)),
            NdIconButton(
                icon: NdIcons.close,
                tooltip: translate('Close'),
                color: c.text,
                iconSize: 20,
                onPressed: onClose),
          ]),
        ),
        const NdRule(),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Row(children: [
            if (state.filesOpen) ...[
              const NdSpinner(),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                  state.filesOpen
                      ? tr('nd-qs-files-open', [name])
                      : tr('nd-qs-files-closed', [name]),
                  style: t.body.copyWith(fontSize: 15, height: 22 / 15)),
            ),
          ]),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            children: [
              if (lines.isEmpty)
                Text(tr('nd-qs-files-none'), style: t.small),
              for (final f in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                            f.toThisComputer
                                ? NdIcons.arrowDownward
                                : NdIcons.arrowUpward,
                            size: 18,
                            color: c.textMuted),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                f.name.isNotEmpty
                                    ? f.name
                                    : tr('nd-qs-file-count', [f.count]),
                                style: t.body.copyWith(
                                    fontSize: 15,
                                    height: 22 / 15,
                                    fontWeight: FontWeight.w600)),
                            Text(
                                f.path.isEmpty
                                    ? tr(f.toThisComputer
                                        ? 'nd-qs-file-to-here'
                                        : 'nd-qs-file-from-here')
                                    : tr(
                                        f.toThisComputer
                                            ? 'nd-qs-file-to'
                                            : 'nd-qs-file-from',
                                        [f.path]),
                                style: t.small),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(sessionFileSize(f.size), style: t.small),
                          Text(_time(f.time), style: t.small),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
