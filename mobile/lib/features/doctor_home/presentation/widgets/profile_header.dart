import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../appointments/domain/clinic.dart';
import '../../../auth/presentation/auth_controller.dart';
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
/// The rooms where this doctor has a schedule patients can book into.
///
/// ---- Why this is not `c.weeklyHours.isNotEmpty` --------------------------
///
/// That is the *building's* opening hours. The server decides whether a slot
/// exists with `scheduleFor`: the doctor's own `Availability` at that
/// location if they have one, and the building's hours only as a fallback.
///
/// So a doctor who published their hours on the Schedules screen — which
/// writes `Availability` and never touches `Clinic.weeklyHours` — had a
/// profile telling them "Not taking bookings" while patients could book them
/// perfectly well. The banner was answering a different question from the one
/// it asked, and wrong in the direction that matters: it understated what the
/// clinic was committed to.
///
/// One request per open room, shared with the Schedules screen's cache.
final publishingRoomsProvider =
    FutureProvider.autoDispose<List<Clinic>>((ref) async {
      final me = ref.watch(authControllerProvider).user?.id;
      final clinics = await ref.watch(clinicsProvider.future);
      final open = [for (final c in clinics) if (c.isActive) c];
      if (me == null || open.isEmpty) {
        return [for (final c in open) if (c.weeklyHours.isNotEmpty) c];
      }

      final out = <Clinic>[];
      for (final room in open) {
        try {
          final hours = await ref.watch(locationHoursProvider(room.id).future);
          final mine = hours.doctors
              .where((d) => d.doctorId == me)
              .firstOrNull;
          // `scheduleFor`, in the same order: their own diary, else the
          // building's.
          final publishes = mine == null || mine.usesLocationHours
              ? room.weeklyHours.isNotEmpty
              : mine.weeklyHours.isNotEmpty;
          if (publishes) out.add(room);
        } catch (_) {
          // A room that cannot be read falls back to what the clinic itself
          // says, rather than dropping out of the count entirely.
          if (room.weeklyHours.isNotEmpty) out.add(room);
        }
      }
      return out;
    });

final nextFreeSlotProvider =
    FutureProvider.autoDispose<({String time, String where})?>((ref) async {
      // The same rooms the banner counts — this filtered on the building's
      // hours too, so a doctor with their own diary never saw a next slot.
      final rooms = await ref.watch(publishingRoomsProvider.future);
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
    /*
     * Published hours at an open location is what makes a slot exist, and
     * "published" means what the server means by it — see
     * publishingRoomsProvider. This read `c.weeklyHours`, the building's own
     * hours, and so told a doctor who had published their own diary that they
     * were not taking bookings while patients could book them.
     *
     * While the rooms are still being read it holds the last answer rather
     * than flashing "Not taking bookings" at somebody who is: an amber
     * warning that appears for a second and corrects itself is worse than a
     * beat of nothing.
     */
    final async = ref.watch(publishingRoomsProvider);
    final publishing = async.valueOrNull;
    final loading = publishing == null;
    final on = publishing != null && publishing.isNotEmpty;

    return Container(
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        // Neutral while it is still being read, so the amber does not appear
        // and then correct itself.
        color: loading
            ? D.track
            : on
            ? D.doneGround
            : D.pendingGround,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Row(
        children: [
          Icon(
            on ? Icons.event_available_rounded : Icons.event_busy_rounded,
            size: D.iconLg,
            color: loading
                ? D.inkFaint
                : on
                ? D.done
                : D.pending,
          ),
          SizedBox(width: D.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loading
                      ? 'Checking your hours'
                      : on
                      ? 'Taking bookings'
                      : 'Not taking bookings',
                  style: D.subtitle.copyWith(
                    color: loading
                        ? D.inkMuted
                        : on
                        ? D.done
                        : D.pending,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  loading
                      ? '${rooms.length} ${rooms.length == 1 ? 'location' : 'locations'}'
                      : on
                      ? _nextLine(ref, publishing.length, rooms.length)
                      : rooms.isEmpty
                      ? 'No location yet, so there is nowhere to publish hours'
                      : 'No published hours, so no slot exists to book',
                  style: D.caption.copyWith(color: D.inkMuted, height: 1.4),
                ),
              ],
            ),
          ),
          SizedBox(width: D.s2),
          /*
           * The action has to answer the sentence beside it.
           *
           * This always said "Take leave", including under "No published
           * hours, so no slot exists to book" — where taking leave does
           * nothing at all, because there is nothing to close. The fix for no
           * hours is to publish some; the fix for no location is to add one.
           * Only a doctor who IS taking bookings has leave to take.
           */
          if (!loading)
            TextButton(
              onPressed: () => context.push(
                on
                    ? '/clinician/more/leave'
                    : rooms.isEmpty
                    ? '/clinician/more/locations'
                    : '/clinician/more/schedule',
              ),
              style: TextButton.styleFrom(
                foregroundColor: D.brand,
                minimumSize: Size(
                  0,
                  MediaQuery.textScalerOf(context).scale(D.tap),
                ),
                padding: EdgeInsets.symmetric(horizontal: D.s2),
              ),
              child: Text(
                on
                    ? 'Take leave'
                    : rooms.isEmpty
                    ? 'Add a location'
                    : 'Publish hours',
                style: D.dateLine.copyWith(
                  color: D.brand,
                  fontWeight: FontWeight.w600,
                ),
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
