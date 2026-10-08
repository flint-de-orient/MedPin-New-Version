import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../appointments/domain/clinic.dart';
import '../../../appointments/presentation/appointment_providers.dart';
// For dateKey — the 'yyyy-MM-dd' the slot endpoint takes. One copy of it,
// shared with the reschedule sheet.
import '../../domain/appointment_book.dart';
import '../../domain/profile_completeness.dart';
import '../../domain/weekly_schedule.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/user_avatar.dart';

/// The blocks under the doctor's name on the Profile screen.
///
/// They were the top of a second screen called My profile, which the Profile
/// screen opened. There is one screen now — see clinician_more_screen.dart —
/// and these are the parts of it that are about the doctor rather than about
/// a setting: what is still blank, the two patient-facing buttons, and whether
/// anybody can book.

/// The first slot still free today, across every room publishing hours.
///
/// The board's "Next free slot: today, 12:15 PM · Salt Lake". Each room's day
/// is read through [slotDayProvider], which the booking screens already use,
/// so this costs one request per room and shares their cache. Null means
/// nothing is left today — said as itself, never as the first slot of a
/// morning that has gone.
final nextFreeSlotProvider =
    FutureProvider.autoDispose<({String time, String where})?>((ref) async {
      final clinics = await ref.watch(clinicsProvider.future);
      final rooms = [
        for (final c in clinics)
          if (c.isActive && c.weeklyHours.isNotEmpty) c,
      ];
      if (rooms.isEmpty) return null;

      final today = dateKey(DateTime.now());
      final days = <({String where, SlotDay day})>[];
      for (final room in rooms) {
        try {
          final day = await ref.watch(
            slotDayProvider((clinicId: room.id, date: today)).future,
          );
          days.add((where: room.name, day: day));
        } catch (_) {
          // One room that cannot be read is not a reason to say nothing about
          // the others.
        }
      }
      return nextFreeToday(days, now: DateTime.now());
    });

/// What is still blank, and what each blank costs.
class ProfileUnfinished extends StatelessWidget {
  const ProfileUnfinished({super.key, required this.missing});

  final List<ProfileGap> missing;

  @override
  Widget build(BuildContext context) {
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
          Text(
            // The board's "Profile 85% complete". A count, not a percentage —
            // see the note at the top of this file.
            '${missing.length} ${missing.length == 1 ? 'thing' : 'things'} to finish',
            style: D.subhead.copyWith(color: D.ink),
          ),
          SizedBox(height: D.s1 / 2),
          Text(
            'Each of these shows up somewhere a patient or a prescription can '
            'see it.',
            style: D.statLabel.copyWith(color: D.inkMuted),
          ),
          for (final gap in missing) ...[
            SizedBox(height: D.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.radio_button_unchecked_rounded,
                  size: D.icon,
                  color: D.pending,
                ),
                SizedBox(width: D.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gap.label,
                        style: D.subtitle.copyWith(
                          color: D.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        gap.cost,
                        style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: D.s2),
                TextButton(
                  onPressed: () => context.push(gap.route),
                  style: TextButton.styleFrom(
                    foregroundColor: D.brand,
                    minimumSize: Size(
                      0,
                      MediaQuery.textScalerOf(context).scale(D.tap),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: D.s2),
                  ),
                  child: Text(
                    'Finish',
                    style: D.dateLine.copyWith(
                      color: D.brand,
                      fontWeight: FontWeight.w600,
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

/// "Taking bookings", and the way to take leave.
///
/// Both halves are real. Whether this doctor is taking bookings is whether an
/// open location publishes hours — which is what a patient's booking screen
/// actually reads — and the leave row opens the closures that stop them.
/// "Next free slot: today, 12:15 PM · Salt Lake", or what is true instead.
///
/// While the slots are still being read it says what it already knows — how
/// many rooms publish hours — rather than flashing a half-sentence.
String _nextLine(WidgetRef ref, int publishing, int total) {
  final next = ref.watch(nextFreeSlotProvider);
  final rooms = '$publishing of $total ${total == 1 ? 'location' : 'locations'} '
      'publishing hours';
  return next.when(
    loading: () => rooms,
    error: (_, _) => rooms,
    data: (slot) => slot == null
        ? 'No free slot left today · $rooms'
        : 'Next free slot: today, ${slot.time} · ${slot.where}',
  );
}

class ProfileBookings extends ConsumerWidget {
  const ProfileBookings({super.key, required this.rooms});

  final List<Clinic> rooms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Published hours at an open location is what makes a slot exist. Without
    // one, "taking bookings" would be a claim with nothing behind it.
    final publishing = [for (final c in rooms) if (c.weeklyHours.isNotEmpty) c];
    final on = publishing.isNotEmpty;

    return Container(
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: on ? D.doneGround : D.pendingGround,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Row(
        children: [
          Icon(
            on ? Icons.event_available_rounded : Icons.event_busy_rounded,
            size: D.iconLg,
            color: on ? D.done : D.pending,
          ),
          SizedBox(width: D.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  on ? 'Taking bookings' : 'Not taking bookings',
                  style: D.subtitle.copyWith(
                    color: on ? D.done : D.pending,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  on
                      ? _nextLine(ref, publishing.length, rooms.length)
                      : 'No published hours, so no slot exists to book',
                  style: D.caption.copyWith(color: D.inkMuted, height: 1.4),
                ),
              ],
            ),
          ),
          SizedBox(width: D.s2),
          TextButton(
            onPressed: () => context.push('/clinician/more/leave'),
            style: TextButton.styleFrom(
              foregroundColor: D.brand,
              minimumSize: Size(0, MediaQuery.textScalerOf(context).scale(D.tap)),
              padding: EdgeInsets.symmetric(horizontal: D.s2),
            ),
            child: Text(
              'Take leave',
              style: D.dateLine.copyWith(color: D.brand, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}


/// The disc, the name, and everything that prints under it.
///
/// The two boards each drew half of this: `Profile` had the photo and the
/// role, `Doctor-MyProfile` had the specialty and the credentials. One screen
/// now, so one block, carrying both.
class ProfileIdentity extends StatelessWidget {
  const ProfileIdentity({
    super.key,
    required this.name,
    required this.phone,
    required this.specialty,
    required this.credentials,
    required this.avatarUrl,
    required this.role,
    required this.uploading,
    required this.onChangePhoto,
    required this.onViewPhoto,
  });

  final String name;
  final String phone;

  /// "Diabetologist · Internal medicine", where it is set.
  final String? specialty;

  /// "MBBS, MD · WBMC 64213", where any of it is set.
  final String? credentials;

  final String? avatarUrl;
  final String role;
  final bool uploading;
  final VoidCallback? onChangePhoto;
  final VoidCallback? onViewPhoto;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        Semantics(
          button: true,
          label: l10n.profileChangePhoto,
          child: GestureDetector(
            onTap: onChangePhoto,
            onLongPress: onViewPhoto,
            child: Stack(
              children: [
                UserAvatar(
                  name: name,
                  avatarUrl: avatarUrl,
                  accent: D.brand,
                  size: D.discXl,
                ),
                if (uploading)
                  Positioned.fill(
                    child: ClipOval(
                      child: ColoredBox(
                        color: D.scrim,
                        child: const Center(
                          child: SizedBox(
                            width: D.icon,
                            height: D.icon,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(width: D.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: D.greeting.copyWith(color: D.ink)),
              if ((specialty ?? '').isNotEmpty)
                Text(
                  specialty!,
                  style: D.statLabel.copyWith(color: D.inkMuted),
                ),
              if ((credentials ?? '').isNotEmpty)
                Text(credentials!, style: D.caption.copyWith(color: D.inkFaint)),
              if (phone.isNotEmpty)
                Text(phone, style: D.caption.copyWith(color: D.inkFaint)),
              SizedBox(height: D.s1),
              Container(
                padding: EdgeInsets.symmetric(horizontal: D.s3, vertical: D.s1 / 2),
                decoration: const BoxDecoration(
                  color: D.brandTint,
                  borderRadius: D.rPill,
                ),
                child: Text(
                  role,
                  style: D.caption.copyWith(
                    color: D.brand,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
