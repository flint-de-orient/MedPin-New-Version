import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../clinician/data/clinician_repository.dart';
import '../../clinician/domain/appointment.dart';
import 'widgets/profile_parts.dart';

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
    .family<List<Appointment>, ({int days, String? status})>((ref, args) {
      final now = DateTime.now();
      return ref
          .watch(clinicianRepositoryProvider)
          .appointmentHistory(
            from: DateTime(now.year, now.month, now.day - args.days),
            to: now,
            status: args.status,
          );
    });

class _DoctorHistoryScreenState extends ConsumerState<DoctorHistoryScreen> {
  final _search = TextEditingController();
  HistoryFilter _filter = HistoryFilter.all;
  HistoryWindow _window = HistoryWindow.quarter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(
      historyProvider((days: _window.days, status: _filter.status)),
    );
    final typed = _search.text.trim();

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
              onWindow: (w) => setState(() => _window = w),
              onFilter: (f) => setState(() => _filter = f),
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
                          Padding(
                            padding: EdgeInsets.fromLTRB(D.s1, 0, D.s1, D.s2),
                            child: Row(
                              children: [
                                Expanded(child: ProfileEyebrow(label: dayLabel(day))),
                                Text(
                                  '${days[day]!.length}',
                                  style: D.chip.copyWith(color: D.inkFaint),
                                ),
                              ],
                            ),
                          ),
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
                                for (final (i, a) in days[day]!.indexed)
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
                          SizedBox(height: D.s4),
                        ],
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
  });

  final TextEditingController search;
  final HistoryWindow window;
  final HistoryFilter filter;
  final VoidCallback onSearch;
  final ValueChanged<HistoryWindow> onWindow;
  final ValueChanged<HistoryFilter> onFilter;

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
          Text('History', style: D.greeting.copyWith(color: D.ink)),
          SizedBox(height: D.s1 / 2),
          Text('All your past appointments', style: D.body.copyWith(color: D.inkMuted)),
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
        if (a.clinicName != null || minutes != null)
          Text(
            [
              if (a.clinicName != null) a.clinicName!,
              if (minutes != null) '$minutes min',
            ].join(' · '),
            style: D.caption.copyWith(color: D.inkFaint),
          ),
      ],
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
@visibleForTesting
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
