import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/error_view.dart';
import '../../appointments/data/appointment_repository.dart';
import '../../appointments/domain/appointment.dart';
import '../../appointments/presentation/appointment_providers.dart';
import '../domain/appointment_book.dart';
import 'widgets/appointment_manage_sheet.dart';
import 'widgets/decline_request_sheet.dart';
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
/// list rather than behind a status filter.
///
/// Both answers are on the row. Giving a time opens the same sheet that moves
/// a booking — it already reads the published slots and already refuses one
/// the server has since filled — and turning a request down is a cancel of a
/// row that never had an hour, which is exactly what the server calls it.
/// Sending a doctor to the desk's screen for either was sending them away
/// from the only screen that had told them somebody was waiting.
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
            // Out of the rows already in hand, not a second request: a
            // declined request is a cancelled row with no hour, and this
            // scope's rows are where it is.
            final declined = declinedRequests(rows);
            final days = diaryDays(rows, newestFirst: _scope == DiaryScope.past);

            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
                children: [
                  if (waiting.isNotEmpty) ...[
                    _Waiting(
                      rows: waiting,
                      onAssign: _assign,
                      onDecline: _decline,
                    ),
                    SizedBox(height: D.s5),
                  ],
                  _Scopes(scope: _scope, onScope: (s) => setState(() => _scope = s)),
                  SizedBox(height: D.s4),
                  _Stats(stats: stats, scope: _scope),
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
                  if (declined.isNotEmpty) ...[
                    SizedBox(height: D.s4),
                    _Declined(rows: declined, onAssign: _assign),
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
    final changed = await manageAppointment(context, _booking(a));
    if (changed) _reload();
  }

  /// Giving a request the hour it asked for.
  ///
  /// The same sheet, opened fresh: a request has no `scheduledFor`, so there
  /// is no "new date" to contrast with and no slot to release. The sheet
  /// already handles that case — it is how a missed appointment is re-booked.
  Future<void> _assign(Appointment a) async {
    final changed = await bookAgain(context, _booking(a));
    if (changed) _reload();
  }

  /// Turning a request down.
  ///
  /// Asked before it happens, because the patient is told: the server writes a
  /// line into their thread and sends them a push, and neither can be taken
  /// back. The reason is optional and goes to the patient as written, so the
  /// sheet says so rather than letting somebody type a note to themselves.
  Future<void> _decline(Appointment a) async {
    final reason = await declineRequest(context, a.patientName ?? 'this patient');
    if (reason == null || !mounted) return;

    try {
      await ref
          .read(appointmentRepositoryProvider)
          .cancel(a.id, reason: reason.isEmpty ? null : reason);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${a.patientName ?? 'The patient'} has been told, and asked to '
            'request another day.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorView.messageFor(context, e))),
      );
    }
  }

  Booking _booking(Appointment a) => (
    id: a.id,
    patientId: a.patientId,
    patientName: a.patientName,
    scheduledFor: a.scheduledFor,
    clinicId: a.clinicId,
    clinicName: a.clinicName,
    doctorName: a.doctorName,
  );
}

/// Requests with no slot yet, oldest first.
class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.rows,
    required this.onAssign,
    required this.onDecline,
  });

  final List<Appointment> rows;
  final ValueChanged<Appointment> onAssign;
  final ValueChanged<Appointment> onDecline;

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
            _RequestRow(
              appointment: a,
              onAssign: () => onAssign(a),
              onDecline: () => onDecline(a),
            ),
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
  const _RequestRow({
    required this.appointment,
    required this.onAssign,
    required this.onDecline,
  });

  final Appointment appointment;
  final VoidCallback onAssign;
  final VoidCallback onDecline;

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
              SizedBox(height: D.s3),
              // Expanded on both and no Spacer between them: the two would
              // split the row with the buttons and leave each label
              // ellipsised beside blank space.
              Row(
                children: [
                  Expanded(
                    child: _RequestAction(
                      label: 'Assign time',
                      onTap: onAssign,
                      primary: true,
                    ),
                  ),
                  SizedBox(width: D.s2),
                  Expanded(
                    child: _RequestAction(
                      label: 'Decline',
                      onTap: onDecline,
                      primary: false,
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

/// One of the two answers to a request.
///
/// Both are buttons rather than one button and one text link: turning somebody
/// down is a decision, not an escape hatch, and a quiet link beside a filled
/// button is read as "the thing you do when you cannot do the real thing".
class _RequestAction extends StatelessWidget {
  const _RequestAction({
    required this.label,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.textScalerOf(context).scale(D.disc);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(D.s3),
    );
    final text = D.subtitle.copyWith(fontWeight: FontWeight.w600);

    if (!primary) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: D.ink,
          side: const BorderSide(color: D.lineStrong),
          minimumSize: Size.fromHeight(height),
          shape: shape,
        ),
        child: Text(label, style: text),
      );
    }
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: D.brand,
        foregroundColor: D.onBrand,
        elevation: 0,
        minimumSize: Size.fromHeight(height),
        shape: shape,
      ),
      child: Text(label, style: text),
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
  const _Stats({required this.stats, required this.scope});

  final ({int booked, int waiting, int cancelled}) stats;
  final DiaryScope scope;

  @override
  Widget build(BuildContext context) {
    final cells = <(String, int)>[
      ('Booked', stats.booked),
      ('Waiting', stats.waiting),
      (cancelledLabel(scope), stats.cancelled),
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

/// The requests that were turned down — folded away, because they are closed.
///
/// ---- Why they are here at all --------------------------------------------
///
/// A request declined by mistake had nowhere to be seen from. The patient was
/// told, the row left the waiting list, and the only way back was the desk's
/// screen and a search by name. Collapsed, so a list of things that need
/// nothing does not sit above the day that does, and openable, so a doctor who
/// declined the wrong row can still give that person a time.
class _Declined extends StatefulWidget {
  const _Declined({required this.rows, required this.onAssign});

  final List<Appointment> rows;
  final ValueChanged<Appointment> onAssign;

  @override
  State<_Declined> createState() => _DeclinedState();
}

class _DeclinedState extends State<_Declined> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;

    return Container(
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      padding: EdgeInsets.symmetric(horizontal: D.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              constraints: BoxConstraints(
                minHeight: MediaQuery.textScalerOf(context).scale(D.rowH),
              ),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Declined requests (${rows.length})',
                      style: D.row.copyWith(
                        color: D.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: D.iconLg,
                    color: D.inkFaint,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            for (final a in rows)
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: D.line)),
                ),
                padding: EdgeInsets.symmetric(vertical: D.s3),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.patientName ?? 'Someone',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: D.subtitle.copyWith(
                              color: D.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            // What they asked for, since there is no hour to
                            // name — and the reason, where one was given, as
                            // the patient read it.
                            [
                              preferenceLine(a) ?? askedLine(a),
                              if ((a.cancellationReason ?? '').trim().isNotEmpty)
                                a.cancellationReason!.trim(),
                            ].join(' · '),
                            style: D.caption.copyWith(color: D.inkFaint),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: D.s2),
                    TextButton(
                      onPressed: () => widget.onAssign(a),
                      style: TextButton.styleFrom(
                        foregroundColor: D.brand,
                        minimumSize: Size(
                          0,
                          MediaQuery.textScalerOf(context).scale(D.tap),
                        ),
                      ),
                      child: Text(
                        // Not "undecline": the patient has already been told
                        // they were turned down. Giving them a time now is a
                        // new booking, and the server makes a new row for it.
                        'Give a time',
                        style: D.subtitle.copyWith(
                          color: D.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (_open) SizedBox(height: D.s2),
        ],
      ),
    );
  }
}
