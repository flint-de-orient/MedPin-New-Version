import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../appointments/domain/clinic.dart';
import '../../../appointments/domain/clinic_status.dart';
import '../../../appointments/presentation/appointment_providers.dart';
import '../../../clinician/domain/appointment.dart';
import '../../domain/patient_queue.dart';
import 'profile_parts.dart';

/// "Which queue are you seeing?" (`Queue-Select`).
///
/// ---- Why it is asked at all ------------------------------------------------
///
/// A doctor with one room never needs this and is never shown it. A doctor who
/// consults at Salt Lake in the morning and New Town in the evening has two
/// waiting rooms, and a screen that guessed would send them to call a name
/// through the wrong door. So where there is more than one location, the queue
/// asks once and then remembers for the day.
///
/// ---- What each line says ---------------------------------------------------
///
/// The hours and the open/closed state come from the clinic's own schedule
/// (see [clinicStatusAt]) rather than a setting that drifts the first time a
/// Saturday changes. The counts are today's diary for that room: booked, and
/// how many of them are already standing there.
class QueueLocation {
  const QueueLocation({
    required this.clinic,
    required this.booked,
    required this.waiting,
    required this.status,
  });

  final Clinic clinic;
  final int booked;
  final int waiting;
  final ClinicStatus status;

  String get id => clinic.id;

  /// "Clinic · 9:00 AM – 1:00 PM", or what today actually looks like.
  String get hours {
    final closes = status.closesAt;
    final opens = status.opensAt;
    if (status.open && closes != null) return 'Open until ${_clock(closes)}';
    if (opens != null) return 'Opens ${_clock(opens)}';
    return status.open ? 'Open today' : 'Closed today';
  }

  static String _clock(DateTime at) => DateFormat.jm().format(at);
}

/// The locations this doctor could be at today, each with its own numbers.
List<QueueLocation> locationsOf(
  List<Clinic> clinics,
  List<Appointment> today, {
  required DateTime now,
}) {
  final groups = <String, List<Appointment>>{};
  for (final a in today) {
    final id = a.clinicId;
    if (id == null) continue;
    (groups[id] ??= []).add(a);
  }

  return [
    for (final c in clinics)
      if (c.isActive)
        QueueLocation(
          clinic: c,
          booked: (groups[c.id] ?? const []).where(inQueue).length,
          waiting: queueGroups(groups[c.id] ?? const [])[QueueStage.waiting]!.length,
          status: clinicStatusAt(c, now),
        ),
  ];
}

/// Which room the doctor said they were at, and whether to stop asking today.
class QueueRoom {
  const QueueRoom(this._prefs);

  final SharedPreferences _prefs;

  static const _clinic = 'queue_clinic_id';
  static const _asked = 'queue_asked_on';

  String? get clinicId => _prefs.getString(_clinic);

  /// True once the doctor has said "don't ask again today" — and only for
  /// today, because tomorrow they may be in the other room.
  bool settledFor(DateTime day) => _prefs.getString(_asked) == _key(day);

  Future<void> choose(String clinicId, {required bool stopAsking, required DateTime day}) async {
    await _prefs.setString(_clinic, clinicId);
    if (stopAsking) {
      await _prefs.setString(_asked, _key(day));
    } else {
      await _prefs.remove(_asked);
    }
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Asks, and answers with the clinic id chosen — or null if dismissed.
Future<String?> chooseQueueLocation(
  BuildContext context, {
  required List<QueueLocation> locations,
  required String? current,
  required Future<void> Function(String clinicId, bool stopAsking) onChosen,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    showDragHandle: false,
    isScrollControlled: true,
    isDismissible: false,
    backgroundColor: D.card,
    barrierColor: D.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
    ),
    builder: (_) => _LocationSheet(
      locations: locations,
      current: current,
      onChosen: onChosen,
    ),
  );
}

class _LocationSheet extends ConsumerStatefulWidget {
  const _LocationSheet({
    required this.locations,
    required this.current,
    required this.onChosen,
  });

  final List<QueueLocation> locations;
  final String? current;
  final Future<void> Function(String clinicId, bool stopAsking) onChosen;

  @override
  ConsumerState<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends ConsumerState<_LocationSheet> {
  late String? _chosen = widget.current ?? _firstOpen();
  bool _stopAsking = true;

  String? _firstOpen() {
    for (final l in widget.locations) {
      if (l.status.open) return l.id;
    }
    return widget.locations.isEmpty ? null : widget.locations.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: D.s8 + D.s1,
                height: D.s1,
                decoration: const BoxDecoration(color: D.lineStrong, borderRadius: D.rPill),
              ),
            ),
            SizedBox(height: D.s5),
            Text(
              'Which queue are you seeing?',
              style: D.screenTitle.copyWith(color: D.ink),
            ),
            SizedBox(height: D.s1),
            Text(
              'Pick where you are consulting right now. You can switch any time.',
              style: D.body.copyWith(color: D.inkMuted),
            ),
            SizedBox(height: D.s4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final l in widget.locations)
                    Padding(
                      padding: EdgeInsets.only(bottom: D.s2),
                      child: _LocationRow(
                        location: l,
                        chosen: l.id == _chosen,
                        onTap: () => setState(() => _chosen = l.id),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: D.s2),
            InkWell(
              onTap: () => setState(() => _stopAsking = !_stopAsking),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: D.s2),
                child: Row(
                  children: [
                    Icon(
                      _stopAsking
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: D.iconMark,
                      color: _stopAsking ? D.brand : D.inkFaint,
                    ),
                    SizedBox(width: D.s3),
                    Expanded(
                      child: Text(
                        'Don’t ask again today',
                        style: D.subtitle.copyWith(color: D.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: D.s3),
            FilledButton(
              onPressed: _chosen == null
                  ? null
                  : () async {
                      await widget.onChosen(_chosen!, _stopAsking);
                      if (context.mounted) Navigator.of(context).pop(_chosen);
                    },
              style: FilledButton.styleFrom(
                backgroundColor: D.brand,
                foregroundColor: D.onBrand,
                disabledBackgroundColor: D.line,
                disabledForegroundColor: D.inkFaint,
                elevation: 0,
                minimumSize: Size.fromHeight(
                  MediaQuery.textScalerOf(context).scale(D.inputH),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rCard)),
              ),
              child: Text(
                'Show queue',
                style: D.input.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.location, required this.chosen, required this.onTap});

  final QueueLocation location;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = location;
    final open = l.status.open;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: chosen,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(D.rCard),
        child: Container(
          padding: EdgeInsets.all(D.s4),
          decoration: BoxDecoration(
            color: D.card,
            borderRadius: BorderRadius.circular(D.rCard),
            border: Border.all(
              color: chosen ? D.brand : D.lineStrong,
              width: chosen ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                chosen
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: D.iconMark,
                color: chosen ? D.brand : D.lineStrong,
              ),
              SizedBox(width: D.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [l.clinic.name, l.clinic.city].where((s) => (s ?? '').isNotEmpty).join(' · '),
                      style: D.subhead.copyWith(color: D.ink),
                    ),
                    SizedBox(height: D.s1 / 2),
                    Text(l.hours, style: D.body.copyWith(color: D.inkMuted)),
                    SizedBox(height: D.s2),
                    Wrap(
                      spacing: D.s2,
                      runSpacing: D.s1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ProfileChip(
                          label: open ? 'Open now' : 'Closed now',
                          kind: open ? ChipKind.brand : ChipKind.plain,
                        ),
                        Text.rich(
                          TextSpan(
                            text: '${l.booked} booked',
                            style: D.statLabel.copyWith(color: D.inkMuted),
                            children: [
                              if (l.waiting > 0)
                                TextSpan(
                                  text: ' · ${l.waiting} waiting',
                                  style: D.statLabel.copyWith(
                                    color: D.pending,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The clinics this practice has, for the queue to ask about.
final queueClinicsProvider = clinicsProvider;
