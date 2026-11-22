import 'package:flutter/material.dart';

import '../../theme/bd_theme.dart';
import 'bd_icons.dart';

/// The Menu component: bgFloat, 1 px rule border, shadow, 32 px items with
/// an 18 px leading column for checks and radio marks.
MenuStyle bdMenuStyle(BuildContext context, {double? minWidth}) {
  final c = context.bd;
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll(c.bgFloat),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: WidgetStatePropertyAll(c.shadowFar),
    elevation: const WidgetStatePropertyAll(8),
    padding:
        const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
    minimumSize: WidgetStatePropertyAll(Size(minWidth ?? 240, 0)),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BdSize.r, side: BorderSide(color: c.rule))),
  );
}

ButtonStyle bdMenuItemStyle(BuildContext context, {bool danger = false}) {
  final c = context.bd;
  final t = context.bdText;
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
    maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 32)),
    padding: const WidgetStatePropertyAll(
        EdgeInsets.only(left: 10, right: 12)),
    textStyle: WidgetStatePropertyAll(t.body),
    foregroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return c.textMuted;
      return danger ? c.danger : c.text;
    }),
    iconColor: WidgetStatePropertyAll(c.textMuted),
    iconSize: const WidgetStatePropertyAll(18),
    backgroundColor: WidgetStateProperty.resolveWith((s) =>
        (s.contains(WidgetState.hovered) ||
                    s.contains(WidgetState.focused)) &&
                !s.contains(WidgetState.disabled)
            ? c.hover
            : Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
    splashFactory: NoSplash.splashFactory,
  );
}

enum BdMenuLead { none, check, radioOn, radioOff }

class _Lead extends StatelessWidget {
  const _Lead(this.lead, this.icon);
  final BdMenuLead lead;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    Widget? child;
    switch (lead) {
      case BdMenuLead.check:
        child = Icon(BdIcons.check, size: 18, color: c.accent);
        break;
      case BdMenuLead.radioOn:
      case BdMenuLead.radioOff:
        final on = lead == BdMenuLead.radioOn;
        child = Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: on ? c.accent : c.border),
          ),
          child: on
              ? Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: c.accent))
              : null,
        );
        break;
      case BdMenuLead.none:
        if (icon != null) child = Icon(icon, size: 18, color: c.textMuted);
        break;
    }
    return SizedBox(width: 18, height: 18, child: Center(child: child));
  }
}

/// One menu entry. [reason] is shown as a tooltip when it is disabled.
class BdMenuItem extends StatelessWidget {
  const BdMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading = BdMenuLead.none,
    this.icon,
    this.trailing,
    this.danger = false,
    this.reason,
    this.closeOnActivate = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final BdMenuLead leading;
  final IconData? icon;
  final String? trailing;
  final bool danger;
  final String? reason;
  final bool closeOnActivate;

  @override
  Widget build(BuildContext context) {
    final t = context.bdText;
    Widget item = MenuItemButton(
      onPressed: onPressed,
      closeOnActivate: closeOnActivate,
      style: bdMenuItemStyle(context, danger: danger),
      leadingIcon: _Lead(leading, icon),
      trailingIcon: trailing == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(trailing!, style: t.small),
            ),
      child: Text(label),
    );
    if (onPressed == null && reason != null && reason!.isNotEmpty) {
      item = Tooltip(message: reason!, child: item);
    }
    return item;
  }
}

/// A menu entry that opens a submenu to the side.
class BdSubmenu extends StatelessWidget {
  const BdSubmenu({
    super.key,
    required this.label,
    required this.children,
    this.enabled = true,
  });

  final String label;
  final List<Widget> children;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    return SubmenuButton(
      style: bdMenuItemStyle(context),
      menuStyle: bdMenuStyle(context),
      leadingIcon: const _Lead(BdMenuLead.none, null),
      trailingIcon: Padding(
        padding: const EdgeInsets.only(left: 24),
        child: Icon(BdIcons.chevronRight, size: 18, color: c.textMuted),
      ),
      menuChildren: enabled ? children : const [],
      child: Text(label),
    );
  }
}

/// A group heading inside a menu (caption 600, muted).
class BdMenuHeading extends StatelessWidget {
  const BdMenuHeading(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.bdText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(38, 8, 12, 4),
      child: Text(label,
          style: t.caption.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class BdMenuDivider extends StatelessWidget {
  const BdMenuDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: context.bd.rule,
      );
}
