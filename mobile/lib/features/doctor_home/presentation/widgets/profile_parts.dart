import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../clinician/domain/patient_summary.dart';

/// The pieces the four record tabs are built from: the card, the section
/// heading, the chip, the row, the little chart.
///
/// They live together because the tabs have to look like one screen. The
/// artboards draw the same white card at radius 24 on every tab, the same
/// hairline between rows, and the same uppercase eyebrow over a list — a tab
/// that invents its own is a tab that looks like a different app.

enum ChipKind { plain, warn, allergy, brand }

class ProfileChip extends StatelessWidget {
  const ProfileChip({super.key, required this.label, this.kind = ChipKind.plain});

  final String label;
  final ChipKind kind;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      ChipKind.warn => (D.pendingGround, D.pending, null),
      ChipKind.allergy => (D.card, D.pending, D.pendingLine),
      ChipKind.brand => (D.brandTint, D.brand, null),
      ChipKind.plain => (D.track, D.inkMuted, null),
    };

    return Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.textScalerOf(context).scale(D.s6 + D.s1 / 2),
      ),
      padding: EdgeInsets.symmetric(horizontal: D.gapIcon, vertical: D.s1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: D.rPill,
        border: border == null ? null : Border.all(color: border),
      ),
      child: Align(
        widthFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kind == ChipKind.allergy) ...[
              const Icon(Icons.warning_amber_rounded, size: D.iconSm, color: D.pending),
              SizedBox(width: D.s1),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: D.caption.copyWith(
                  color: fg,
                  fontWeight: kind == ChipKind.plain ? FontWeight.w600 : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The white card every section on these tabs sits in.
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    this.lifted = false,
    required this.child,
  });

  final String? title;
  final String? subtitle;

  /// A link in the heading's right-hand corner.
  final Widget? action;

  /// The artboard lifts one card per tab with the deeper brand shadow — the
  /// thing it wants read first.
  final bool lifted;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s5),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: lifted ? D.liftBrand : D.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: D.screenTitle.copyWith(color: D.ink)),
                      if (subtitle != null) ...[
                        SizedBox(height: D.s1 / 2),
                        Text(subtitle!, style: D.body.copyWith(color: D.inkMuted)),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...[SizedBox(width: D.s3), action!],
              ],
            ),
            SizedBox(height: D.s4),
          ],
          child,
        ],
      ),
    );
  }
}

/// An uppercase eyebrow over a list.
class ProfileEyebrow extends StatelessWidget {
  const ProfileEyebrow({super.key, required this.label, this.colour = D.inkFaint});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) =>
      Text(label.toUpperCase(), style: D.chip.copyWith(color: colour));
}

/// A row in a list inside a card, with the artboard's hairline above it.
class ProfileRow extends StatelessWidget {
  const ProfileRow({super.key, required this.child, this.first = false, this.onTap});

  final Widget child;
  final bool first;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: D.cardPad),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: D.line)),
      ),
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

/// Nothing to show, said rather than left blank.
class ProfileEmpty extends StatelessWidget {
  const ProfileEmpty({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: D.s6),
      child: Column(
        children: [
          if (icon != null) ...[
            Icon(icon, size: D.s8, color: D.inkFaint),
            SizedBox(height: D.s3),
          ],
          Text(text, textAlign: TextAlign.center, style: D.body.copyWith(color: D.inkMuted)),
        ],
      ),
    );
  }
}

/// The record did not load — said once, with a way to ask again.
class ProfileFailed extends StatelessWidget {
  const ProfileFailed({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(D.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The record did not load.',
              textAlign: TextAlign.center,
              style: D.body.copyWith(color: D.inkMuted),
            ),
            SizedBox(height: D.s3),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: D.brandTint,
                foregroundColor: D.brand,
                minimumSize: D.hug,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
              ),
              child: Text('Try again', style: D.dateLine),
            ),
          ],
        ),
      ),
    );
  }
}

/// A measurement tile: the label, the figure, and what it means in a word.
class VitalTile extends StatelessWidget {
  const VitalTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.band,
    this.bandColour = D.inkMuted,
  });

  final String label;
  final String value;
  final String? unit;
  final String? band;
  final Color bandColour;

  /// Nothing has been measured. The tile stays — a doctor needs to see that
  /// the blood pressure is missing, not that there is no row for it — but it
  /// reads as an absence rather than a figure.
  bool get missing => value.trim().isEmpty || value == '—';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.cardPad, vertical: D.s3),
      decoration: BoxDecoration(color: D.ground, borderRadius: BorderRadius.circular(D.s3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: D.statLabel.copyWith(color: D.inkMuted)),
          SizedBox(height: D.s1),
          Text.rich(
            TextSpan(
              text: missing ? '—' : value,
              style: D.tileFigure.copyWith(color: missing ? D.inkFaint : D.ink),
              children: [
                if (!missing && unit != null && unit!.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: D.statLabel.copyWith(color: D.inkFaint, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
          if (missing) ...[
            SizedBox(height: D.s1),
            Text(
              'Not recorded',
              style: D.caption.copyWith(color: D.inkFaint, fontWeight: FontWeight.w600),
            ),
          ] else if (band != null) ...[
            SizedBox(height: D.s1),
            Text(
              band!,
              style: D.caption.copyWith(color: bandColour, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

/// A fortnight of readings, drawn plainly.
///
/// ---- What is not on it ----------------------------------------------------
///
/// The artboard draws a dashed "Target 130" across the chart. A target is a
/// clinical decision — it belongs to the patient's own plan, and this server
/// does not send one. Drawing a number nobody set would make every reading
/// above it look like a failure somebody chose; so the line is the readings and
/// their average, and the average is labelled.
///
/// The axis reaches the lowest reading or 70, whichever is lower, and never
/// starts at a figure that would flatter the series.
class GlucoseChart extends StatelessWidget {
  const GlucoseChart({super.key, required this.points});

  final List<GlucoseDailyPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return ProfileEmpty(
        text: points.isEmpty
            ? 'No readings logged yet. Record a fasting sugar and the line starts here.'
            : 'One reading so far — a line needs two.',
      );
    }
    return AspectRatio(
      aspectRatio: 310 / 150,
      child: CustomPaint(painter: _GlucosePainter(points, MediaQuery.textScalerOf(context))),
    );
  }
}

class _GlucosePainter extends CustomPainter {
  _GlucosePainter(this.points, this.scaler);

  final List<GlucoseDailyPoint> points;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [for (final p in points) p.average];
    final top = (values.reduce(math.max) + 20).ceilToDouble();
    final bottom = math.min(70, values.reduce(math.min) - 20).toDouble();
    final span = math.max(top - bottom, 1).toDouble();

    const gutter = 34.0;
    final chart = Rect.fromLTRB(gutter, 8, size.width, size.height - 22);

    final grid = Paint()
      ..color = D.line
      ..strokeWidth = 1;
    final label = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      final value = (top - span * i / 3).round();
      label
        ..text = TextSpan(
          text: '$value',
          style: D.caption.copyWith(color: D.inkFaint, fontSize: scaler.scale(11)),
        )
        ..layout();
      label.paint(canvas, Offset(chart.left - label.width - 6, y - label.height / 2));
    }

    double x(int i) => chart.left + chart.width * i / (points.length - 1);
    double y(num v) => chart.bottom - (v - bottom) / span * chart.height;

    final path = Path()..moveTo(x(0), y(points.first.average));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(points[i].average));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = D.brand
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    for (var i = 0; i < points.length; i++) {
      final at = Offset(x(i), y(points[i].average));
      final last = i == points.length - 1;
      canvas.drawCircle(at, last ? 3.5 : 3, Paint()..color = last ? D.brand : D.card);
      canvas.drawCircle(
        at,
        last ? 3.5 : 3,
        Paint()
          ..color = D.brand
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    // The ends of the window, named. Every tick between them would not fit at
    // 360dp and would be read as a reading that is not there.
    void day(int i, TextAlign align) {
      label
        ..text = TextSpan(
          text: _short(points[i].date),
          style: D.caption.copyWith(color: D.inkFaint, fontSize: scaler.scale(11)),
        )
        ..textAlign = align
        ..layout();
      final at = x(i);
      label.paint(
        canvas,
        Offset(
          align == TextAlign.left ? at : at - label.width,
          size.height - label.height,
        ),
      );
    }

    day(0, TextAlign.left);
    day(points.length - 1, TextAlign.right);
  }

  static String _short(DateTime d) => '${d.day}/${d.month}';

  @override
  bool shouldRepaint(_GlucosePainter old) => old.points != points;
}
