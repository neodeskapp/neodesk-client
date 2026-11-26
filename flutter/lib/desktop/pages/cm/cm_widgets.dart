// The connection manager's parts (DESIGN.md, Connection manager) as
// widgets without app state, shared by the app and the screenshot tests.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

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
  });

  final String name;
  final String subtitle;
  final bool mono;
  final Widget? avatar;

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

/// The body of a request: header, title, note and the switches.
///
/// When the request arrives, the screen reader says who wants to connect.
/// With [focusOnArrival] the title also takes keyboard focus, so Tab goes on
/// to the switches and the buttons. The title is not a button: Enter there
/// does nothing, so typing that was meant for another window cannot allow a
/// connection.
class CmRequestBody extends StatefulWidget {
  const CmRequestBody({
    super.key,
    required this.header,
    required this.name,
    required this.permissions,
    this.focusOnArrival = false,
  });

  final Widget header;
  final String name;
  final List<CmPermission> permissions;
  final bool focusOnArrival;

  @override
  State<CmRequestBody> createState() => _CmRequestBodyState();
}

class _CmRequestBodyState extends State<CmRequestBody> {
  final _titleFocus = FocusNode(debugLabel: 'connection request');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.focusOnArrival) _titleFocus.requestFocus();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header,
        const SizedBox(height: 16),
        Focus(
          focusNode: _titleFocus,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Semantics(
            header: true,
            child: _focused ? NdFocusRing(child: title) : title,
          ),
        ),
        const SizedBox(height: 6),
        Text(tr('nd-cm-request-note'), style: t.small),
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
      this.showFiles = true, this.unread = 0});
  final CmTab value;
  final ValueChanged<CmTab> onChanged;
  final bool showFiles;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return NdTabs<CmTab>(
      gap: 24,
      tabs: [
        NdTab(CmTab.access, tr('nd-cm-tab-access')),
        NdTab(CmTab.chat,
            unread > 0 ? '${translate('Chat')} ($unread)' : translate('Chat')),
        if (showFiles) NdTab(CmTab.files, tr('nd-cm-tab-files')),
      ],
      value: value,
      onChanged: onChanged,
    );
  }
}

/// "Connected for 12 minutes" or "Connected for 1 h 20 min".
String cmConnectedFor(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 60) {
    return tr('nd-cm-connected-min', [minutes < 1 ? 1 : minutes]);
  }
  return tr('nd-cm-connected-h', [d.inHours, minutes % 60]);
}
