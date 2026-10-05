import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../clinician/data/clinician_repository.dart';
import '../../domain/consultation_report.dart';

/// The pieces the Reports tab is built from, and the windows it reads.

/// The four the artboard offers.
enum ReportRange { today, week, month, custom }

extension ReportRangeText on ReportRange {
  String get label => switch (this) {
    ReportRange.today => 'Today',
    ReportRange.week => '7 days',
    ReportRange.month => '30 days',
    ReportRange.custom => 'Custom',
  };
}

/// The days a range covers, ending today.
///
/// "7 days" is this day and the six before it, not the calendar week: a doctor
/// looking on a Tuesday wants the last seven days of work, and a week that
/// resets on Monday would show one day on a Monday morning.
({DateTime from, DateTime to}) windowFor(ReportRange range, {DateTimeRange? custom}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return switch (range) {
    ReportRange.today => (from: today, to: today),
    ReportRange.week => (from: today.subtract(const Duration(days: 6)), to: today),
    ReportRange.month => (from: today.subtract(const Duration(days: 29)), to: today),
    ReportRange.custom => custom == null
        ? (from: today.subtract(const Duration(days: 29)), to: today)
        : (from: custom.start, to: custom.end),
  };
}

final consultationSummaryProvider = FutureProvider.autoDispose
    .family<ConsultationSummary, ({DateTime from, DateTime to})>(
      (ref, window) => ref
          .watch(clinicianRepositoryProvider)
          .consultationSummary(from: window.from, to: window.to),
    );

final consultationRegisterProvider = FutureProvider.autoDispose
    .family<List<ConsultationRow>, ({DateTime from, DateTime to})>(
      (ref, window) => ref
          .watch(clinicianRepositoryProvider)
          .consultationRegister(from: window.from, to: window.to),
    );

final prescriptionRegisterProvider = FutureProvider.autoDispose
    .family<List<PrescriptionRow>, ({DateTime from, DateTime to})>(
      (ref, window) => ref
          .watch(clinicianRepositoryProvider)
          .prescriptionRegister(from: window.from, to: window.to),
    );

final followUpComplianceProvider = FutureProvider.autoDispose
    .family<FollowUpCompliance, ({DateTime from, DateTime to})>(
      (ref, window) => ref
          .watch(clinicianRepositoryProvider)
          .followUpCompliance(from: window.from, to: window.to),
    );

/// Whether a change is worth reading as good news.
enum DeltaTone { good, bad, flat }

/// One figure, with what it was last time underneath.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.delta,
    required this.tone,
  });

  final String label;
  final String value;
  final String delta;
  final DeltaTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rCardLg),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: D.statLabel.copyWith(color: D.inkMuted)),
          SizedBox(height: D.gapTight),
          Text(value, style: D.score.copyWith(color: D.ink)),
          SizedBox(height: D.gapTight),
          Text(
            delta,
            style: D.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: switch (tone) {
                DeltaTone.good => D.done,
                DeltaTone.bad => D.danger,
                DeltaTone.flat => D.inkMuted,
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A card on the reports tab.
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.title, this.note, required this.child});

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s5),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(title, style: D.subhead.copyWith(color: D.ink))),
              if (note != null)
                Text(note!, style: D.statLabel.copyWith(color: D.inkFaint)),
            ],
          ),
          SizedBox(height: D.s4),
          child,
        ],
      ),
    );
  }
}

/// One bar per day of the window.
///
/// A day with nobody on it is drawn as a hairline rather than nothing, so a
/// Sunday the clinic is shut reads as a closed day and not as a gap in the
/// chart — and the busiest day is marked, because that is the one question a
/// doctor asks of this shape.
class DailyBars extends StatelessWidget {
  const DailyBars({super.key, required this.days});

  final List<DayCount> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return Text('Nothing in this window.', style: D.body.copyWith(color: D.inkMuted));
    }

    final peak = days.map((d) => d.count).fold(0, math.max);
    final busiest = peak == 0 ? null : days.firstWhere((d) => d.count == peak);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: D.tileMin + D.s5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, d) in days.indexed) ...[
                if (i != 0) SizedBox(width: D.hair),
                Expanded(
                  child: Semantics(
                    label: '${DateFormat('d MMM').format(d.date)}: ${d.count}',
                    child: Container(
                      height: peak == 0
                          ? D.hair
                          : math.max(D.hair, (D.tileMin + D.s5) * d.count / peak),
                      decoration: BoxDecoration(
                        color: d.count == 0
                            ? D.lineStrong
                            : (d == busiest ? D.brand : D.brandBar),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(D.rTick),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: D.s2),
        Row(
          children: [
            Text(
              DateFormat('d MMM').format(days.first.date),
              style: D.caption.copyWith(color: D.inkFaint),
            ),
            const Spacer(),
            Text(
              DateFormat('d MMM').format(days.last.date),
              style: D.caption.copyWith(color: D.inkFaint),
            ),
          ],
        ),
        if (busiest != null) ...[
          SizedBox(height: D.s3),
          Text(
            'Busiest: ${DateFormat('EEEE d MMM').format(busiest.date)} · $peak',
            style: D.statLabel.copyWith(color: D.inkMuted),
          ),
        ],
      ],
    );
  }
}

/// A list of named counts, each with its share of the whole.
class ShareBars extends StatelessWidget {
  const ShareBars({super.key, required this.rows, required this.total});

  final List<NamedCount> rows;

  /// What the share is of. Zero means no share can be worked out, and the rows
  /// then carry their count alone rather than a percentage of nothing.
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i != 0) SizedBox(height: D.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(r.name, style: D.subtitle.copyWith(color: D.ink))),
              SizedBox(width: D.s2),
              Text(
                '${r.count}',
                style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w700),
              ),
              if (total > 0)
                Text(
                  ' · ${((r.count / total) * 100).round()}%',
                  style: D.subtitle.copyWith(color: D.inkFaint),
                ),
            ],
          ),
          SizedBox(height: D.gapTight),
          ClipRRect(
            borderRadius: D.rPill,
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : (r.count / total).clamp(0, 1),
              minHeight: D.s2,
              backgroundColor: D.track,
              valueColor: const AlwaysStoppedAnimation(D.brand),
            ),
          ),
        ],
      ],
    );
  }
}
