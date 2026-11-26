import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/nd_theme.dart';
import 'nd_button.dart';
import 'nd_pressable.dart';
import 'nd_icons.dart';

/// bgSubtle with 4 px corners; only for the ID and password, code boxes and
/// copy fields.
class NdPanel extends StatelessWidget {
  const NdPanel({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration:
            BoxDecoration(color: context.nd.bgSubtle, borderRadius: NdSize.r),
        child: child,
      );
}

class NdRule extends StatelessWidget {
  const NdRule({super.key, this.vertical = false});
  final bool vertical;

  @override
  Widget build(BuildContext context) => Container(
        width: vertical ? 1 : null,
        height: vertical ? null : 1,
        color: context.nd.rule,
      );
}

/// A Copy button whose label reads "Copied" for 1.5 s after a click.
class NdCopyButton extends StatefulWidget {
  const NdCopyButton({
    super.key,
    required this.value,
    required this.label,
    required this.copiedLabel,
    this.size = NdButtonSize.sm,
  });

  /// What goes on the clipboard (IDs without spaces).
  final String Function() value;
  final String label;
  final String copiedLabel;
  final NdButtonSize size;

  @override
  State<NdCopyButton> createState() => _NdCopyButtonState();
}

class _NdCopyButtonState extends State<NdCopyButton> {
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
  Widget build(BuildContext context) => NdButton(
        label: _copied ? widget.copiedLabel : widget.label,
        onPressed: _copy,
        size: widget.size,
      );
}

/// A value people copy, in mono on bgSubtle, with Copy at the end.
class NdCopyField extends StatelessWidget {
  const NdCopyField({
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
    final c = context.nd;
    final t = context.ndText;
    return Container(
      height: NdSize.controlLg,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: c.bgSubtle,
        borderRadius: NdSize.r,
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
        NdCopyButton(
            value: () => value, label: copyLabel, copiedLabel: copiedLabel),
      ]),
    );
  }
}

class NdFact {
  const NdFact(this.label, this.value, {this.mono = false, this.child});
  final String label;
  final String value;
  final bool mono;
  final Widget? child;
}

/// Label and value pairs, label muted, rules between rows.
class NdFacts extends StatelessWidget {
  const NdFacts({super.key, required this.facts, this.labelWidth});
  final List<NdFact> facts;

  /// The label column's least width, so pages line up; a wider label (a
  /// longer language) widens it. By default the widest label decides.
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
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
            ? MaxColumnWidth(
                FixedColumnWidth(labelWidth!), const IntrinsicColumnWidth())
            : const IntrinsicColumnWidth(),
        1: const FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }
}

enum NdTone { info, warning, danger, good }

Color ndToneColor(NdColors c, NdTone tone) => switch (tone) {
      NdTone.info => c.info,
      NdTone.warning => c.warning,
      NdTone.danger => c.danger,
      NdTone.good => c.success,
    };

/// One message that must be seen: icon, text, optional action, a 3 px start
/// border in the tone and a 9 % tone background.
class NdNotice extends StatelessWidget {
  const NdNotice({
    super.key,
    required this.text,
    this.tone = NdTone.info,
    this.icon,
    this.title,
    this.action,
    this.textWidget,
  });

  final String text;
  final NdTone tone;
  final IconData? icon;
  final String? title;
  final Widget? action;
  final Widget? textWidget;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final color = ndToneColor(c, tone);
    final ic = icon ??
        switch (tone) {
          NdTone.info => NdIcons.info,
          NdTone.warning => NdIcons.warning,
          NdTone.danger => NdIcons.error,
          NdTone.good => NdIcons.checkCircle,
        };
    return Container(
      decoration: BoxDecoration(
        color: tone == NdTone.info ? c.bgSubtle : c.noticeBg(color),
        borderRadius: NdSize.r,
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
                    left: Radius.circular(NdSize.radius)),
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

enum NdStatusKind { good, wait, bad, offline }

/// An 8 px mark and a word. Never a pill.
class NdStatus extends StatelessWidget {
  const NdStatus({super.key, required this.kind, required this.text,
      this.textWidget, this.style});
  final NdStatusKind kind;
  final String text;
  final Widget? textWidget;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final t = context.ndText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NdStatusMark(kind: kind),
        const SizedBox(width: 8),
        Flexible(child: textWidget ?? Text(text, style: style ?? t.body)),
      ],
    );
  }
}

class NdStatusMark extends StatelessWidget {
  const NdStatusMark({super.key, required this.kind});
  final NdStatusKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    if (kind == NdStatusKind.offline) {
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
      NdStatusKind.good => c.success,
      NdStatusKind.wait => c.warning,
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
class NdSpinner extends StatefulWidget {
  const NdSpinner({super.key, this.size = 16, this.color});
  final double size;
  final Color? color;

  @override
  State<NdSpinner> createState() => _NdSpinnerState();
}

class _NdSpinnerState extends State<NdSpinner>
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
    final c = context.nd;
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
class NdAvatar extends StatelessWidget {
  const NdAvatar({super.key, required this.name, this.size = 40, this.picture});
  final String name;
  final double size;

  /// A profile picture (PNG, JPEG, WebP or GIF) shown in place of the
  /// initials, cut to fill the box; the initials stay when it can't be
  /// decoded.
  final Uint8List? picture;

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
    final c = context.nd;
    final t = context.ndText;
    final color =
        c.avatars[name.codeUnits.fold<int>(0, (a, b) => a + b) % 3];
    final initialsBox = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: c.tint16(color), borderRadius: NdSize.r),
      child: Text(initials(name),
          style: t.label.copyWith(
              fontSize: size >= 48 ? 17 : 15,
              fontWeight: FontWeight.w600,
              height: 1,
              color: color)),
    );
    final bytes = picture;
    if (bytes == null || bytes.isEmpty) return initialsBox;
    return ClipRRect(
      borderRadius: NdSize.r,
      child: Image.memory(bytes,
          key: const ValueKey('nd-avatar-picture'),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => initialsBox),
    );
  }
}

/// The NeoDesk mark (rounded square, circle, overlap) in the logo
/// colours of the theme. Never the accent.
class NdLogoMark extends StatelessWidget {
  const NdLogoMark({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    return CustomPaint(
      size: Size.square(size),
      painter: NdMarkPainter(c.logoSquare, c.logoCircle, c.logoOverlap),
    );
  }
}

/// Draws the mark in a 44 unit box (viewBox 10 10 44 44 of the brand SVG).
class NdMarkPainter extends CustomPainter {
  NdMarkPainter(this.square, this.circle, this.overlap, {this.unit});
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
  bool shouldRepaint(NdMarkPainter oldDelegate) =>
      oldDelegate.square != square ||
      oldDelegate.circle != circle ||
      oldDelegate.overlap != overlap;
}

/// The mark and the "neodesk" wordmark.
class NdWordmark extends StatelessWidget {
  const NdWordmark({super.key, this.height = 18});
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = context.nd.isDark;
    return SvgPicture.asset(
      dark ? 'assets/nd-logo-dark.svg' : 'assets/nd-logo-light.svg',
      height: height,
      semanticsLabel: 'NeoDesk',
    );
  }
}

enum NdOs { windows, apple, linux, android, other }

NdOs ndOsFromPlatform(String platform) {
  final p = platform.toLowerCase();
  if (p.contains('win')) return NdOs.windows;
  if (p.contains('mac') || p.contains('ios') || p.contains('darwin')) {
    return NdOs.apple;
  }
  if (p.contains('android')) return NdOs.android;
  if (p.contains('linux') || p.contains('ubuntu') || p.contains('debian')) {
    return NdOs.linux;
  }
  return NdOs.other;
}

/// The operating system mark (Phosphor fill) in its system colour, or in
/// [color] where it sits on a coloured tile.
class NdOsMark extends StatelessWidget {
  const NdOsMark({super.key, required this.os, this.size = 16, this.color});
  final NdOs os;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final (asset, systemColor) = switch (os) {
      NdOs.windows => ('assets/nd-os-windows.svg', c.osWindows),
      NdOs.apple => ('assets/nd-os-apple.svg', c.osApple),
      NdOs.linux => ('assets/nd-os-linux.svg', c.osLinux),
      NdOs.android => ('assets/nd-os-android.svg', c.success),
      NdOs.other => ('', c.textMuted),
    };
    final fg = color ?? systemColor;
    if (asset.isEmpty) {
      return Icon(NdIcons.computer, size: size, color: fg);
    }
    return SvgPicture.asset(asset,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(fg, BlendMode.srcIn));
  }
}

/// The Dialog component: bgFloat, 4 px corners, rule border, shadow, title
/// in title-md with a close button, actions at the end, primary last.
class NdDialog extends StatelessWidget {
  const NdDialog({
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
    final c = context.nd;
    final t = context.ndText;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.bgFloat,
        borderRadius: NdSize.r,
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
                    NdIconButton(
                        icon: NdIcons.close,
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
class NdDisclosure extends StatelessWidget {
  const NdDisclosure({
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
    final c = context.nd;
    final t = context.ndText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        NdPressable(
          label: label,
          expanded: open,
          onPressed: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(open ? NdIcons.expandMore : NdIcons.chevronRight,
                  size: 18, color: c.text),
              const SizedBox(width: 10),
              Text(label, style: t.label.copyWith(fontSize: 15)),
            ]),
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
enum NdStepState { done, running, todo }

class NdStepRow extends StatelessWidget {
  const NdStepRow({super.key, required this.state, required this.text});
  final NdStepState state;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.nd;
    final t = context.ndText;
    final Widget mark = switch (state) {
      NdStepState.done => Icon(NdIcons.check, size: 20, color: c.success),
      NdStepState.running => const NdSpinner(size: 16),
      NdStepState.todo => Container(
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
                    color: state == NdStepState.todo ? c.textMuted : c.text)),
          ),
        ],
      ),
    );
  }
}
