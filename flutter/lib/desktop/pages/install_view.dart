import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/bd/bd.dart';

/// The install page (DESIGN.md, Install): one Install button, the options
/// folded away, Run without installing and the licence at the foot.
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
  final String? error;
  final String? installingLead;

  @override
  Widget build(BuildContext context) {
    final t = context.bdText;
    final c = context.bd;
    final lead1 = t.body.copyWith(fontSize: 16, height: 24 / 16, color: c.text);
    if (installing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('bd-install-installing'), style: t.title),
            const SizedBox(height: 16),
            Row(children: [
              const BdSpinner(),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(installingLead ?? tr('bd-install-installing-lead'),
                      style: lead1)),
            ]),
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
                Text(tr('bd-install-title'), style: t.title),
                const SizedBox(height: 16),
                Text(lead, style: lead1),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  BdNotice(
                    tone: BdTone.danger,
                    text: tr('bd-install-failed', [error]),
                    action: BdButton(
                        label: tr('bd-try-again'),
                        size: BdButtonSize.sm,
                        onPressed: onInstall),
                  ),
                ],
                const SizedBox(height: 28),
                BdButton.primary(
                    label: tr('bd-install'),
                    size: BdButtonSize.lg,
                    onPressed: onInstall),
                const SizedBox(height: 10),
                Text(tr('bd-install-hint'), style: t.body.copyWith(color: c.textMuted)),
                const SizedBox(height: 28),
                BdDisclosure(
                  label: tr('bd-install-options'),
                  open: optionsOpen,
                  onToggle: onToggleOptions,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('bd-install-in'), style: t.label),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: BdField(
                              controller: pathController,
                              mono: true,
                              readOnly: true),
                        ),
                        const SizedBox(width: 8),
                        BdButton(label: tr('bd-change'), onPressed: onChangePath),
                      ]),
                      const SizedBox(height: 16),
                      BdCheckbox(
                          value: startMenu,
                          onChanged: onStartMenu,
                          label: tr('bd-install-start-menu')),
                      const SizedBox(height: 14),
                      BdCheckbox(
                          value: desktopIcon,
                          onChanged: onDesktopIcon,
                          label: tr('bd-install-desktop')),
                      if (showPrinter) ...[
                        const SizedBox(height: 14),
                        BdCheckbox(
                            value: printer,
                            onChanged: onPrinter,
                            label: tr('bd-install-printer'),
                            hint: tr('bd-install-printer-hint')),
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
              BdButton.link(
                  label: tr('bd-install-run-without'), onPressed: onRunWithout),
            const Spacer(),
            Text(tr('bd-install-accept'), style: t.body.copyWith(color: c.textMuted)),
            BdButton.link(label: tr('bd-install-licence'), onPressed: onLicence),
            Text('.', style: t.body.copyWith(color: c.textMuted)),
          ]),
        ),
      ],
    );
  }
}
