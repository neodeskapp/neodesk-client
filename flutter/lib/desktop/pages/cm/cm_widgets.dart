// The connection manager's parts (DESIGN.md, Connection manager) as
// widgets without app state, shared by the app and the screenshot tests.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/onboarding/joining_view.dart' show formatNdId;

/// The connection manager's title: in quick support the name the quick
/// support window has, in the language of the app (L554).
String cmWindowTitle(String appName, {required bool quickSupport}) =>
    quickSupport ? tr('nd-qs-window-title') : appName;

/// Whether [peerId] is a NeoDesk ID (digits). The console's web viewer
/// names itself with an id of its own, which means nothing to the person.
bool cmPeerIsDevice(String peerId) =>
    RegExp(r'^\d+$').hasMatch(peerId.replaceAll(' ', ''));

/// Whether a request gets Allow: what the approve mode says, and in quick
/// support (password only) a caller the server vouched for (A271).
bool cmOffersAllow(String approveMode, {required bool vouched}) =>
    approveMode != 'password' || vouched;

/// Who asks to connect, as the connection manager shows it (A271).
class CmCaller {
  const CmCaller(
      {required this.name,
      required this.line,
      this.lineIsId = false,
      this.unknown = false,
      this.warning});

  /// The name in the header and the title.
  final String name;

  /// The line under the name.
  final String line;

  /// [line] is a NeoDesk ID, set in the mono font.
  final bool lineIsId;

  /// The window does not name the caller: nothing of theirs is shown.
  final bool unknown;

  /// Shown above the switches when the caller is not confirmed.
  final String? warning;
}

/// What the window says about a caller. A caller the server vouched for
/// (A271) has the helper's name the server gave and "From the NeoDesk web
/// console", or "From the NeoDesk app" for a signed-in app the server
/// vouched for on the receiver (A279, [vouchedVia] 'desktop'). Any other caller's ID and name are its own claim: in quick
/// support, and for a caller without a NeoDesk ID, the window calls it
/// unknown; elsewhere a desktop caller keeps its name and ID as before.
/// Unconfirmed, the window warns before Allow, and in quick support says
/// that only the password lets someone in.
CmCaller cmCaller(
    {required String name,
    required String peerId,
    required bool vouched,
    required bool quickSupport,
    required bool offersAllow,
    String vouchedVia = ''}) {
  if (vouched && name.trim().isNotEmpty) {
    return CmCaller(
        name: name,
        line: tr(vouchedVia == 'desktop'
            ? 'nd-cm-from-app'
            : 'nd-cm-from-console'));
  }
  final warning = offersAllow
      ? tr('nd-cm-unknown-warning')
      : quickSupport
          ? tr('nd-cm-password-only')
          : null;
  if (!quickSupport && cmPeerIsDevice(peerId)) {
    return CmCaller(
        name: name.isNotEmpty ? name : peerId,
        line: formatNdId(peerId),
        lineIsId: true,
        warning: warning);
  }
  return CmCaller(
      name: tr('nd-cm-unknown-caller'),
      line: tr('nd-cm-not-confirmed'),
      unknown: true,
      warning: warning);
}

/// The line that says the server confirmed who is connected (A271, A279),
/// shown under the time once the session runs; null for a caller nobody
/// confirmed.
String? cmConfirmedLine(CmCaller caller, {required bool vouched}) =>
    vouched && !caller.unknown && !caller.lineIsId ? caller.line : null;

/// The window of a request or a session: the body takes the room left, the
/// buttons stay at the foot whatever the body holds.
class CmScreen extends StatelessWidget {
  const CmScreen({super.key, required this.body, required this.foot});

  final Widget body;
  final Widget foot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.nd.rule))),
          child: foot,
        ),
      ],
    );
  }
}

class CmPermission {
  const CmPermission({
    required this.label,
    required this.value,
    required this.onChanged,
    this.reason,
  });

  final String label;
  final bool value;

  /// Null when the person may not change it here.
  final ValueChanged<bool>? onChanged;

  /// Why it cannot be changed ("Turned off in Settings").
  final String? reason;
}

/// Avatar, name and the line under it (the ID while asking, the time once
/// connected).
class CmHeader extends StatelessWidget {
  const CmHeader({
    super.key,
    required this.name,
    required this.subtitle,
    this.mono = false,
    this.avatar,
    this.kind,
    this.note,
  });

  final String name;
  final String subtitle;
  final bool mono;
  final Widget? avatar;

  /// A line under the subtitle, such as who confirmed the caller.
  final String? note;

  /// Transfer file, Terminal, View camera, port forward.
  final String? kind;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    return Row(children: [
      SizedBox(
          width: 48,
          height: 48,
          child: avatar ?? NdAvatar(name: name, size: 48)),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.heading.copyWith(fontSize: 16)),
            const SizedBox(height: 2),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono
                    ? t.mono.copyWith(fontSize: 13, color: context.nd.textMuted)
                    : t.body.copyWith(color: context.nd.textMuted)),
            if (note != null && note!.isNotEmpty)
              Text(note!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.small.copyWith(color: context.nd.textMuted)),
            if (kind != null && kind!.isNotEmpty)
              Text(kind!, style: t.small),
          ],
        ),
      ),
    ]);
  }
}

/// The switches of what the person may do, 38 px rows with rules.
class CmPermissionList extends StatelessWidget {
  const CmPermissionList({super.key, required this.items, this.heading});
  final List<CmPermission> items;
  final String? heading;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading != null) ...[
          Text(heading!,
              style: t.label.copyWith(
                  fontWeight: FontWeight.w600, color: c.textMuted)),
          const SizedBox(height: 6),
        ],
        for (var i = 0; i < items.length; i++)
          Tooltip(
            message: items[i].onChanged == null ? (items[i].reason ?? '') : '',
            child: Container(
              constraints: const BoxConstraints(minHeight: 38),
              decoration: BoxDecoration(
                border: i == items.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.rule)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(items[i].label,
                          style: t.body.copyWith(fontSize: 15, height: 22 / 15)),
                      if (items[i].onChanged == null &&
                          (items[i].reason ?? '').isNotEmpty)
                        Text(items[i].reason!, style: t.small),
                    ],
                  ),
                ),
                NdSwitch(
                  value: items[i].value,
                  onChanged: items[i].onChanged,
                  semanticLabel: items[i].label,
                ),
              ]),
            ),
          ),
      ],
    );
  }
}

/// The body of a request: header, title, note, a warning about a caller
/// nobody confirmed, and the switches.
///
/// When the request arrives, the screen reader says who wants to connect.
/// With [focusOnArrival] the title also takes keyboard focus, so Tab goes on
/// to the switches and the buttons. The title is not a button: Enter there
/// does nothing, so typing that was meant for another window cannot allow a
/// connection.
///
/// The title draws its focus ring only when the user moved focus there, or
/// when the system asks for visible focus (a screen reader or high contrast
/// is on). Focus given on arrival alone shows no ring.
class CmRequestBody extends StatefulWidget {
  const CmRequestBody({
    super.key,
    required this.header,
    required this.name,
    required this.permissions,
    this.warning,
    this.focusOnArrival = false,
  });

  final Widget header;
  final String name;
  final List<CmPermission> permissions;
  final String? warning;
  final bool focusOnArrival;

  @override
  State<CmRequestBody> createState() => _CmRequestBodyState();
}

class _CmRequestBodyState extends State<CmRequestBody> {
  final _titleFocus = FocusNode(debugLabel: 'connection request');
  bool _focused = false;

  /// True while the title holds the focus it was given on arrival.
  bool _arrivalFocus = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.focusOnArrival) {
        _arrivalFocus = true;
        _titleFocus.requestFocus();
      }
      ndAnnounce(context, tr('nd-cm-request-title', [widget.name]),
          assertive: true);
    });
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    final name = widget.name;
    final title = Text(tr('nd-cm-request-title', [name]), style: t.titleMd);
    final systemWantsRing = (MediaQuery.maybeAccessibleNavigationOf(context) ??
            false) ||
        (MediaQuery.maybeHighContrastOf(context) ?? false);
    final showRing = _focused && (!_arrivalFocus || systemWantsRing);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header,
        const SizedBox(height: 16),
        Focus(
          focusNode: _titleFocus,
          onFocusChange: (f) => setState(() {
            _focused = f;
            if (!f) _arrivalFocus = false;
          }),
          child: Semantics(
            header: true,
            child: showRing ? NdFocusRing(child: title) : title,
          ),
        ),
        const SizedBox(height: 6),
        Text(tr('nd-cm-request-note'), style: t.small),
        if ((widget.warning ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          NdNotice(text: widget.warning!, tone: NdTone.warning),
        ],
        if (widget.permissions.isNotEmpty) ...[
          const SizedBox(height: 14),
          CmPermissionList(
              heading: tr('nd-cm-may', [name]), items: widget.permissions),
        ],
      ],
    );
  }
}

/// The foot of a request: Decline, Allow, and Allow with administrator
/// rights when that is possible.
class CmRequestActions extends StatelessWidget {
  const CmRequestActions({
    super.key,
    required this.onDecline,
    this.onAllow,
    this.onAllowElevated,
  });

  final VoidCallback onDecline;

  /// Null when only the password lets someone in.
  final VoidCallback? onAllow;
  final VoidCallback? onAllowElevated;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: NdButton(
              label: translate('Decline'),
              size: NdButtonSize.lg,
              block: true,
              onPressed: onDecline),
        ),
        if (onAllow != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: NdButton.primary(
                label: tr('nd-allow'),
                size: NdButtonSize.lg,
                block: true,
                onPressed: onAllow),
          ),
        ],
      ]),
      if (onAllowElevated != null) ...[
        const SizedBox(height: 12),
        NdButton.link(
            label: tr('nd-cm-allow-elevated'), onPressed: onAllowElevated),
      ],
    ]);
  }
}

/// Access, Chat and Files under the header once connected.
enum CmTab { access, chat, files }

class CmTabs extends StatelessWidget {
  const CmTabs({super.key, required this.value, required this.onChanged,
      this.showAccess = true, this.showFiles = true, this.unread = 0});
  final CmTab value;
  final ValueChanged<CmTab> onChanged;

  /// A file transfer has no switches: no Access tab.
  final bool showAccess;
  final bool showFiles;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return NdTabs<CmTab>(
      gap: 24,
      tabs: [
        if (showAccess) NdTab(CmTab.access, tr('nd-cm-tab-access')),
        NdTab(CmTab.chat,
            unread > 0 ? '${translate('Chat')} ($unread)' : translate('Chat')),
        if (showFiles) NdTab(CmTab.files, tr('nd-cm-tab-files')),
      ],
      value: value,
      onChanged: onChanged,
    );
  }
}

/// The tab a card shows for the one chosen: a file transfer has no Access
/// tab and opens on Files, a camera has no Files tab.
CmTab cmShownTab(CmTab chosen, {bool file = false, bool camera = false}) {
  if (file && chosen == CmTab.access) return CmTab.files;
  if (camera && chosen == CmTab.files) return CmTab.access;
  return chosen;
}

/// The room under the tabs: the switches, the chat or the files. Each tab
/// has the whole room, so the window keeps its size when the tab changes.
class CmTabBody extends StatelessWidget {
  const CmTabBody({
    super.key,
    required this.tab,
    required this.access,
    required this.chat,
    required this.files,
  });

  final CmTab tab;
  final List<CmPermission> access;
  final WidgetBuilder chat;
  final WidgetBuilder files;

  @override
  Widget build(BuildContext context) => switch (tab) {
        // The list scrolls at full width, so its scrollbar runs along the
        // window's edge and not over the switches.
        CmTab.access => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: CmPermissionList(items: access),
          ),
        CmTab.chat => chat(context),
        CmTab.files => files(context),
      };
}

/// "Connected for 12 minutes" or "Connected for 1 h 20 min".
String cmConnectedFor(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 60) {
    return tr('nd-cm-connected-min', [minutes < 1 ? 1 : minutes]);
  }
  return tr('nd-cm-connected-h', [d.inHours, minutes % 60]);
}

/// What the connection window shows: the card (requests, the switches, the
/// tabs of several people), the bar at the top of the screen during a
/// session, or the bar with the chat or the files open under it.
enum CmShape { card, bar, barPanel }

/// The window around the bar: wide enough for the bar and its shadow, and
/// taller with a panel open under it.
const kCmBarWindow = Size(760, 64);
const kCmBarWindowPanel = Size(760, 64 + 8 + 400);

/// The connection window during a session: the [bar] while [barAllowed]
/// (someone was let in and nobody waits for Allow), the [card] once the
/// person expands the bar, and the bar again when they collapse the card.
/// A session that is let in starts as the bar. The card stays built while
/// the bar shows, so its timers and state carry on, but it takes no focus.
class CmBarOrCard extends StatefulWidget {
  const CmBarOrCard({
    super.key,
    required this.barAllowed,
    required this.bar,
    required this.card,
    this.panelOpen = false,
    this.onShape,
  });

  final bool barAllowed;

  /// The bar; Expand calls the callback.
  final Widget Function(VoidCallback expand) bar;

  /// The card; the callback collapses it into the bar, null when there is
  /// no bar to collapse into.
  final Widget Function(VoidCallback? collapse) card;

  /// The bar has the chat or the files open under it.
  final bool panelOpen;

  /// The shape after each build, for the window around it.
  final ValueChanged<CmShape>? onShape;

  @override
  State<CmBarOrCard> createState() => _CmBarOrCardState();
}

class _CmBarOrCardState extends State<CmBarOrCard> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant CmBarOrCard old) {
    super.didUpdateWidget(old);
    if (!old.barAllowed && widget.barAllowed) _expanded = false;
  }

  CmShape get _shape => !widget.barAllowed || _expanded
      ? CmShape.card
      : widget.panelOpen
          ? CmShape.barPanel
          : CmShape.bar;

  @override
  Widget build(BuildContext context) {
    final shape = _shape;
    if (widget.onShape != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onShape?.call(shape));
    }
    final bar = shape != CmShape.card;
    final card = widget.card(
        widget.barAllowed ? () => setState(() => _expanded = false) : null);
    return Stack(children: [
      Positioned.fill(
        child: Offstage(
          offstage: bar,
          child: ExcludeFocus(excluding: bar, child: card),
        ),
      ),
      if (bar)
        Positioned.fill(
            child: widget.bar(() => setState(() => _expanded = true))),
    ]);
  }
}

/// The bar's sentence, with the part to set in bold.
class CmBarText {
  const CmBarText(this.sentence, {this.name = ''});
  final String sentence;
  final String name;
}

/// The bar's sentence for the people connected now, each named as the
/// window names them (cmCaller) and counted once however many connections
/// they have: "<name> is viewing and controlling your computer", "<name>
/// is using your computer" while their input arrives, or how many people
/// are connected.
CmBarText cmBarText(List<String> names, {required bool using}) {
  if (names.length > 1) {
    return CmBarText(tr('nd-cm-bar-count', [names.length]));
  }
  final name = names.isEmpty ? '' : names.first;
  return CmBarText(
      using ? tr('nd-qs-bar-using', [name]) : tr('nd-qs-bar-viewing', [name]),
      name: name);
}

/// The bar at the top of the screen during a session: drag handle, mark,
/// who is connected, Files once files move, Chat, Stop and Expand. When it
/// appears, the screen reader says who is on the computer.
class CmSessionBar extends StatefulWidget {
  const CmSessionBar({
    super.key,
    required this.text,
    required this.onStop,
    required this.onExpand,
    this.onChat,
    this.onFiles,
    this.filesLabel,
    this.filesOpen = false,
    this.onDrag,
  });

  final CmBarText text;
  final VoidCallback onStop;
  final VoidCallback onExpand;

  /// Null leaves Chat out (nobody to chat with).
  final VoidCallback? onChat;

  /// Null leaves Files out: no files moved yet.
  final VoidCallback? onFiles;
  final String? filesLabel;
  final bool filesOpen;

  /// Starts moving the window (the drag handle).
  final VoidCallback? onDrag;

  @override
  State<CmSessionBar> createState() => _CmSessionBarState();
}

class _CmSessionBarState extends State<CmSessionBar> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ndAnnounce(context, widget.text.sentence, assertive: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final sentence = widget.text.sentence;
    final name = widget.text.name;
    // The name in bold inside the translated sentence
    final i = name.isEmpty ? -1 : sentence.indexOf(name);
    final style = t.body.copyWith(fontSize: 15, height: 22 / 15);
    final text = i < 0
        ? Text(sentence,
            style: style, maxLines: 1, overflow: TextOverflow.ellipsis)
        : Text.rich(
            TextSpan(style: style, children: [
              TextSpan(text: sentence.substring(0, i)),
              TextSpan(
                  text: name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: sentence.substring(i + name.length)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis);
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 4, right: 4),
      decoration: BoxDecoration(
        color: c.bgFloat,
        borderRadius: NdSize.r,
        border: Border.all(color: c.rule),
        boxShadow: c.shadowFloat,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onPanStart: widget.onDrag == null ? null : (_) => widget.onDrag!(),
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
        Flexible(child: text),
        const SizedBox(width: 14),
        if (widget.onFiles != null) ...[
          NdButton(
              label: widget.filesLabel ?? tr('nd-qs-files'),
              icon: widget.filesOpen ? NdIcons.folderOpen : NdIcons.folder,
              size: NdButtonSize.sm,
              onPressed: widget.onFiles),
          const SizedBox(width: 8),
        ],
        if (widget.onChat != null) ...[
          NdButton(
              label: translate('Chat'),
              size: NdButtonSize.sm,
              onPressed: widget.onChat),
          const SizedBox(width: 8),
        ],
        NdButton(
            label: tr('nd-stop'),
            size: NdButtonSize.sm,
            kind: NdButtonKind.danger,
            onPressed: widget.onStop),
        const SizedBox(width: 4),
        NdIconButton(
            icon: NdIcons.expandMore,
            tooltip: tr('nd-cm-bar-expand'),
            color: c.text,
            iconSize: 20,
            onPressed: widget.onExpand),
      ]),
    );
  }
}

/// The chat or the files under the bar: a title with Close over [child].
class CmBarPanel extends StatelessWidget {
  const CmBarPanel({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.closeFocusable = true,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  /// False keeps Close out of the keyboard's reach (keys a remote computer
  /// types can reach the window while the chat is open).
  final bool closeFocusable;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    return Container(
      width: 400,
      height: 388,
      decoration: BoxDecoration(
        color: c.bgFloat,
        borderRadius: NdSize.r,
        border: Border.all(color: c.rule),
        boxShadow: c.shadowFloat,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            Expanded(
                child: Semantics(
                    header: true,
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.ndText.heading))),
            ExcludeFocus(
              excluding: !closeFocusable,
              child: NdIconButton(
                  icon: NdIcons.close,
                  tooltip: translate('Close'),
                  color: c.text,
                  iconSize: 20,
                  onPressed: onClose),
            ),
          ]),
        ),
        const NdRule(),
        Expanded(child: child),
      ]),
    );
  }
}

/// The bar window's content: the bar at the top, a panel under it, and
/// nothing else on the transparent window.
class CmBarWindow extends StatelessWidget {
  const CmBarWindow({super.key, required this.bar, this.panel});
  final Widget bar;
  final Widget? panel;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              bar,
              if (panel != null) ...[const SizedBox(height: 8), panel!],
            ],
          ),
        ),
      ),
    );
  }
}
