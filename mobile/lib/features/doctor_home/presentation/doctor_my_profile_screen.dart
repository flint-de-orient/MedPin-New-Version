import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../appointments/domain/clinic.dart';
import '../../appointments/presentation/appointment_providers.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/profile_completeness.dart';
import 'widgets/profile_parts.dart';

/// Everything about being this clinic's doctor (`Doctor-MyProfile`).
///
/// ---- What this is, and what the Profile tab is -----------------------------
///
/// The Profile tab is the account: language, app lock, log out, and the clinic
/// tools. This is the doctor — the credentials that print on a prescription,
/// the rooms they consult in, the diary, and the people they work with. The tab
/// opens it from the identity block, as the artboard does.
///
/// ---- Rows that go nowhere are not drawn -----------------------------------
///
/// The artboard lists a dozen settings this system does not record: booking
/// rules, follow-up reminder timing, when patients may message, leave and
/// holidays as a thing of its own, payouts, a bio and languages for patient
/// search. Each would be a row that opens a screen that cannot save. They are
/// named once at the foot instead, so the doctor can see what is coming
/// without being invited to tap it.
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
              SizedBox(height: D.s5),
            ],

            const ProfileEyebrow(label: 'The prescription'),
            SizedBox(height: D.s2),
            _Group(
              rows: [
                (
                  title: 'Professional details',
                  sub: user?.qualifications?.trim().isNotEmpty == true
                      ? [
                          user!.qualifications!.trim(),
                          if ((user.registrationNo ?? '').trim().isNotEmpty)
                            user.registrationNo!.trim(),
                        ].join(' · ')
                      : 'Printed at the top of every prescription',
                  route: '/clinician/more/professional',
                  warn: (user?.qualifications ?? '').trim().isEmpty,
                ),
                (
                  title: 'Letterhead and signature',
                  sub: (user?.signatureUrl ?? '').isEmpty
                      ? 'No signature uploaded'
                      : 'Printed on every prescription',
                  route: '/clinician/practice',
                  warn: (user?.signatureUrl ?? '').isEmpty,
                ),
              ],
            ),
            SizedBox(height: D.s5),

            const ProfileEyebrow(label: 'The diary'),
            SizedBox(height: D.s2),
            _Group(
              rows: [
                (
                  title: 'Appointments',
                  sub: 'Who is coming, who is waiting for a time',
                  route: '/clinician/appointments',
                  warn: false,
                ),
                (
                  title: 'Patient queue',
                  sub: 'Today’s waiting room, in the order you call it',
                  route: '/clinician/queue',
                  warn: false,
                ),
                (
                  title: 'Follow-ups',
                  sub: 'Who you asked back, and who has not come',
                  route: '/clinician/follow-ups',
                  warn: false,
                ),
              ],
            ),
            SizedBox(height: D.s5),

            const ProfileEyebrow(label: 'Where you consult'),
            SizedBox(height: D.s2),
            _Group(
              rows: [
                (
                  title: 'Locations',
                  // Hours, slot length and day closures are all inside a
                  // location, which is where the server keeps them.
                  sub: rooms.isEmpty
                      ? 'No open location yet'
                      : '${rooms.length} ${rooms.length == 1 ? 'location' : 'locations'} · hours, slots and closures',
                  route: '/clinician/clinics',
                  warn: rooms.isEmpty,
                ),
                (
                  title: 'Departments',
                  sub: 'How the practice is divided up',
                  route: '/clinician/departments',
                  warn: false,
                ),
              ],
            ),
            SizedBox(height: D.s5),

            const ProfileEyebrow(label: 'Who you work with'),
            SizedBox(height: D.s2),
            _Group(
              rows: [
                (
                  title: 'People',
                  sub: 'Doctors, front desk and dieticians',
                  route: '/clinician/team',
                  warn: false,
                ),
                (
                  title: 'Front desk',
                  sub: 'Who can register patients and run the diary',
                  route: '/clinician/staff',
                  warn: false,
                ),
              ],
            ),
            SizedBox(height: D.s5),

            const ProfileEyebrow(label: 'The practice'),
            SizedBox(height: D.s2),
            _Group(
              rows: [
                (
                  title: 'Practice',
                  sub: 'Name, letterhead and who works here',
                  route: '/clinician/practice',
                  warn: false,
                ),
                (
                  title: 'Plan and billing',
                  sub: 'What you are on, and what you are using',
                  route: '/clinician/billing',
                  warn: false,
                ),
              ],
            ),
            SizedBox(height: D.s5),
            const _NotYet(),
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
          width: D.discLg,
          height: D.discLg,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: D.brandTint, shape: BoxShape.circle),
          child: Text(
            initialsOf(name.isEmpty ? '?' : name),
            style: D.opening.copyWith(color: D.brand),
          ),
        ),
        SizedBox(width: D.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Your profile' : name,
                style: D.opening.copyWith(color: D.ink),
              ),
              if ((user?.specialty ?? '').trim().isNotEmpty)
                Text(
                  user!.specialty!.trim(),
                  style: D.statLabel.copyWith(color: D.inkMuted),
                ),
              if (line.isNotEmpty)
                Text(line, style: D.caption.copyWith(color: D.inkFaint)),
              if ((user?.phone ?? '').isNotEmpty)
                Text(user!.phone, style: D.caption.copyWith(color: D.inkFaint)),
            ],
          ),
        ),
      ],
    );
  }
}

/// What is not filled in, and what each gap actually costs.
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Not finished yet',
                  style: D.subhead.copyWith(color: D.ink),
                ),
              ),
              Text(
                '${missing.length} to go',
                style: D.statLabel.copyWith(color: D.pending),
              ),
            ],
          ),
          SizedBox(height: D.s1 / 2),
          Text(
            // Not a percentage: the figure a percentage implies — how complete
            // the profile is out of some agreed whole — is not a thing this
            // app knows. What it knows is which of these are blank.
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

/// One card of rows, each going somewhere.
class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<({String title, String sub, String route, bool warn})> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        children: [
          for (final (i, r) in rows.indexed)
            ProfileRow(
              first: i == 0,
              onTap: () => context.push(r.route),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.title,
                          style: D.subtitle.copyWith(
                            color: D.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          r.sub,
                          style: D.statLabel.copyWith(
                            color: r.warn ? D.pending : D.inkFaint,
                          ),
                        ),
                      ],
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
    );
  }
}

/// The artboard's settings that have nothing behind them, said once.
class _NotYet extends StatelessWidget {
  const _NotYet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.brandTint,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: D.iconLg, color: D.brand),
          SizedBox(width: D.s3),
          Expanded(
            child: Text(
              'Services and fees, booking rules, follow-up reminder timing, '
              'when patients may message you, leave and holidays, payouts, and '
              'a bio and languages for patient search are all in the design and '
              'none of them are recorded anywhere yet. They are left off rather '
              'than drawn as settings that cannot save.',
              style: D.statLabel.copyWith(color: D.brand, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
