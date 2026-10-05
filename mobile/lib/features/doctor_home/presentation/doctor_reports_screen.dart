import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../domain/consultation_report.dart';
import 'widgets/profile_parts.dart';
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
/// ---- Two of the artboard's cards are not here ------------------------------
///
/// Fees collected and referrals. Nothing in this system records either — the
/// money it knows about is the practice's own subscription, not a consultation
/// fee — so the screen says so once, plainly, rather than showing ₹0 and a
/// referral count of nothing.
class DoctorReportsScreen extends ConsumerStatefulWidget {
  const DoctorReportsScreen({super.key});

  @override
  ConsumerState<DoctorReportsScreen> createState() => _DoctorReportsScreenState();
}

class _DoctorReportsScreenState extends ConsumerState<DoctorReportsScreen> {
  ReportRange _range = ReportRange.month;
  DateTimeRange? _custom;

  ({DateTime from, DateTime to}) get _window => windowFor(_range, custom: _custom);

  @override
  Widget build(BuildContext context) {
    final window = _window;
    final summary = ref.watch(consultationSummaryProvider((from: window.from, to: window.to)));

    return Scaffold(
      backgroundColor: D.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              range: _range,
              window: window,
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
                          child: DailyBars(days: report.perDay),
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
                      const ProfileEyebrow(label: 'Detailed reports'),
                      SizedBox(height: D.s2),
                      _Registers(window: window),
                      SizedBox(height: D.s4),
                      const _NotRecorded(),
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

class _Header extends StatelessWidget {
  const _Header({required this.range, required this.window, required this.onRange});

  final ReportRange range;
  final ({DateTime from, DateTime to}) window;
  final ValueChanged<ReportRange> onRange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.cardPad),
      decoration: const BoxDecoration(
        color: D.card,
        border: Border(bottom: BorderSide(color: D.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reports', style: D.greeting.copyWith(color: D.ink)),
          SizedBox(height: D.s1 / 2),
          Text('Your consultation MIS', style: D.body.copyWith(color: D.inkMuted)),
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

  final ({DateTime from, DateTime to}) window;

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

/// What this report cannot tell them, said once.
class _NotRecorded extends StatelessWidget {
  const _NotRecorded();

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
              'Fees and referrals are not on this report because nothing in the app '
              'records them yet — not because they were nil.',
              style: D.statLabel.copyWith(color: D.brand, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
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
