import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/nd/nd.dart';

/// The steps of an exe install, in the order the install page shows them
/// (install_progress.rs on the Rust side).
enum InstallStep { permission, copying, service, starting }

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
            Text(tr('nd-install-installing'), style: t.title),
            const SizedBox(height: 16),
            Text(installingLead ?? tr('nd-install-installing-lead'),
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
}
