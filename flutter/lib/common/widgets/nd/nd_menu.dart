import 'package:flutter/material.dart';

import '../../theme/nd_theme.dart';
import 'nd_icons.dart';

/// The Menu component: bgFloat, 1 px rule border, shadow, 32 px items with
/// an 18 px leading column for checks and radio marks.
MenuStyle ndMenuStyle(BuildContext context, {double? minWidth}) {
  final c = context.nd;
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll(c.bgFloat),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: WidgetStatePropertyAll(c.shadowFar),
    elevation: const WidgetStatePropertyAll(8),
    padding:
        const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
    minimumSize: WidgetStatePropertyAll(Size(minWidth ?? 240, 0)),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: NdSize.r, side: BorderSide(color: c.rule))),
  );
}

ButtonStyle ndMenuItemStyle(BuildContext context, {bool danger = false}) {
  final c = context.nd;
  final t = context.ndText;
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

enum NdMenuLead { none, check, radioOn, radioOff }

class _Lead extends StatelessWidget {
  const _Lead(this.lead, this.icon);
  final NdMenuLead lead;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    Widget? child;
    switch (lead) {
      case NdMenuLead.check:
        child = Icon(NdIcons.check, size: 18, color: c.accent);
        break;
      case NdMenuLead.radioOn:
      case NdMenuLead.radioOff:
        final on = lead == NdMenuLead.radioOn;
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
      case NdMenuLead.none:
        if (icon != null) child = Icon(icon, size: 18, color: c.textMuted);
        break;
    }
    return SizedBox(width: 18, height: 18, child: Center(child: child));
  }
}

/// One menu entry. [reason] is shown as a tooltip when it is disabled.
class NdMenuItem extends StatelessWidget {
  const NdMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading = NdMenuLead.none,
    this.icon,
    this.trailing,
    this.danger = false,
    this.reason,
    this.closeOnActivate = true,
    this.prefix,
  });

  final String label;
  final VoidCallback? onPressed;
  final NdMenuLead leading;
  final IconData? icon;
  final String? trailing;
  final bool danger;
  final String? reason;
  final bool closeOnActivate;

  /// Shown between the lead column and the label, such as a language's flag.
  final Widget? prefix;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    Widget item = MenuItemButton(
      onPressed: onPressed,
      closeOnActivate: closeOnActivate,
      style: ndMenuItemStyle(context, danger: danger),
      leadingIcon: _Lead(leading, icon),
      trailingIcon: trailing == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(trailing!, style: t.small),
            ),
      child: prefix == null
          ? Text(label)
          : Row(mainAxisSize: MainAxisSize.min, children: [
              prefix!,
              const SizedBox(width: 8),
              Text(label),
            ]),
    );
    if (onPressed == null && reason != null && reason!.isNotEmpty) {
      item = Tooltip(message: reason!, child: item);
    }
    return item;
  }
}

/// The style of an item that opens a submenu. Flutter's SubmenuButton
/// draws a Material arrow (24 px, in the icon colour) at the end of every
/// such item; this style makes that arrow transparent, and NdSubmenuMark
/// draws NdIcons.chevronRight in its place.
ButtonStyle ndSubmenuItemStyle(BuildContext context) =>
    ndMenuItemStyle(context).copyWith(
        iconColor: const WidgetStatePropertyAll(Colors.transparent));

/// [child], a SubmenuButton with ndSubmenuItemStyle, with the chevron drawn
/// where Flutter's arrow is: 24 px wide, before the item's 12 px end padding.
class NdSubmenuMark extends StatelessWidget {
  const NdSubmenuMark({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.passthrough, children: [
      child,
      Positioned(
        top: 0,
        bottom: 0,
        right: 12 + (24 - 18) / 2,
        child: IgnorePointer(
          child: Center(
            child: Icon(NdIcons.chevronRight,
                size: 18, color: context.nd.textMuted),
          ),
        ),
      ),
    ]);
  }
}

/// A menu entry that opens a submenu to the side.
class NdSubmenu extends StatelessWidget {
  const NdSubmenu({
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
    return NdSubmenuMark(
      child: SubmenuButton(
        style: ndSubmenuItemStyle(context),
        menuStyle: ndMenuStyle(context),
        leadingIcon: const _Lead(NdMenuLead.none, null),
        menuChildren: enabled ? children : const [],
        child: Text(label),
      ),
    );
  }
}

/// A group heading inside a menu (caption 600, muted).
class NdMenuHeading extends StatelessWidget {
  const NdMenuHeading(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(38, 8, 12, 4),
      child: Text(label,
          style: t.caption.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class NdMenuDivider extends StatelessWidget {
  const NdMenuDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: context.nd.rule,
      );
}
