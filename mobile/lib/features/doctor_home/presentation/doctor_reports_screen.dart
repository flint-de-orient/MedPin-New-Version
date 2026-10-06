import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../appointments/domain/clinic.dart';
import '../../appointments/presentation/appointment_providers.dart';
import '../domain/consultation_report.dart';
import 'widgets/profile_parts.dart';
import 'widgets/report_export.dart';
import 'widgets/report_parts.dart';

/// The consultation MIS (`Doctor-Reports`).
///
/// ---- Counted, not modelled -------------------------------------------------
///
/// Every number here is a count of rows the practice owns, and every one of
/// them can be opened as the list it was counted from. A doctor reads these to
/// decide how their month went; a figure they cannot check against the diary is
/// one they are right not to trust.
///
/// ---- Fees, and the half of them this cannot see ----------------------------
///
/// Fees are here now, and they are specifically what patients paid *through
/// the app*: a visit booked against one of the practice's services and settled
/// in the payment sheet. The desk's cash is not in the app and never has been,
/// so the card carries how many of the window's consultations it is counting —
/// eleven of two hundred is a figure about eleven consultations, and a card
/// that showed the money without the count would read as the month's takings.
///
/// Referrals are still not here. Nothing records one, so there is nothing to
/// count, and the note at the foot says that rather than showing a nought.
class DoctorReportsScreen extends ConsumerStatefulWidget {
  const DoctorReportsScreen({super.key});

  @override
  ConsumerState<DoctorReportsScreen> createState() => _DoctorReportsScreenState();
}

class _DoctorReportsScreenState extends ConsumerState<DoctorReportsScreen> {
  ReportRange _range = ReportRange.month;
  DateTimeRange? _custom;

  /// Null is every room the doctor works in, which is the default.
  Clinic? _clinic;

  /// Whether the day chart is read as bars or as the days themselves.
  bool _asTable = false;

  ReportWindow get _window {
    final days = windowFor(_range, custom: _custom);
    return (from: days.from, to: days.to, clinicId: _clinic?.id);
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;
    final summary = ref.watch(consultationSummaryProvider(window));

    return Scaffold(
      backgroundColor: D.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              range: _range,
              window: window,
              onExport: summary.valueOrNull == null
                  ? null
                  : () => shareTable(
                      context,
                      filename: reportFilename(summary.value!),
                      csv: reportCsv(summary.value!),
                    ),
              onRange: (r) async {
                if (r == ReportRange.custom) {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(DateTime.now().year - 2),
                    lastDate: DateTime.now(),
                    initialDateRange: _custom,
                  );
                  if (picked == null) return;
                  setState(() {
                    _custom = picked;
                    _range = r;
                  });
                  return;
                }
                setState(() => _range = r);
              },
              clinic: _clinic,
              onClinic: (c) => setState(() => _clinic = c),
            ),
            Expanded(
              child: summary.when(
                loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
                error: (e, _) => ProfileFailed(
        error: e,
                  onRetry: () => ref.invalidate(consultationSummaryProvider),
                ),
                data: (report) => RefreshIndicator(
                  onRefresh: () async => ref.invalidate(consultationSummaryProvider),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(D.s4, D.s5, D.s4, D.s8),
                    children: [
                      Padding(
                        padding: EdgeInsets.only(left: D.s1, bottom: D.s3),
                        child: Text(
                          comparedLine(report),
                          style: D.statLabel.copyWith(color: D.inkMuted),
                        ),
                      ),
                      if (report.isEmpty)
                        // Counted from booked appointments, so a clinic that
                        // consults straight from the record has nothing here
                        // and nothing wrong.
                        ProfileEmpty(
                          text: 'No appointments in this window. '
                              'Consultations are counted from the diary.',
                          icon: Icons.insights_outlined,
                        )
                      else ...[
                        _Kpis(report: report),
                        SizedBox(height: D.s4),
                        ReportCard(
                          title: 'Consultations per day',
                          action: TextButton(
                            onPressed: () => setState(() => _asTable = !_asTable),
                            style: TextButton.styleFrom(
                              foregroundColor: D.brand,
                              minimumSize: D.hug,
                              padding: EdgeInsets.symmetric(horizontal: D.s2),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _asTable ? 'Chart' : 'Table',
                              style: D.dateLine.copyWith(
                                color: D.brand,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          child: _asTable
                              ? DailyTable(days: report.perDay)
                              : DailyBars(days: report.perDay),
                        ),
                        SizedBox(height: D.s4),
                        if (report.byLocation.isNotEmpty) ...[
                          ReportCard(
                            title: 'By location',
                            note: '${report.consultations.value} total',
                            child: ShareBars(
                              rows: report.byLocation,
                              total: report.consultations.value,
                            ),
                          ),
                          SizedBox(height: D.s4),
                        ],
                        if (report.byDiagnosis.isNotEmpty) ...[
                          ReportCard(
                            title: 'Top diagnoses',
                            note: 'On prescriptions written',
                            child: ShareBars(
                              rows: report.byDiagnosis,
                              total: report.prescriptions.value,
                            ),
                          ),
                          SizedBox(height: D.s4),
                        ],
                      ],
                      if (!report.fees.isEmpty) ...[
                        ReportCard(
                          title: 'Fees through the app',
                          note: feeCoverage(report.fees),
                          child: _Fees(fees: report.fees),
                        ),
                        SizedBox(height: D.s4),
                      ],
                      const ProfileEyebrow(label: 'Detailed reports'),
                      SizedBox(height: D.s2),
                      _Registers(window: window),
                      SizedBox(height: D.s4),
                      _NotRecorded(fees: report.fees),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.range,
    required this.window,
    required this.onRange,
    required this.onExport,
    required this.clinic,
    required this.onClinic,
  });

  final ReportRange range;
  final ReportWindow window;
  final ValueChanged<ReportRange> onRange;
  final Clinic? clinic;
  final ValueChanged<Clinic?> onClinic;

  /// Null until there are figures to hand over.
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A doctor with one address is never asked which one. The row is the
    // artboard's, and it only earns its place where there is a choice.
    final clinics = ref.watch(clinicsProvider).valueOrNull ?? const <Clinic>[];
    final rooms = [for (final c in clinics) if (c.isActive) c];

    return Container(
      padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.cardPad),
      decoration: const BoxDecoration(
        color: D.card,
        border: Border(bottom: BorderSide(color: D.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reports', style: D.greeting.copyWith(color: D.ink)),
                    SizedBox(height: D.s1 / 2),
                    Text(
                      'Your consultation MIS',
                      style: D.body.copyWith(color: D.inkMuted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: D.s3),
              ExportButton(label: 'Export', onPressed: onExport),
            ],
          ),
          SizedBox(height: D.cardPad),
          // The artboard's segmented control, in its sunken track.
          Container(
            padding: EdgeInsets.all(D.s1),
            decoration: BoxDecoration(
              color: D.track,
              borderRadius: BorderRadius.circular(D.rCard),
            ),
            child: Row(
              children: [
                for (final r in ReportRange.values) ...[
                  if (r != ReportRange.values.first) SizedBox(width: D.s1),
                  Expanded(
                    child: Semantics(
                      inMutuallyExclusiveGroup: true,
                      selected: r == range,
                      button: true,
                      child: InkWell(
                        onTap: () => onRange(r),
                        borderRadius: BorderRadius.circular(D.s3),
                        child: Container(
                          height: MediaQuery.textScalerOf(context).scale(D.tap - D.s1),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: r == range ? D.card : null,
                            borderRadius: BorderRadius.circular(D.s3),
                            boxShadow: r == range ? D.lift : null,
                          ),
                          child: Text(
                            r.label,
                            style: D.dateLine.copyWith(
                              color: r == range ? D.ink : D.inkMuted,
                              fontWeight: r == range ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (rooms.length > 1) ...[
            SizedBox(height: D.s3),
            Row(
              children: [
                const Icon(Icons.tune_rounded, size: D.icon, color: D.inkMuted),
                SizedBox(width: D.gapTight),
                Text('Filters', style: D.dateLine.copyWith(color: D.inkMuted)),
                SizedBox(width: D.s3),
                // Expanded and right-aligned rather than a Spacer beside a
                // Flexible: those two split the free space between them, and
                // a long clinic name would ellipsise with blank room next to it.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<String?>(
                      tooltip: 'Which location',
                      initialValue: clinic?.id,
                      onSelected: (id) => onClinic(
                        id == null ? null : rooms.firstWhere((c) => c.id == id),
                      ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: null, child: Text('All locations')),
                        for (final c in rooms)
                          PopupMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      child: Container(
                        constraints: BoxConstraints(
                          minHeight: MediaQuery.textScalerOf(context).scale(D.tap - D.s2),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: D.s3),
                        decoration: BoxDecoration(
                          borderRadius: D.rPill,
                          border: Border.all(color: D.lineStrong),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                clinic?.name ?? 'All locations',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: D.dateLine.copyWith(color: D.ink),
                              ),
                            ),
                            const Icon(
                              Icons.expand_more_rounded,
                              size: D.icon,
                              color: D.inkMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The figures, two across.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.report});

  final ConsultationSummary report;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      KpiCard(
        label: 'Consultations',
        value: '${report.consultations.value}',
        delta: deltaLine(report.consultations, 'before'),
        tone: toneOf(report.consultations, moreIsBetter: true),
      ),
      KpiCard(
        label: 'New patients',
        value: '${report.newPatients.value}',
        delta: deltaLine(report.newPatients, 'before'),
        tone: toneOf(report.newPatients, moreIsBetter: true),
      ),
      KpiCard(
        label: 'Avg. consult time',
        value: report.average.minutes == null ? '—' : '${report.average.minutes} min',
        // Says what it is made of, because an average of four consultations is
        // not the month's average.
        delta: report.average.minutes == null
            ? 'Not timed yet'
            : 'From ${report.average.from} timed',
        tone: DeltaTone.flat,
      ),
      KpiCard(
        label: 'Missed appointments',
        value: '${report.missed.value}',
        delta: 'Booked, didn’t come',
        tone: report.missed.value == 0 ? DeltaTone.flat : DeltaTone.bad,
      ),
      KpiCard(
        label: 'Prescriptions',
        value: '${report.prescriptions.value}',
        delta: report.prescribedShare == null
            ? 'Nobody seen'
            : '${report.prescribedShare}% of consultations',
        tone: DeltaTone.flat,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final width = (c.maxWidth - D.s2) / 2;
        return Wrap(
          spacing: D.s2,
          runSpacing: D.s2,
          children: [for (final card in cards) SizedBox(width: width, child: card)],
        );
      },
    );
  }
}

/// The lists every figure above was counted from.
class _Registers extends StatelessWidget {
  const _Registers({required this.window});

  final ReportWindow window;

  @override
  Widget build(BuildContext context) {
    String q(String path) =>
        '$path?from=${_day(window.from)}&to=${_day(window.to)}';

    final rows = <({String title, String sub, String route})>[
      (
        title: 'Consultation register',
        sub: 'Every visit, with who and when',
        route: q('/clinician/reports/consultations'),
      ),
      (
        title: 'Prescription register',
        sub: 'Medicines and tests you prescribed',
        route: q('/clinician/reports/prescriptions'),
      ),
      (
        title: 'Fees through the app',
        // Named for what it is. "Fees and collections", the artboard's title,
        // would be read as the practice's takings, and the desk's cash has
        // never been in this app.
        sub: 'What patients paid online, and who still owes',
        route: q('/clinician/reports/fees'),
      ),
      (
        title: 'Follow-up compliance',
        sub: 'Who was asked back, and who came',
        route: q('/clinician/reports/follow-ups'),
      ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        children: [
          for (final (i, r) in rows.indexed)
            ProfileRow(
              first: i == 0,
              onTap: () => context.push(r.route),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.title,
                          style: D.subtitle.copyWith(
                            color: D.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(r.sub, style: D.statLabel.copyWith(color: D.inkFaint)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: D.iconLg, color: D.inkFaint),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// The money paid through the app, and how much of the month that is.
class _Fees extends StatelessWidget {
  const _Fees({required this.fees});

  final FeeTotals fees;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Collected',
                    style: D.statLabel.copyWith(color: D.inkMuted),
                  ),
                  Text(fees.collected, style: D.score.copyWith(color: D.ink)),
                  Text(
                    deltaMoney(fees),
                    style: D.caption.copyWith(
                      color: fees.collectedPaise >= fees.previousCollectedPaise
                          ? D.done
                          : D.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: D.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Still owed',
                    style: D.statLabel.copyWith(color: D.inkMuted),
                  ),
                  Text(
                    fees.outstanding,
                    style: D.score.copyWith(
                      color: fees.outstandingPaise > 0 ? D.pending : D.ink,
                    ),
                  ),
                  Text(
                    fees.outstandingCount == 0
                        ? 'Nothing unpaid'
                        : '${fees.outstandingCount} '
                              '${fees.outstandingCount == 1 ? 'booking' : 'bookings'}',
                    style: D.caption.copyWith(
                      color: D.inkFaint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (fees.refundedPaise > 0) ...[
          SizedBox(height: D.s3),
          Text(
            '${FeeTotals(collectedPaise: fees.refundedPaise).collected} refunded, '
            'already taken off the figure above.',
            style: D.statLabel.copyWith(color: D.inkMuted),
          ),
        ],
      ],
    );
  }
}

/// What this report cannot tell them, said once.
class _NotRecorded extends StatelessWidget {
  const _NotRecorded({required this.fees});

  final FeeTotals fees;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.brandTint,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: D.iconLg, color: D.brand),
          SizedBox(width: D.s3),
          Expanded(
            child: Text(
              notRecordedLine(fees),
              style: D.statLabel.copyWith(color: D.brand, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Paid in the app for 11 of 286 consultations".
///
/// On the card, beside the money, because the money without it reads as the
/// practice's takings — and the desk's cash is not in this app.
@visibleForTesting
String feeCoverage(FeeTotals fees) {
  if (fees.consultations == 0) return '${fees.countedOf} charged in the app';
  return '${fees.countedOf} of ${fees.consultations} consultations';
}

/// "+₹4,200 vs before", or what the figures can honestly carry.
@visibleForTesting
String deltaMoney(FeeTotals fees) {
  final change = fees.collectedPaise - fees.previousCollectedPaise;
  if (fees.previousCollectedPaise == 0) {
    return change == 0 ? 'None before either' : 'Nothing to compare';
  }
  if (change == 0) return 'Same as before';
  final size = FeeTotals(collectedPaise: change.abs()).collected;
  return '${change > 0 ? '+' : '−'}$size vs before';
}

/// What the report cannot tell them, in the words that are true today.
///
/// Two separate facts, and they were one sentence while neither was recorded.
/// Fees are recorded now, but only the ones paid in the app — so the sentence
/// about them changed from "not recorded" to "not all of them", which is a
/// different warning and the one a doctor reading a takings figure needs.
@visibleForTesting
String notRecordedLine(FeeTotals fees) {
  const referrals =
      'Referrals are not on this report because nothing in the app records '
      'them — not because nobody was referred.';
  if (fees.isEmpty) {
    return 'Fees are not on this report because nothing was charged through '
        'the app in this window. Cash taken at the desk is not recorded '
        'anywhere in the app. $referrals';
  }
  return 'Fees count only what patients paid through the app. Cash taken at '
      'the desk is not recorded anywhere in the app, so this is not the '
      'practice\'s takings. $referrals';
}

/// "1 – 30 Sep 2026 · compared with 1 – 31 Aug".
@visibleForTesting
String comparedLine(ConsultationSummary r) {
  final sameMonth = r.from.month == r.to.month && r.from.year == r.to.year;
  final window = sameMonth
      ? '${r.from.day} – ${DateFormat('d MMM yyyy').format(r.to)}'
      : '${DateFormat('d MMM').format(r.from)} – ${DateFormat('d MMM yyyy').format(r.to)}';
  final before = '${DateFormat('d MMM').format(r.previousFrom)} – '
      '${DateFormat('d MMM').format(r.previousTo)}';
  return '$window · compared with $before';
}

/// "+12%", "+9", "Same as before" — whichever the figures can carry.
@visibleForTesting
String deltaLine(ReportCount count, String before) {
  if (count.previous == 0) {
    return count.value == 0 ? 'None $before either' : 'Nothing to compare';
  }
  if (count.change == 0) return 'Same as $before';
  final percent = count.percent;
  final sign = count.change > 0 ? '+' : '−';
  // A percentage of a handful is noise; the count itself is the honest figure.
  if (count.previous < 10 || percent == null) {
    return '$sign${count.change.abs()} vs $before';
  }
  return '$sign${percent.abs()}% vs $before';
}

@visibleForTesting
DeltaTone toneOf(ReportCount count, {required bool moreIsBetter}) {
  if (count.previous == 0 || count.change == 0) return DeltaTone.flat;
  final up = count.change > 0;
  return up == moreIsBetter ? DeltaTone.good : DeltaTone.bad;
}
