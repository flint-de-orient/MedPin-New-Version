import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/providers/preferences_provider.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/language_picker.dart';
import '../../auth/presentation/auth_controller.dart';
import 'widgets/live_fields.dart';
import 'widgets/profile_parts.dart';

/// What a patient reads before booking, and which languages they will be
/// answered in (`Doctor-MyProfile` → About you).
///
/// ---- Two rows, one screen -------------------------------------------------
///
/// The board lists "About and photo" and "Languages" separately. They are both
/// what a patient sees on a doctor, they are saved by the same call, and a
/// screen each would be two screens with one field on them.
///
/// The photo itself is set on the Profile screen, where it already is — the
/// disc there is the control. This says so rather than offering a second
/// uploader that writes the same field.
class DoctorAboutScreen extends ConsumerStatefulWidget {
  const DoctorAboutScreen({super.key});

  @override
  ConsumerState<DoctorAboutScreen> createState() => _DoctorAboutScreenState();
}

class _DoctorAboutScreenState extends ConsumerState<DoctorAboutScreen> {
  late final TextEditingController _bio;
  late List<String> _languages;
  bool _dirty = false;
  bool _busy = false;
  String? _failed;

  /// The three the app itself speaks, in their own script, plus the ones a
  /// clinic is likely to add. A doctor who consults in Odia types it.
  static const _suggested = [
    'English',
    'বাংলা',
    'हिन्दी',
    'Urdu',
    'Odia',
    'Nepali',
  ];

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _bio = TextEditingController(text: user?.bio ?? '');
    _languages = [...?user?.languages];
    _bio.addListener(() {
      if (!_dirty) setState(() => _dirty = true);
    });
  }

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text('About you', style: D.screenTitle.copyWith(color: D.ink)),
        actions: [
          TextButton(
            key: const Key('about-save'),
            onPressed: _dirty && !_busy ? _save : null,
            style: TextButton.styleFrom(
              foregroundColor: D.brand,
              disabledForegroundColor: D.inkFaint,
            ),
            child: _busy
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
        child: ListView(
          padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
          children: [
            const ProfileEyebrow(label: 'ABOUT'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                TextFieldRow(
                  first: true,
                  label: 'What patients read before booking',
                  hint: 'Diabetes and heart care since 2011.',
                  controller: _bio,
                  fieldKey: const Key('about-bio'),
                  lines: 5,
                  caps: TextCapitalization.sentences,
                  counter: 1200,
                ),
              ],
            ),
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                'Your photo is the disc on the Profile screen — tap it there to '
                'change it.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
            SizedBox(height: D.s6),

            const ProfileEyebrow(label: 'LANGUAGES'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                TagField(
                  first: true,
                  label: 'The languages you consult in',
                  note: 'Patients see these before booking.',
                  values: _languages,
                  suggestions: _suggested,
                  onChanged: (v) => setState(() {
                    _languages = v;
                    _dirty = true;
                  }),
                ),
              ],
            ),
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                // Two different things that would otherwise be confused: the
                // language the app is in, and the languages this doctor can
                // hold a consultation in.
                'These are the languages you speak with patients, not the '
                'language the app is in — that is App language, under '
                'Account.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
            SizedBox(height: D.s6),

            if (_failed != null)
              Container(
                padding: EdgeInsets.all(D.s4),
                decoration: BoxDecoration(
                  color: D.dangerGround,
                  borderRadius: BorderRadius.circular(D.rCard),
                ),
                child: Text(
                  _failed!,
                  style: D.statLabel.copyWith(color: D.danger, height: 1.45),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final updated = await ref.read(authRepositoryProvider).updateMe(
        professional: {
          'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
          'languages': _languages,
        },
      );
      ref.read(authControllerProvider.notifier).replaceUser(updated);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }
}

/// Which pushes this phone shows (`Doctor-MyProfile` → Account).
///
/// ---- Why these are the doctor's own, not the practice's -------------------
///
/// They are this handset's settings, kept on it. A doctor with the app on a
/// phone and a tablet can want the tablet quiet, and nothing about that is a
/// fact the clinic needs to know.
///
/// The two a doctor actually receives are here. Medication and check-in
/// reminders are a patient's, and a screen that offered a doctor a switch for
/// their own medication reminders would be a screen nobody trusts.
class DoctorNotificationsScreen extends ConsumerWidget {
  const DoctorNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPreferencesProvider);
    final controller = ref.read(appPreferencesProvider.notifier);

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
        title: Text('Notifications', style: D.screenTitle.copyWith(color: D.ink)),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
          children: [
            const ProfileEyebrow(label: 'ON THIS PHONE'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                SwitchField(
                  first: true,
                  title: 'Appointments',
                  sub: 'Booked, moved and cancelled',
                  value: prefs.appointmentAlerts,
                  onChanged: controller.setAppointmentAlerts,
                ),
                SwitchField(
                  title: 'Clinical alerts',
                  sub: 'Readings and symptoms that need a look',
                  value: prefs.clinicAlerts,
                  onChanged: controller.setClinicAlerts,
                ),
              ],
            ),
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                // Said plainly, because a doctor who turns these off and then
                // misses an emergency should have been told which half they
                // were turning off.
                'These are this handset’s. Turning one off stops the push; '
                'the alert is still raised and is still on your Home screen '
                'when you open the app.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
            SizedBox(height: D.s6),

            const ProfileEyebrow(label: 'LANGUAGE'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                ProfileRow(
                  first: true,
                  child: Text(
                    'Notifications arrive in the app’s language: '
                    '${LanguagePicker.options.map((o) => o.native).join(', ')} '
                    '— whichever is set under Account.',
                    style: D.statLabel.copyWith(color: D.inkMuted, height: 1.45),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
