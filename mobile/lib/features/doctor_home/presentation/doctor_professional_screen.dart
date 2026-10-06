import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/error_view.dart';
import '../../auth/presentation/auth_controller.dart';
import 'widgets/not_on_file.dart';
import 'widgets/profile_parts.dart';

/// What the prescription says about the doctor (`Profile-Professional`).
///
/// ---- Three fields work; the rest of the board is drawn and inert ----------
///
/// `/auth/me` keeps qualifications, specialty and a registration number, and
/// those three print at the top of every prescription. The board asks for a
/// great deal more — a profession type that reshapes the profile, a council
/// and a registration year, an ABDM HPR link, each qualification as a row with
/// its institution and a verified mark, specialisations, the conditions this
/// doctor treats, and years in practice.
///
/// Those are drawn as the design has them and marked "Not on file yet". None
/// of them shows a value, and none can be typed into: a greyed
/// "MBBS, Calcutta Medical College" would be read as this doctor's own by the
/// first person to glance at it, and a "Verified" tick with nothing verifying
/// it has no business near a prescription at all.
class DoctorProfessionalScreen extends ConsumerStatefulWidget {
  const DoctorProfessionalScreen({super.key});

  @override
  ConsumerState<DoctorProfessionalScreen> createState() =>
      _DoctorProfessionalScreenState();
}

class _DoctorProfessionalScreenState
    extends ConsumerState<DoctorProfessionalScreen> {
  late final TextEditingController _quals;
  late final TextEditingController _specialty;
  late final TextEditingController _registration;

  bool _busy = false;
  String? _failed;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _quals = TextEditingController(text: user?.qualifications ?? '');
    _specialty = TextEditingController(text: user?.specialty ?? '');
    _registration = TextEditingController(text: user?.registrationNo ?? '');
    for (final c in [_quals, _specialty, _registration]) {
      c.addListener(_typed);
    }
  }

  void _typed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    for (final c in [_quals, _specialty, _registration]) {
      c.dispose();
    }
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
        title: Text(
          'Professional details',
          style: D.screenTitle.copyWith(color: D.ink),
        ),
        actions: [
          TextButton(
            key: const Key('pd-save'),
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
            // ---- Your profession -------------------------------------
            const ProfileEyebrow(label: 'YOUR PROFESSION'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                PendingChoice(
                  first: true,
                  label: 'Profession',
                  note: 'The profile is tailored to it. A psychologist sets '
                      'session length and therapy approaches; a physiotherapist '
                      'can offer home visits.',
                  options: const [
                    'Doctor',
                    'Psychologist',
                    'Physiotherapist',
                    'Dietician',
                    'Fitness coach',
                    'Other',
                  ],
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Registration ----------------------------------------
            const ProfileEyebrow(label: 'REGISTRATION'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                const PendingField(first: true, label: 'Council'),
                _Field(
                  label: 'Registration number',
                  hint: 'WBMC 64213',
                  controller: _registration,
                  fieldKey: const Key('pd-registration'),
                ),
                const PendingField(label: 'Year'),
              ],
            ),
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                // Said once, here, where the artboard shows a tick.
                'The design shows a "Verified" mark beside the number. Nothing '
                'checks it against a council, so none is shown.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
            SizedBox(height: D.s6),

            // ---- ABDM ------------------------------------------------
            const ProfileEyebrow(label: 'ABDM'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: const [
                PendingRow(
                  first: true,
                  title: 'HPR ID',
                  subtitle: 'Healthcare Professionals Registry',
                ),
              ],
            ),
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                'Linking an HPR ID would verify this doctor through ABDM and '
                'let records reach patients’ ABHA accounts, with consent.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
            SizedBox(height: D.s6),

            // ---- Qualifications --------------------------------------
            //
            // The board lists these as rows with an institution, a year and a
            // verified mark. One string is what is kept, so the string is the
            // field that works and the structure is drawn beneath it.
            const ProfileEyebrow(label: 'QUALIFICATIONS'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                _Field(
                  first: true,
                  label: 'As printed on your prescription',
                  hint: 'MBBS, MD (Medicine)',
                  controller: _quals,
                  fieldKey: const Key('pd-qualifications'),
                  caps: TextCapitalization.characters,
                ),
                const PendingRow(
                  title: 'Each degree on its own',
                  subtitle: 'Institution, year and proof',
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Specialty -------------------------------------------
            const ProfileEyebrow(label: 'SPECIALTY'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                _Field(
                  first: true,
                  label: 'As printed on your prescription',
                  hint: 'Consultant Physician & Diabetologist',
                  controller: _specialty,
                  fieldKey: const Key('pd-specialty'),
                  caps: TextCapitalization.words,
                ),
                const PendingRow(
                  title: 'Specialisations',
                  subtitle: 'Each one on its own, for search',
                ),
                const PendingRow(
                  title: 'Conditions you treat',
                  subtitle: 'Patients find you when they search these',
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Experience ------------------------------------------
            const ProfileEyebrow(label: 'EXPERIENCE'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: const [
                PendingField(first: true, label: 'Practising since'),
              ],
            ),
            SizedBox(height: D.s6),

            if (_failed != null) ...[
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
              SizedBox(height: D.s5),
            ],

            const PendingNote(
              what: 'your profession, council and registration year, the ABDM '
                  'link, each degree on its own, your specialisations and the '
                  'conditions you treat, and years in practice',
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
        qualifications: _quals.text.trim(),
        specialty: _specialty.text.trim(),
        registrationNo: _registration.text.trim(),
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

/// A label above a box, as every field in this design is drawn.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.fieldKey,
    this.first = false,
    this.caps = TextCapitalization.none,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Key fieldKey;
  final bool first;
  final TextCapitalization caps;

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      first: first,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: D.statLabel.copyWith(color: D.inkMuted)),
          SizedBox(height: D.gapTight),
          Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(D.inputH),
            ),
            padding: EdgeInsets.symmetric(horizontal: D.s4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.rCard),
              border: Border.all(color: D.lineStrong),
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              key: fieldKey,
              controller: controller,
              textCapitalization: caps,
              style: D.input.copyWith(color: D.ink),
              decoration: D.bareField(
                hint: hint,
                hintStyle: D.input.copyWith(color: D.inkFaint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
