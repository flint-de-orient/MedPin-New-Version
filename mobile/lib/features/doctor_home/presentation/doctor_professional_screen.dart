import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/error_view.dart';
import '../../auth/presentation/auth_controller.dart';
import 'widgets/profile_parts.dart';

/// What the prescription says about the doctor (`Profile-Professional`).
///
/// ---- Three fields, not thirteen ---------------------------------------------
///
/// The artboard asks for a great deal more: a profession type that reshapes the
/// rest of the profile, a council and a registration year, an ABDM/HPR link,
/// qualifications as rows with institution, year and a verified mark,
/// specialisations and conditions treated as tags, and years in practice.
/// `/auth/me` stores three strings — qualifications, specialty, registration
/// number — and these three are the ones that print at the top of every
/// prescription, which is what this screen is for.
///
/// The rest is not drawn as empty boxes. A "Verified" mark with nothing
/// verifying it, or a council field that goes nowhere, is worse on a clinical
/// document than an honest blank: it invites the doctor to believe the app
/// checked something. What is missing is said once, at the foot, with the
/// offer to add it.
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
            Padding(
              padding: EdgeInsets.only(left: D.s1, bottom: D.s4),
              child: Text(
                'These three lines print at the top of every prescription you '
                'write, exactly as they are typed here.',
                style: D.statLabel.copyWith(color: D.inkMuted, height: 1.45),
              ),
            ),
            Container(
              padding: EdgeInsets.all(D.s5),
              decoration: BoxDecoration(
                color: D.card,
                borderRadius: BorderRadius.circular(D.rSection),
                border: Border.all(color: D.line),
                boxShadow: D.lift,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Field(
                    label: 'Qualifications',
                    hint: 'MBBS, MD (Medicine)',
                    controller: _quals,
                    fieldKey: const Key('pd-qualifications'),
                    caps: TextCapitalization.characters,
                  ),
                  SizedBox(height: D.s4),
                  _Field(
                    label: 'Specialty',
                    hint: 'Consultant Physician & Diabetologist',
                    controller: _specialty,
                    fieldKey: const Key('pd-specialty'),
                    caps: TextCapitalization.words,
                  ),
                  SizedBox(height: D.s4),
                  _Field(
                    label: 'Registration number',
                    hint: 'WBMC 64213',
                    controller: _registration,
                    fieldKey: const Key('pd-registration'),
                  ),
                ],
              ),
            ),
            if (_failed != null) ...[
              SizedBox(height: D.s4),
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
            SizedBox(height: D.s5),
            const ProfileEyebrow(label: 'Not on this screen'),
            SizedBox(height: D.s2),
            Container(
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
                      'The design also asks for your council and registration '
                      'year, an ABDM HPR link, each qualification with its '
                      'institution and year, and the conditions you treat. '
                      'Nothing in the app records any of those yet, and a '
                      '“Verified” mark with nothing behind it does not belong on '
                      'a prescription.',
                      style: D.statLabel.copyWith(color: D.brand, height: 1.45),
                    ),
                  ),
                ],
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
    this.caps = TextCapitalization.none,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Key fieldKey;
  final TextCapitalization caps;

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}
