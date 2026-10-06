import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/error_view.dart';
import '../../appointments/data/clinic_repository.dart';
import '../../appointments/domain/clinic.dart';
import '../../appointments/domain/doctor_hours.dart';
import '../../appointments/presentation/appointment_providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/weekly_schedule.dart';
import '../../clinician/data/practice_repository.dart';
import '../../clinician/domain/practice.dart';

import 'widgets/live_fields.dart';
import 'widgets/not_on_file.dart';
import 'widgets/profile_parts.dart';

/// When this doctor sits, and how long they give each patient
/// (`Profile-Schedule`).
///
/// ---- Why it is per location -----------------------------------------------
///
/// Because the server keeps it per location, and so does the day: a doctor who
/// is at Salt Lake on Monday mornings and New Town on Thursday evenings has two
/// diaries, not one with a note. The chips across the top are the locations
/// this practice has, and everything below them belongs to the chosen one.
///
/// ---- Two scopes on one screen --------------------------------------------
///
/// The hours and the slot rules are this doctor's at this location. The
/// booking rules below them are the practice's — one set, wherever the doctor
/// is sitting, because a patient who may cancel two hours before at Salt Lake
/// and not at New Town is a patient who rings the desk to ask which. The
/// screen says which is which rather than letting a doctor believe they have
/// closed booking at one room.
///
/// Video is a location on the board, with its own chip and its own hours. It
/// is not one here: a teleconsult has no `Clinic` row, so there is nowhere for
/// video hours to live. That chip stays inert.
class DoctorScheduleScreen extends ConsumerStatefulWidget {
  const DoctorScheduleScreen({super.key, this.clinicId});

  /// Which location to open on. Null opens the first one.
  final String? clinicId;

  @override
  ConsumerState<DoctorScheduleScreen> createState() =>
      _DoctorScheduleScreenState();
}

class _DoctorScheduleScreenState extends ConsumerState<DoctorScheduleScreen> {
  String? _clinicId;

  /// The working copy. Null until a location's hours have been read, so an
  /// edit is never applied to a diary that has not loaded.
  List<WeeklyHour>? _hours;
  int _slotMinutes = 15;
  int _patientsPerSlot = 1;
  int _walkInPlaces = 0;
  int _breakMinutes = 0;

  /// The practice's, edited here because the board puts them here. Null until
  /// the practice has been read.
  PracticeRules? _rules;

  bool _dirty = false;
  bool _saving = false;
  String? _failed;

  @override
  void initState() {
    super.initState();
    _clinicId = widget.clinicId;
  }

  @override
  Widget build(BuildContext context) {
    final clinics = ref.watch(clinicsProvider);
    final rooms = [
      for (final c in clinics.valueOrNull ?? const <Clinic>[])
        if (c.isActive) c,
    ];
    final chosen = _clinicId ?? (rooms.isEmpty ? null : rooms.first.id);

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Schedules and slots',
              style: D.screenTitle.copyWith(color: D.ink),
            ),
            Text(
              'Set separately for each location',
              style: D.statLabel.copyWith(color: D.inkMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('sched-save'),
            onPressed: _dirty && !_saving && chosen != null ? () => _save(chosen) : null,
            style: TextButton.styleFrom(
              foregroundColor: D.brand,
              disabledForegroundColor: D.inkFaint,
            ),
            child: _saving
                ? const SizedBox(
                    width: D.icon,
                    height: D.icon,
                    child: CircularProgressIndicator(strokeWidth: 2, color: D.brand),
                  )
                : Text(
                    'Save',
                    style: D.bodyStrong.copyWith(
                      color: _dirty ? D.brand : D.inkFaint,
                    ),
                  ),
          ),
          SizedBox(width: D.s2),
        ],
      ),
      body: SafeArea(
        top: false,
        child: clinics.when(
          loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
          error: (e, _) => ProfileFailed(
            error: e,
            onRetry: () => ref.invalidate(clinicsProvider),
          ),
          data: (_) => rooms.isEmpty
              ? const ProfileEmpty(
                  text: 'This practice has no open location yet, so there are '
                      'no hours to publish and nobody can book a time.',
                  icon: Icons.event_busy_outlined,
                )
              : _Editor(
                  key: ValueKey(chosen),
                  rooms: rooms,
                  clinicId: chosen!,
                  onPickRoom: (id) => setState(() {
                    _clinicId = id;
                    _hours = null;
                    _dirty = false;
                    _failed = null;
                  }),
                  hours: _hours,
                  slotMinutes: _slotMinutes,
                  patientsPerSlot: _patientsPerSlot,
                  walkInPlaces: _walkInPlaces,
                  breakMinutes: _breakMinutes,
                  rules: _rules,
                  failed: _failed,
                  onLoaded: _adopt,
                  onRules: _adoptRules,
                  onChanged: (hours, slot) => setState(() {
                    _hours = hours;
                    _slotMinutes = slot;
                    _dirty = true;
                  }),
                  onSlotRule: (patients, walkIns, gap) => setState(() {
                    _patientsPerSlot = patients;
                    _walkInPlaces = walkIns;
                    _breakMinutes = gap;
                    _dirty = true;
                  }),
                ),
        ),
      ),
    );
  }

  /// Take the server's copy as the working one, after the frame that read it.
  void _adopt(DoctorHours hours) {
    if (_hours != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hours != null) return;
      setState(() {
        _hours = [...hours.weeklyHours];
        _slotMinutes = hours.slotMinutes ?? 15;
        _patientsPerSlot = hours.patientsPerSlot;
        _walkInPlaces = hours.walkInPlaces;
        _breakMinutes = hours.breakMinutes;
      });
    });
  }

  /// The practice's rules, taken once. After the frame that read them, for the
  /// same reason as the hours.
  void _adoptRules(PracticeRules rules) {
    if (_rules != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _rules != null) return;
      setState(() => _rules = rules);
    });
  }

  Future<void> _save(String clinicId) async {
    final hours = _hours;
    final doctorId = ref.read(authControllerProvider).user?.id;
    if (hours == null || doctorId == null) return;

    setState(() {
      _saving = true;
      _failed = null;
    });
    try {
      final result = await ref
          .read(clinicRepositoryProvider)
          .setDoctorHours(
            clinicId,
            doctorId,
            slotMinutes: _slotMinutes,
            weeklyHours: hours,
            patientsPerSlot: _patientsPerSlot,
            walkInPlaces: _walkInPlaces,
            breakMinutes: _breakMinutes,
          );
      ref.invalidate(locationHoursProvider(clinicId));

      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      // The server checks the doctor's other locations and says where this
      // clashes. Swallowing that is how somebody is booked in two buildings
      // at nine o'clock on a Tuesday.
      final clash = result.overlaps;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            clash.isEmpty
                ? 'Hours saved'
                : 'Saved, but this clashes with ${clash.first.locationName}'
                      '${clash.length > 1 ? ' and ${clash.length - 1} more' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }
}

/// The chosen location's week, once its hours have been read.
class _Editor extends ConsumerWidget {
  const _Editor({
    super.key,
    required this.rooms,
    required this.clinicId,
    required this.onPickRoom,
    required this.hours,
    required this.slotMinutes,
    required this.patientsPerSlot,
    required this.walkInPlaces,
    required this.breakMinutes,
    required this.rules,
    required this.failed,
    required this.onLoaded,
    required this.onRules,
    required this.onChanged,
    required this.onSlotRule,
  });

  final List<Clinic> rooms;
  final String clinicId;
  final ValueChanged<String> onPickRoom;
  final List<WeeklyHour>? hours;
  final int slotMinutes;
  final int patientsPerSlot;
  final int walkInPlaces;
  final int breakMinutes;

  /// The practice's booking rules, or null while they load.
  final PracticeRules? rules;

  final String? failed;
  final ValueChanged<DoctorHours> onLoaded;
  final ValueChanged<PracticeRules> onRules;
  final void Function(List<WeeklyHour>, int) onChanged;

  /// patients per slot, walk-in places, break — all three, so the screen's
  /// state moves in one step rather than three rebuilds.
  final void Function(int, int, int) onSlotRule;


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctorId = ref.watch(authControllerProvider).user?.id;
    final loaded = ref.watch(locationHoursProvider(clinicId));

    return loaded.when(
      loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
      error: (e, _) => ProfileFailed(
        error: e,
        onRetry: () => ref.invalidate(locationHoursProvider(clinicId)),
      ),
      data: (location) {
        final mine = location.doctors.where((d) => d.doctorId == doctorId).firstOrNull;
        if (mine != null) onLoaded(mine);
        final practice = ref.watch(practiceOverviewProvider).valueOrNull;
        if (practice != null) onRules(practice.rules);
        final week = hours;
        final everyMinutes = slotMinutes + breakMinutes;

        return ListView(
          padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
          children: [
            if (rooms.length > 1) ...[
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(D.tap + D.s3),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: rooms.length + 1,
                  separatorBuilder: (_, _) => SizedBox(width: D.s2),
                  itemBuilder: (context, i) => i == rooms.length
                      // Video is a location on the board. It is not one here:
                      // a teleconsult has no clinic row for hours to live on.
                      ? const _RoomChip.pending(label: 'Video')
                      : _RoomChip(
                          clinic: rooms[i],
                          on: rooms[i].id == clinicId,
                          onTap: () => onPickRoom(rooms[i].id),
                        ),
                ),
              ),
              SizedBox(height: D.s5),
            ],

            if (week == null)
              const Center(child: CircularProgressIndicator(color: D.brand))
            else ...[
              Row(
                children: [
                  Expanded(
                    child: ProfileEyebrow(
                      label: 'WEEKLY HOURS · ${location.location.name.toUpperCase()}',
                    ),
                  ),
                  if (week.isNotEmpty)
                    TextButton(
                      onPressed: () => _copyAcross(context, week),
                      style: TextButton.styleFrom(
                        foregroundColor: D.brand,
                        minimumSize: D.hug,
                        padding: EdgeInsets.symmetric(horizontal: D.s2),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Copy hours',
                        style: D.dateLine.copyWith(
                          color: D.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: D.s2),
              ProfileGroup(
                children: [
                  for (final day in weekOrder)
                    ProfileRow(
                      first: day == weekOrder.first,
                      onTap: () => _editDay(context, week, day),
                      child: Row(
                        children: [
                          SizedBox(
                            width: D.s8 + D.s4,
                            child: Text(
                              dayName(day),
                              style: D.body.copyWith(
                                color: D.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              dayHoursLine(week, day),
                              style: D.body.copyWith(
                                color: hoursOn(week, day).isEmpty
                                    ? D.inkFaint
                                    : D.inkMuted,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: D.iconLg,
                            color: D.inkFaint,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              SizedBox(height: D.s2),
              Padding(
                padding: EdgeInsets.only(left: D.s1),
                child: Text(
                  summaryLine(week, slotMinutes),
                  style: D.statLabel.copyWith(color: D.inkMuted),
                ),
              ),
              SizedBox(height: D.s6),

              const ProfileEyebrow(label: 'SLOTS'),
              SizedBox(height: D.s2),
              ProfileGroup(
                children: [
                  ProfileRow(
                    first: true,
                    child: _Stepper(
                      title: 'Slot length',
                      sub: 'Time you plan per patient',
                      value: '$slotMinutes min',
                      onLess: slotMinutes <= 5
                          ? null
                          : () => onChanged(week, slotMinutes - 5),
                      onMore: slotMinutes >= 120
                          ? null
                          : () => onChanged(week, slotMinutes + 5),
                    ),
                  ),
                  StepperField(
                    title: 'Patients per slot',
                    sub: 'More than 1 lets you double-book',
                    value: patientsPerSlot,
                    min: 1,
                    max: 10,
                    onChanged: (v) =>
                        onSlotRule(v ?? 1, walkInPlaces, breakMinutes),
                  ),
                  StepperField(
                    title: 'Walk-in places',
                    sub: 'Kept free each session',
                    value: walkInPlaces,
                    min: 0,
                    max: 50,
                    onChanged: (v) =>
                        onSlotRule(patientsPerSlot, v ?? 0, breakMinutes),
                  ),
                  StepperField(
                    title: 'Break between patients',
                    sub: 'For notes and hand-wash',
                    value: breakMinutes,
                    min: 0,
                    max: 60,
                    step: 5,
                    unit: ' min',
                    onChanged: (v) =>
                        onSlotRule(patientsPerSlot, walkInPlaces, v ?? 0),
                  ),
                ],
              ),
              SizedBox(height: D.s6),

              // A patient starts every slot plus the break after the last
              // one, so a 15-minute slot with a 5-minute break is one every
              // 20. The preview has to be cut the same way the server cuts it
              // or it is a picture of a different day.
              if (hoursOn(week, nextOpenDay(week) ?? 1).isNotEmpty) ...[
                ProfileEyebrow(
                  label: 'SLOT PREVIEW · ${dayName(nextOpenDay(week)!).toUpperCase()}',
                ),
                SizedBox(height: D.s2),
                _Preview(
                  times: previewSlots(week, nextOpenDay(week)!, everyMinutes),
                  total: countSlots(week, nextOpenDay(week)!, everyMinutes),
                  perSlot: patientsPerSlot,
                  walkIns: walkInPlaces,
                ),
                SizedBox(height: D.s6),
              ],
            ],

            const ProfileEyebrow(label: 'BOOKING RULES'),
            SizedBox(height: D.s2),
            if (rules == null)
              const ProfileGroup(
                children: [
                  ProfileRow(
                    first: true,
                    child: Center(
                      child: SizedBox(
                        width: D.icon,
                        height: D.icon,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: D.brand,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              // Shown, not edited. They are the practice's, and one setting
              // with two editors is a setting that ends up disagreeing with
              // itself — see doctor_care_rules_screen.dart.
              ProfileGroup(
                children: [
                  ProfileLink(
                    first: true,
                    title: 'Online booking',
                    value: rules!.onlineBooking ? 'Open' : 'Closed',
                    onTap: () => context.push('/clinician/more/care'),
                  ),
                  ProfileLink(
                    title: 'Open booking',
                    value: rules!.windowLine,
                    onTap: () => context.push('/clinician/more/care'),
                  ),
                  ProfileLink(
                    title: 'Cancel or reschedule',
                    value: rules!.cancelLine,
                    onTap: () => context.push('/clinician/more/care'),
                  ),
                ],
              ),
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                // Said plainly: the three above are not this room's. A doctor
                // who closes booking here has closed it everywhere.
                'These three are the practice\u2019s and apply at every '
                'location \u2014 tap one to change them. The hours and slots '
                'above are yours, here.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
            SizedBox(height: D.s6),

            // ---- Leave and holidays -------------------------------------
            //
            // The board's last section, on the board's own screen. It also has
            // its own row on the hub, as the board does — both reach the same
            // closures.
            const ProfileEyebrow(label: 'LEAVE AND HOLIDAYS'),
            SizedBox(height: D.s2),
            _Leave(clinicId: clinicId, location: location.location),
            SizedBox(height: D.s6),

            if (failed != null) ...[
              Container(
                padding: EdgeInsets.all(D.s4),
                decoration: BoxDecoration(
                  color: D.dangerGround,
                  borderRadius: BorderRadius.circular(D.rCard),
                ),
                child: Text(
                  failed!,
                  style: D.statLabel.copyWith(color: D.danger, height: 1.45),
                ),
              ),
              SizedBox(height: D.s5),
            ],

            const PendingNote(what: 'video as a location of its own'),
          ],
        );
      },
    );
  }

  /// One day's windows, edited.
  Future<void> _editDay(
    BuildContext context,
    List<WeeklyHour> week,
    int day,
  ) async {
    final existing = hoursOn(week, day);
    final picked = await showModalBottomSheet<List<WeeklyHour>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: D.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
      ),
      builder: (_) => _DaySheet(day: day, windows: existing),
    );
    if (picked == null) return;
    onChanged(withDay(week, day, picked), slotMinutes);
  }

  /// Give every open day the hours of the first one.
  Future<void> _copyAcross(BuildContext context, List<WeeklyHour> week) async {
    final from = nextOpenDay(week);
    if (from == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: D.card,
        title: Text(
          'Copy ${dayName(from)}’s hours?',
          style: D.subhead.copyWith(color: D.ink),
        ),
        content: Text(
          'Monday to Saturday will all take ${dayHoursLine(week, from)}. '
          'Sunday is left closed.',
          style: D.body.copyWith(color: D.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: D.bodyStrong.copyWith(color: D.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Copy', style: D.bodyStrong.copyWith(color: D.brand)),
          ),
        ],
      ),
    );
    if (sure != true) return;
    onChanged(copiedAcross(week, from), slotMinutes);
  }
}

/// The days this room is shut, and the way to add more.
///
/// ---- Two of the board's words are not true here ---------------------------
///
/// It says a leave covers "all locations" and that "14 patients will be told".
/// A closure hangs on a location, so taking a week off is marking it at each
/// of them; and nothing tells anybody — a booking already made survives the
/// closure and the desk still has to ring. Both are said as they are, because
/// a doctor who believes their patients have been told is a doctor who does
/// not ring them.
class _Leave extends ConsumerWidget {
  const _Leave({required this.clinicId, required this.location});

  final String clinicId;
  final Clinic location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closures = upcomingClosures(location.overrides);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileGroup(
          children: [
            if (closures.isEmpty)
              ProfileRow(
                first: true,
                child: Text(
                  'No days closed at ${location.name}.',
                  style: D.row.copyWith(color: D.inkMuted),
                ),
              )
            else
              for (final (i, o) in closures.take(3).indexed)
                ProfileRow(
                  first: i == 0,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          closureLine(o.date),
                          style: D.row.copyWith(color: D.ink),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: D.s2,
                          vertical: D.s1 / 2,
                        ),
                        decoration: const BoxDecoration(
                          color: D.pendingGround,
                          borderRadius: D.rPill,
                        ),
                        child: Text(
                          'Closed',
                          style: D.caption.copyWith(
                            color: D.pending,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ProfileLink(
              title: closures.isEmpty ? 'Add leave' : 'All leave at this location',
              onTap: () =>
                  context.push('/clinician/more/leave?clinicId=$clinicId'),
            ),
          ],
        ),
        SizedBox(height: D.s2),
        Padding(
          padding: EdgeInsets.only(left: D.s1),
          child: Text(
            'Leave is per location, and nobody is told: an appointment already '
            'booked on a closed day stands, and the desk still has to ring '
            'those patients.',
            style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({required this.clinic, required this.on, required this.onTap})
    : label = null;

  /// A location the board has and the record cannot hold — video.
  const _RoomChip.pending({required this.label})
    : clinic = null,
      on = false,
      onTap = null;

  final Clinic? clinic;
  final bool on;
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (clinic == null) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: D.s4),
        decoration: BoxDecoration(
          borderRadius: D.rPill,
          border: Border.all(color: D.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label!, style: D.dateLine.copyWith(color: D.inkFaint)),
            SizedBox(width: D.s2),
            const NotOnFile(),
          ],
        ),
      );
    }
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: on,
      button: true,
      child: Material(
        color: on ? D.brand : D.card,
        borderRadius: D.rPill,
        child: InkWell(
          onTap: onTap,
          borderRadius: D.rPill,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: D.s4),
            decoration: BoxDecoration(
              borderRadius: D.rPill,
              border: Border.all(color: on ? D.brand : D.lineStrong),
            ),
            child: Align(
              widthFactor: 1,
              child: Text(
                clinic!.name,
                style: D.dateLine.copyWith(color: on ? D.onBrand : D.inkMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A figure with a minus and a plus, as the artboard draws every slot setting.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.title,
    required this.sub,
    required this.value,
    required this.onLess,
    required this.onMore,
  });

  final String title;
  final String sub;
  final String value;
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: D.body.copyWith(color: D.ink)),
              Text(sub, style: D.statLabel.copyWith(color: D.inkFaint)),
            ],
          ),
        ),
        SizedBox(width: D.s2),
        _Round(icon: Icons.remove_rounded, onTap: onLess, label: 'Less $title'),
        SizedBox(
          width: D.s8 + D.s4,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w700),
          ),
        ),
        _Round(icon: Icons.add_rounded, onTap: onMore, label: 'More $title'),
      ],
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: onTap == null ? D.track : D.brandTint,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: D.tap,
            height: D.tap,
            child: Icon(
              icon,
              size: D.iconMd,
              color: onTap == null ? D.inkFaint : D.brand,
            ),
          ),
        ),
      ),
    );
  }
}

/// What the day's slots come out as, so the settings can be checked before
/// a patient is the one who finds out.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.times,
    required this.total,
    required this.perSlot,
    required this.walkIns,
  });

  final List<String> times;
  final int total;
  final int perSlot;

  /// Held back from the published list, off the end of the sitting: a doctor
  /// who runs late loses the end of the session, not the morning.
  final int walkIns;

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
          Wrap(
            spacing: D.s2,
            runSpacing: D.s2,
            children: [
              for (final t in times)
                Container(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.textScalerOf(context).scale(D.tap - D.s2),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: D.s3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(D.rCard),
                    border: Border.all(color: D.lineStrong),
                  ),
                  child: Text(t, style: D.dateLine.copyWith(color: D.ink)),
                ),
            ],
          ),
          SizedBox(height: D.s3),
          Text(
            slotPreviewLine(
              slots: total,
              shown: times.length,
              perSlot: perSlot,
              walkIns: walkIns,
            ),
            style: D.statLabel.copyWith(color: D.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// One day's sittings: add, change or clear them.
class _DaySheet extends StatefulWidget {
  const _DaySheet({required this.day, required this.windows});

  final int day;
  final List<WeeklyHour> windows;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  late List<WeeklyHour> _windows = [...widget.windows];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: D.s8 + D.s3,
                height: D.s1,
                decoration: const BoxDecoration(
                  color: D.lineStrong,
                  borderRadius: D.rPill,
                ),
              ),
            ),
            SizedBox(height: D.s4),
            Text(dayName(widget.day), style: D.opening.copyWith(color: D.ink)),
            Text(
              _windows.isEmpty
                  ? 'Closed — nobody can book this day'
                  : 'Patients can book inside these hours',
              style: D.statLabel.copyWith(color: D.inkMuted),
            ),
            SizedBox(height: D.s5),
            for (final (i, w) in _windows.indexed)
              ProfileRow(
                first: i == 0,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${clock(w.start)} – ${clock(w.end)}',
                        style: D.body.copyWith(color: D.ink),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _edit(i),
                      child: Text(
                        'Change',
                        style: D.dateLine.copyWith(color: D.brand),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove these hours',
                      icon: const Icon(Icons.close_rounded, size: D.iconMd),
                      color: D.inkFaint,
                      onPressed: () => setState(() => _windows.removeAt(i)),
                    ),
                  ],
                ),
              ),
            SizedBox(height: D.s3),
            OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded, size: D.iconMd),
              label: Text(
                _windows.isEmpty ? 'Open this day' : 'Add another sitting',
                style: D.bodyStrong.copyWith(color: D.brand),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: D.brand,
                side: const BorderSide(color: D.lineStrong),
                minimumSize: Size(
                  0,
                  MediaQuery.textScalerOf(context).scale(D.inputH),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(D.rCard),
                ),
              ),
            ),
            SizedBox(height: D.s4),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_windows),
              style: FilledButton.styleFrom(
                backgroundColor: D.brand,
                foregroundColor: D.onBrand,
                minimumSize: Size(
                  0,
                  MediaQuery.textScalerOf(context).scale(D.inputH),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(D.rCard),
                ),
              ),
              child: Text('Done', style: D.bodyStrong.copyWith(color: D.onBrand)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    final start = await _ask('Starts at', const TimeOfDay(hour: 9, minute: 0));
    if (start == null || !mounted) return;
    final end = await _ask('Ends at', TimeOfDay(hour: (start.hour + 4) % 24, minute: start.minute));
    if (end == null) return;
    final added = WeeklyHour(
      dayOfWeek: widget.day,
      start: hhmm(start),
      end: hhmm(end),
    );
    // Refused rather than stored: the server validates it too, and a sitting
    // that ends before it starts publishes no slots at all.
    if (!endsAfterStart(added)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The end has to be after the start.')),
        );
      }
      return;
    }
    setState(() => _windows = sortedWindows([..._windows, added]));
  }

  Future<void> _edit(int index) async {
    final current = _windows[index];
    final start = await _ask('Starts at', fromHhmm(current.start));
    if (start == null || !mounted) return;
    final end = await _ask('Ends at', fromHhmm(current.end));
    if (end == null) return;
    final changed = WeeklyHour(
      dayOfWeek: widget.day,
      start: hhmm(start),
      end: hhmm(end),
    );
    if (!endsAfterStart(changed)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The end has to be after the start.')),
        );
      }
      return;
    }
    setState(() {
      final next = [..._windows]..[index] = changed;
      _windows = sortedWindows(next);
    });
  }

  Future<TimeOfDay?> _ask(String label, TimeOfDay initial) => showTimePicker(
    context: context,
    initialTime: initial,
    helpText: label.toUpperCase(),
  );
}
