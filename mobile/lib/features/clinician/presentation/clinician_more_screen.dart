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
import '../../../shared/widgets/language_picker.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../doctor_home/presentation/doctor_signature_screen.dart';
import '../../doctor_home/presentation/widgets/profile_parts.dart';
import '../../feedback/data/feedback_repository.dart';
import '../data/practice_repository.dart';
import '../domain/practice.dart';
import 'clinician_tabs.dart';
import 'widgets/clinician_notification_sheet.dart';

/// The roles the server lets read patient feedback — `DIRECT_PATIENT_ACCESS` in
/// backend/src/middleware/auth.js. A practice manager and a dietician are not
/// among them.
bool _readsPatientFeedback(String? role) =>
    const {'doctor', 'staff', 'doctor_assistant', 'lab_manager', 'lab_technician'}.contains(role);

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
/// ---- What is here and what is one tap away --------------------------------
///
/// This is the account and the clinic's tools. The doctor *as a doctor* — the
/// credentials that print on a prescription, the rooms, the diary, the people —
/// is My profile, under Account. The diary is also listed here in its own
/// group, because "where are my appointments" is the question this screen is
/// most often opened to answer and it should not need two taps.
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
    final unreadFeedback = ref.watch(feedbackUnreadProvider).valueOrNull ?? 0;

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
        title: Text('Profile', style: D.screenTitle.copyWith(color: D.ink)),
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
        child: ListView(
          padding: EdgeInsets.fromLTRB(D.s4, D.s5, D.s4, D.s8),
          children: [
            _Identity(
              name: user?.name ?? roleLabel,
              phone: user?.phone ?? '',
              avatarUrl: user?.avatarUrl,
              role: roleLabel,
              uploading: _uploadingAvatar,
              onChangePhoto: _uploadingAvatar ? null : _changeAvatar,
              onViewPhoto: user?.avatarUrl == null
                  ? null
                  : () => FullscreenPhoto.show(context, user!.avatarUrl),
            ),
            SizedBox(height: D.s6),

            // ---- Account ------------------------------------------------
            ProfileEyebrow(label: l10n.profileAccount.toUpperCase()),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                ProfileLink(
                  first: true,
                  title: l10n.profileEditProfile,
                  onTap: () => context.push('/clinician/more/edit'),
                ),
                // Everything about being this clinic's doctor rather than
                // about this account.
                ProfileLink(
                  title: 'My profile',
                  subtitle: 'Credentials, locations and the people you work with',
                  onTap: () => context.push('/clinician/more/profile'),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- The diary ----------------------------------------------
            //
            // Its own group rather than a row buried in the tools. The design
            // puts the day's work first on every other doctor screen, and
            // this one was the exception.
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
                    subtitle: 'Today’s waiting room, in the order you call it',
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

            // ---- Language -----------------------------------------------
            ProfileEyebrow(label: l10n.profileLanguage.toUpperCase()),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                ProfileRow(
                  first: true,
                  child: LanguagePicker(
                    selected: currentLocale?.languageCode,
                    onChanged: _changeLanguage,
                  ),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Clinic tools -------------------------------------------
            const ProfileEyebrow(label: 'CLINIC TOOLS'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                // Messages deliberately absent: it is a tab. A duplicate here
                // pointed at the retired DirectMessage inbox, so the same word
                // opened different data depending on where you tapped it.
                ProfileLink(
                  first: true,
                  title: 'Practice',
                  subtitle: 'Letterhead, locations and who works here',
                  onTap: () => context.push('/clinician/practice'),
                ),
                // Readable by any doctor, not gated on MANAGE_STAFF. Knowing
                // the clinic is on a trial that ends on the 14th is not
                // privileged, and hiding it until somebody holds a billing
                // permission is how a practice discovers its plan by being cut
                // off. The buttons inside are gated; the screen is not.
                if (isDoctor)
                  ProfileLink(
                    title: 'Plan and billing',
                    subtitle: 'What you are on, and what you are using',
                    onTap: () => context.push('/clinician/billing'),
                  ),
                // The doctor's own day. Not gated on a plan: a summary of the
                // consultations somebody did is part of doing them.
                if (isDoctor)
                  ProfileLink(
                    title: 'Daily report',
                    subtitle: 'Who you saw, as a PDF to keep or share',
                    onTap: () => context.push('/clinician/daily-report'),
                  ),
                ProfileLink(
                  title: 'Clinical alerts',
                  subtitle: 'Readings and symptoms that need a look',
                  onTap: () => context.push('/clinician/alerts'),
                ),
                // Nutrition was the fourth tab until Reports took its place.
                // The stream is still there and this is how it is reached — on
                // the same condition the tab had: somebody has to be able to
                // answer in it.
                if (nutritionAnswerable(caps))
                  ProfileLink(
                    title: 'Nutrition',
                    subtitle: 'The dietician’s conversations with your patients',
                    onTap: () => context.push('/clinician/nutrition'),
                  ),
                // Home shows the day and nothing else. These are the cards
                // that used to sit under it.
                ProfileLink(
                  title: 'Clinical cards',
                  subtitle: 'Blood pressure, follow-ups, recent labs, chat summaries',
                  onTap: () => context.push('/clinician/clinical-cards'),
                ),
                ProfileLink(
                  title: 'People',
                  subtitle: 'Doctors, front desk and dieticians',
                  onTap: () => context.push('/clinician/team'),
                ),
                if (caps.has(Cap.reportExport))
                  ProfileLink(
                    title: 'Export data',
                    subtitle: 'Patients, alerts and figures as CSV or JSON',
                    onTap: () => context.push('/clinician/export'),
                  ),
                // Reviewing what the assistant said is a screen with nothing
                // on it where there is no assistant.
                if (caps.has(Cap.aiAssistant))
                  ProfileLink(
                    title: 'Chat review',
                    subtitle: 'What the assistant has been telling patients',
                    onTap: () => context.push('/clinician/chat-review'),
                  ),
                ProfileLink(
                  title: 'Knowledge base',
                  subtitle: 'Clinic answers the assistant draws on',
                  onTap: () => context.push('/clinician/knowledge'),
                ),
                // Only for somebody the server lets read it: a role that opens
                // patients directly, holding VIEW_PATIENT. A practice manager
                // was shown the row and refused behind it.
                if (caps.can(Perm.viewPatient) && _readsPatientFeedback(user?.role))
                  ProfileLink(
                    title: 'Patient feedback',
                    subtitle: 'What patients registered here have written',
                    badge: unreadFeedback == 0 ? null : '$unreadFeedback new',
                    badgeGround: D.brandTint,
                    badgeInk: D.brand,
                    onTap: () => context.push('/clinician/feedback'),
                  ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Prescription letterhead (doctor only) ------------------
            if (isDoctor) ...[
              const ProfileEyebrow(label: 'PRESCRIPTION LETTERHEAD'),
              SizedBox(height: D.s2),
              ProfileGroup(
                children: [
                  ProfileLink(
                    first: true,
                    title: 'Professional details',
                    // The label always says what the row is for; what is
                    // currently set goes on the right. Putting the saved
                    // qualifications in the subtitle meant the row described
                    // itself on an empty profile and stopped describing itself
                    // the moment it was filled in.
                    subtitle: 'Qualifications, specialty and registration no.',
                    badge: (user?.qualifications?.trim().isNotEmpty ?? false)
                        ? null
                        : 'Not set',
                    badgeGround: D.pendingGround,
                    badgeInk: D.pending,
                    onTap: () => context.push('/clinician/more/professional'),
                  ),
                  ProfileLink(
                    title: 'Digital signature',
                    subtitle: 'Printed on every prescription',
                    badge: (user?.signatureUrl ?? '').isEmpty ? 'Not set' : null,
                    badgeGround: D.pendingGround,
                    badgeInk: D.pending,
                    onTap: () => context.push('/clinician/more/signature'),
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
                              style: D.body.copyWith(color: D.ink),
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
                        ? 'Not set — patients have no number to ring'
                        : formatPhone(practice.emergencyPhone),
                    onTap: mayEditPractice ? () => _editPracticePhone(practice) : null,
                  ),
                ],
              ),
              SizedBox(height: D.s6),
            ],

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
                  onTap: _confirmLogout,
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

  Future<void> _changeLanguage(String code) async {
    await ref.read(localeControllerProvider.notifier).setLanguage(code);
    ref.read(authControllerProvider.notifier).updateLocalUserLanguage(code);
    try {
      await ref.read(authRepositoryProvider).updateMe(language: code);
    } on ApiException {
      // Local preference still applies.
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

  Future<void> _confirmLogout() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: D.card,
        title: Text('Log out?', style: D.subhead.copyWith(color: D.ink)),
        content: Text(
          'You will need to log in again to open the clinic dashboard.',
          style: D.body.copyWith(color: D.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Stay', style: D.bodyStrong.copyWith(color: D.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.profileLogout,
              style: D.bodyStrong.copyWith(color: D.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).logout();
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

/// The disc, the name, and what this person is at this practice.
class _Identity extends StatelessWidget {
  const _Identity({
    required this.name,
    required this.phone,
    required this.avatarUrl,
    required this.role,
    required this.uploading,
    required this.onChangePhoto,
    required this.onViewPhoto,
  });

  final String name;
  final String phone;
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
                  size: D.discLg,
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
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: EdgeInsets.all(D.s1 / 2),
                    decoration: const BoxDecoration(
                      color: D.brand,
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(
                        BorderSide(color: D.ground, width: 2),
                      ),
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      size: D.iconSm,
                      color: D.onBrand,
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
              Text(name, style: D.opening.copyWith(color: D.ink)),
              if (phone.isNotEmpty)
                Text(phone, style: D.statLabel.copyWith(color: D.inkMuted)),
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
