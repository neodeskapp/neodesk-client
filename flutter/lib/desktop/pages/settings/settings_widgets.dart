// The settings page's parts (DESIGN.md, Settings) as widgets without app
// state, shared by the app and the screenshot tests.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

class SettingsNavItem<T> {
  const SettingsNavItem(this.value, this.label, {this.dividerBefore = false});
  final T value;
  final String label;
  final bool dividerBefore;
}

/// The navigation column: search field, the groups, About after a rule.
class SettingsNav<T> extends StatelessWidget {
  const SettingsNav({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.search,
  });

  final List<SettingsNavItem<T>> items;
  final T? value;
  final ValueChanged<T> onChanged;
  final Widget search;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Container(
      width: 224,
      decoration: BoxDecoration(
        color: c.bgSubtle,
        border: Border(right: BorderSide(color: c.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 14),
          for (final item in items) ...[
            if (item.dividerBefore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(height: 1, color: c.rule),
              ),
            _NavItem(
              label: item.label,
              selected: item.value == value,
              onTap: () => onChanged(item.value),
              style: t.label.copyWith(fontSize: 15, height: 22 / 15),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem(
      {required this.label,
      required this.selected,
      required this.onTap,
      required this.style});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final TextStyle style;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 36,
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: widget.selected || _hover ? c.hover : Colors.transparent,
            borderRadius: NdSize.r,
          ),
          child: Row(children: [
            Container(
              width: 3,
              height: 20,
              color: widget.selected ? c.accent : Colors.transparent,
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(widget.label, style: widget.style)),
          ]),
        ),
      ),
    );
  }
}

/// A group page: title, one sentence, then the sections. 32 / 56 padding,
/// at most 680 wide.
class SettingsGroupPage extends StatelessWidget {
  const SettingsGroupPage({
    super.key,
    required this.title,
    required this.lead,
    required this.children,
    this.controller,
  });

  final String title;
  final String lead;
  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(56, 32, 56, 48),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: t.title),
              const SizedBox(height: 8),
              Text(lead, style: t.lead),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// A section: heading, one sentence, rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    this.lead,
    required this.children,
    this.trailing,
  });

  final String title;
  final String? lead;
  final List<Widget> children;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: t.heading.copyWith(fontSize: 17))),
            ...?trailing,
          ]),
          if (lead != null && lead!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(lead!, style: t.body.copyWith(color: context.nd.textMuted)),
          ],
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// One setting: label, a one-line description, the control at the end.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.description,
    this.control,
    this.enabled = true,
    this.below,
    this.rule = true,
  });

  final String label;
  final String? description;
  final Widget? control;
  final bool enabled;

  /// Extra content under the label (a field, a folder path).
  final Widget? below;
  final bool rule;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: rule ? Border(bottom: BorderSide(color: c.rule)) : null,
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: t.label.copyWith(
                          fontSize: 15,
                          height: 22 / 15,
                          fontWeight: FontWeight.w600)),
                  if (description != null && description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(description!,
                        style: t.body.copyWith(color: c.textMuted)),
                  ],
                  if (below != null) ...[const SizedBox(height: 8), below!],
                ],
              ),
            ),
            if (control != null) ...[const SizedBox(width: 24), control!],
          ],
        ),
      ),
    );
  }
}

/// The lock notice above Security and the Server connection settings.
class SettingsLockNotice extends StatelessWidget {
  const SettingsLockNotice({super.key, required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: NdNotice(
        tone: NdTone.warning,
        icon: NdIcons.lock,
        text: tr('nd-set-locked'),
        action: NdButton(
            label: tr('nd-set-unlock'),
            size: NdButtonSize.sm,
            onPressed: onUnlock),
      ),
    );
  }
}

/// The top of the Server group: status, how it was set up, the addresses
/// and key, and the ways to change them.
class ServerSummary extends StatelessWidget {
  const ServerSummary({
    super.key,
    required this.connected,
    required this.server,
    required this.relay,
    required this.api,
    required this.keyText,
    this.joinedLine,
    this.tokenLine,
    required this.actions,
  });

  final bool connected;
  final String server;
  final String relay;
  final String api;
  final String keyText;
  final String? joinedLine;
  final String? tokenLine;
  final List<Widget> actions;

  static String shortKey(String key) =>
      key.length > 18 ? '${key.substring(0, 8)}…${key.substring(key.length - 6)}' : key;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    final c = context.nd;
    final none = tr('nd-set-not-set');
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NdStatus(
            kind: server.isEmpty
                ? NdStatusKind.offline
                : (connected ? NdStatusKind.good : NdStatusKind.bad),
            text: server.isEmpty
                ? tr('nd-set-no-server')
                : (connected
                    ? tr('nd-set-connected-to', [server])
                    : tr('nd-set-not-connected', [server])),
            style: t.body.copyWith(fontSize: 15, height: 22 / 15),
          ),
          if (joinedLine != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Text(joinedLine!,
                  style: t.body.copyWith(color: c.textMuted)),
            ),
          const SizedBox(height: 18),
          NdFacts(labelWidth: 118, facts: [
            NdFact(tr('nd-set-server-address'), server.isEmpty ? none : server),
            NdFact(tr('nd-set-relay'),
                relay.isEmpty ? tr('nd-set-same-as-server') : relay),
            NdFact(tr('nd-set-api'), api.isEmpty ? none : api),
            NdFact(tr('nd-set-key'), keyText.isEmpty ? none : '',
                child: keyText.isEmpty
                    ? null
                    : Tooltip(
                        message: keyText,
                        child: Text(shortKey(keyText),
                            style: t.mono.copyWith(fontSize: 14, height: 20 / 14)),
                      )),
            if (tokenLine != null) NdFact(tr('nd-set-device-token'), tokenLine!),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

class AboutFacts {
  const AboutFacts({
    required this.version,
    required this.buildDate,
    required this.id,
    required this.fingerprint,
  });
  final String version;
  final String buildDate;
  final String id;
  final String fingerprint;
}

/// The app names of NeoDesk's own builds. A custom client config that sets
/// another name makes a branded build.
const kNeoDeskOwnAppNames = {
  'NeoDesk Client',
  'NeoDesk Support Agent',
  'NeoDesk Quick Support',
};

/// What About's Discord link does: [open] in NeoDesk's own builds, nothing
/// (no row) in a branded one, whose users belong to whoever branded it:
/// another [appName], or a company's name, contact or logo
/// ([companyBranded]).
VoidCallback? aboutCommunityLink(
        {required String appName,
        required bool companyBranded,
        required VoidCallback open}) =>
    kNeoDeskOwnAppNames.contains(appName) && !companyBranded ? open : null;

/// Opens [url] with [launch]. When nothing opens it (Linux without a
/// browser set up for links), puts it on the clipboard with [copy] and says
/// so with the address through [say], instead of doing nothing.
Future<void> openLinkOrShowAddress(String url,
    {required Future<bool> Function(String url) launch,
    required void Function(String url) copy,
    required void Function(String message) say}) async {
  var opened = false;
  try {
    opened = await launch(url);
  } catch (_) {}
  if (opened) return;
  copy(url);
  say(tr('nd-link-copied', [url]));
}

/// About: the logo, the facts, Check for updates and the copyright line.
class AboutView extends StatelessWidget {
  const AboutView({
    super.key,
    required this.facts,
    required this.onViewLicence,
    required this.onSource,
    required this.onUpstream,
    required this.onCheckUpdates,
    this.onCommunity,
    this.updateResult,
    this.updateActionLabel,
    this.onUpdateAction,
    this.checking = false,
    this.sourceLabel = 'github.com/neodeskapp/neodesk-client',
  });

  final AboutFacts facts;
  final VoidCallback onViewLicence;
  final VoidCallback onSource;
  final VoidCallback onUpstream;
  final VoidCallback onCheckUpdates;
  /// Opens the NeoDesk Discord; no Help row without it.
  final VoidCallback? onCommunity;
  final String? updateResult;
  /// The button a found release gets next to the result: Update to <version>
  /// where the app updates itself, Download <version> elsewhere.
  final String? updateActionLabel;
  final VoidCallback? onUpdateAction;
  /// A check is running: the button waits.
  final bool checking;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    final c = context.nd;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(56, 32, 56, 48),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const NdWordmark(height: 34),
              const SizedBox(height: 24),
              NdFacts(labelWidth: 102, facts: [
                NdFact(tr('nd-about-version'), facts.version),
                NdFact(tr('nd-about-build'), facts.buildDate),
                NdFact(tr('nd-fact-id'), formatGroupedId(facts.id), mono: true),
                NdFact(tr('nd-about-fingerprint'), facts.fingerprint, mono: true),
                NdFact(tr('nd-about-licence'), '',
                    child: Row(children: [
                      Text('AGPL-3.0', style: t.body),
                      const SizedBox(width: 12),
                      NdButton.link(
                          label: tr('nd-about-view-licence'),
                          onPressed: onViewLicence),
                    ])),
                NdFact(tr('nd-about-source'), '',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: NdButton.link(label: sourceLabel, onPressed: onSource),
                    )),
                NdFact(tr('nd-about-based-on'), '',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: NdButton.link(label: 'RustDesk', onPressed: onUpstream),
                    )),
                if (onCommunity != null)
                  NdFact(tr('nd-about-help'), '',
                      child: Row(children: [
                        Icon(NdIcons.forum, size: 18, color: c.textMuted),
                        const SizedBox(width: 6),
                        NdButton.link(
                            label: tr('nd-about-community'),
                            onPressed: onCommunity),
                      ])),
              ]),
              const SizedBox(height: 20),
              Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (updateActionLabel != null && onUpdateAction != null)
                      NdButton.primary(
                          label: updateActionLabel!,
                          onPressed: onUpdateAction),
                    NdButton(
                        label: tr('nd-about-check'),
                        onPressed: checking ? null : onCheckUpdates),
                    if (updateResult != null)
                      Text(updateResult!,
                          style: t.body.copyWith(color: c.textMuted)),
                  ]),
              const SizedBox(height: 24),
              Text(tr('nd-about-copyright'),
                  style: t.body.copyWith(color: c.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// An ID in groups of three; leaves other text as it is.
String formatGroupedId(String id) {
  final digits = id.replaceAll(' ', '');
  if (!RegExp(r'^\d+$').hasMatch(digits)) return id;
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
    b.write(digits[i]);
  }
  return b.toString();
}

/// One search hit: the setting, where it lives, and its description.
class SettingsSearchHit {
  const SettingsSearchHit(
      {required this.label, required this.path, this.description, this.onTap});
  final String label;
  final String path;
  final String? description;
  final VoidCallback? onTap;
}

class SettingsSearchResults extends StatelessWidget {
  const SettingsSearchResults({super.key, required this.query, required this.hits});
  final String query;
  final List<SettingsSearchHit> hits;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    final c = context.nd;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(56, 32, 56, 48),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: hits.isEmpty
              ? Text(tr('nd-set-search-none', [query]), style: t.lead)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final h in hits)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: h.onTap,
                          behavior: HitTestBehavior.opaque,
                          child: SettingsRow(
                            label: h.label,
                            description: [
                              h.path,
                              if ((h.description ?? '').isNotEmpty) h.description!,
                            ].join('\n'),
                            control: Icon(NdIcons.chevronRight,
                                size: 18, color: c.textMuted),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// translate() of [key], or null when no language has text for it.
String? translateOrNull(String key) {
  final v = translate(key);
  return v == key ? null : v;
}
