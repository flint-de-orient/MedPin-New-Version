import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/submission_keys.dart';
import '../../../../core/theme/doctor_tokens.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../appointments/data/appointment_repository.dart';
import '../../../appointments/domain/clinic.dart';
import '../../../appointments/presentation/appointment_providers.dart';
import '../../domain/appointment_book.dart';

/// Moving or calling off one booking (`Appointments-Manage`).
///
/// ---- Why the slots are fetched rather than offered ------------------------
///
/// The grid is the clinic's published schedule for the chosen day, with the
/// times somebody already holds struck through and untappable. A reschedule
/// sheet that let the doctor type a time would produce double bookings the
/// front desk discovers when two people arrive at once — so the only times
/// offered are times the server says are free, and the server checks again
/// when the move is sent.
///
/// A booking with no location has no published day to read, so this offers the
/// cancel and says plainly that the move has to happen where the schedule is.
///
/// One booking, named without either Appointment class.
///
/// The doctor's diary and the doctor's history read two different models of
/// the same row — one from the appointments feature, one from the clinician's
/// — and this sheet is opened from both. What it needs is these six fields, so
/// that is what it asks for, and neither caller has to convert into the
/// other's model to use it.
typedef Booking = ({
  String id,
  String? patientId,
  String? patientName,
  DateTime? scheduledFor,
  String? clinicId,
  String? clinicName,
  String? doctorName,
});

/// Returns true when something changed, so the diary behind it can reload.
Future<bool> manageAppointment(BuildContext context, Booking booking) =>
    _open(context, booking, fresh: false);

/// A new appointment for a patient whose last one was missed or called off.
///
/// Not a reschedule: the server refuses to move anything completed, cancelled
/// or missed, and is right to — the old row is what happened, and overwriting
/// it would lose that. This books a second one.
Future<bool> bookAgain(BuildContext context, Booking booking) =>
    _open(context, booking, fresh: true);

Future<bool> _open(
  BuildContext context,
  Booking booking, {
  required bool fresh,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: D.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
    ),
    builder: (_) => _ManageSheet(booking: booking, fresh: fresh),
  );
  return changed ?? false;
}

class _ManageSheet extends ConsumerStatefulWidget {
  const _ManageSheet({required this.booking, required this.fresh});

  final Booking booking;

  /// True to book a second appointment, false to move this one.
  final bool fresh;

  @override
  ConsumerState<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends ConsumerState<_ManageSheet> {
  /// Made once when the sheet opens, so a tap that times out and is retried is
  /// the same move to the server rather than a second booking.
  final _submission = SubmissionKeys();

  late final List<DateTime> _days = rescheduleDays();
  late DateTime _day = _days.first;
  Slot? _slot;
  bool _busy = false;
  String? _failed;

  Booking get _a => widget.booking;

  bool get _fresh => widget.fresh;

  @override
  Widget build(BuildContext context) {
    final clinicId = _a.clinicId;
    final at = _a.scheduledFor?.toLocal();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
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
              Text(
                _fresh ? 'Book again' : 'Manage appointment',
                style: D.opening.copyWith(color: D.ink),
              ),
              SizedBox(height: D.s1),
              Text(
                [
                  _a.patientName ?? 'This patient',
                  if (at != null) DateFormat('h:mm a').format(at),
                  if ((_a.doctorName ?? '').isNotEmpty) _a.doctorName!,
                ].join(' · '),
                style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
              ),
              Text(
                [
                  if (at != null) diaryDayLabel(DateTime(at.year, at.month, at.day)),
                  if ((_a.clinicName ?? '').isNotEmpty) _a.clinicName!,
                ].join(' · '),
                style: D.statLabel.copyWith(color: D.inkMuted),
              ),
              SizedBox(height: D.s5),

              if (clinicId == null)
                _Note(
                  text: _fresh
                      ? 'This appointment had no location on it, so there is no '
                            'published day to book into. The front desk can book '
                            'one at a location.'
                      : 'This booking has no location on it, so there is no '
                            'published day to move it into. The front desk can '
                            'give it a location, or it can be called off here.',
                )
              else ...[
                _Eyebrow(_fresh ? 'Date' : 'New date'),
                SizedBox(height: D.s2),
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(D.tap - D.s2),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: _days.length,
                    separatorBuilder: (_, _) => SizedBox(width: D.s2),
                    itemBuilder: (context, i) => _DayChip(
                      day: _days[i],
                      on: _days[i] == _day,
                      onTap: () => setState(() {
                        _day = _days[i];
                        _slot = null;
                      }),
                    ),
                  ),
                ),
                SizedBox(height: D.s5),
                _Eyebrow('Time · ${DateFormat('EEE d MMM').format(_day)}'),
                SizedBox(height: D.s2),
                _Slots(
                  clinicId: clinicId,
                  day: _day,
                  chosen: _slot,
                  onPick: (s) => setState(() => _slot = s),
                ),
              ],

              if (_failed != null) ...[
                SizedBox(height: D.s4),
                _Note(text: _failed!, bad: true),
              ],

              SizedBox(height: D.s5),
              if (clinicId != null)
                FilledButton(
                  onPressed: _slot == null || _busy ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: D.brand,
                    disabledBackgroundColor: D.track,
                    foregroundColor: D.onBrand,
                    disabledForegroundColor: D.inkFaint,
                    minimumSize: Size(
                      0,
                      MediaQuery.textScalerOf(context).scale(D.inputH),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(D.rCard),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: D.icon,
                          height: D.icon,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: D.onBrand,
                          ),
                        )
                      : Text(
                          _slot == null
                              ? (_fresh ? 'Pick a time' : 'Pick a time to move it')
                              : (_fresh
                                    ? 'Book ${_slot!.time}'
                                    : 'Reschedule to ${_slot!.time}'),
                          style: D.bodyStrong.copyWith(color: D.onBrand),
                        ),
                ),
              if (!_fresh) ...[
                SizedBox(height: D.s3),
                TextButton(
                  onPressed: _busy ? null : _callOff,
                  style: TextButton.styleFrom(
                    foregroundColor: D.danger,
                    minimumSize: Size(
                      0,
                      MediaQuery.textScalerOf(context).scale(D.tap),
                    ),
                  ),
                  child: Text(
                    'Cancel appointment',
                    style: D.bodyStrong.copyWith(color: D.danger),
                  ),
                ),
                Text(
                  '${_a.patientName ?? 'The patient'} will be told, and the slot '
                  'opens for others.',
                  textAlign: TextAlign.center,
                  style: D.caption.copyWith(color: D.inkFaint),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send() async {
    final slot = _slot;
    if (slot == null) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final repo = ref.read(appointmentRepositoryProvider);
      if (_fresh) {
        await repo.book(
          clinicId: _a.clinicId,
          scheduledForIso: slot.iso,
          patientId: _a.patientId,
          submission: _submission,
        );
      } else {
        await repo.reschedule(_a.id, slot.iso, submission: _submission);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }

  Future<void> _callOff() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: D.card,
        title: Text(
          'Cancel this appointment?',
          style: D.subhead.copyWith(color: D.ink),
        ),
        content: Text(
          '${_a.patientName ?? 'The patient'} will be told it is off. '
          'Moving it instead keeps them in the diary.',
          style: D.body.copyWith(color: D.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep it', style: D.bodyStrong.copyWith(color: D.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Cancel it',
              style: D.bodyStrong.copyWith(color: D.danger),
            ),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      await ref
          .read(appointmentRepositoryProvider)
          .cancel(_a.id, submission: _submission);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }
}

/// The published times for one day, as the artboard draws them.
class _Slots extends ConsumerWidget {
  const _Slots({
    required this.clinicId,
    required this.day,
    required this.chosen,
    required this.onPick,
  });

  final String clinicId;
  final DateTime day;
  final Slot? chosen;
  final ValueChanged<Slot> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(
      slotDayProvider((clinicId: clinicId, date: dateKey(day))),
    );

    return slots.when(
      loading: () => Padding(
        padding: EdgeInsets.symmetric(vertical: D.s5),
        child: const Center(child: CircularProgressIndicator(color: D.brand)),
      ),
      error: (e, _) => _Note(text: ErrorView.messageFor(context, e), bad: true),
      data: (dayslots) {
        if (dayslots.slots.isEmpty) {
          return _Note(
            // A closed day and a full day are different answers, and the
            // doctor acts differently on each.
            text: dayslots.isActive
                ? 'Nothing published for this day.'
                : 'The clinic is closed on this day.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: D.s2,
              runSpacing: D.s2,
              children: [
                for (final s in dayslots.slots)
                  _SlotChip(slot: s, on: s.iso == chosen?.iso, onTap: () => onPick(s)),
              ],
            ),
            SizedBox(height: D.s2),
            Text(
              'Crossed-out times are already booked.',
              style: D.caption.copyWith(color: D.inkFaint),
            ),
          ],
        );
      },
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slot, required this.on, required this.onTap});

  final Slot slot;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final taken = !slot.available;
    return Semantics(
      button: !taken,
      selected: on,
      label: taken ? '${slot.time}, already booked' : slot.time,
      child: Material(
        color: on ? D.brandTint : (taken ? D.track : D.card),
        borderRadius: BorderRadius.circular(D.rCard),
        child: InkWell(
          onTap: taken ? null : onTap,
          borderRadius: BorderRadius.circular(D.rCard),
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(D.tap),
            ),
            padding: EdgeInsets.symmetric(horizontal: D.s4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.rCard),
              border: Border.all(
                color: on ? D.brand : (taken ? D.track : D.lineStrong),
                width: on ? 1.5 : 1,
              ),
            ),
            child: Align(
              widthFactor: 1,
              child: Text(
                slot.time,
                style: D.dateLine.copyWith(
                  color: on ? D.brand : (taken ? D.inkFaint : D.ink),
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  decoration: taken ? TextDecoration.lineThrough : null,
                  decorationColor: D.inkFaint,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.on, required this.onTap});

  final DateTime day;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                DateFormat('EEE d MMM').format(day),
                style: D.dateLine.copyWith(color: on ? D.onBrand : D.inkMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: D.statLabel.copyWith(color: D.ink, fontWeight: FontWeight.w700),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.bad = false});

  final String text;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: bad ? D.dangerGround : D.track,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Text(
        text,
        style: D.statLabel.copyWith(
          color: bad ? D.danger : D.inkMuted,
          height: 1.45,
        ),
      ),
    );
  }
}
