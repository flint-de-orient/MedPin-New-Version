import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/capabilities/capabilities.dart';
import '../../../core/router/area.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/doctor_tokens.dart';
import '../../../core/update/build_info.dart';
import '../../../core/update/version_gate.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/data/care_contact.dart';
import '../../../shared/data/upload_repository.dart';
import '../../../shared/providers/app_lock_provider.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/utils/phone_format.dart';
import '../../../shared/widgets/fullscreen_photo.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../appointments/domain/clinic.dart';
import '../../appointments/presentation/appointment_providers.dart';
import '../../doctor_home/domain/profile_completeness.dart';
import '../../doctor_home/presentation/doctor_signature_screen.dart';
import '../../doctor_home/presentation/widgets/profile_header.dart';
import '../../doctor_home/presentation/widgets/profile_parts.dart';
import '../data/practice_repository.dart';
import '../domain/practice.dart';
import '../../doctor_home/presentation/widgets/profile_actions.dart';
import '../domain/team_member.dart';
import 'clinician_providers.dart';
import 'clinician_refresh.dart';
import 'widgets/clinician_notification_sheet.dart';

/// "MBBS, MD · WBMC 64213", or null while there is nothing to print.
///
/// Null rather than an empty string: a row with a blank second line is taller
/// than its neighbours for no reason anybody can see.
@visibleForTesting
String? credentialsLine(AppUser? user) {
  final parts = [
    if ((user?.qualifications ?? '').trim().isNotEmpty) user!.qualifications!.trim(),
    if ((user?.specialty ?? '').trim().isNotEmpty) user!.specialty!.trim(),
    if ((user?.registrationNo ?? '').trim().isNotEmpty) user!.registrationNo!.trim(),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The doctor's Profile (`Profile`), opened from the avatar on Home.
///
/// ---- Why this was rebuilt -------------------------------------------------
///
/// It kept the old panel's colours and spacing while everything around it moved
/// to the design canvas, so the one screen a doctor reaches from every other
/// screen was the one that looked like a different app. The rows were already
/// the artboard's; the drawing was not, and content matching is not the design
/// matching.
///
/// ---- One screen, not two --------------------------------------------------
///
/// The design draws this across two boards: `Profile`, the account and the
/// clinic's tools, and `Doctor-MyProfile`, the doctor as a doctor — the
/// credentials that print on a prescription, the rooms, the people. They were
/// two screens here too, one opening the other, and the second was somewhere
/// nobody went.
///
/// Both boards are on this screen now. Where they overlapped — Plan and
/// billing, the letterhead, the language, the sign-out, the people — the row
/// appears once, in the group that describes it best, and the duplicate is
/// gone. Everything else keeps the heading its own board gave it.
class ClinicianMoreScreen extends ConsumerStatefulWidget {
  const ClinicianMoreScreen({super.key});

  @override
  ConsumerState<ClinicianMoreScreen> createState() =>
      _ClinicianMoreScreenState();
}

class _ClinicianMoreScreenState extends ConsumerState<ClinicianMoreScreen> {
  bool _uploadingAvatar = false;

  @override
  Widget build(BuildContext context) {
    // What this practice has, so the tools list is what it can use rather
    // than a menu with dead entries in it.
    final caps = ref.watch(capabilitySetProvider);
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authControllerProvider).user;
    final isDoctor = user?.role == 'doctor';
    final currentLocale = ref.watch(localeControllerProvider);
    final lockEnabled = ref.watch(appLockProvider).enabled;
    // Their actual job. This said "Doctor" or "Clinic staff", which was true
    // while there were two kinds of clinician and tells a laboratory
    // technician the wrong thing about themselves now.
    final roleLabel = roleLabels[user?.role ?? ''] ?? 'Clinic staff';
    // The practice's own record, for the number its patients ring. Null while
    // it loads and for an account with no practice, and the row is simply
    // absent then — never somebody else's number standing in.
    final practice = ref.watch(practiceOverviewProvider).valueOrNull;
    final mayEditPractice = caps.can(Perm.manageStaff);
    final clinics = ref.watch(clinicsProvider).valueOrNull ?? const <Clinic>[];
    // Read for the two counts in the Team section. The board puts a figure on
    // each row — "2 people", "and 4 more" — and a row that promised a count
    // and showed none was the commonest thing to notice about this screen.
    final roster = ref.watch(teamProvider).valueOrNull;
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
        // The artboard's header is the lockup and the bell, with no title: it
        // is a tab there and has nowhere to go back to. Here it is opened from
        // Home's avatar, so the arrow stays and the lockup takes the title's
        // place rather than a word repeating the row that was tapped.
        title: const AppWordmark(height: D.logo),
        actions: [
          // The same counted bell as the tabs. A bell that shows a number on
          // Home and none here reads as "nothing waiting" on whichever screen
          // the doctor happens to be looking at.
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded, size: D.iconDisc),
            color: D.ink,
            onPressed: () => showClinicianNotifications(context),
          ),
          SizedBox(width: D.s1),
        ],
      ),
      body: SafeArea(
        top: false,
        /*
         * Pull to refresh, because nothing else on this screen ever asks
         * again.
         *
         * It had neither a pull nor a timer, and every live figure on it —
         * the locations count, the two team counts, whether the doctor is
         * taking bookings, what is left to finish — was whatever the server
         * said when the screen first opened. A location added at the desk, a
         * colleague suspended by a colleague, a practice phone changed on
         * another handset: none of it appeared until the app was killed and
         * reopened, and nothing on the screen suggested that was necessary.
         */
        child: RefreshIndicator(
          color: D.brand,
          onRefresh: () => refreshClinicianContext(ref),
          child: ListView(
            // Always scrollable, or a short screen — a receptionist's, with
            // half these sections hidden — cannot be pulled at all.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(D.s4, D.s5, D.s4, D.s8),
            children: [
            ProfileIdentity(
              name: user?.name ?? roleLabel,
              // Grouped, as every other number in this app is shown. Raw, it
              // ran as one thirteen-digit string nobody can read back.
              phone: formatPhone(user?.phone),
              specialty: user?.specialty?.trim(),
              credentials: credentialsLine(user),
              avatarUrl: user?.avatarUrl,
              // "Doctor · Owner", which is what the board says and what the
              // membership knows. The role alone left out the half that
              // decides what this person may change.
              role: caps.isOwner ? '$roleLabel · Owner' : roleLabel,
              uploading: _uploadingAvatar,
              onChangePhoto: _uploadingAvatar ? null : _changeAvatar,
              onViewPhoto: user?.avatarUrl == null
                  ? null
                  : () => FullscreenPhoto.show(context, user!.avatarUrl),
            ),
            SizedBox(height: D.s5),
            if (missing.isNotEmpty) ...[
              ProfileUnfinished(missing: missing),
              SizedBox(height: D.s4),
            ],
            const ProfilePublicButtons(),
            SizedBox(height: D.s4),
            ProfileBookings(rooms: rooms),
            SizedBox(height: D.s6),

            // ---- About you ----------------------------------------------
            const ProfileEyebrow(label: 'ABOUT YOU'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                ProfileLink(
                  first: true,
                  title: l10n.profileEditProfile,
                  onTap: () => context.push('/clinician/more/edit'),
                ),
                ProfileLink(
                  title: 'Professional details',
                  subtitle: credentialsLine(user),
                  badge: (user?.qualifications?.trim().isNotEmpty ?? false)
                      ? null
                      : 'Not set',
                  badgeGround: D.pendingGround,
                  badgeInk: D.pending,
                  onTap: () => context.push('/clinician/more/professional'),
                ),
                ProfileLink(
                  title: 'ABDM · HPR ID',
                  subtitle: 'Ayushman Bharat Digital Mission',
                  // It lives with the rest of the registration, which is
                  // where somebody filling one in already is.
                  value: (user?.hprId ?? '').isEmpty ? 'Not set' : null,
                  onTap: () => context.push('/clinician/more/professional'),
                ),
                ProfileLink(
                  title: 'About and photo',
                  subtitle: 'Bio patients read before booking',
                  onTap: () => context.push('/clinician/more/about'),
                ),
                ProfileLink(
                  title: 'Languages',
                  subtitle: 'The languages you consult in',
                  value: (user?.languages.isEmpty ?? true)
                      ? null
                      : '${user!.languages.length}',
                  onTap: () => context.push('/clinician/more/about'),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- The diary ----------------------------------------------
            //
            // Not on either board. "Where are my appointments" is the question
            // this screen is most often opened to answer, and it was two taps
            // down a list called Clinic tools.
            if (isDoctor) ...[
              const ProfileEyebrow(label: 'THE DIARY'),
              SizedBox(height: D.s2),
              ProfileGroup(
                children: [
                  ProfileLink(
                    first: true,
                    title: 'Appointments',
                    subtitle: 'Who is coming, who is waiting for a time',
                    onTap: () => context.push('/clinician/appointments'),
                  ),
                  ProfileLink(
                    title: 'Patient queue',
                    subtitle: 'Today\u2019s waiting room, in the order you call it',
                    onTap: () => context.push('/clinician/queue'),
                  ),
                  ProfileLink(
                    title: 'Follow-ups',
                    subtitle: 'Who you asked back, and who has not come',
                    onTap: () => context.push('/clinician/follow-ups'),
                  ),
                ],
              ),
              SizedBox(height: D.s6),
            ],

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
                ProfileLink(
                  first: true,
                  title: 'Booking rules',
                  subtitle: 'How far ahead, and when they may cancel',
                  onTap: () => context.push('/clinician/more/care'),
                ),
                ProfileLink(
                  title: 'Follow-up reminders',
                  subtitle: 'When a patient is reminded to come back',
                  onTap: () => context.push('/clinician/more/care'),
                ),
                ProfileLink(
                  title: 'Chat and urgent messages',
                  subtitle: 'When patients can message you',
                  onTap: () => context.push('/clinician/more/care'),
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
                // Two rows into one list, as the board draws them: somebody
                // looking for the desk and somebody looking for a colleague
                // ask different questions of the same screen. Each carries
                // its own half of the count, so neither claims the other's.
                ProfileLink(
                  first: true,
                  title: 'Staff and assistants',
                  subtitle: 'Who can register patients and run the diary',
                  value: _headcount(roster, clinical: false),
                  onTap: () => context.push('/clinician/team'),
                ),
                ProfileLink(
                  title: 'Colleagues you work with',
                  subtitle: 'Doctors, dieticians and the rest of the practice',
                  value: _headcount(roster, clinical: true),
                  onTap: () => context.push('/clinician/team'),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Clinic tools --------------------------------------------
            //
            // One row. The other seven — Practice, Daily report, Clinical
            // alerts, Export data, Chat review, Knowledge base, Patient
            // feedback — are how you run the clinic, not who you are, and the
            // canvas gives them rows of their own (Clinic operations, AI
            // assistant & feedback, Team billing & reports). They are
            // unreachable until those are built, which is the cost of taking
            // them off a screen they did not belong on.
            //
            // Plan and billing stays, and is readable by any doctor rather
            // than gated on MANAGE_STAFF: knowing the clinic is on a trial
            // that ends on the 14th is not privileged, and hiding it until
            // somebody holds a billing permission is how a practice discovers
            // its plan by being cut off. The buttons inside are gated.
            if (isDoctor) ...[
              const ProfileEyebrow(label: 'CLINIC TOOLS'),
              SizedBox(height: D.s2),
              ProfileGroup(
                children: [
                  ProfileLink(
                    first: true,
                    title: 'Plan and billing',
                    onTap: () => context.push('/clinician/billing'),
                  ),
                ],
              ),
              SizedBox(height: D.s6),
            ],

            // ---- Security -----------------------------------------------
            ProfileEyebrow(label: l10n.profileSecurity.toUpperCase()),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                ProfileRow(
                  first: true,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.profileAppLock,
                              style: D.row.copyWith(color: D.ink),
                            ),
                            Text(
                              l10n.profileAppLockSub,
                              style: D.statLabel.copyWith(color: D.inkFaint),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: D.s2),
                      Switch(
                        value: lockEnabled,
                        onChanged: _toggleAppLock,
                        activeThumbColor: D.onBrand,
                        activeTrackColor: D.brand,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Clinic -------------------------------------------------
            //
            // The number patients ring belongs to the practice, set once for
            // every location. Editable by whoever administers the practice;
            // shown to everyone else, because a doctor asked "what number do
            // patients call?" should be able to answer.
            if (practice != null) ...[
              ProfileEyebrow(label: l10n.profileClinic.toUpperCase()),
              SizedBox(height: D.s2),
              ProfileGroup(
                children: [
                  ProfileLink(
                    first: true,
                    title: 'Patient call number',
                    subtitle: practice.emergencyPhone == null
                        ? 'Not set \u2014 patients have no number to ring'
                        : formatPhone(practice.emergencyPhone),
                    onTap: mayEditPractice ? () => _editPracticePhone(practice) : null,
                  ),
                ],
              ),
              SizedBox(height: D.s6),
            ],

            // ---- Account ------------------------------------------------
            ProfileEyebrow(label: l10n.profileAccount.toUpperCase()),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                ProfileLink(
                  first: true,
                  title: 'Notifications',
                  onTap: () => context.push('/clinician/more/notifications'),
                ),
                ProfileLink(
                  title: 'Payouts and bank account',
                  subtitle: 'Where online fees are settled',
                  value: practice?.payout.onFile == true ? null : 'Not set',
                  onTap: () => context.push('/clinician/more/payouts'),
                ),
                ProfileLink(
                  title: 'Privacy and data',
                  onTap: () => context.push('/clinician/more/privacy'),
                ),
                ProfileLink(
                  title: 'App language',
                  value: languageName(currentLocale?.languageCode),
                  onTap: () => pickAppLanguage(context, ref),
                ),
                ProfileLink(
                  title: 'Help and support',
                  onTap: () => context.push('/clinician/more/help'),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- About --------------------------------------------------
            const ProfileEyebrow(label: 'ABOUT'),
            SizedBox(height: D.s2),
            ProfileGroup(children: [const _Version(first: true)]),
            SizedBox(height: D.s6),


            // ---- Log out ------------------------------------------------
            ProfileGroup(
              children: [
                ProfileRow(
                  first: true,
                  onTap: () => confirmLogout(context, ref),
                  child: Row(
                    children: [
                      const Icon(Icons.logout_rounded, size: D.iconLg, color: D.danger),
                      SizedBox(width: D.s3),
                      Expanded(
                        child: Text(
                          l10n.profileLogout,
                          style: D.body.copyWith(
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
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- actions ----

  Future<void> _changeAvatar() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final source = await pickImageSource(context);
    if (source == null) return;

    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final asset = await ref
          .read(uploadRepositoryProvider)
          .uploadImage(
            path: file.path,
            filename: file.name,
            kind: UploadKind.avatar,
          );
      final user = await ref
          .read(authRepositoryProvider)
          .updateMe(avatarAssetId: asset.id);
      ref.read(authControllerProvider.notifier).replaceUser(user);
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
    } on ApiException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatAttachFailed)));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }



  Future<void> _toggleAppLock(bool enable) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(appLockProvider.notifier);
    if (enable) {
      if (!await controller.canUse()) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.appLockUnavailable)));
        return;
      }
      if (!await controller.enable(l10n.appLockPrompt)) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.appLockUnavailable)));
      }
    } else {
      await controller.disable();
    }
  }


  /// The number this practice's patients ring, edited on the practice.
  ///
  /// It edited `clinics.first` — whichever location the list returned first —
  /// and created a location called "Clinic" when there was none. The number is
  /// the practice's, set once for all of its locations, and an empty field
  /// clears it rather than being ignored.
  Future<void> _editPracticePhone(PracticeOverview practice) async {
    final controller = TextEditingController(
      text: practice.emergencyPhone ?? '',
    );
    final messenger = ScaffoldMessenger.of(context);

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: D.card,
        title: Text(
          'Patient call number',
          style: D.subhead.copyWith(color: D.ink),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The number patients are given for this practice, at every '
              'location. Leave it empty to remove it.',
              style: D.statLabel.copyWith(color: D.inkMuted, height: 1.45),
            ),
            SizedBox(height: D.s4),
            TextField(
              key: const Key('practice-phone'),
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              style: D.input.copyWith(color: D.ink),
              decoration: const InputDecoration(hintText: '+91 33 4000 1234'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: D.bodyStrong.copyWith(color: D.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Save', style: D.bodyStrong.copyWith(color: D.brand)),
          ),
        ],
      ),
    );
    final typedNumber = controller.text.trim();
    controller.dispose();
    if (save != true) return;

    try {
      final typed = typedNumber;
      await ref.read(practiceRepositoryProvider).update(practice.id, {
        // Empty clears it rather than being ignored.
        'emergencyPhone': typed.isEmpty ? null : typed,
      });
      ref.invalidate(practiceOverviewProvider);
      ref.invalidate(careContactProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            typed.isEmpty
                ? 'Patient call number removed'
                : 'Patient call number saved',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The version, and whether a newer one exists.
///
/// Its own row rather than the shared [AppSection], which draws itself in the
/// old panel's card and would have put one grey box inside a white one.
class _Version extends ConsumerWidget {
  const _Version({required this.first});

  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(versionStatusProvider).valueOrNull;
    final canUpdate = status?.canUpdate ?? false;

    return ProfileRow(
      first: first,
      child: Row(
        children: [
          Expanded(child: Text('App version', style: D.body.copyWith(color: D.ink))),
          if (canUpdate)
            Container(
              padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.s1 / 2),
              decoration: const BoxDecoration(
                color: D.pendingGround,
                borderRadius: D.rPill,
              ),
              child: Text(
                'Update available',
                style: D.caption.copyWith(
                  color: D.pending,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            const Icon(Icons.check_rounded, size: D.icon, color: D.done),
          SizedBox(width: D.gapTight),
          Text(
            'v${BuildInfo.current.version}',
            style: D.statLabel.copyWith(color: D.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// How many of the practice's people each Team row is about.
///
/// Split the way the two rows are: the clinicians a doctor works beside, and
/// the staff who run the desk and the laboratory. Null while the roster is
/// loading, so the row shows nothing rather than a confident "0 people" that
/// turns into eleven a second later.
///
/// Counts only people who can sign in. Somebody suspended is still on the
/// list and still has a row there — they are not somebody you have.
String? _headcount(TeamRoster? roster, {required bool clinical}) {
  if (roster == null) return null;
  const clinicians = {'doctor', 'dietician'};
  final n = roster.items
      .where((m) => m.isActive && clinicians.contains(m.role) == clinical)
      .length;
  return n == 1 ? '1 person' : '$n people';
}
