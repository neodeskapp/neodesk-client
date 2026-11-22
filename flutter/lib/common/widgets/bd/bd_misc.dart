import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/bd_theme.dart';
import 'bd_button.dart';
import 'bd_icons.dart';

/// bgSubtle with 4 px corners; only for the ID and password, code boxes and
/// copy fields.
class BdPanel extends StatelessWidget {
  const BdPanel({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration:
            BoxDecoration(color: context.bd.bgSubtle, borderRadius: BdSize.r),
        child: child,
      );
}

class BdRule extends StatelessWidget {
  const BdRule({super.key, this.vertical = false});
  final bool vertical;

  @override
  Widget build(BuildContext context) => Container(
        width: vertical ? 1 : null,
        height: vertical ? null : 1,
        color: context.bd.rule,
      );
}

/// A Copy button whose label reads "Copied" for 1.5 s after a click.
class BdCopyButton extends StatefulWidget {
  const BdCopyButton({
    super.key,
    required this.value,
    required this.label,
    required this.copiedLabel,
    this.size = BdButtonSize.sm,
  });

  /// What goes on the clipboard (IDs without spaces).
  final String Function() value;
  final String label;
  final String copiedLabel;
  final BdButtonSize size;

  @override
  State<BdCopyButton> createState() => _BdCopyButtonState();
}

class _BdCopyButtonState extends State<BdCopyButton> {
  Timer? _timer;
  bool _copied = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.value()));
    _timer?.cancel();
    setState(() => _copied = true);
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) => BdButton(
        label: _copied ? widget.copiedLabel : widget.label,
        onPressed: _copy,
        size: widget.size,
      );
}

/// A value people copy, in mono on bgSubtle, with Copy at the end.
class BdCopyField extends StatelessWidget {
  const BdCopyField({
    super.key,
    required this.value,
    required this.copyLabel,
    required this.copiedLabel,
  });

  final String value;
  final String copyLabel;
  final String copiedLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    return Container(
      height: BdSize.controlLg,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: c.bgSubtle,
        borderRadius: BdSize.r,
        border: Border.all(color: c.rule),
      ),
      child: Row(children: [
        Expanded(
          child: Text(value,
              style: t.mono.copyWith(fontSize: 14, height: 20 / 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        BdCopyButton(
            value: () => value, label: copyLabel, copiedLabel: copiedLabel),
      ]),
    );
  }
}

class BdFact {
  const BdFact(this.label, this.value, {this.mono = false, this.child});
  final String label;
  final String value;
  final bool mono;
  final Widget? child;
}

/// Label and value pairs, label muted, rules between rows.
class BdFacts extends StatelessWidget {
  const BdFacts({super.key, required this.facts, this.labelWidth});
  final List<BdFact> facts;

  /// Fixed label column; by default the widest label decides.
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final rows = <TableRow>[];
    for (final f in facts) {
      final cellDeco = BoxDecoration(
          border: Border(bottom: BorderSide(color: c.rule, width: 1)));
      rows.add(TableRow(decoration: cellDeco, children: [
        Padding(
          padding: const EdgeInsets.only(top: 9, bottom: 9, right: 24),
          child: Text(f.label, style: t.body.copyWith(color: c.textMuted)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: f.child ??
              SelectableText(f.value,
                  style: f.mono
                      ? t.mono.copyWith(fontSize: 14, height: 20 / 14)
                      : t.body),
        ),
      ]));
    }
    return Table(
      columnWidths: {
        0: labelWidth != null
            ? FixedColumnWidth(labelWidth!)
            : const IntrinsicColumnWidth(),
        1: const FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }
}

enum BdTone { info, warning, danger, good }

Color bdToneColor(BdColors c, BdTone tone) => switch (tone) {
      BdTone.info => c.info,
      BdTone.warning => c.warning,
      BdTone.danger => c.danger,
      BdTone.good => c.success,
    };

/// One message that must be seen: icon, text, optional action, a 3 px start
/// border in the tone and a 9 % tone background.
class BdNotice extends StatelessWidget {
  const BdNotice({
    super.key,
    required this.text,
    this.tone = BdTone.info,
    this.icon,
    this.title,
    this.action,
    this.textWidget,
  });

  final String text;
  final BdTone tone;
  final IconData? icon;
  final String? title;
  final Widget? action;
  final Widget? textWidget;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final color = bdToneColor(c, tone);
    final ic = icon ??
        switch (tone) {
          BdTone.info => BdIcons.info,
          BdTone.warning => BdIcons.warning,
          BdTone.danger => BdIcons.error,
          BdTone.good => BdIcons.checkCircle,
        };
    return Container(
      decoration: BoxDecoration(
        color: tone == BdTone.info ? c.bgSubtle : c.noticeBg(color),
        borderRadius: BdSize.r,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(BdSize.radius)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(ic, size: 18, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: textWidget ??
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (title != null)
                                Text(title!,
                                    style: t.body.copyWith(
                                        fontWeight: FontWeight.w600)),
                              Text(text, style: t.body),
                            ],
                          ),
                    ),
                    if (action != null) ...[
                      const SizedBox(width: 12),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum BdStatusKind { good, wait, bad, offline }

/// An 8 px mark and a word. Never a pill.
class BdStatus extends StatelessWidget {
  const BdStatus({super.key, required this.kind, required this.text,
      this.textWidget, this.style});
  final BdStatusKind kind;
  final String text;
  final Widget? textWidget;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final t = context.bdText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BdStatusMark(kind: kind),
        const SizedBox(width: 8),
        Flexible(child: textWidget ?? Text(text, style: style ?? t.body)),
      ],
    );
  }
}

class BdStatusMark extends StatelessWidget {
  const BdStatusMark({super.key, required this.kind});
  final BdStatusKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    if (kind == BdStatusKind.offline) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.textMuted, width: 1.5),
        ),
      );
    }
    final color = switch (kind) {
      BdStatusKind.good => c.success,
      BdStatusKind.wait => c.warning,
      _ => c.danger,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// A 16 px ring, accent on rule, only while the app waits on the network.
/// With reduced motion it stands still.
class BdSpinner extends StatefulWidget {
  const BdSpinner({super.key, this.size = 16, this.color});
  final double size;
  final Color? color;

  @override
  State<BdSpinner> createState() => _BdSpinnerState();
}

class _BdSpinnerState extends State<BdSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
      _c.value = 0.1;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: Size.square(widget.size),
        painter: _RingPainter(
            angle: _c.value * 2 * math.pi,
            arc: widget.color ?? c.accent,
            track: c.rule),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.angle, required this.arc, required this.track});
  final double angle;
  final Color arc;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 2.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(w / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    canvas.drawOval(r, p..color = track);
    canvas.drawArc(r, angle - math.pi / 2, math.pi / 2, false, p..color = arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.angle != angle || old.arc != arc || old.track != track;
}

/// Initials in a 4 px box in one of the avatar colours on a 16 % tint.
class BdAvatar extends StatelessWidget {
  const BdAvatar({super.key, required this.name, this.size = 40});
  final String name;
  final double size;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final l = parts.toList();
    final a = l.first.characters.first;
    final b = l.length > 1 ? l.last.characters.first : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final color =
        c.avatars[name.codeUnits.fold<int>(0, (a, b) => a + b) % 3];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: c.tint16(color), borderRadius: BdSize.r),
      child: Text(initials(name),
          style: t.label.copyWith(
              fontSize: size >= 48 ? 17 : 15,
              fontWeight: FontWeight.w600,
              height: 1,
              color: color)),
    );
  }
}

/// The NeoDesk mark (rounded square, circle, overlap) in the logo
/// colours of the theme. Never the accent.
class BdLogoMark extends StatelessWidget {
  const BdLogoMark({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    return CustomPaint(
      size: Size.square(size),
      painter: BdMarkPainter(c.logoSquare, c.logoCircle, c.logoOverlap),
    );
  }
}

/// Draws the mark in a 44 unit box (viewBox 10 10 44 44 of the brand SVG).
class BdMarkPainter extends CustomPainter {
  BdMarkPainter(this.square, this.circle, this.overlap, {this.unit});
  final Color square, circle, overlap;
  final double? unit;

  @override
  void paint(Canvas canvas, Size size) {
    final k = unit ?? size.width / 44;
    canvas.save();
    canvas.scale(k);
    canvas.translate(-10, -10);
    final rect =
        RRect.fromRectAndRadius(Rect.fromLTWH(10, 22, 32, 32), Radius.circular(10));
    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: const Offset(38, 26), radius: 16));
    canvas.drawRRect(rect, Paint()..color = square);
    canvas.drawPath(circlePath, Paint()..color = circle);
    canvas.save();
    canvas.clipPath(circlePath);
    canvas.drawRRect(rect, Paint()..color = overlap);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(BdMarkPainter oldDelegate) =>
      oldDelegate.square != square ||
      oldDelegate.circle != circle ||
      oldDelegate.overlap != overlap;
}

/// The mark and the "neodesk" wordmark.
class BdWordmark extends StatelessWidget {
  const BdWordmark({super.key, this.height = 18});
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = context.bd.isDark;
    return SvgPicture.asset(
      dark ? 'assets/bd-logo-dark.svg' : 'assets/bd-logo-light.svg',
      height: height,
      semanticsLabel: 'NeoDesk',
    );
  }
}

enum BdOs { windows, apple, linux, android, other }

BdOs bdOsFromPlatform(String platform) {
  final p = platform.toLowerCase();
  if (p.contains('win')) return BdOs.windows;
  if (p.contains('mac') || p.contains('ios') || p.contains('darwin')) {
    return BdOs.apple;
  }
  if (p.contains('android')) return BdOs.android;
  if (p.contains('linux') || p.contains('ubuntu') || p.contains('debian')) {
    return BdOs.linux;
  }
  return BdOs.other;
}

/// The operating system mark (Phosphor fill) in its system colour, or in
/// [color] where it sits on a coloured tile.
class BdOsMark extends StatelessWidget {
  const BdOsMark({super.key, required this.os, this.size = 16, this.color});
  final BdOs os;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final (asset, systemColor) = switch (os) {
      BdOs.windows => ('assets/bd-os-windows.svg', c.osWindows),
      BdOs.apple => ('assets/bd-os-apple.svg', c.osApple),
      BdOs.linux => ('assets/bd-os-linux.svg', c.osLinux),
      BdOs.android => ('assets/bd-os-android.svg', c.success),
      BdOs.other => ('', c.textMuted),
    };
    final fg = color ?? systemColor;
    if (asset.isEmpty) {
      return Icon(BdIcons.computer, size: size, color: fg);
    }
    return SvgPicture.asset(asset,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(fg, BlendMode.srcIn));
  }
}

/// The Dialog component: bgFloat, 4 px corners, rule border, shadow, title
/// in title-md with a close button, actions at the end, primary last.
class BdDialog extends StatelessWidget {
  const BdDialog({
    super.key,
    required this.title,
    required this.children,
    required this.actions,
    this.width = 520,
    this.onClose,
    this.closeTooltip = 'Close',
    this.startAction,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final double width;
  final VoidCallback? onClose;
  final String closeTooltip;
  final Widget? startAction;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.bgFloat,
        borderRadius: BdSize.r,
        border: Border.all(color: c.rule),
        boxShadow: c.shadowFloat,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(title, style: t.titleMd)),
                  if (onClose != null)
                    BdIconButton(
                        icon: BdIcons.close,
                        tooltip: closeTooltip,
                        onPressed: onClose,
                        iconSize: 20,
                        color: c.text),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: 18),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
              child: Row(
                children: [
                  if (startAction != null) startAction!,
                  const Spacer(),
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row with a chevron that shows or hides [child] (Relay and API server,
/// install Options).
class BdDisclosure extends StatelessWidget {
  const BdDisclosure({
    super.key,
    required this.label,
    required this.open,
    required this.onToggle,
    required this.child,
    this.indent = 28,
  });

  final String label;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(open ? BdIcons.expandMore : BdIcons.chevronRight,
                    size: 18, color: c.text),
                const SizedBox(width: 10),
                Text(label, style: t.label.copyWith(fontSize: 15)),
              ]),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: EdgeInsets.only(left: indent, top: 12),
            child: child,
          ),
      ],
    );
  }
}

/// Steps with a state mark (joining): done, running, to do.
enum BdStepState { done, running, todo }

class BdStepRow extends StatelessWidget {
  const BdStepRow({super.key, required this.state, required this.text});
  final BdStepState state;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.bd;
    final t = context.bdText;
    final Widget mark = switch (state) {
      BdStepState.done => Icon(BdIcons.check, size: 20, color: c.success),
      BdStepState.running => const BdSpinner(size: 16),
      BdStepState.todo => Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: c.border, width: 1.5),
          ),
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 20, height: 20, child: Center(child: mark)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(text,
                style: t.body.copyWith(
                    fontSize: 15,
                    height: 22 / 15,
                    color: state == BdStepState.todo ? c.textMuted : c.text)),
          ),
        ],
      ),
    );
  }
}
