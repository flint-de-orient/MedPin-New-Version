import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../appointments/domain/clinic.dart';
import '../../appointments/presentation/appointment_providers.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../shared/providers/locale_provider.dart';
// For dateKey — the 'yyyy-MM-dd' the slot endpoint takes. One copy of it,
// shared with the reschedule sheet.
import '../domain/appointment_book.dart';
import '../domain/profile_completeness.dart';
import '../domain/weekly_schedule.dart';
import 'widgets/not_on_file.dart';
import 'widgets/profile_actions.dart';
import 'widgets/profile_parts.dart';

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

/// Everything about being this clinic's doctor (`Doctor-MyProfile`).
///
/// ---- This is the board, whole ---------------------------------------------
///
/// Six groups and twenty-one rows, in the board's own order and under its own
/// headings. About half open something; the rest are settings the app has
/// nowhere to keep yet, drawn inert and marked "Not on file yet" — shown so the
/// shape of the profile is visible, inert so nobody sets something that is not
/// saved. See widgets/not_on_file.dart.
///
/// ---- The one figure that is not drawn --------------------------------------
///
/// "Profile 85% complete". A percentage needs an agreed whole, and there is
/// none: the figure would fall every time a field was added, so a doctor who
/// changed nothing would watch their profile get worse. The card is the
/// board's and it counts the blanks instead — a number that means something
/// and goes down as they are filled.
class DoctorMyProfileScreen extends ConsumerWidget {
  const DoctorMyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final clinics = ref.watch(clinicsProvider).valueOrNull ?? const <Clinic>[];
    final rooms = [for (final c in clinics) if (c.isActive) c];
    final missing = whatIsMissing(user, rooms: rooms.length);

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
        title: Text('My profile', style: D.screenTitle.copyWith(color: D.ink)),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(D.s4, D.s5, D.s4, D.s8),
          children: [
            _Identity(user: user),
            SizedBox(height: D.s5),
            if (missing.isNotEmpty) ...[
              _Unfinished(missing: missing),
              SizedBox(height: D.s4),
            ],
            const _PublicProfile(),
            SizedBox(height: D.s4),
            _Bookings(rooms: rooms),
            SizedBox(height: D.s6),

            // ---- About you ----------------------------------------------
            const ProfileEyebrow(label: 'ABOUT YOU'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                ProfileLink(
                  first: true,
                  title: 'Professional details',
                  subtitle: 'Profession, qualifications, registration',
                  badge: (user?.qualifications?.trim().isNotEmpty ?? false)
                      ? null
                      : 'Not set',
                  badgeGround: D.pendingGround,
                  badgeInk: D.pending,
                  onTap: () => context.push('/clinician/more/professional'),
                ),
                const PendingRow(
                  title: 'ABDM · HPR ID',
                  subtitle: 'Ayushman Bharat Digital Mission',
                ),
                const PendingRow(
                  title: 'About and photo',
                  subtitle: 'Bio patients read before booking',
                ),
                const PendingRow(
                  title: 'Languages',
                  subtitle: 'The languages you consult in',
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Practice ------------------------------------------------
            const ProfileEyebrow(label: 'PRACTICE'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                ProfileLink(
                  first: true,
                  title: 'Locations',
                  subtitle: 'Map, address and contact',
                  badge: rooms.isEmpty ? 'None' : '${rooms.length}',
                  badgeGround: rooms.isEmpty ? D.pendingGround : D.brandTint,
                  badgeInk: rooms.isEmpty ? D.pending : D.brand,
                  onTap: () => context.push('/clinician/more/locations'),
                ),
                ProfileLink(
                  title: 'Schedules and slots',
                  subtitle: 'Hours and slot rules for each location',
                  onTap: () => context.push('/clinician/more/schedule'),
                ),
                ProfileLink(
                  title: 'Services and fees',
                  subtitle: 'What a consultation costs',
                  onTap: () => context.push('/clinician/more/services'),
                ),
                ProfileLink(
                  title: 'Leave and holidays',
                  subtitle: 'Days you are not seeing patients',
                  onTap: () => context.push('/clinician/more/leave'),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Patients and care ---------------------------------------
            const ProfileEyebrow(label: 'PATIENTS AND CARE'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                const PendingRow(
                  first: true,
                  title: 'Booking rules',
                  subtitle: 'How far ahead, cancellations, walk-ins',
                ),
                const PendingRow(
                  title: 'Follow-up reminders',
                  subtitle: 'When a patient is reminded to come back',
                ),
                const PendingRow(
                  title: 'Chat and urgent messages',
                  subtitle: 'When patients can message you',
                ),
                ProfileLink(
                  title: 'Prescription letterhead and signature',
                  subtitle: 'Printed on every prescription',
                  badge: (user?.signatureUrl ?? '').isEmpty
                      ? 'Signature missing'
                      : null,
                  badgeGround: D.pendingGround,
                  badgeInk: D.pending,
                  onTap: () => context.push('/clinician/more/signature'),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Team ----------------------------------------------------
            const ProfileEyebrow(label: 'TEAM'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                ProfileLink(
                  first: true,
                  title: 'Staff and assistants',
                  subtitle: 'Who can register patients and run the diary',
                  onTap: () => context.push('/clinician/staff'),
                ),
                ProfileLink(
                  title: 'Colleagues you work with',
                  subtitle: 'Doctors, dieticians and the rest of the practice',
                  onTap: () => context.push('/clinician/team'),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Account -------------------------------------------------
            const ProfileEyebrow(label: 'ACCOUNT'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                const PendingRow(first: true, title: 'Notifications'),
                const PendingRow(
                  title: 'Payouts and bank account',
                  subtitle: 'Where online fees are settled',
                ),
                ProfileLink(
                  title: 'Plan and billing',
                  subtitle: 'What you are on, and what you are using',
                  onTap: () => context.push('/clinician/billing'),
                ),
                const PendingRow(title: 'Privacy and data'),
                ProfileLink(
                  title: 'App language',
                  value: languageName(
                    ref.watch(localeControllerProvider)?.languageCode,
                  ),
                  onTap: () => pickAppLanguage(context, ref),
                ),
                const PendingRow(title: 'Help and support'),
                ProfileRow(
                  onTap: () => confirmLogout(context, ref),
                  child: Row(
                    children: [
                      const Icon(Icons.logout_rounded, size: D.iconLg, color: D.danger),
                      SizedBox(width: D.s3),
                      Expanded(
                        child: Text(
                          'Log out',
                          style: D.row.copyWith(
                            color: D.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            const PendingNote(
              what: 'the ABDM link, your bio and photo, the languages you '
                  'consult in, booking rules, follow-up reminder timing, when '
                  'patients may message you, payouts, notifications, privacy '
                  'and help',
            ),
          ],
        ),
      ),
    );
  }
}

/// The disc, the name, and what prints under it.
class _Identity extends StatelessWidget {
  const _Identity({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final name = user?.name ?? '';
    final line = [
      if ((user?.qualifications ?? '').trim().isNotEmpty) user!.qualifications!.trim(),
      if ((user?.registrationNo ?? '').trim().isNotEmpty) user!.registrationNo!.trim(),
    ].join(' · ');

    return Row(
      children: [
        Container(
          width: D.discXl,
          height: D.discXl,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: D.brandTint, shape: BoxShape.circle),
          child: Text(
            initialsOf(name.isEmpty ? '?' : name),
            style: D.greeting.copyWith(color: D.brand),
          ),
        ),
        SizedBox(width: D.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Your profile' : name,
                style: D.greeting.copyWith(color: D.ink),
              ),
              if ((user?.specialty ?? '').trim().isNotEmpty)
                Text(
                  user!.specialty!.trim(),
                  style: D.statLabel.copyWith(color: D.inkMuted),
                ),
              if (line.isNotEmpty)
                Text(line, style: D.caption.copyWith(color: D.inkFaint)),
            ],
          ),
        ),
      ],
    );
  }
}

/// What is still blank, and what each blank costs.
class _Unfinished extends StatelessWidget {
  const _Unfinished({required this.missing});

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

/// The board's two buttons under the identity.
///
/// Both need something that does not exist: there is no patient-facing doctor
/// page to preview, and nothing to share a link to. Drawn as the board has
/// them, off, with the reason under them rather than a tap that does nothing.
class _PublicProfile extends StatelessWidget {
  const _PublicProfile();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.textScalerOf(context).scale(D.tap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final (i, label) in const [
              'See as a patient',
              'Share profile',
            ].indexed) ...[
              if (i != 0) SizedBox(width: D.s2),
              Expanded(
                child: Container(
                  height: height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(D.rCard),
                    border: Border.all(color: D.line),
                  ),
                  child: Text(label, style: D.dateLine.copyWith(color: D.inkFaint)),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: D.s2),
        Row(
          children: [
            const NotOnFile(),
            SizedBox(width: D.s2),
            Expanded(
              child: Text(
                'There is no patient-facing page for a doctor yet, so there is '
                'nothing to preview or share.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
          ],
        ),
      ],
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

class _Bookings extends ConsumerWidget {
  const _Bookings({required this.rooms});

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
