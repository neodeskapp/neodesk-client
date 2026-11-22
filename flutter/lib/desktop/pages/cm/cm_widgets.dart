// The connection manager's parts (DESIGN.md, Connection manager) as
// widgets without app state, shared by the app and the screenshot tests.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/bd/bd.dart';

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
    final t = context.bdText;
    return Row(children: [
      SizedBox(
          width: 48,
          height: 48,
          child: avatar ?? BdAvatar(name: name, size: 48)),
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
                    ? t.mono.copyWith(fontSize: 13, color: context.bd.textMuted)
                    : t.body.copyWith(color: context.bd.textMuted)),
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
    final c = context.bd;
    final t = context.bdText;
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
                BdSwitch(
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
class CmRequestBody extends StatelessWidget {
  const CmRequestBody({
    super.key,
    required this.header,
    required this.name,
    required this.permissions,
  });

  final Widget header;
  final String name;
  final List<CmPermission> permissions;

  @override
  Widget build(BuildContext context) {
    final t = context.bdText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 22),
        Text(tr('bd-cm-request-title', [name]), style: t.titleMd),
        const SizedBox(height: 8),
        Text(tr('bd-cm-request-note'), style: t.small.copyWith(fontSize: 14)),
        if (permissions.isNotEmpty) ...[
          const SizedBox(height: 16),
          CmPermissionList(
              heading: tr('bd-cm-may', [name]), items: permissions),
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
          child: BdButton(
              label: translate('Decline'),
              size: BdButtonSize.lg,
              block: true,
              onPressed: onDecline),
        ),
        if (onAllow != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: BdButton.primary(
                label: tr('bd-allow'),
                size: BdButtonSize.lg,
                block: true,
                onPressed: onAllow),
          ),
        ],
      ]),
      if (onAllowElevated != null) ...[
        const SizedBox(height: 12),
        BdButton.link(
            label: tr('bd-cm-allow-elevated'), onPressed: onAllowElevated),
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
    return BdTabs<CmTab>(
      gap: 24,
      tabs: [
        BdTab(CmTab.access, tr('bd-cm-tab-access')),
        BdTab(CmTab.chat,
            unread > 0 ? '${translate('Chat')} ($unread)' : translate('Chat')),
        if (showFiles) BdTab(CmTab.files, tr('bd-cm-tab-files')),
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
    return tr('bd-cm-connected-min', [minutes < 1 ? 1 : minutes]);
  }
  return tr('bd-cm-connected-h', [d.inHours, minutes % 60]);
}
