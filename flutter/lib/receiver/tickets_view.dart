// My tickets in the receiver's home window: the person's tickets with their
// status in plain words, the form for "Something isn't working" and one
// ticket's conversation with a field to answer.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/desktop/pages/nd_chat_page.dart'
    show ndChatDate, ndChatSize;

import 'tickets_model.dart';

/// What My tickets needs from the system.
class NdTicketActions {
  const NdTicketActions({
    required this.pickFiles,
    required this.screenshot,
    required this.saveFile,
  });

  /// The files the person chose; empty when they cancelled.
  final Future<List<NdTicketLocalFile>> Function() pickFiles;

  /// A picture of the screen taken with the window hidden; null when none
  /// could be taken.
  final Future<NdTicketLocalFile?> Function() screenshot;

  /// Asks where to save a file of the open ticket and saves it there:
  /// where, '' when the person cancelled, null when it failed.
  final Future<String?> Function(NdTicketFile file) saveFile;
}

/// The file the server attaches to every ticket with what it knows about
/// the computer; the person didn't add it, so it isn't listed.
const kNdTicketComputerInfo = 'computer-info.json';

/// A ticket's status in plain words.
String ndTicketStatus(String status) => switch (status) {
      'in_progress' => tr('nd-rcv-status-in-progress'),
      'resolved' => tr('nd-rcv-status-resolved'),
      'closed' => tr('nd-rcv-status-closed'),
      _ => tr('nd-rcv-status-open'),
    };

String _date(DateTime? d) =>
    d == null ? '' : ndChatDate(d, tr('nd-chat-date-format'));

String _time(DateTime? d) => d == null
    ? ''
    : '${_date(d)}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class TicketsView extends StatefulWidget {
  const TicketsView({super.key, required this.model, required this.actions});

  final NdTicketsModel model;
  final NdTicketActions actions;

  @override
  State<TicketsView> createState() => _TicketsViewState();
}

class _TicketsViewState extends State<TicketsView> {
  bool _writing = false;
  bool _justSent = false;

  NdTicketsModel get _m => widget.model;

  @override
  void initState() {
    super.initState();
    _m.addListener(_changed);
    if (_m.state != NdTicketsState.ready) _m.load();
  }

  @override
  void dispose() {
    _m.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_m.openId != null) {
      return TicketDetailView(
        key: ValueKey('rcv-ticket-${_m.openId}'),
        model: _m,
        actions: widget.actions,
        justSent: _justSent,
        onBack: () {
          _justSent = false;
          _m.closeTicket();
        },
      );
    }
    if (_writing) {
      return TicketFormView(
        model: _m,
        actions: widget.actions,
        onCancel: () => setState(() => _writing = false),
        onSent: (id) {
          setState(() {
            _writing = false;
            _justSent = true;
          });
          if (id != null) _m.openTicket(id);
        },
      );
    }
    return _list(context);
  }

  Widget _list(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final newButton = NdButton.primary(
      key: const ValueKey('rcv-ticket-new'),
      label: tr('nd-rcv-tickets-new'),
      icon: NdIcons.add,
      onPressed: _m.state == NdTicketsState.unavailable
          ? null
          : () => setState(() => _writing = true),
    );
    Widget body;
    switch (_m.state) {
      case NdTicketsState.loading:
        body = const Padding(
            padding: EdgeInsets.only(top: 24), child: NdSpinner());
        break;
      case NdTicketsState.unavailable:
        body = Padding(
          padding: const EdgeInsets.only(top: 8),
          child: NdNotice(
              tone: NdTone.info, text: tr('nd-rcv-tickets-unavailable')),
        );
        break;
      case NdTicketsState.failed:
        body = Padding(
          padding: const EdgeInsets.only(top: 8),
          child: NdNotice(
            tone: NdTone.warning,
            text: tr('nd-rcv-tickets-failed'),
            action: NdButton(label: tr('nd-try-again'), onPressed: _m.load),
          ),
        );
        break;
      case NdTicketsState.ready:
        if (_m.tickets.isEmpty) {
          body = Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('nd-rcv-tickets-empty'),
                style: t.body.copyWith(color: c.textMuted)),
          );
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 1, color: c.rule),
              for (final ticket in _m.tickets) ...[
                _TicketRow(
                    ticket: ticket, onOpen: () => _m.openTicket(ticket.id)),
                Container(height: 1, color: c.rule),
              ],
            ],
          );
        }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 36, 40, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(tr('nd-rcv-tickets-title'),
                    style: t.titleMd.copyWith(fontSize: 26, height: 32 / 26)),
              ),
            ),
            newButton,
          ]),
          const SizedBox(height: 20),
          body,
        ],
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket, required this.onOpen});
  final NdTicket ticket;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final title = ticket.title.trim().isEmpty
        ? tr('nd-rcv-ticket-untitled')
        : ticket.title.trim();
    final line = tr('nd-rcv-ticket-line',
        [ndTicketStatus(ticket.status), _date(ticket.createdAt)]);
    return NdPressable(
      key: ValueKey('rcv-ticket-row-${ticket.id}'),
      onPressed: onOpen,
      label: ticket.unread
          ? '$title, $line, ${tr('nd-rcv-ticket-unread')}'
          : '$title, $line',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.label.copyWith(
                        fontWeight:
                            ticket.unread ? FontWeight.w700 : FontWeight.w600)),
                const SizedBox(height: 2),
                Text(line, style: t.small.copyWith(color: c.textMuted)),
              ],
            ),
          ),
          if (ticket.unread) ...[
            const SizedBox(width: 12),
            Text(tr('nd-rcv-ticket-unread'),
                key: ValueKey('rcv-ticket-unread-${ticket.id}'),
                style: t.small
                    .copyWith(color: c.accent, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(width: 8),
          Icon(NdIcons.chevronRight, size: 20, color: c.textMuted),
        ]),
      ),
    );
  }
}

/// "Something isn't working": what's wrong, a picture of the screen and
/// files.
class TicketFormView extends StatefulWidget {
  const TicketFormView({
    super.key,
    required this.model,
    required this.actions,
    required this.onCancel,
    required this.onSent,
  });

  final NdTicketsModel model;
  final NdTicketActions actions;
  final VoidCallback onCancel;

  /// The new ticket's id.
  final ValueChanged<int?> onSent;

  @override
  State<TicketFormView> createState() => _TicketFormViewState();
}

class _TicketFormViewState extends State<TicketFormView> {
  final _text = TextEditingController();
  NdTicketLocalFile? _picture;
  final _files = <NdTicketLocalFile>[];
  bool _sending = false;
  bool _taking = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? _problemText(NdTicketProblem? p) => switch (p) {
        NdTicketProblem.tooMany => tr('nd-rcv-form-too-many'),
        NdTicketProblem.tooBig => tr('nd-rcv-form-too-big'),
        NdTicketProblem.failed => tr('nd-rcv-form-failed'),
        null => null,
      };

  Future<void> _takePicture() async {
    setState(() => _taking = true);
    final picture = await widget.actions.screenshot();
    if (!mounted) return;
    setState(() {
      _taking = false;
      if (picture == null) {
        _problem = tr('nd-rcv-screenshot-failed');
        return;
      }
      final p = widget.model.check(_files, picture);
      if (p != null) {
        _problem = _problemText(p);
        return;
      }
      _problem = null;
      _picture = picture;
    });
  }

  Future<void> _addFiles() async {
    final picked = await widget.actions.pickFiles();
    if (!mounted || picked.isEmpty) return;
    final all = [..._files, ...picked];
    final p = widget.model.check(all, _picture);
    setState(() {
      _problem = _problemText(p);
      if (p == null) {
        _files
          ..clear()
          ..addAll(all);
      }
    });
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _problem = null;
    });
    final id = await widget.model
        .create(_text.text, picture: _picture, files: List.of(_files));
    if (!mounted) return;
    if (id == null) {
      setState(() {
        _sending = false;
        _problem = tr('nd-rcv-form-failed');
      });
      return;
    }
    widget.onSent(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final picture = _picture;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(tr('nd-rcv-form-title'),
                  style: t.titleMd.copyWith(fontSize: 26, height: 32 / 26)),
            ),
            const SizedBox(height: 20),
            NdField(
              key: const ValueKey('rcv-form-what'),
              label: tr('nd-rcv-form-what'),
              hint: tr('nd-rcv-form-what-hint'),
              controller: _text,
              lines: 4,
              autofocus: true,
              enabled: !_sending,
            ),
            const SizedBox(height: 20),
            if (picture == null) ...[
              NdButton(
                key: const ValueKey('rcv-form-picture'),
                label: tr('nd-rcv-form-picture'),
                icon: NdIcons.desktopWindows,
                onPressed: _sending || _taking ? null : _takePicture,
              ),
              const SizedBox(height: 6),
              Text(tr('nd-rcv-form-picture-hint'),
                  style: t.small.copyWith(color: c.textMuted)),
            ] else ...[
              Text(tr('nd-rcv-form-picture-label'), style: t.label),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Semantics(
                  image: true,
                  label: tr('nd-rcv-form-picture-label'),
                  child: Container(
                    key: const ValueKey('rcv-form-preview'),
                    constraints:
                        const BoxConstraints(maxHeight: 135, maxWidth: 240),
                    decoration: BoxDecoration(
                      border: Border.all(color: c.border),
                      borderRadius: NdSize.r,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.file(File(picture.path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => SizedBox(
                            width: 240,
                            height: 135,
                            child: Icon(NdIcons.desktopWindows,
                                size: 32, color: c.textMuted))),
                  ),
                ),
                const SizedBox(width: 12),
                NdButton(
                  key: const ValueKey('rcv-form-picture-remove'),
                  label: tr('nd-rcv-form-picture-remove'),
                  icon: NdIcons.close,
                  onPressed:
                      _sending ? null : () => setState(() => _picture = null),
                ),
              ]),
            ],
            const SizedBox(height: 20),
            NdButton(
              key: const ValueKey('rcv-form-files'),
              label: tr('nd-rcv-form-files'),
              icon: NdIcons.attachFile,
              onPressed: _sending ? null : _addFiles,
            ),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final f in _files.toList())
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(NdIcons.description, size: 18, color: c.textMuted),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('${f.name}  ${ndChatSize(f.size)}',
                          overflow: TextOverflow.ellipsis, style: t.body),
                    ),
                    const SizedBox(width: 4),
                    NdIconButton(
                      icon: NdIcons.close,
                      tooltip: tr('nd-chat-remove-file', [f.name]),
                      size: NdSize.controlSm,
                      iconSize: 18,
                      onPressed: _sending
                          ? null
                          : () => setState(() => _files.remove(f)),
                    ),
                  ]),
                ),
            ],
            const SizedBox(height: 24),
            Text(tr('nd-rcv-form-sent-with'),
                style: t.small.copyWith(color: c.textMuted)),
            if (_problem != null) ...[
              const SizedBox(height: 16),
              NdNotice(
                  key: const ValueKey('rcv-form-problem'),
                  tone: NdTone.danger,
                  text: _problem!),
            ],
            const SizedBox(height: 20),
            Row(children: [
              NdButton.primary(
                key: const ValueKey('rcv-form-send'),
                label: _sending
                    ? tr('nd-rcv-form-sending')
                    : tr('nd-rcv-form-send'),
                onPressed: _text.text.trim().isEmpty || _sending || _taking
                    ? null
                    : _send,
              ),
              const SizedBox(width: 10),
              NdButton(
                  label: translate('Cancel'),
                  onPressed: _sending ? null : widget.onCancel),
            ]),
          ],
        ),
      ),
    );
  }
}

/// One ticket: its status, what the person wrote, the support team's
/// answers and a field to answer. Opening it marks it read.
class TicketDetailView extends StatefulWidget {
  const TicketDetailView({
    super.key,
    required this.model,
    required this.actions,
    required this.onBack,
    this.justSent = false,
  });

  final NdTicketsModel model;
  final NdTicketActions actions;
  final VoidCallback onBack;

  /// The ticket was just sent: say that it arrived.
  final bool justSent;

  @override
  State<TicketDetailView> createState() => _TicketDetailViewState();
}

class _TicketDetailViewState extends State<TicketDetailView> {
  final _reply = TextEditingController();
  bool _sending = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _reply.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _notice = null;
    });
    final ok = await widget.model.reply(_reply.text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) {
        _reply.clear();
      } else {
        _notice = tr('nd-rcv-ticket-reply-failed');
      }
    });
  }

  Future<void> _save(NdTicketFile f) async {
    final where = await widget.actions.saveFile(f);
    if (!mounted) return;
    setState(() {
      if (where == null) {
        _notice = tr('nd-chat-download-failed');
      } else if (where.isNotEmpty) {
        _notice = tr('nd-chat-saved', [where]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final detail = widget.model.open;
    final back = NdIconButton(
      key: const ValueKey('rcv-ticket-back'),
      icon: NdIcons.arrowBack,
      tooltip: tr('nd-rcv-ticket-back'),
      size: NdSize.control,
      iconSize: 20,
      color: c.textMuted,
      onPressed: widget.onBack,
    );
    if (detail == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 28, 40, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            back,
            const SizedBox(height: 20),
            if (widget.model.openLoading)
              const NdSpinner()
            else
              NdNotice(tone: NdTone.warning, text: tr('nd-rcv-ticket-failed')),
          ],
        ),
      );
    }
    final ticket = detail.ticket;
    final title = ticket.title.trim().isEmpty
        ? tr('nd-rcv-ticket-untitled')
        : ticket.title.trim();
    final files = detail.files
        .where((f) => f.name != kNdTicketComputerInfo)
        .toList(growable: false);
    final entries = <Widget>[
      _Entry(
        name: tr('nd-rcv-ticket-you'),
        time: _time(ticket.createdAt),
        body: ticket.description.trim().isEmpty ? title : ticket.description,
      ),
      for (final comment in detail.comments)
        _Entry(
          key: ValueKey('rcv-comment-${comment.id}'),
          name: comment.fromStaff
              ? (comment.authorName.trim().isEmpty
                  ? translate('Support')
                  : comment.authorName.trim())
              : tr('nd-rcv-ticket-you'),
          time: _time(comment.createdAt),
          body: comment.body,
          staff: comment.fromStaff,
        ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 40, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              back,
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMd.copyWith(fontSize: 22, height: 28 / 22)),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: NdSize.control + 8, top: 4),
              child: Text(
                  tr('nd-rcv-ticket-status', [ndTicketStatus(ticket.status)]),
                  key: const ValueKey('rcv-ticket-status'),
                  style: t.body.copyWith(color: c.textMuted)),
            ),
            if (widget.justSent) ...[
              const SizedBox(height: 16),
              NdNotice(tone: NdTone.good, text: tr('nd-rcv-ticket-sent')),
            ],
            const SizedBox(height: 20),
            Container(height: 1, color: c.rule),
            for (final e in entries) ...[
              e,
              Container(height: 1, color: c.rule),
            ],
            if (files.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(tr('nd-rcv-ticket-files'), style: t.label),
              const SizedBox(height: 6),
              for (final f in files)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(NdIcons.description, size: 18, color: c.textMuted),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('${f.name}  ${ndChatSize(f.size)}',
                          overflow: TextOverflow.ellipsis, style: t.body),
                    ),
                    const SizedBox(width: 4),
                    NdIconButton(
                      icon: NdIcons.download,
                      tooltip: tr('nd-chat-download', [f.name]),
                      size: NdSize.controlSm,
                      iconSize: 18,
                      onPressed: () => _save(f),
                    ),
                  ]),
                ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 16),
              NdNotice(tone: NdTone.info, text: _notice!),
            ],
            const SizedBox(height: 24),
            NdField(
              key: const ValueKey('rcv-ticket-reply'),
              label: tr('nd-rcv-ticket-reply'),
              controller: _reply,
              lines: 3,
              enabled: !_sending,
            ),
            const SizedBox(height: 12),
            NdButton.primary(
              key: const ValueKey('rcv-ticket-send'),
              label: tr('nd-chat-send'),
              onPressed: _reply.text.trim().isEmpty || _sending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.name,
    required this.time,
    required this.body,
    this.staff = false,
  });

  final String name;
  final String time;
  final String body;
  final bool staff;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(name,
                style: t.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: staff ? c.accent : c.text)),
            const SizedBox(width: 10),
            Text(time, style: t.small.copyWith(color: c.textMuted)),
          ]),
          const SizedBox(height: 6),
          SelectableText(body, style: t.body.copyWith(height: 1.45)),
        ],
      ),
    );
  }
}
