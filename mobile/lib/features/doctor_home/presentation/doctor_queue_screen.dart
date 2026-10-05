import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../clinician/data/clinician_repository.dart';
import '../../appointments/domain/clinic.dart';
import '../../clinician/domain/appointment.dart';
import '../../../shared/providers/core_providers.dart';
import '../../clinician/presentation/clinician_providers.dart';
import '../domain/patient_queue.dart';
import 'widgets/profile_parts.dart';
import 'widgets/queue_location_sheet.dart';

/// Today's waiting room (`Queue-List`).
///
/// ---- What a doctor needs from it -------------------------------------------
///
/// Who is in the room, who has been waiting longest, and one tap to start.
/// Everything else on this screen exists to answer the first question without
/// the doctor counting: the four figures at the top, the groups in the order
/// the room is called, and the person who is next marked as next.
///
/// It re-asks the server every half minute, because a queue read once is a
/// queue that is wrong by the time it is looked at — and says when it last
/// did, so a stale screen is visibly stale rather than quietly so.
class DoctorQueueScreen extends ConsumerStatefulWidget {
  const DoctorQueueScreen({super.key});

  @override
  ConsumerState<DoctorQueueScreen> createState() => _DoctorQueueScreenState();
}

class _DoctorQueueScreenState extends ConsumerState<DoctorQueueScreen> {
  Timer? _tick;
  DateTime _now = DateTime.now();
  String? _busyWith;

  /// The room being seen. Null until it is known — one location needs no
  /// asking, several do.
  String? _clinicId;
  bool _asked = false;

  /// null = everybody; otherwise the one group being shown.
  QueueStage? _only;

  @override
  void initState() {
    super.initState();
    // Two things move on their own here: the clock against which every wait is
    // measured, and the room itself.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      ref.invalidate(appointmentsTodayProvider);
    });
    _clinicId = QueueRoom(ref.read(sharedPreferencesProvider)).clinicId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _askWhichRoom());
  }

  /// Asks which waiting room this is, once a day, and only when there is more
  /// than one it could be.
  Future<void> _askWhichRoom({bool force = false}) async {
    if (_asked && !force) return;
    _asked = true;

    // The queue is the point; the room is a refinement of it. A practice
    // whose locations cannot be read still has patients waiting, so a failure
    // here means the question is not asked — never that the screen is empty.
    final List<Clinic> clinics;
    final List<Appointment> today;
    try {
      clinics = await ref.read(queueClinicsProvider.future);
      today = await ref.read(appointmentsTodayProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted) return;

    final rooms = locationsOf(clinics, today, now: DateTime.now());
    // One room is not a choice, and a practice with none has nothing to ask
    // about — in both cases the queue is simply the day.
    if (rooms.length < 2) {
      if (rooms.length == 1 && _clinicId == null) {
        setState(() => _clinicId = rooms.single.id);
      }
      return;
    }

    final room = QueueRoom(ref.read(sharedPreferencesProvider));
    if (!force && room.settledFor(DateTime.now()) && _clinicId != null) return;

    final chosen = await chooseQueueLocation(
      context,
      locations: rooms,
      current: _clinicId,
      onChosen: (clinicId, stopAsking) => room.choose(
        clinicId,
        stopAsking: stopAsking,
        day: DateTime.now(),
      ),
    );
    if (chosen != null && mounted) setState(() => _clinicId = chosen);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _move(Appointment a, String status, {String? then}) async {
    if (_busyWith != null) return;
    setState(() => _busyWith = a.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(clinicianRepositoryProvider)
          .setAppointmentStatus(appointmentId: a.id, status: status);
      ref.invalidate(appointmentsTodayProvider);
      if (!mounted) return;
      if (then != null) context.push(then, extra: a.patientName);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not move ${a.patientName}. $e')),
      );
    } finally {
      if (mounted) setState(() => _busyWith = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(appointmentsTodayProvider);

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
        title: Text('Patient queue', style: D.screenTitle.copyWith(color: D.ink)),
      ),
      body: SafeArea(
        top: false,
        child: today.when(
          loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
          error: (e, _) => ProfileFailed(
        error: e,
            onRetry: () => ref.invalidate(appointmentsTodayProvider),
          ),
          data: (everywhere) {
            // One room's queue. Anything with no room on it stays in the list:
            // an appointment the desk never assigned a location is still
            // somebody waiting, and hiding it is how they are forgotten.
            final all = _clinicId == null
                ? everywhere
                : [
                    for (final a in everywhere)
                      if (a.clinicId == null || a.clinicId == _clinicId) a,
                  ];
            final groups = queueGroups(all);
            final next = nextUp(all);
            final shown = _only == null
                ? QueueStage.values
                : [_only!];

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(appointmentsTodayProvider),
              child: ListView(
                padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.s8),
                children: [
                  if (_clinicId != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: D.s3),
                      child: _Room(
                        name: roomName(everywhere, _clinicId!),
                        onChange: () => _askWhichRoom(force: true),
                      ),
                    ),
                  _Stats(groups: groups, all: all, now: _now),
                  SizedBox(height: D.s4),
                  Wrap(
                    spacing: D.s2,
                    runSpacing: D.s2,
                    children: [
                      _Filter(
                        label: 'All · ${queueOrder(all).length}',
                        on: _only == null,
                        onTap: () => setState(() => _only = null),
                      ),
                      for (final stage in QueueStage.values)
                        if (groups[stage]!.isNotEmpty)
                          _Filter(
                            label: '${stage.title} · ${groups[stage]!.length}',
                            on: _only == stage,
                            onTap: () => setState(() => _only = stage),
                          ),
                    ],
                  ),
                  SizedBox(height: D.s4),
                  if (queueOrder(all).isEmpty)
                    const ProfileEmpty(
                      text: 'Nobody on today’s list yet.',
                      icon: Icons.groups_2_outlined,
                    ),
                  for (final stage in shown)
                    if (groups[stage]!.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.only(left: D.s1, bottom: D.s2),
                        child: Row(
                          children: [
                            Expanded(child: ProfileEyebrow(label: stage.title)),
                            Text(
                              '${groups[stage]!.length}',
                              style: D.chip.copyWith(color: D.inkFaint),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: D.s5),
                        decoration: BoxDecoration(
                          color: D.card,
                          borderRadius: BorderRadius.circular(D.rSection),
                          border: Border.all(
                            color: stage == QueueStage.inConsultation ? D.brand : D.line,
                            width: stage == QueueStage.inConsultation ? 1.5 : 1,
                          ),
                          boxShadow:
                              stage == QueueStage.inConsultation ? D.liftBrand : D.lift,
                        ),
                        child: Column(
                          children: [
                            for (final (i, a) in groups[stage]!.indexed)
                              _QueueRow(
                                appointment: a,
                                stage: stage,
                                first: i == 0,
                                isNext: next?.id == a.id,
                                busy: _busyWith == a.id,
                                now: _now,
                                onStart: () => _move(
                                  a,
                                  'in_consultation',
                                  then: '/clinician/patients/${a.patientId}/consult',
                                ),
                                onResume: () => context.push(
                                  '/clinician/patients/${a.patientId}/consult',
                                  extra: a.patientName,
                                ),
                                onDone: () => _move(a, 'completed'),
                                onOpen: () => context.push(
                                  '/clinician/patients/${a.patientId}',
                                  extra: a.patientName,
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
}

/// Which waiting room this is, and the way to the other one.
class _Room extends StatelessWidget {
  const _Room({required this.name, required this.onChange});

  final String? name;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(D.s4, D.s3, D.s2, D.s3),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rCard),
        border: Border.all(color: D.lineStrong),
      ),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, size: D.iconLg, color: D.brand),
          SizedBox(width: D.s3),
          Expanded(
            child: Text(
              name ?? 'This location',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(minimumSize: D.hug),
            child: Text('Change', style: D.dateLine.copyWith(color: D.brand)),
          ),
        ],
      ),
    );
  }
}

/// The name today's diary gives that room, since the queue already holds it.
@visibleForTesting
String? roomName(List<Appointment> today, String clinicId) {
  for (final a in today) {
    if (a.clinicId == clinicId && (a.clinicName ?? '').isNotEmpty) return a.clinicName;
  }
  return null;
}

/// The four figures the room is read by.
class _Stats extends StatelessWidget {
  const _Stats({required this.groups, required this.all, required this.now});

  final Map<QueueStage, List<Appointment>> groups;
  final List<Appointment> all;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final average = averageWait(all, now: now);
    final cells = <({String figure, String label, Color colour})>[
      (
        figure: '${groups[QueueStage.waiting]!.length}',
        label: 'Waiting',
        colour: groups[QueueStage.waiting]!.isEmpty ? D.ink : D.pending,
      ),
      (
        figure: '${groups[QueueStage.inConsultation]!.length}',
        label: 'In consult',
        colour: D.ink,
      ),
      (figure: '${groups[QueueStage.completed]!.length}', label: 'Completed', colour: D.ink),
      // Null rather than zero: nobody's arrival time known is not a nought-
      // minute wait.
      (figure: average == null ? '—' : '$average', label: 'Avg wait', colour: D.ink),
    ];

    return Container(
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rCard),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Row(
        children: [
          for (final (i, c) in cells.indexed)
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.s3),
                decoration: BoxDecoration(
                  border: i == 0 ? null : const Border(left: BorderSide(color: D.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.figure, style: D.tileFigure.copyWith(color: c.colour)),
                    SizedBox(height: D.s1 / 2),
                    Text(
                      c.label,
                      maxLines: 2,
                      style: D.caption.copyWith(color: D.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One person in the room.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.appointment,
    required this.stage,
    required this.first,
    required this.isNext,
    required this.busy,
    required this.now,
    required this.onStart,
    required this.onResume,
    required this.onDone,
    required this.onOpen,
  });

  final Appointment appointment;
  final QueueStage stage;
  final bool first;
  final bool isNext;
  final bool busy;
  final DateTime now;
  final VoidCallback onStart;
  final VoidCallback onResume;
  final VoidCallback onDone;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final meta = metaLine(a);
    final time = timeLine(a, now: now);
    final late = waitingTooLong(a, now: now);
    final (statusBg, statusFg) = switch (stage) {
      QueueStage.inConsultation => (D.brandTint, D.brand),
      QueueStage.waiting => (D.pendingGround, D.pending),
      QueueStage.notArrived => (D.track, D.inkMuted),
      QueueStage.completed => (D.doneGround, D.done),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: D.line)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: D.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Token(
                  number: a.queueNumber,
                  inConsultation: stage == QueueStage.inConsultation,
                ),
                SizedBox(width: D.s3),
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                a.patientName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: D.subtitle.copyWith(
                                  color: D.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isNext) ...[
                              SizedBox(width: D.s2),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: D.s2,
                                  vertical: D.s1 / 2,
                                ),
                                decoration: const BoxDecoration(
                                  color: D.brand,
                                  borderRadius: D.rPill,
                                ),
                                child: Text(
                                  'NEXT',
                                  style: D.chip.copyWith(color: D.onBrand),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (meta.isNotEmpty)
                          Text(meta, style: D.statLabel.copyWith(color: D.inkMuted)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: D.s2),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: D.gapIcon, vertical: D.s1),
                  decoration: BoxDecoration(color: statusBg, borderRadius: D.rPill),
                  child: Text(
                    stage.status,
                    style: D.caption.copyWith(color: statusFg, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (time != null) ...[
              SizedBox(height: D.s2),
              Padding(
                padding: EdgeInsets.only(left: D.disc + D.s3),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: D.iconSm,
                      color: late ? D.pending : D.inkFaint,
                    ),
                    SizedBox(width: D.gapTight),
                    // Flexible, because "Started 9:14 AM · 1 hr 26 min" is
                    // longer than the row at a large text size.
                    Flexible(
                      child: Text(
                        time,
                        style: D.statLabel.copyWith(
                          color: late ? D.pending : D.inkFaint,
                          fontWeight: late ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (stage != QueueStage.notArrived) ...[
              SizedBox(height: D.s3),
              Padding(
                padding: EdgeInsets.only(left: D.disc + D.s3),
                child: switch (stage) {
                  QueueStage.inConsultation => Row(
                    children: [
                      Expanded(
                        child: _Action(
                          label: 'Resume',
                          busy: busy,
                          onTap: onResume,
                          tone: _Tone.tonal,
                        ),
                      ),
                      SizedBox(width: D.s2),
                      Expanded(
                        child: _Action(
                          label: 'Done',
                          busy: busy,
                          onTap: onDone,
                          tone: _Tone.quiet,
                        ),
                      ),
                    ],
                  ),
                  QueueStage.waiting => _Action(
                    label: 'Start consultation',
                    busy: busy,
                    onTap: onStart,
                    tone: isNext ? _Tone.primary : _Tone.tonal,
                  ),
                  QueueStage.completed => _Action(
                    label: 'View record',
                    busy: busy,
                    onTap: onOpen,
                    tone: _Tone.quiet,
                  ),
                  QueueStage.notArrived => const SizedBox.shrink(),
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The number they were given at the desk.
class _Token extends StatelessWidget {
  const _Token({required this.number, required this.inConsultation});

  final int? number;
  final bool inConsultation;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.textScalerOf(context).scale(D.tap);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inConsultation ? D.brand : D.track,
        borderRadius: BorderRadius.circular(D.s3),
      ),
      child: number == null
          // Nobody has been given a token until they arrive, and a dash says
          // that better than a zero.
          ? Icon(Icons.remove_rounded, size: D.icon, color: D.inkFaint)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'NO.',
                  style: D.chip.copyWith(
                    color: inConsultation ? D.onBrandProse : D.inkFaint,
                  ),
                ),
                Text(
                  '$number',
                  style: D.subhead.copyWith(
                    color: inConsultation ? D.onBrand : D.ink,
                  ),
                ),
              ],
            ),
    );
  }
}

enum _Tone { primary, tonal, quiet }

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.busy,
    required this.onTap,
    required this.tone,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.textScalerOf(context).scale(D.disc);
    final child = busy
        ? SizedBox(
            width: D.icon,
            height: D.icon,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tone == _Tone.primary ? D.onBrand : D.brand,
            ),
          )
        : Text(label, style: D.subtitle.copyWith(fontWeight: FontWeight.w600));

    if (tone == _Tone.quiet) {
      return OutlinedButton(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: D.ink,
          side: const BorderSide(color: D.lineStrong),
          minimumSize: Size.fromHeight(height),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
        ),
        child: child,
      );
    }

    return FilledButton(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: tone == _Tone.primary ? D.brand : D.brandTint,
        foregroundColor: tone == _Tone.primary ? D.onBrand : D.brand,
        elevation: 0,
        minimumSize: Size.fromHeight(height),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
      ),
      child: child,
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({required this.label, required this.on, required this.onTap});

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
