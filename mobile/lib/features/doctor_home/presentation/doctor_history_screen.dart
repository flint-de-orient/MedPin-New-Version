import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../clinician/data/clinician_repository.dart';
import '../../clinician/domain/appointment.dart';
import 'widgets/profile_parts.dart';
import 'widgets/report_export.dart';

/// Every past appointment, newest first (`Doctor-History`).
///
/// ---- The diary, read backwards ---------------------------------------------
///
/// The queue is today and the reports are counts; this is the list itself —
/// who was booked, what became of it, and the way back to what was written. It
/// reads the same diary the rest of the app reads, asked for a window instead
/// of a day.
///
/// ---- What the design shows that this cannot --------------------------------
///
/// A "Rescheduled" filter. Moving an appointment changes its time in place —
/// there is no such status and nothing records that it moved — so a chip for it
/// would select nothing forever. The four that are real are here.
class DoctorHistoryScreen extends ConsumerStatefulWidget {
  const DoctorHistoryScreen({super.key});

  @override
  ConsumerState<DoctorHistoryScreen> createState() => _DoctorHistoryScreenState();
}

/// The outcomes an appointment can have had.
enum HistoryFilter { all, completed, missed, cancelled }

extension HistoryFilterText on HistoryFilter {
  String get label => switch (this) {
    HistoryFilter.all => 'All',
    HistoryFilter.completed => 'Completed',
    HistoryFilter.missed => 'Missed',
    HistoryFilter.cancelled => 'Cancelled',
  };

  String? get status => switch (this) {
    HistoryFilter.all => null,
    HistoryFilter.completed => 'completed',
    HistoryFilter.missed => 'no_show',
    HistoryFilter.cancelled => 'cancelled',
  };
}

/// How far back to look.
enum HistoryWindow { month, quarter, year }

extension HistoryWindowText on HistoryWindow {
  String get label => switch (this) {
    HistoryWindow.month => '1 month',
    HistoryWindow.quarter => '3 months',
    HistoryWindow.year => '1 year',
  };

  int get days => switch (this) {
    HistoryWindow.month => 30,
    HistoryWindow.quarter => 90,
    HistoryWindow.year => 365,
  };
}

final historyProvider = FutureProvider.autoDispose
    .family<List<Appointment>, ({int days, String? status, int limit})>((ref, args) {
      final now = DateTime.now();
      return ref
          .watch(clinicianRepositoryProvider)
          .appointmentHistory(
            from: DateTime(now.year, now.month, now.day - args.days),
            to: now,
            status: args.status,
            limit: args.limit,
          );
    });

/// How many of a day's appointments are shown before the day is folded.
const _perDay = 5;

/// How many the server is asked for at a time.
const _page = 200;

class _DoctorHistoryScreenState extends ConsumerState<DoctorHistoryScreen> {
  final _search = TextEditingController();
  HistoryFilter _filter = HistoryFilter.all;
  HistoryWindow _window = HistoryWindow.quarter;

  /// Days the doctor has opened up, and how many rows have been asked for.
  final _opened = <DateTime>{};
  int _limit = _page;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(
      historyProvider((days: _window.days, status: _filter.status, limit: _limit)),
    );
    final typed = _search.text.trim();
    final loaded = rows.valueOrNull;

    return Scaffold(
      backgroundColor: D.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              search: _search,
              window: _window,
              filter: _filter,
              onSearch: () => setState(() {}),
              onWindow: (w) => setState(() {
                _window = w;
                _opened.clear();
                _limit = _page;
              }),
              onFilter: (f) => setState(() {
                _filter = f;
                _opened.clear();
                _limit = _page;
              }),
              onDownload: loaded == null || loaded.isEmpty
                  ? null
                  : () => shareTable(
                      context,
                      filename: historyFilename(_window.days),
                      csv: historyCsv(matching(loaded, typed)),
                    ),
            ),
            Expanded(
              child: rows.when(
                loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
                error: (e, _) => ProfileFailed(
        error: e,
                  onRetry: () => ref.invalidate(historyProvider),
                ),
                data: (all) {
                  final shown = matching(all, typed);
                  if (shown.isEmpty) {
                    return ProfileEmpty(
                      text: typed.isEmpty
                          // Which is a fact about the diary, not a failure: a
                          // consultation written straight from a record leaves
                          // a prescription and no appointment behind it.
                          ? 'No appointments in the last ${_window.label}. '
                                'Only booked appointments appear here.'
                          : 'Nobody matching “$typed” in the last ${_window.label}.',
                      icon: Icons.history_rounded,
                    );
                  }
                  final days = byDay(shown);
                  final now = DateTime.now();
                  final windowStart = DateTime(now.year, now.month, now.day - _window.days);
                  // The month cards are a breakdown by outcome, so they are
                  // only honest with every outcome in the list. A filtered
                  // list would show one bar at 100% and call it the month.
                  final months = _filter == HistoryFilter.all && typed.isEmpty
                      ? monthOpeners(days.keys)
                      : const <DateTime>{};

                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(historyProvider),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
                      children: [
                        if (typed.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(left: D.s1, bottom: D.s3),
                            child: Text(
                              // Said plainly: this searched what was loaded for
                              // the window, not the whole diary.
                              '${shown.length} in the last ${_window.label}',
                              style: D.statLabel.copyWith(color: D.inkFaint),
                            ),
                          ),
                        for (final day in days.keys) ...[
                          if (months.contains(day)) ...[
                            _MonthCard(
                              month: DateTime(day.year, day.month),
                              rows: shown,
                              windowStart: windowStart,
                            ),
                            SizedBox(height: D.s4),
                          ],
                          Padding(
                            padding: EdgeInsets.fromLTRB(D.s1, 0, D.s1, D.s2),
                            child: Row(
                              children: [
                                Expanded(child: ProfileEyebrow(label: dayLabel(day))),
                                Text(
                                  countLine(days[day]!.length),
                                  style: D.chip.copyWith(color: D.inkFaint),
                                ),
                              ],
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              final dayRows = days[day]!;
                              final open = _opened.contains(day);
                              final shownRows = open
                                  ? dayRows
                                  : dayRows.take(_perDay).toList();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: D.s4),
                                    decoration: BoxDecoration(
                                      color: D.card,
                                      borderRadius: BorderRadius.circular(D.rSection),
                                      border: Border.all(color: D.line),
                                      boxShadow: D.lift,
                                    ),
                                    child: Column(
                                      children: [
                                        for (final (i, a) in shownRows.indexed)
                                          ProfileRow(
                                            first: i == 0,
                                            onTap: () => context.push(
                                              '/clinician/patients/${a.patientId}',
                                              extra: a.patientName,
                                            ),
                                            child: _HistoryRow(appointment: a),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (!open && dayRows.length > _perDay)
                                    _MoreButton(
                                      label: 'Show ${dayRows.length - _perDay} more from '
                                          '${DateFormat('d MMM').format(day)}',
                                      onTap: () => setState(() => _opened.add(day)),
                                    ),
                                ],
                              );
                            },
                          ),
                          SizedBox(height: D.s4),
                        ],
                        // Only when the server filled the page, because that
                        // is the only time there might be more behind it.
                        if (all.length >= _limit)
                          _MoreButton(
                            label: 'Show more',
                            onTap: () => setState(() => _limit += _page),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.search,
    required this.window,
    required this.filter,
    required this.onSearch,
    required this.onWindow,
    required this.onFilter,
    required this.onDownload,
  });

  final TextEditingController search;
  final HistoryWindow window;
  final HistoryFilter filter;
  final VoidCallback onSearch;
  final ValueChanged<HistoryWindow> onWindow;
  final ValueChanged<HistoryFilter> onFilter;

  /// Null until there is a list to hand over.
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final searching = search.text.isNotEmpty;

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
                    Text('History', style: D.greeting.copyWith(color: D.ink)),
                    SizedBox(height: D.s1 / 2),
                    Text(
                      'All your past appointments',
                      style: D.body.copyWith(color: D.inkMuted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: D.s3),
              ExportButton(label: 'Download', onPressed: onDownload),
            ],
          ),
          SizedBox(height: D.cardPad),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: MediaQuery.textScalerOf(context).scale(D.disc),
                  padding: EdgeInsets.symmetric(horizontal: D.s4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(D.rCard),
                    border: Border.all(
                      color: searching ? D.brand : D.lineStrong,
                      width: searching ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, size: D.iconMd, color: D.inkFaint),
                      SizedBox(width: D.gapIcon),
                      Expanded(
                        child: TextField(
                          key: const Key('h-search'),
                          controller: search,
                          onChanged: (_) => onSearch(),
                          style: D.subtitle.copyWith(color: D.ink),
                          decoration: D.bareField(
                            hint: 'Search patient',
                            hintStyle: D.subtitle.copyWith(color: D.inkFaint),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: D.s2),
              PopupMenuButton<HistoryWindow>(
                tooltip: 'How far back',
                initialValue: window,
                onSelected: onWindow,
                itemBuilder: (_) => [
                  for (final w in HistoryWindow.values)
                    PopupMenuItem(value: w, child: Text(w.label)),
                ],
                child: Container(
                  height: MediaQuery.textScalerOf(context).scale(D.disc),
                  padding: EdgeInsets.symmetric(horizontal: D.s3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(D.rCard),
                    border: Border.all(color: D.lineStrong),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: D.icon,
                        color: D.inkMuted,
                      ),
                      SizedBox(width: D.gapTight),
                      Text(window.label, style: D.dateLine.copyWith(color: D.ink)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: D.s3),
          // Four, not the design's five: there is no "rescheduled" to select.
          Wrap(
            spacing: D.s2,
            runSpacing: D.s2,
            children: [
              for (final f in HistoryFilter.values)
                _Chip(label: f.label, on: f == filter, onTap: () => onFilter(f)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final (label, bg, fg) = outcomeOf(a);
    final minutes = a.calledAt != null && a.completedAt != null
        ? a.completedAt!.difference(a.calledAt!).inMinutes
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                a.patientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(width: D.s2),
            Container(
              padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.s1 / 2),
              decoration: BoxDecoration(color: bg, borderRadius: D.rPill),
              child: Text(
                label,
                style: D.caption.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        SizedBox(height: D.s1 / 2),
        Text(detailOf(a), style: D.statLabel.copyWith(color: D.inkMuted)),
        SizedBox(height: D.s1 / 2),
        Row(
          children: [
            Expanded(
              child: Text(
                [
                  if (a.clinicName != null) a.clinicName!,
                  if (minutes != null) '$minutes min',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: D.caption.copyWith(color: D.inkFaint),
              ),
            ),
            SizedBox(width: D.s2),
            _RowLink(appointment: a),
          ],
        ),
      ],
    );
  }
}

/// The link at the end of a row, which is a different offer per outcome.
///
/// A visit that happened has something written from it; one that did not has
/// only the record behind it. Naming the link after what is actually there is
/// the difference between an affordance and a dead end.
class _RowLink extends StatelessWidget {
  const _RowLink({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final completed = a.status == 'completed';
    final label = completed ? 'Prescription' : 'View record';

    return Semantics(
      button: true,
      label: '$label for ${a.patientName}',
      child: InkWell(
        borderRadius: BorderRadius.circular(D.s2),
        onTap: () => context.push(
          completed
              ? '/clinician/patients/${a.patientId}?tab=prescriptions'
              : '/clinician/patients/${a.patientId}',
          extra: a.patientName,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: D.s1, vertical: D.s1),
          child: Text(
            label,
            style: D.dateLine.copyWith(color: D.brand, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// A month the list has crossed into, and what became of it.
///
/// The counts are of the rows in this list, which is the window the doctor
/// chose — so a month the window only partly covers says which day it counts
/// from rather than passing a slice off as the month.
class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.month,
    required this.rows,
    required this.windowStart,
  });

  final DateTime month;
  final List<Appointment> rows;
  final DateTime windowStart;

  @override
  Widget build(BuildContext context) {
    final n = monthCounts(rows, month);
    if (n.total == 0) return const SizedBox.shrink();
    // The window started after this month did, so the list holds only part
    // of it and the card says from when.
    final partial = windowStart.isAfter(month);
    final bars = <(String, int, Color)>[
      ('Completed', n.completed, D.brand),
      ('Missed', n.missed, D.danger),
      ('Cancelled', n.cancelled, D.lineStrong),
      ('Other', n.other, D.pending),
    ];

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
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(month),
                  style: D.subhead.copyWith(color: D.ink),
                ),
              ),
              Text(
                partial
                    ? '${n.total} since ${DateFormat('d MMM').format(windowStart)}'
                    : countLine(n.total),
                style: D.statLabel.copyWith(color: D.inkFaint),
              ),
            ],
          ),
          SizedBox(height: D.s3),
          Semantics(
            label: '${n.total} appointments: ${n.completed} completed, '
                '${n.missed} missed, ${n.cancelled} cancelled',
            child: ClipRRect(
              borderRadius: D.rPill,
              child: SizedBox(
                height: D.s2,
                child: Row(
                  children: [
                    for (final (_, count, colour) in bars)
                      if (count > 0)
                        Expanded(flex: count, child: ColoredBox(color: colour)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: D.s3),
          Wrap(
            spacing: D.s4,
            runSpacing: D.s2,
            children: [
              for (final (label, count, colour) in bars)
                if (count > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: D.s2,
                        height: D.s2,
                        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
                      ),
                      SizedBox(width: D.gapTight),
                      Text('$label ', style: D.statLabel.copyWith(color: D.inkMuted)),
                      Text(
                        '$count',
                        style: D.statLabel.copyWith(
                          color: D.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Show 8 more from 30 Sep", and the one at the foot of the list.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: D.brand,
        minimumSize: Size(0, MediaQuery.textScalerOf(context).scale(D.tap)),
      ),
      child: Text(
        label,
        style: D.subtitle.copyWith(color: D.brand, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? D.brand : D.card,
      borderRadius: D.rPill,
      child: InkWell(
        onTap: onTap,
        borderRadius: D.rPill,
        child: Container(
          constraints: BoxConstraints(
            minHeight: MediaQuery.textScalerOf(context).scale(D.tap),
          ),
          padding: EdgeInsets.symmetric(horizontal: D.s4),
          decoration: BoxDecoration(
            borderRadius: D.rPill,
            border: Border.all(color: on ? D.brand : D.lineStrong),
          ),
          child: Align(
            widthFactor: 1,
            child: Text(
              label,
              style: D.dateLine.copyWith(color: on ? D.onBrand : D.inkMuted),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================== reading ====

/// Only the ones whose name matches, when something has been typed.
///
/// It searches the window that was loaded, which is what the line above the
/// list says — not the whole diary, which would need the server's own search.
@visibleForTesting
List<Appointment> matching(List<Appointment> all, String typed) {
  if (typed.trim().isEmpty) return all;
  final needle = typed.toLowerCase().trim();
  return [
    for (final a in all)
      if (a.patientName.toLowerCase().contains(needle)) a,
  ];
}

/// Grouped by the day they were booked for, newest day first.
@visibleForTesting
Map<DateTime, List<Appointment>> byDay(List<Appointment> all) {
  final out = <DateTime, List<Appointment>>{};
  for (final a in all) {
    final at = a.scheduledFor;
    if (at == null) continue;
    final day = DateTime(at.year, at.month, at.day);
    (out[day] ??= []).add(a);
  }
  return out;
}

/// "1 appointment", "13 appointments".
@visibleForTesting
String countLine(int n) => n == 1 ? '1 appointment' : '$n appointments';

/// The days a month card is drawn above.
///
/// The first day of each month the list crosses into — once per month, not
/// once per day in it — and never the month still running: a summary of a
/// month half finished reads as the month's total, and the figure a doctor
/// would quote from it would be wrong by however much of it is left.
@visibleForTesting
Set<DateTime> monthOpeners(Iterable<DateTime> days, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final current = DateTime(today.year, today.month);
  final seen = <DateTime>{};
  final out = <DateTime>{};
  for (final d in days) {
    final month = DateTime(d.year, d.month);
    if (month == current || !seen.add(month)) continue;
    out.add(d);
  }
  return out;
}

/// What became of one month's appointments, counted from the list on screen.
@visibleForTesting
({int total, int completed, int missed, int cancelled, int other}) monthCounts(
  List<Appointment> rows,
  DateTime month,
) {
  var total = 0, completed = 0, missed = 0, cancelled = 0, other = 0;
  for (final a in rows) {
    final at = a.scheduledFor;
    if (at == null || at.year != month.year || at.month != month.month) continue;
    total++;
    switch (a.status) {
      case 'completed':
        completed++;
      case 'no_show':
        missed++;
      case 'cancelled':
        cancelled++;
      default:
        other++;
    }
  }
  return (
    total: total,
    completed: completed,
    missed: missed,
    cancelled: cancelled,
    other: other,
  );
}

/// "Today", "Yesterday", "Wed, 30 Sep".
@visibleForTesting
String dayLabel(DateTime day, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(today.year, today.month, today.day).difference(day).inDays;
  if (days == 0) return 'Today, ${DateFormat('d MMM').format(day)}';
  if (days == 1) return 'Yesterday, ${DateFormat('d MMM').format(day)}';
  return DateFormat('EEE, d MMM').format(day);
}

/// What became of it, as a word and the colours that carry it.
/// Also read by the export, so the file and the screen agree on the word.
(String, Color, Color) outcomeOf(Appointment a) => switch (a.status) {
  'completed' => ('Completed', D.doneGround, D.done),
  'no_show' => ('Missed', D.dangerGround, D.danger),
  'cancelled' => ('Cancelled', D.track, D.inkMuted),
  'in_consultation' => ('In consultation', D.brandTint, D.brand),
  'checked_in' => ('Waiting', D.pendingGround, D.pending),
  _ => ('Booked', D.track, D.inkMuted),
};

/// "9:10 AM · Follow-up", from what the diary holds.
@visibleForTesting
String detailOf(Appointment a) {
  final at = a.scheduledFor;
  final reason = (a.reason ?? '').trim();
  return [
    if (at != null) DateFormat('h:mm a').format(at),
    if (reason.isNotEmpty) reason,
    if (a.mode == 'teleconsult') 'Video',
  ].join(' · ');
}
