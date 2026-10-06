import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../appointments/domain/appointment.dart';
import '../../appointments/presentation/appointment_providers.dart';
import '../domain/appointment_book.dart';
import 'widgets/appointment_manage_sheet.dart';
import 'widgets/profile_parts.dart';

/// The doctor's own diary (`Appointments`).
///
/// ---- Two different readers --------------------------------------------- --
///
/// The front desk's diary at /staff/appointments runs the day: it rings
/// patients, writes to them, takes walk-ins. This one answers the doctor's
/// narrower questions — who is coming, who is still waiting for a time, and
/// can I move somebody — so it reads the same server a second way rather than
/// the desk's screen being bent to serve two people at once.
///
/// ---- Requests first --------------------------------------------------------
///
/// A patient who asked for a time and has not been given one is waiting on
/// somebody here, and is undated by definition, so requests sit above the day
/// list rather than behind a status filter. Giving one a time is the desk's
/// job and needs the slot grid, so this hands them over to the desk's screen
/// rather than offering half of it.
class DoctorAppointmentsScreen extends ConsumerStatefulWidget {
  const DoctorAppointmentsScreen({super.key});

  @override
  ConsumerState<DoctorAppointmentsScreen> createState() =>
      _DoctorAppointmentsScreenState();
}

class _DoctorAppointmentsScreenState
    extends ConsumerState<DoctorAppointmentsScreen> {
  DiaryScope _scope = DiaryScope.today;

  AppointmentQuery get _query {
    final bounds = boundsFor(_scope);
    return (from: bounds.from, to: bounds.to, status: null, clinicId: null);
  }

  static const AppointmentQuery _requests = (
    from: null,
    to: null,
    status: 'requested',
    clinicId: null,
  );

  void _reload() {
    ref.invalidate(appointmentDiaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final diary = ref.watch(appointmentDiaryProvider(_query));
    final requests = ref.watch(appointmentDiaryProvider(_requests));
    final waiting = requests.valueOrNull?.items ?? const <Appointment>[];

    return Scaffold(
      backgroundColor: D.ground,
      appBar: AppBar(
        backgroundColor: D.card,
        surfaceTintColor: D.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: D.line)),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(D.bar),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded, size: D.iconDisc),
          color: D.ink,
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Text('Appointments', style: D.screenTitle.copyWith(color: D.ink)),
      ),
      body: SafeArea(
        top: false,
        child: diary.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: D.brand)),
          error: (e, _) => ProfileFailed(error: e, onRetry: _reload),
          data: (paged) {
            final rows = paged.items;
            final stats = diaryStats(rows, waiting);
            final days = diaryDays(rows, newestFirst: _scope == DiaryScope.past);

            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
                children: [
                  if (waiting.isNotEmpty) ...[
                    _Waiting(rows: waiting),
                    SizedBox(height: D.s5),
                  ],
                  _Scopes(scope: _scope, onScope: (s) => setState(() => _scope = s)),
                  SizedBox(height: D.s4),
                  _Stats(stats: stats),
                  SizedBox(height: D.s5),
                  if (days.isEmpty)
                    ProfileEmpty(
                      text: switch (_scope) {
                        DiaryScope.today => 'Nothing booked for today.',
                        DiaryScope.upcoming => 'Nothing booked in the next two months.',
                        DiaryScope.past => 'Nothing in the last two months.',
                      },
                      icon: Icons.event_available_outlined,
                    )
                  else
                    for (final day in days.keys) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(D.s1, 0, D.s1, D.s2),
                        child: Row(
                          children: [
                            Expanded(
                              child: ProfileEyebrow(label: diaryDayLabel(day)),
                            ),
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
                                child: _BookingRow(
                                  appointment: a,
                                  onManage: () => _manage(a),
                                ),
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
    );
  }

  Future<void> _manage(Appointment a) async {
    final changed = await manageAppointment(context, (
      id: a.id,
      patientId: a.patientId,
      patientName: a.patientName,
      scheduledFor: a.scheduledFor,
      clinicId: a.clinicId,
      clinicName: a.clinicName,
      doctorName: a.doctorName,
    ));
    if (changed) _reload();
  }
}

/// Requests with no slot yet, oldest first.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.rows});

  final List<Appointment> rows;

  @override
  Widget build(BuildContext context) {
    // Oldest first: a request from last Tuesday that nobody answered is more
    // urgent than one from this morning, not less.
    final oldest = [...rows]
      ..sort(
        (a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)),
      );
    final shown = oldest.take(3).toList();

    return Container(
      padding: EdgeInsets.all(D.s5),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.pendingLine),
        boxShadow: D.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Waiting for a time',
                  style: D.subhead.copyWith(color: D.ink),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: D.badgeMin),
                padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.s1 / 2),
                decoration: const BoxDecoration(
                  color: D.pendingGround,
                  borderRadius: D.rPill,
                ),
                child: Text(
                  '${rows.length}',
                  textAlign: TextAlign.center,
                  style: D.badgeText.copyWith(color: D.pending),
                ),
              ),
            ],
          ),
          SizedBox(height: D.s1 / 2),
          Text(
            'Requests with no slot yet, oldest first',
            style: D.statLabel.copyWith(color: D.inkMuted),
          ),
          for (final a in shown) ...[
            SizedBox(height: D.s4),
            _RequestRow(appointment: a),
          ],
          if (rows.length > shown.length) ...[
            SizedBox(height: D.s2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                // Giving a request a time needs the slot grid and the desk's
                // own checks, and that screen already has both.
                onPressed: () => context.push('/clinician/appointments/desk'),
                style: TextButton.styleFrom(
                  foregroundColor: D.brand,
                  minimumSize: Size(
                    0,
                    MediaQuery.textScalerOf(context).scale(D.tap),
                  ),
                ),
                child: Text(
                  'View all ${rows.length}',
                  style: D.subtitle.copyWith(
                    color: D.brand,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final pref = preferenceLine(a);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: D.disc,
          height: D.disc,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: D.brandTint, shape: BoxShape.circle),
          child: Text(
            initialsOf(a.patientName ?? '?'),
            style: D.statLabel.copyWith(color: D.brand, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(width: D.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.patientName ?? 'Someone',
                style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w700),
              ),
              Text(askedLine(a), style: D.caption.copyWith(color: D.inkFaint)),
              if ((a.reason ?? '').trim().isNotEmpty) ...[
                SizedBox(height: D.s1 / 2),
                Text(a.reason!.trim(), style: D.statLabel.copyWith(color: D.inkMuted)),
              ],
              if (pref != null) ...[
                SizedBox(height: D.s1 / 2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Requested: ',
                        style: D.caption.copyWith(color: D.inkFaint),
                      ),
                      TextSpan(
                        text: pref,
                        style: D.caption.copyWith(
                          color: D.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Today / Upcoming / Past, in the artboard's sunken track.
class _Scopes extends StatelessWidget {
  const _Scopes({required this.scope, required this.onScope});

  final DiaryScope scope;
  final ValueChanged<DiaryScope> onScope;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s1),
      decoration: BoxDecoration(
        color: D.track,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Row(
        children: [
          for (final s in DiaryScope.values) ...[
            if (s != DiaryScope.values.first) SizedBox(width: D.s1),
            Expanded(
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                selected: s == scope,
                button: true,
                child: InkWell(
                  onTap: () => onScope(s),
                  borderRadius: BorderRadius.circular(D.s3),
                  child: Container(
                    height: MediaQuery.textScalerOf(context).scale(D.tap - D.s1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s == scope ? D.card : null,
                      borderRadius: BorderRadius.circular(D.s3),
                      boxShadow: s == scope ? D.lift : null,
                    ),
                    child: Text(
                      s.label,
                      style: D.dateLine.copyWith(
                        color: s == scope ? D.ink : D.inkMuted,
                        fontWeight: s == scope ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.stats});

  final ({int booked, int waiting, int cancelled}) stats;

  @override
  Widget build(BuildContext context) {
    final cells = <(String, int)>[
      ('Booked', stats.booked),
      ('Waiting', stats.waiting),
      ('Cancelled', stats.cancelled),
    ];

    return Row(
      children: [
        for (final (i, (label, n)) in cells.indexed) ...[
          if (i != 0) SizedBox(width: D.s2),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: D.s3, horizontal: D.s3),
              decoration: BoxDecoration(
                color: D.card,
                borderRadius: BorderRadius.circular(D.rCardLg),
                border: Border.all(color: D.line),
                boxShadow: D.lift,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$n', style: D.metric.copyWith(color: D.ink)),
                  Text(label, style: D.statLabel.copyWith(color: D.inkMuted)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.appointment, required this.onManage});

  final Appointment appointment;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final at = a.scheduledFor?.toLocal();
    final (label, bg, fg) = bookingState(a);
    final where = whereLine(a);
    // Nothing to move once it has happened or been called off.
    final movable = !a.isPast && a.status != 'cancelled' && a.status != 'completed';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: D.s8 + D.s5,
          child: Text(
            at == null ? '—' : DateFormat('h:mm a').format(at),
            style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(width: D.s2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.patientName ?? 'Someone',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
              ),
              if (where.isNotEmpty)
                Text(
                  where,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: D.caption.copyWith(color: D.inkFaint),
                ),
              // Only where the app is collecting for this visit. A line here
              // on every row would read as a bill on the ones the desk takes
              // cash for.
              if (a.fee.line != null)
                Text(
                  a.fee.line!,
                  style: D.caption.copyWith(
                    color: a.fee.paid ? D.done : D.pending,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              SizedBox(height: D.s1),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: D.s2,
                      vertical: D.s1 / 2,
                    ),
                    decoration: BoxDecoration(color: bg, borderRadius: D.rPill),
                    child: Text(
                      label,
                      style: D.caption.copyWith(color: fg, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  if (movable)
                    InkWell(
                      onTap: onManage,
                      borderRadius: BorderRadius.circular(D.s2),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: D.s1,
                          vertical: D.s1,
                        ),
                        child: Text(
                          'Manage',
                          style: D.dateLine.copyWith(
                            color: D.brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
