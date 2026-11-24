// The parts of Home (DESIGN.md, Home) as widgets without app state, so the
// app and the screenshot tests draw the same thing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';
import 'package:flutter_hbb/onboarding/joining_view.dart' show formatNdId;

/// Two columns: this computer (392) and connect (the rest), 48 apart.
/// Incoming-only clients show the left column alone, centred; outgoing-only
/// clients the right one alone.
class HomeLayout extends StatelessWidget {
  const HomeLayout({super.key, this.left, this.right});
  final Widget? left;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    if (right == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 40),
          child: SizedBox(width: 392, child: left),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (left != null) ...[
            SizedBox(width: 392, child: left),
            const SizedBox(width: 48),
          ],
          Expanded(child: right!),
        ],
      ),
    );
  }
}

class HomeSupportContact {
  const HomeSupportContact({
    required this.company,
    this.phone = '',
    this.email = '',
    this.website = '',
    this.onPhone,
    this.onEmail,
    this.onWebsite,
  });

  final String company;
  final String phone;
  final String email;
  final String website;
  final VoidCallback? onPhone;
  final VoidCallback? onEmail;
  final VoidCallback? onWebsite;

  bool get isEmpty => phone.isEmpty && email.isEmpty && website.isEmpty;
}

class HomeStatus {
  const HomeStatus(this.kind, this.text, {this.linkLabel, this.onLink});
  final NdStatusKind kind;
  final String text;
  final String? linkLabel;
  final VoidCallback? onLink;
}

/// The left column: status, notices, the ID and password panel, the hint
/// and the server's contact details.
class ThisComputerColumn extends StatefulWidget {
  const ThisComputerColumn({
    super.key,
    required this.id,
    required this.status,
    this.password,
    this.permanentOnly = false,
    this.onlyClick = false,
    this.notices = const [],
    this.support,
    this.onNewPassword,
    this.revealPassword = false,
    this.statusWidget,
    this.footer,
    this.unavailable = false,
  });

  final String id;
  final HomeStatus status;

  /// Replaces the status line drawn from [status] (the app's live status).
  final Widget? statusWidget;

  /// Below everything else (Quit in incoming-only clients).
  final Widget? footer;

  /// The one-time password; null hides the password row.
  final String? password;

  /// Only the permanent password works: it is never shown.
  final bool permanentOnly;

  /// Security, How someone gets in is Only Allow.
  final bool onlyClick;
  final List<Widget> notices;
  final HomeSupportContact? support;
  final Future<void> Function()? onNewPassword;

  /// Start with the password shown (screenshots).
  final bool revealPassword;

  /// The service isn't running, so nobody can connect with the ID and
  /// password: they are greyed and can't be copied (the status line says
  /// why).
  final bool unavailable;

  @override
  State<ThisComputerColumn> createState() => _ThisComputerColumnState();
}

class _ThisComputerColumnState extends State<ThisComputerColumn> {
  late bool _shown = widget.revealPassword;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _newPassword() async {
    await widget.onNewPassword?.call();
    if (!mounted) return;
    setState(() => _shown = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _shown = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final st = widget.status;
    final showPassword = !widget.onlyClick && widget.password != null;

    Widget statusLine = widget.statusWidget ?? HomeStatusLine(status: st);

    final panel = NdPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(tr('nd-home-id'),
                    style: t.body.copyWith(color: c.textMuted))),
            NdCopyButton(
              value: () => widget.id.replaceAll(' ', ''),
              label: tr('nd-copy'),
              copiedLabel: translate('Copied'),
            ),
          ]),
          const SizedBox(height: 6),
          SelectableText(formatNdId(widget.id), style: t.id),
          if (showPassword || widget.permanentOnly) ...[
            const SizedBox(height: 16),
            const NdRule(),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Text(
                    widget.permanentOnly
                        ? tr('nd-home-permanent-password')
                        : tr('nd-home-one-time-password'),
                    style: t.body.copyWith(color: c.textMuted)),
              ),
              if (!widget.permanentOnly) ...[
                NdButton(
                  label: _shown ? tr('nd-hide') : tr('nd-show'),
                  size: NdButtonSize.sm,
                  onPressed: () => setState(() => _shown = !_shown),
                ),
                const SizedBox(width: 8),
                NdCopyButton(
                  value: () => widget.password ?? '',
                  label: tr('nd-copy'),
                  copiedLabel: translate('Copied'),
                ),
              ],
            ]),
            const SizedBox(height: 8),
            Text(
              _shown && !widget.permanentOnly
                  ? (widget.password ?? '')
                  : '•' * ((widget.password ?? '').length.clamp(6, 12)),
              style: t.password,
            ),
            if (!widget.permanentOnly && widget.onNewPassword != null) ...[
              const SizedBox(height: 10),
              NdButton.link(
                  label: tr('nd-home-new-password'), onPressed: _newPassword),
            ],
          ],
        ],
      ),
    );

    final support = widget.support;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('nd-home-this-computer'), style: t.title),
                const SizedBox(height: 6),
                statusLine,
                const SizedBox(height: 20),
                for (final n in widget.notices) ...[n, const SizedBox(height: 16)],
                IgnorePointer(
                  ignoring: widget.unavailable,
                  child: Opacity(
                      opacity: widget.unavailable ? 0.4 : 1, child: panel),
                ),
                if (!widget.unavailable) ...[
                  const SizedBox(height: 16),
                  Text(
                    widget.onlyClick
                        ? tr('nd-home-hint-click')
                        : tr('nd-home-hint'),
                    style: t.small,
                  ),
                ],
                const Spacer(),
                if (support != null && !support.isEmpty) ...[
                  const SizedBox(height: 32),
                  const NdRule(),
                  const SizedBox(height: 20),
                  Text(tr('nd-home-help-from', [support.company]),
                      style: t.heading),
                  const SizedBox(height: 10),
                  if (support.phone.isNotEmpty)
                    _ContactRow(
                        icon: NdIcons.call,
                        text: support.phone,
                        onTap: support.onPhone),
                  if (support.email.isNotEmpty)
                    _ContactRow(
                        icon: NdIcons.mail,
                        text: support.email,
                        link: true,
                        onTap: support.onEmail),
                  if (support.website.isNotEmpty)
                    _ContactRow(
                        icon: NdIcons.language,
                        text: support.website,
                        link: true,
                        onTap: support.onWebsite),
                ],
                if (widget.footer != null) ...[
                  const SizedBox(height: 16),
                  widget.footer!,
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark, the sentence and an optional link of the home status.
class HomeStatusLine extends StatelessWidget {
  const HomeStatusLine({super.key, required this.status});
  final HomeStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        NdStatusMark(kind: status.kind),
        const SizedBox(width: 10),
        Flexible(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(status.text, style: t.body),
              if (status.linkLabel != null)
                NdButton.link(label: status.linkLabel!, onPressed: status.onLink),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow(
      {required this.icon, required this.text, this.link = false, this.onTap});
  final IconData icon;
  final String text;
  final bool link;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 18, color: c.textMuted),
        const SizedBox(width: 14),
        Flexible(
          child: link
              ? NdButton.link(label: text, onPressed: onTap)
              : Text(text, style: t.body.copyWith(fontSize: 15)),
        ),
      ]),
    );
  }
}

/// The top of the right column: title, the ID field with Connect, the hint
/// and More ways to connect.
class ConnectHeader extends StatelessWidget {
  const ConnectHeader({
    super.key,
    required this.field,
    required this.onConnect,
    required this.moreWays,
  });

  /// The ID field (an autocomplete field in the app).
  final Widget field;
  final VoidCallback? onConnect;

  /// (label, action) of More ways to connect.
  final List<(String, VoidCallback)> moreWays;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('nd-home-connect-title'), style: t.title),
        const SizedBox(height: 20),
        Text(tr('nd-home-connect-field'), style: t.label),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: field),
          const SizedBox(width: 8),
          NdButton.primary(
              label: translate('Connect'),
              size: NdButtonSize.lg,
              onPressed: onConnect),
        ]),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(tr('nd-home-connect-hint'), style: t.small),
            ),
            MenuAnchor(
              style: ndMenuStyle(context),
              alignmentOffset: const Offset(0, 4),
              menuChildren: [
                for (final m in moreWays)
                  NdMenuItem(label: m.$1, onPressed: m.$2),
              ],
              builder: (context, controller, _) => NdButton(
                label: tr('nd-home-more-ways'),
                kind: NdButtonKind.ghost,
                size: NdButtonSize.sm,
                trailingIcon: NdIcons.expandMore,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One computer in the list: name and ID, system, status, Connect on hover
/// and the row menu.
class NdPeerRow extends StatefulWidget {
  const NdPeerRow({
    super.key,
    required this.name,
    required this.id,
    required this.platform,
    required this.online,
    this.favourite = false,
    this.note,
    this.lastSeen,
    this.showStatus = true,
    this.selected = false,
    this.onConnect,
    this.onTap,
    this.onMenu,
    this.forceHover = false,
    this.leading,
  });

  final String name;
  final String id;
  final String platform;
  final bool online;
  final bool favourite;
  final String? note;
  final String? lastSeen;

  /// False while the server is not reachable: the status column is empty
  /// and Connect is hidden.
  final bool showStatus;
  final bool selected;
  final VoidCallback? onConnect;
  final VoidCallback? onTap;

  /// Opens the row menu at the given global position.
  final void Function(Offset globalPosition)? onMenu;
  final bool forceHover;

  /// A checkbox in multi-selection mode.
  final Widget? leading;

  @override
  State<NdPeerRow> createState() => _NdPeerRowState();
}

class _NdPeerRowState extends State<NdPeerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final hover = _hover || widget.forceHover;
    final os = ndOsFromPlatform(widget.platform);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onConnect,
        onSecondaryTapUp: widget.onMenu == null
            ? null
            : (d) => widget.onMenu!(d.globalPosition),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: hover || widget.selected ? c.hover : Colors.transparent,
            border: Border(bottom: BorderSide(color: c.rule)),
          ),
          child: Row(children: [
            if (widget.leading != null) ...[
              widget.leading!,
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.label.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (widget.favourite) ...[
                      const SizedBox(width: 4),
                      Icon(NdIcons.starFilled, size: 16, color: c.textMuted),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    [
                      formatNdId(widget.id),
                      if ((widget.note ?? '').isNotEmpty) widget.note!,
                    ].join('   '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.mono.copyWith(color: c.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 126,
              child: Row(children: [
                NdOsMark(os: os),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(widget.platform,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body),
                ),
              ]),
            ),
            if (widget.lastSeen != null)
              SizedBox(
                width: 98,
                child: Text(widget.lastSeen!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(color: c.textMuted)),
              ),
            SizedBox(
              width: 76,
              child: widget.showStatus
                  ? NdStatus(
                      kind: widget.online
                          ? NdStatusKind.good
                          : NdStatusKind.offline,
                      text: widget.online
                          ? tr('nd-online')
                          : tr('nd-offline'))
                  : const SizedBox.shrink(),
            ),
            SizedBox(
              width: 76,
              child: hover && widget.showStatus && widget.onConnect != null
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: NdButton(
                          label: translate('Connect'),
                          size: NdButtonSize.sm,
                          onPressed: widget.onConnect),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Builder(
              builder: (bctx) => NdIconButton(
                icon: NdIcons.moreVert,
                tooltip: tr('nd-row-menu'),
                color: c.text,
                onPressed: widget.onMenu == null
                    ? null
                    : () {
                        final box = bctx.findRenderObject() as RenderBox;
                        widget.onMenu!(
                            box.localToGlobal(box.size.center(Offset.zero)));
                      },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The list's header: text tabs, the search field and [actions].
class PeerListHeader<T> extends StatelessWidget {
  const PeerListHeader({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
    required this.search,
    this.actions = const [],
  });

  final List<NdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;
  final Widget search;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return NdTabs<T>(
      tabs: tabs,
      value: value,
      onChanged: onChanged,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        search,
        for (final a in actions) ...[const SizedBox(width: 4), a],
      ]),
    );
  }
}

/// A sentence in place of an empty list.
class PeerListEmpty extends StatelessWidget {
  const PeerListEmpty({super.key, required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(text, style: t.body.copyWith(color: context.nd.textMuted)),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// Puts [text] on the clipboard.
void ndCopy(String text) => Clipboard.setData(ClipboardData(text: text));
