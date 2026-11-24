import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

/// The steps of an exe install, in the order the install page shows them
/// (install_progress.rs on the Rust side).
enum InstallStep { permission, copying, service, starting }

/// A NeoDesk installed on this computer from another file, as the exe sees
/// it (installed_standing_json in windows.rs).
class InstalledStanding {
  const InstalledStanding(
      {required this.standing,
      required this.installed,
      required this.version,
      this.msi = false});

  /// 'older', 'newer' or 'unknown' (the same version opens the installed one).
  final String standing;

  /// The installed version, '' when it can't be read.
  final String installed;

  /// This exe's version.
  final String version;

  /// Installed with the MSI.
  final bool msi;

  /// The exe updates an older exe install.
  bool get offersUpdate => standing == 'older' && !msi;

  /// From the JSON the core gives, null when nothing else is installed.
  static InstalledStanding? parse(String json) {
    if (json.trim().isEmpty) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return InstalledStanding(
        standing: '${m['standing'] ?? 'unknown'}',
        installed: '${m['installed'] ?? ''}',
        version: '${m['this'] ?? ''}',
        msi: m['msi'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The install page (DESIGN.md, Install): one Install button, the options
/// folded away, Run without installing and the licence at the foot. While
/// it installs, the steps with the one that runs, as joining shows them.
class InstallView extends StatelessWidget {
  const InstallView({
    super.key,
    required this.lead,
    required this.pathController,
    required this.startMenu,
    required this.desktopIcon,
    required this.printer,
    required this.onStartMenu,
    required this.onDesktopIcon,
    required this.onPrinter,
    required this.onInstall,
    required this.onChangePath,
    required this.onLicence,
    this.onRunWithout,
    this.showPrinter = true,
    this.optionsOpen = false,
    required this.onToggleOptions,
    this.installing = false,
    this.error,
    this.installingLead,
    this.step = InstallStep.permission,
    this.copyPercent,
    this.installed,
    this.onUpdate,
    this.onOpenInstalled,
  });

  final String lead;
  final TextEditingController pathController;
  final bool startMenu;
  final bool desktopIcon;
  final bool printer;
  final ValueChanged<bool> onStartMenu;
  final ValueChanged<bool> onDesktopIcon;
  final ValueChanged<bool> onPrinter;
  final VoidCallback onInstall;
  final VoidCallback onChangePath;
  final VoidCallback onLicence;
  final VoidCallback? onRunWithout;
  final bool showPrinter;
  final bool optionsOpen;
  final VoidCallback onToggleOptions;
  final bool installing;

  /// The whole sentence the page shows when an install failed.
  final String? error;
  final String? installingLead;
  final InstallStep step;

  /// How much is copied, while copying.
  final int? copyPercent;

  /// A NeoDesk installed from another file: the page offers to update it
  /// or to open it instead of installing.
  final InstalledStanding? installed;
  final VoidCallback? onUpdate;
  final VoidCallback? onOpenInstalled;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    final c = context.nd;
    final lead1 = t.body.copyWith(fontSize: 16, height: 24 / 16, color: c.text);
    if (installing) {
      NdStepState st(InstallStep s) => step.index > s.index
          ? NdStepState.done
          : (step == s ? NdStepState.running : NdStepState.todo);
      return Padding(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                tr(installed == null
                    ? 'nd-install-installing'
                    : 'nd-update-updating'),
                style: t.title),
            const SizedBox(height: 16),
            Text(
                installed == null
                    ? installingLead ?? tr('nd-install-installing-lead')
                    : tr('nd-install-installing-lead'),
                style: lead1),
            const SizedBox(height: 24),
            NdStepRow(
                state: st(InstallStep.permission),
                text: tr('nd-install-step-permission')),
            NdStepRow(
                state: st(InstallStep.copying),
                text: step == InstallStep.copying && copyPercent != null
                    ? tr('nd-install-step-copying-percent', ['$copyPercent'])
                    : tr('nd-install-step-copying')),
            NdStepRow(
                state: st(InstallStep.service),
                text: tr('nd-install-step-service')),
            NdStepRow(
                state: st(InstallStep.starting),
                text: tr('nd-install-step-starting')),
          ],
        ),
      );
    }
    if (installed != null) return _installedPage(context, installed!, lead1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('nd-install-title'), style: t.title),
                const SizedBox(height: 16),
                Text(lead, style: lead1),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  NdNotice(
                    tone: NdTone.danger,
                    text: error!,
                    action: NdButton(
                        label: tr('nd-try-again'),
                        size: NdButtonSize.sm,
                        onPressed: onInstall),
                  ),
                ],
                const SizedBox(height: 28),
                NdButton.primary(
                    label: tr('nd-install'),
                    size: NdButtonSize.lg,
                    onPressed: onInstall),
                const SizedBox(height: 10),
                Text(tr('nd-install-hint'), style: t.body.copyWith(color: c.textMuted)),
                const SizedBox(height: 28),
                NdDisclosure(
                  label: tr('nd-install-options'),
                  open: optionsOpen,
                  onToggle: onToggleOptions,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('nd-install-in'), style: t.label),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: NdField(
                              controller: pathController,
                              mono: true,
                              readOnly: true),
                        ),
                        const SizedBox(width: 8),
                        NdButton(label: tr('nd-change'), onPressed: onChangePath),
                      ]),
                      const SizedBox(height: 16),
                      NdCheckbox(
                          value: startMenu,
                          onChanged: onStartMenu,
                          label: tr('nd-install-start-menu')),
                      const SizedBox(height: 14),
                      NdCheckbox(
                          value: desktopIcon,
                          onChanged: onDesktopIcon,
                          label: tr('nd-install-desktop')),
                      if (showPrinter) ...[
                        const SizedBox(height: 14),
                        NdCheckbox(
                            value: printer,
                            onChanged: onPrinter,
                            label: tr('nd-install-printer'),
                            hint: tr('nd-install-printer-hint')),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.rule))),
          child: Row(children: [
            if (onRunWithout != null)
              NdButton.link(
                  label: tr('nd-install-run-without'), onPressed: onRunWithout),
            const Spacer(),
            Text(tr('nd-install-accept'), style: t.body.copyWith(color: c.textMuted)),
            NdButton.link(label: tr('nd-install-licence'), onPressed: onLicence),
            Text('.', style: t.body.copyWith(color: c.textMuted)),
          ]),
        ),
      ],
    );
  }

  /// A NeoDesk installed from another file: an older exe install is
  /// offered the update; a newer one, an MSI install and one whose version
  /// can't be read are left alone and can be opened.
  Widget _installedPage(
      BuildContext context, InstalledStanding s, TextStyle lead1) {
    final t = context.ndText;
    final c = context.nd;
    final update = s.offersUpdate;
    final String title;
    final String text;
    if (update) {
      title = tr('nd-update-title');
      text = tr('nd-update-lead', [s.installed, s.version]);
    } else if (s.standing == 'older' && s.msi) {
      title = tr('nd-update-title');
      text = tr('nd-update-lead-msi', [s.installed, s.version]);
    } else if (s.standing == 'newer') {
      title = tr('nd-installed-title');
      text = tr('nd-installed-newer', [s.installed, s.version]);
    } else {
      title = tr('nd-installed-title');
      text = tr('nd-installed-unknown');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.title),
                const SizedBox(height: 16),
                Text(text, style: lead1),
                if (error != null && update) ...[
                  const SizedBox(height: 16),
                  NdNotice(
                    tone: NdTone.danger,
                    text: error!,
                    action: NdButton(
                        label: tr('nd-try-again'),
                        size: NdButtonSize.sm,
                        onPressed: onUpdate),
                  ),
                ],
                const SizedBox(height: 28),
                if (update) ...[
                  NdButton.primary(
                      label: tr('nd-update-button', [s.version]),
                      size: NdButtonSize.lg,
                      onPressed: onUpdate),
                  const SizedBox(height: 10),
                  Text(tr('nd-update-hint'),
                      style: t.body.copyWith(color: c.textMuted)),
                ] else
                  NdButton.primary(
                      label: tr('nd-open-installed'),
                      size: NdButtonSize.lg,
                      onPressed: onOpenInstalled),
              ],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.rule))),
          child: Row(children: [
            if (onRunWithout != null)
              NdButton.link(
                  label: tr('nd-install-run-without'), onPressed: onRunWithout),
            const Spacer(),
            if (update) ...[
              Text(tr('nd-update-accept'),
                  style: t.body.copyWith(color: c.textMuted)),
              NdButton.link(
                  label: tr('nd-install-licence'), onPressed: onLicence),
              Text('.', style: t.body.copyWith(color: c.textMuted)),
            ],
          ]),
        ),
      ],
    );
  }
}
