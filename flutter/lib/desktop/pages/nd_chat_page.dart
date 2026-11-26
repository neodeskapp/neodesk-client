// The chat window: the computer's own conversation with the support staff,
// as the console's chat PROTOCOL.md (section 9) asks a computer to show it.
// It draws NdChatModel; what needs the platform (picking and saving files,
// loading pictures, opening links) comes in through NdChatPageActions, so
// the widget tests run it without the app.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/models/nd_chat_model.dart';

/// The reactions the person can give.
const kNdChatReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// The widest the header, the messages and the field get. The page itself
/// fills the window, so its rules and background reach both edges.
const kNdChatColumn = 760.0;

class NdChatPageActions {
  const NdChatPageActions({
    required this.pickFiles,
    required this.saveFile,
    required this.picture,
    required this.openLink,
  });

  /// The files the person chose; empty when they cancelled.
  final Future<List<NdChatLocalFile>> Function() pickFiles;

  /// Saves a file of a message and answers where, null when it didn't.
  final Future<String?> Function(NdChatFile file) saveFile;

  /// A picture's bytes to show, null when it can't be loaded.
  final Future<Uint8List?> Function(NdChatFile file) picture;
  final void Function(Uri uri) openLink;
}

class NdChatPage extends StatefulWidget {
  const NdChatPage({
    super.key,
    required this.model,
    required this.actions,
    required this.onClose,
    required this.windowFocused,
  });

  final NdChatModel model;
  final NdChatPageActions actions;
  final VoidCallback onClose;

  /// Whether the app's window has the focus: with the page shown, the chat
  /// is in front.
  final ValueListenable<bool> windowFocused;

  @override
  State<NdChatPage> createState() => _NdChatPageState();
}

class _NdChatPageState extends State<NdChatPage> {
  final _text = TextEditingController();
  late final FocusNode _field = FocusNode(onKeyEvent: _onFieldKey);
  final _scroll = ScrollController();
  final _files = <NdChatLocalFile>[];
  final _keys = <String, GlobalKey>{};
  NdChatMessage? _replyTo;
  NdChatMessage? _editing;
  String? _notice;
  Timer? _noticeTimer;

  NdChatModel get _m => widget.model;

  @override
  void initState() {
    super.initState();
    _m.addListener(_changed);
    widget.windowFocused.addListener(_front);
    _scroll.addListener(_scrolled);
    _front();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _field.requestFocus();
    });
  }

  @override
  void didUpdateWidget(NdChatPage old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) {
      old.model.removeListener(_changed);
      old.model.setFront(false);
      _m.addListener(_changed);
      _front();
    }
    if (old.windowFocused != widget.windowFocused) {
      old.windowFocused.removeListener(_front);
      widget.windowFocused.addListener(_front);
      _front();
    }
  }

  @override
  void dispose() {
    _m.removeListener(_changed);
    _m.setFront(false);
    widget.windowFocused.removeListener(_front);
    _noticeTimer?.cancel();
    _text.dispose();
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _front() => _m.setFront(widget.windowFocused.value);

  void _scrolled() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    _m.setAtNewest(p.pixels <= 48);
    if (p.pixels >= p.maxScrollExtent - 120) _m.loadOlder();
  }

  void _say(String text) {
    _noticeTimer?.cancel();
    setState(() => _notice = text);
    _noticeTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      if (_text.value.composing.isValid) return KeyEventResult.ignored;
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _escape() {
    if (_editing != null || _replyTo != null) {
      setState(() {
        if (_editing != null) _text.clear();
        _editing = null;
        _replyTo = null;
      });
      return;
    }
    widget.onClose();
  }

  bool get _canSend =>
      _m.connected &&
      (_text.text.trim().isNotEmpty || (_files.isNotEmpty && _editing == null));

  void _submit() {
    if (!_canSend) return;
    final editing = _editing;
    if (editing != null) {
      _m.edit(editing.id, _text.text);
    } else {
      _m.sendMessage(_text.text,
          replyTo: _replyTo?.id,
          paths: _files.map((f) => f.path).toList());
    }
    setState(() {
      _text.clear();
      _files.clear();
      _replyTo = null;
      _editing = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _attach() async {
    final picked = await widget.actions.pickFiles();
    if (!mounted || picked.isEmpty) return;
    final all = [..._files, ...picked];
    switch (_m.checkFiles(all)) {
      case NdChatFileProblem.tooMany:
        _say(tr('nd-chat-too-many'));
        return;
      case NdChatFileProblem.tooBig:
        _say(tr('nd-chat-too-big'));
        return;
      default:
        setState(() => _files
          ..clear()
          ..addAll(all));
    }
    _field.requestFocus();
  }

  void _reply(NdChatMessage m) {
    setState(() {
      if (_editing != null) _text.clear();
      _editing = null;
      _replyTo = m;
    });
    _field.requestFocus();
  }

  void _edit(NdChatMessage m) {
    setState(() {
      _replyTo = null;
      _editing = m;
      _text.text = m.text;
      _text.selection = TextSelection.collapsed(offset: m.text.length);
    });
    _field.requestFocus();
  }

  Future<void> _delete(NdChatMessage m) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => Center(
          child: NdDialog(
        title: tr('nd-chat-delete-question'),
        width: 360,
        closeTooltip: translate('Close'),
        onClose: () => Navigator.of(context).pop(false),
        children: [Text(tr('nd-chat-delete-text'), style: context.ndText.body)],
        actions: [
          NdButton(
              label: translate('Cancel'),
              onPressed: () => Navigator.of(context).pop(false)),
          NdButton(
              label: tr('nd-chat-delete'),
              kind: NdButtonKind.danger,
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(true)),
        ],
      )),
    );
    if (yes == true) _m.delete(m.id);
  }

  Future<void> _save(NdChatFile f) async {
    final where = await widget.actions.saveFile(f);
    if (!mounted) return;
    if (where == null) {
      _say(tr('nd-chat-download-failed'));
    } else if (where.isNotEmpty) {
      _say(tr('nd-chat-saved', [where]));
    }
  }

  /// The options of [m]: the reactions, then Reply, Edit and Delete.
  List<Widget> _options(NdChatMessage m, MenuController menu) => [
        _ReactionsRow(onReact: (e) {
          menu.close();
          _m.react(m.id, e);
        }),
        const NdMenuDivider(),
        NdMenuItem(label: tr('nd-chat-reply'), onPressed: () => _reply(m)),
        if (_m.canEdit(m))
          NdMenuItem(label: tr('nd-chat-edit'), onPressed: () => _edit(m)),
        if (_m.canDelete(m))
          NdMenuItem(
              label: tr('nd-chat-delete'),
              danger: true,
              onPressed: () => _delete(m)),
      ];

  void _goTo(String id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.5, duration: const Duration(milliseconds: 200));
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: FocusScope(
        child: ColoredBox(
          color: c.bg,
          child: LayoutBuilder(builder: (context, box) {
            // What the column leaves free on each side of a wide window.
            final side = box.maxWidth > kNdChatColumn
                ? (box.maxWidth - kNdChatColumn) / 2
                : 0.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, side),
                Container(height: 1, color: c.rule),
                Expanded(child: _list(context, side)),
                if (_m.availability == NdChatAvailability.refused)
                  Padding(
                    padding: EdgeInsets.fromLTRB(12 + side, 12, 12 + side, 12),
                    child: NdNotice(
                        tone: NdTone.danger,
                        text: tr('nd-chat-not-available')),
                  )
                else
                  _composer(context, side),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, double side) {
    final c = context.nd;
    final t = context.ndText;
    String status;
    if (_m.typingName != null) {
      // In the header, where it takes no room from the messages.
      status = tr('nd-chat-typing', [_m.typingName]);
    } else if (_m.helperClosed) {
      status = tr('nd-chat-closed');
    } else if (_m.helperName != null) {
      status = tr('nd-chat-helping', [_m.helperName]);
    } else if (_m.helperKnown) {
      status = tr('nd-chat-waiting');
    } else {
      status = '';
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(8 + side, 10, 16 + side, 10),
      child: Row(children: [
        _IconAction(
          icon: NdIcons.arrowBack,
          label: tr('nd-chat-close'),
          onPressed: widget.onClose,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('nd-chat-title'),
                  style: t.heading, overflow: TextOverflow.ellipsis),
              if (status.isNotEmpty)
                Text(status,
                    key: ValueKey(_m.typingName != null
                        ? 'nd-chat-typing'
                        : 'nd-chat-helper'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small.copyWith(color: c.textMuted)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _list(BuildContext context, double side) {
    final c = context.nd;
    final t = context.ndText;
    final items = _items();
    final top = <Widget>[
      if (!_m.connected && _m.availability != NdChatAvailability.refused)
        Padding(
          padding: EdgeInsets.fromLTRB(12 + side, 10, 12 + side, 0),
          child: NdNotice(
              key: const ValueKey('nd-chat-offline'),
              tone: NdTone.warning,
              text: tr('nd-chat-not-connected')),
        ),
      if (_notice != null)
        Padding(
          padding: EdgeInsets.fromLTRB(12 + side, 10, 12 + side, 0),
          child: NdNotice(tone: NdTone.info, text: _notice!),
        ),
    ];
    Widget body;
    if (items.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('nd-chat-empty'),
              textAlign: TextAlign.center,
              style: t.body.copyWith(color: c.textMuted)),
        ),
      );
    } else {
      body = SelectionArea(
        child: ListView.builder(
          controller: _scroll,
          reverse: true,
          // As wide as the window, so the wheel scrolls it anywhere and the
          // scroll bar sits at the window's edge.
          padding: EdgeInsets.fromLTRB(12 + side, 8, 12 + side, 8),
          itemCount: items.length,
          itemBuilder: (context, i) => items[items.length - 1 - i],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...top, Expanded(child: body)],
    );
  }

  /// The rows of the list, oldest first.
  List<Widget> _items() {
    final out = <Widget>[];
    final msgs = _m.messages;
    if (msgs.isEmpty && _m.pending.isEmpty) return out;
    if (_m.olderExist) {
      out.add(Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: NdButton.link(
              label: tr('nd-chat-older'), onPressed: _m.loadOlder),
        ),
      ));
    }
    final seen = _m.seenId;
    DateTime? day;
    for (final m in msgs) {
      final at = _m.localTime(m.createdAt);
      final d = DateTime(at.year, at.month, at.day);
      if (day == null || d != day) {
        day = d;
        out.add(_DayLine(label: _dayLabel(d)));
      }
      out.add(KeyedSubtree(
        key: _keys.putIfAbsent(m.id, () => GlobalKey()),
        child: _MessageRow(
          message: m,
          own: _m.isOwn(m),
          time: _time(at),
          seen: seen == m.id,
          model: _m,
          actions: widget.actions,
          options: (menu) => _options(m, menu),
          onQuote: _goTo,
          onSave: _save,
        ),
      ));
    }
    for (final p in _m.pending) {
      out.add(_PendingRow(
        pending: p,
        onRetry: () => _m.retry(p.clientId),
      ));
    }
    return out;
  }

  String _dayLabel(DateTime d) {
    final now = _m.localNow.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return tr('nd-chat-today');
    if (d == today.subtract(const Duration(days: 1))) {
      return tr('nd-chat-yesterday');
    }
    return ndChatDate(d, tr('nd-chat-date-format'));
  }

  String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  Widget _composer(BuildContext context, double side) {
    final c = context.nd;
    final reply = _replyTo;
    final editing = _editing;
    return Container(
      key: const ValueKey('nd-chat-composer'),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.rule))),
      padding: EdgeInsets.fromLTRB(8 + side, 10, 8 + side, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reply != null || editing != null)
            _ComposeContext(
              icon: editing != null ? NdIcons.edit : NdIcons.reply,
              title: editing != null
                  ? tr('nd-chat-editing')
                  : tr('nd-chat-replying-to', [reply!.from.name]),
              text: editing != null
                  ? ''
                  : reply!.deleted
                      ? tr('nd-chat-deleted')
                      : reply.text.isNotEmpty
                          ? reply.text
                          : reply.files.isNotEmpty
                              ? reply.files.first.name
                              : '',
              stopLabel: editing != null
                  ? tr('nd-chat-stop-edit')
                  : tr('nd-chat-stop-reply'),
              onStop: _escape,
            ),
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in _files.toList())
                  _FileChip(
                    name: _baseName(f.path),
                    size: f.size,
                    onRemove: () => setState(() => _files.remove(f)),
                  ),
              ]),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _IconAction(
                icon: NdIcons.attachFile,
                label: tr('nd-chat-attach'),
                onPressed: _m.connected && editing == null ? _attach : null,
              ),
              const SizedBox(width: 4),
              Expanded(child: _messageField(context)),
              const SizedBox(width: 4),
              _IconAction(
                icon: NdIcons.send,
                label: tr('nd-chat-send'),
                color: _canSend ? c.accent : null,
                onPressed: _canSend ? _submit : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _messageField(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Container(
      constraints: const BoxConstraints(minHeight: NdSize.control),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: NdSize.r,
        border: Border.all(color: _field.hasFocus ? c.accent : c.border),
      ),
      child: Semantics(
        label: tr('nd-chat-field-label'),
        textField: true,
        child: TextField(
          controller: _text,
          focusNode: _field,
          minLines: 1,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: t.body,
          cursorColor: c.text,
          cursorWidth: 1,
          onChanged: (_) {
            if (_editing == null) _m.typed();
            setState(() {});
          },
          decoration: InputDecoration(
            isCollapsed: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            filled: false,
            hintText: tr('nd-chat-field'),
            hintStyle: t.body.copyWith(color: c.textMuted),
          ),
        ),
      ),
    );
  }
}

String _baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? path : parts.last;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// [d] in [pattern]: d, M, MMM and yyyy are replaced.
String ndChatDate(DateTime d, String pattern) {
  final p = pattern.isEmpty || pattern == 'nd-chat-date-format'
      ? 'd MMM yyyy'
      : pattern;
  return p
      .replaceAll('yyyy', '${d.year}')
      .replaceAll('MMM', '\u0000')
      .replaceAll('M', '${d.month}')
      .replaceAll('d', '${d.day}')
      .replaceAll('\u0000', _months[d.month - 1]);
}

/// A file size as people read it: 512 B, 48 KB, 3.2 MB.
String ndChatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
}

/// The text of a message with its http and https addresses as links.
List<InlineSpan> ndChatTextSpans(
    String text, TextStyle link, void Function(Uri) open) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);
  var at = 0;
  for (final m in re.allMatches(text)) {
    var url = m.group(0)!;
    // Punctuation after an address belongs to the sentence.
    final trail = RegExp(r'[.,;:!?)\]]+$').firstMatch(url);
    var end = m.end;
    if (trail != null) {
      url = url.substring(0, trail.start);
      end -= trail.end - trail.start;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) continue;
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    spans.add(TextSpan(
      text: url,
      style: link,
      recognizer: TapGestureRecognizer()..onTap = () => open(uri),
      mouseCursor: SystemMouseCursors.click,
    ));
    at = end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// An icon button with its label for screen readers and as tooltip.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: NdIconButton(
          icon: icon,
          tooltip: label,
          size: NdSize.control,
          iconSize: 20,
          color: color ?? c.textMuted,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// The width of a message's options menu: the six reactions and their
/// padding.
const _kOptionsWidth = 216.0;
const _kOptionsButton = 28.0;

/// The ⋮ button of a message and its options menu, the app's menu with no
/// opening animation, just below the button. With [alignEnd] (own messages,
/// whose button is left of the bubble) the menu ends where the button ends,
/// so it opens beside the message instead of over it.
class _OptionsButton extends StatefulWidget {
  const _OptionsButton({required this.options, required this.alignEnd});
  final List<Widget> Function(MenuController menu) options;
  final bool alignEnd;

  @override
  State<_OptionsButton> createState() => _OptionsButtonState();
}

class _OptionsButtonState extends State<_OptionsButton> {
  // Kept across rebuilds: the page rebuilds whenever the chat changes, and
  // an open menu has to stay attached to its controller.
  final _menu = MenuController();

  void _toggle() => _menu.isOpen ? _menu.close() : _menu.open();

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      style: ndMenuStyle(context, minWidth: _kOptionsWidth).copyWith(
          maximumSize: const WidgetStatePropertyAll(
              Size(_kOptionsWidth, double.infinity))),
      alignmentOffset: Offset(
          widget.alignEnd ? _kOptionsButton - _kOptionsWidth : 0, 4),
      menuChildren: widget.options(_menu),
      builder: (context, _, __) => Semantics(
        container: true,
        button: true,
        label: tr('nd-chat-options'),
        onTap: _toggle,
        excludeSemantics: true,
        child: NdIconButton(
          icon: NdIcons.moreVert,
          tooltip: tr('nd-chat-options'),
          size: _kOptionsButton,
          iconSize: 18,
          onPressed: _toggle,
        ),
      ),
    );
  }
}

/// The row of reactions at the top of a message's options.
class _ReactionsRow extends StatelessWidget {
  const _ReactionsRow({required this.onReact});
  final void Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final e in kNdChatReactions)
          Semantics(
            container: true,
            button: true,
            label: '${tr('nd-chat-react')} $e',
            onTap: () => onReact(e),
            excludeSemantics: true,
            child: InkWell(
              borderRadius: NdSize.r,
              hoverColor: c.hover,
              focusColor: c.hover,
              splashFactory: NoSplash.splashFactory,
              onTap: () => onReact(e),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 18))),
              ),
            ),
          ),
      ]),
    );
  }
}

class _DayLine extends StatelessWidget {
  const _DayLine({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(child: Container(height: 1, color: c.rule)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label, style: t.small.copyWith(color: c.textMuted)),
        ),
        Expanded(child: Container(height: 1, color: c.rule)),
      ]),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.own,
    required this.time,
    required this.seen,
    required this.model,
    required this.actions,
    required this.options,
    required this.onQuote,
    required this.onSave,
  });

  final NdChatMessage message;
  final bool own;
  final String time;
  final bool seen;
  final NdChatModel model;
  final NdChatPageActions actions;
  final List<Widget> Function(MenuController menu) options;
  final void Function(String id) onQuote;
  final void Function(NdChatFile file) onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final m = message;
    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!own) ...[
          Flexible(
            child: Text(m.from.name,
                overflow: TextOverflow.ellipsis,
                style: t.small.copyWith(color: c.text, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
        Text(time, style: t.small.copyWith(color: c.textMuted)),
        if (m.edited && !m.deleted) ...[
          const SizedBox(width: 6),
          Text(tr('nd-chat-edited'), style: t.small.copyWith(color: c.textMuted)),
        ],
      ],
    );
    final content = <Widget>[];
    final reply = m.replyTo;
    if (reply != null && !m.deleted) {
      content.add(_Quote(reply: reply, onTap: () => onQuote(reply.id)));
    }
    if (m.deleted) {
      content.add(Text(tr('nd-chat-deleted'),
          style: t.body.copyWith(color: c.textMuted, fontStyle: FontStyle.italic)));
    } else if (m.text.isNotEmpty) {
      content.add(Text.rich(
        TextSpan(
          style: t.body,
          children: ndChatTextSpans(
              m.text,
              t.body.copyWith(
                  color: c.accent, decoration: TextDecoration.underline),
              actions.openLink),
        ),
      ));
    }
    for (final f in m.files) {
      content.add(Padding(
        padding: EdgeInsets.only(top: content.isEmpty ? 0 : 6),
        child: f.isPicture
            ? _Picture(file: f, actions: actions)
            : _FileRow(file: f, onSave: () => onSave(f)),
      ));
    }
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: own ? c.accentTint : c.bgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: own ? null : Border.all(color: c.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: content,
      ),
    );
    final optionsButton = m.deleted
        ? const SizedBox(width: 30)
        : _OptionsButton(options: options, alignEnd: own);
    final reactions = m.reactions.entries.where((e) => e.value.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 3, left: 2, right: 2),
            child: meta,
          ),
          Row(
            mainAxisAlignment:
                own ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (own) optionsButton,
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: bubble,
                ),
              ),
              if (!own) optionsButton,
            ],
          ),
          if (reactions.isNotEmpty && !m.deleted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (final e in reactions)
                  _ReactionChip(
                    emoji: e.key,
                    count: e.value.length,
                    names: e.value.map((p) => p.name).join(', '),
                    mine: model.reactedByMe(m, e.key),
                    onTap: () => model.react(m.id, e.key),
                  ),
              ]),
            ),
          if (seen)
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 2),
              child: Text(tr('nd-chat-seen'),
                  key: const ValueKey('nd-chat-seen'),
                  style: t.small.copyWith(color: c.textMuted)),
            ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.reply, required this.onTap});
  final NdChatReply reply;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            decoration: BoxDecoration(
              color: c.bg.withOpacity(0.6),
              border: Border(left: BorderSide(color: c.accent, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(reply.fromName,
                    style: t.small
                        .copyWith(color: c.text, fontWeight: FontWeight.w600)),
                Text(
                  reply.deleted ? tr('nd-chat-deleted') : reply.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.small.copyWith(
                      color: c.textMuted,
                      fontStyle:
                          reply.deleted ? FontStyle.italic : FontStyle.normal),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Picture extends StatefulWidget {
  const _Picture({required this.file, required this.actions});
  final NdChatFile file;
  final NdChatPageActions actions;

  @override
  State<_Picture> createState() => _PictureState();
}

class _PictureState extends State<_Picture> {
  late final Future<Uint8List?> _bytes = widget.actions.picture(widget.file);

  Size get _size {
    final w = (widget.file.width ?? 1).toDouble();
    final h = (widget.file.height ?? 1).toDouble();
    final scale = [240 / w, 180 / h, 1.0].reduce((a, b) => a < b ? a : b);
    return Size((w * scale).clamp(48, 240), (h * scale).clamp(48, 180));
  }

  void _open(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: context.nd.bgFloat,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(children: [
          InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
          Positioned(
            right: 4,
            top: 4,
            child: _IconAction(
              icon: NdIcons.close,
              label: translate('Close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final size = _size;
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) {
        final bytes = snap.data;
        Widget child = bytes == null
            ? Center(
                child: snap.connectionState == ConnectionState.done
                    ? Icon(NdIcons.imageSearch, color: c.textMuted)
                    : const NdSpinner())
            : Image.memory(bytes, fit: BoxFit.cover);
        child = ClipRRect(
          borderRadius: NdSize.r,
          child: Container(
              width: size.width,
              height: size.height,
              color: c.bg,
              child: child),
        );
        return Semantics(
          container: true,
          button: true,
          image: true,
          label: tr('nd-chat-open-picture', [widget.file.name]),
          onTap: bytes == null ? null : () => _open(bytes),
          excludeSemantics: true,
          child: MouseRegion(
            cursor: bytes == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: bytes == null ? null : () => _open(bytes),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onSave});
  final NdChatFile file;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: NdSize.r,
        border: Border.all(color: c.rule),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(NdIcons.description, size: 18, color: c.textMuted),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(file.name,
                  overflow: TextOverflow.ellipsis, style: t.body),
              Text(ndChatSize(file.size),
                  style: t.small.copyWith(color: c.textMuted)),
            ],
          ),
        ),
        const SizedBox(width: 4),
        _IconAction(
          icon: NdIcons.download,
          label: tr('nd-chat-download', [file.name]),
          onPressed: onSave,
        ),
      ]),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.names,
    required this.mine,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final String names;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Semantics(
      container: true,
      button: true,
      selected: mine,
      label: tr('nd-chat-reaction', [emoji, names]),
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: names,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: mine ? c.accentTint : c.bgSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: mine ? c.accent : c.rule),
            ),
            child: Text('$emoji $count', style: t.small.copyWith(color: c.text)),
          ),
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.pending, required this.onRetry});
  final NdChatPending pending;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final p = pending;
    final failed = p.state == NdChatSendState.failed;
    final problem = switch (p.problem) {
      NdChatFileProblem.storageFull => tr('nd-chat-storage-full'),
      NdChatFileProblem.serverStarting => tr('nd-chat-server-starting'),
      NdChatFileProblem.uploadFailed => tr('nd-chat-upload-failed'),
      NdChatFileProblem.tooBig => tr('nd-chat-too-big'),
      NdChatFileProblem.tooMany => tr('nd-chat-too-many'),
      null => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Opacity(
                    opacity: failed ? 1 : 0.7,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.accentTint,
                        borderRadius: BorderRadius.circular(8),
                        border: failed ? Border.all(color: c.danger) : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (p.text.isNotEmpty) Text(p.text, style: t.body),
                          for (final path in p.paths)
                            Text(_baseName(path),
                                style: t.small.copyWith(color: c.textMuted)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (failed) ...[
            if (problem != null)
              Text(problem, style: t.small.copyWith(color: c.danger)),
            NdButton.link(
                key: ValueKey('nd-chat-retry-${p.clientId}'),
                label: tr('nd-chat-not-sent'),
                onPressed: onRetry),
          ] else
            Text(tr('nd-chat-sending'),
                style: t.small.copyWith(color: c.textMuted)),
        ],
      ),
    );
  }
}

class _ComposeContext extends StatelessWidget {
  const _ComposeContext({
    required this.icon,
    required this.title,
    required this.text,
    required this.stopLabel,
    required this.onStop,
  });

  final IconData icon;
  final String title;
  final String text;
  final String stopLabel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
      decoration: BoxDecoration(
        color: c.bgSubtle,
        borderRadius: NdSize.r,
        border: Border(left: BorderSide(color: c.accent, width: 3)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: c.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: t.small
                      .copyWith(color: c.text, fontWeight: FontWeight.w600)),
              if (text.isNotEmpty)
                Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small.copyWith(color: c.textMuted)),
            ],
          ),
        ),
        _IconAction(icon: NdIcons.close, label: stopLabel, onPressed: onStop),
      ]),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip(
      {required this.name, required this.size, required this.onRemove});
  final String name;
  final int size;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: c.bgSubtle,
        borderRadius: NdSize.r,
        border: Border.all(color: c.rule),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text('$name (${ndChatSize(size)})',
              overflow: TextOverflow.ellipsis, style: t.small),
        ),
        _IconAction(
            icon: NdIcons.close,
            label: tr('nd-chat-remove-file', [name]),
            onPressed: onRemove),
      ]),
    );
  }
}

/// The Home entry: "Chat with support" with the count of new messages.
class NdChatEntry extends StatelessWidget {
  const NdChatEntry({super.key, required this.model, required this.onOpen});
  final NdChatModel model;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        if (!model.showEntry) return const SizedBox.shrink();
        final c = context.nd;
        final t = context.ndText;
        final unread = model.unread;
        final entry = Semantics(
          container: true,
          button: true,
          label: unread > 0
              ? '${tr('nd-chat-open')}, ${tr('nd-chat-new-label', [unread])}'
              : tr('nd-chat-open'),
          onTap: onOpen,
          excludeSemantics: true,
          child: NdButton(
            label: tr('nd-chat-open'),
            icon: NdIcons.chat,
            block: true,
            onPressed: onOpen,
            trailingIcon: null,
            tooltip: null,
          ).withBadge(unread > 0
              ? Container(
                  key: const ValueKey('nd-chat-unread'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(tr('nd-chat-new', [unread]),
                      style: t.small.copyWith(
                          color: c.onAccent, fontWeight: FontWeight.w600)),
                )
              : null),
        );
        return Padding(padding: const EdgeInsets.only(top: 16), child: entry);
      },
    );
  }
}

extension on NdButton {
  /// The button with [badge] at its end, inside its frame.
  Widget withBadge(Widget? badge) {
    if (badge == null) return this;
    return Stack(alignment: Alignment.centerRight, children: [
      this,
      Padding(
        padding: const EdgeInsets.only(right: 10),
        child: IgnorePointer(child: badge),
      ),
    ]);
  }
}
