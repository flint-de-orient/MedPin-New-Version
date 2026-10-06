import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/capabilities/capabilities.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/doctor_tokens.dart';
import '../../../core/utils/auth_validators.dart';
import '../../doctor_home/presentation/widgets/profile_parts.dart';
import '../data/clinician_repository.dart';
import '../domain/team_member.dart';
import 'clinician_providers.dart';
import 'widgets/team_parts.dart';
import 'widgets/team_pickers.dart';
import 'widgets/verified_phone_field.dart';

/// Adding somebody to the practice (`People — add` on the canvas).
///
/// ---- No password, for anybody -------------------------------------------
///
/// The form used to offer one "for a handset that lives on a counter with no
/// personal phone". What that made was a credential the person adding a
/// colleague chose, knew, and passed on by word of mouth — for an account that
/// may read every patient at the practice. Staff sign in with a code texted to
/// their own number, and the server refuses a hire that carries a password.
/// Passwords people already have keep working until they are retired.
///
/// ---- A screen, not a sheet ----------------------------------------------
///
/// The board draws this with its own header and its own back arrow, and it is
/// right to: the form is nine fields and an OTP, which is longer than a sheet
/// can be without the keyboard eating half of it.
class TeamAddScreen extends ConsumerStatefulWidget {
  const TeamAddScreen({super.key});

  @override
  ConsumerState<TeamAddScreen> createState() => _TeamAddScreenState();
}

class _TeamAddScreenState extends ConsumerState<TeamAddScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _quals = TextEditingController();
  final _reg = TextEditingController();

  String _role = 'staff';
  String? _phoneToken;
  String? _departmentId;

  /// The locations they may run. Empty is every one of them, which is the
  /// server's reading and the row every colleague hired before this field
  /// existed holds.
  final _locationIds = <String>[];

  bool _saving = false;
  String? _failed;

  @override
  void dispose() {
    _name.dispose();
    _quals.dispose();
    _reg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(teamProvider).valueOrNull ?? TeamRoster.empty;
    final isDoctor = _role == 'doctor';
    final repository = ref.read(clinicianRepositoryProvider);

    return Scaffold(
      backgroundColor: D.ground,
      appBar: teamBar(context, title: 'Add someone'),
      body: SafeArea(
        top: false,
        child: Form(
          key: _form,
          child: ListView(
            padding: EdgeInsets.fromLTRB(D.s5, D.s2, D.s5, D.s8),
            children: [
              FieldLabel(
                label: 'Role',
                child: Wrap(
                  spacing: D.s2,
                  runSpacing: D.s2,
                  children: [
                    for (final role in teamRoles)
                      TeamChip(
                        label: roleLabel(role),
                        on: _role == role,
                        onTap: () => setState(() => _role = role),
                      ),
                  ],
                ),
              ),
              SizedBox(height: D.s6),

              FieldLabel(
                label: 'Full name',
                child: TeamTextField(
                  controller: _name,
                  hint: 'Dr. Ananya Basu',
                  caps: TextCapitalization.words,
                  maxLength: AuthValidators.maxNameLength,
                  validator: (v) {
                    final name = (v ?? '').trim();
                    if (name.isEmpty) return 'Enter their name.';
                    if (name.length < AuthValidators.minNameLength) {
                      return 'Name must be at least '
                          '${AuthValidators.minNameLength} characters.';
                    }
                    return null;
                  },
                ),
              ),
              SizedBox(height: D.s6),

              FieldLabel(
                label: 'Phone',
                note: 'They sign in with a code texted to this number. If they '
                    'already use MedPin, they keep their account and sign in '
                    'as before.',
                child: VerifiedPhoneField(
                  label: 'Their mobile number',
                  onToken: (t) => setState(() => _phoneToken = t),
                  // The team's routes, not registration's. Registration
                  // refuses a number that already has an account, and that is
                  // every doctor or receptionist who already uses MedPin
                  // somewhere else — so none of them could ever be added here.
                  sendCode: repository.requestHireCode,
                  verifyCode: repository.verifyHireCode,
                ),
              ),

              if (isDoctor) ...[
                SizedBox(height: D.s6),
                const ProfileEyebrow(label: 'DOCTOR DETAILS'),
                SizedBox(height: D.hair / 2),
                Text(
                  'Printed on this doctor’s prescriptions.',
                  style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                ),
                SizedBox(height: D.s4),
                FieldLabel(
                  label: 'Qualifications',
                  child: TeamTextField(
                    controller: _quals,
                    hint: 'MBBS, DNB (Endocrinology)',
                    maxLength: 120,
                  ),
                ),
                SizedBox(height: D.s4),
                FieldLabel(
                  label: 'Registration number',
                  note: 'Prints under their signature.',
                  child: TeamTextField(
                    controller: _reg,
                    hint: 'WBMC 71842',
                    maxLength: 60,
                  ),
                ),
              ],

              if (roster.departments.isNotEmpty) ...[
                SizedBox(height: D.s6),
                FieldLabel(
                  label: 'Department',
                  child: TeamSelect(
                    value: _departmentId,
                    options: roster.departments,
                    emptyLabel: 'Not set',
                    onChanged: (v) => setState(() => _departmentId = v),
                  ),
                ),
              ],

              if (roster.locations.length > 1) ...[
                SizedBox(height: D.s6),
                FieldLabel(
                  label: 'Locations',
                  note: 'Leave all of them unticked and they may work at every '
                      'location, including any the practice opens later.',
                  child: TeamLocations(
                    locations: roster.locations,
                    chosen: _locationIds,
                    onChanged: (next) => setState(() {
                      _locationIds
                        ..clear()
                        ..addAll(next);
                    }),
                  ),
                ),
              ],

              SizedBox(height: D.s6),
              TeamNote(
                title: 'Permissions come from the role',
                // Read out of the role's own preset rather than written here,
                // so a preset changed on the server cannot leave this
                // sentence describing last month's grant.
                body: '${roleLabel(_role)}: ${_grantSentence(_role)}. '
                    'There is no separate permission step.',
              ),

              if (_failed != null) ...[
                SizedBox(height: D.s4),
                TeamFailure(message: _failed!),
              ],

              SizedBox(height: D.s6),
              TeamButton(
                label: 'Add to team',
                busy: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final token = _phoneToken;
    if (!(_form.currentState?.validate() ?? false)) return;
    if (token == null) {
      setState(() => _failed = 'Verify the phone number first.');
      return;
    }

    setState(() {
      _saving = true;
      _failed = null;
    });
    try {
      final existing = await ref.read(clinicianRepositoryProvider).hire(
            role: _role,
            name: _name.text.trim(),
            phoneToken: token,
            departmentId: _departmentId,
            locationIds: _locationIds,
            qualifications: _role == 'doctor' ? _quals.text.trim() : null,
            registrationNo: _role == 'doctor' ? _reg.text.trim() : null,
          );
      ref.invalidate(teamProvider);
      if (!mounted) return;
      context.pop();

      // Said on the screen that now lists them. The form read as making an
      // account, and for somebody who already uses MedPin it did not: they
      // sign in exactly as they did before.
      if (!existing) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'They already use MedPin, so they keep their account and now '
            'work here too.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = teamProblem(
          e,
          'Could not add them. Check the connection and try again.',
        );
      });
    }
  }
}

/// The role's grant in one clause, built from [permissionLabels] so it cannot
/// drift from the list on a member's own screen.
///
/// Only what the role is *given*. A sentence that also listed what it is
/// refused would be nine clauses, and the member screen is where the whole
/// grant is read.
String _grantSentence(String role) {
  final given = _presetOf(role);
  final words = permissionLabels
      .where((p) => given.contains(p.$1))
      .map((p) => p.$2.toLowerCase())
      .toList();
  if (words.isEmpty) return 'nothing yet — the practice sets what they may do';
  return words.join(', ');
}

/// What each role is granted when nobody has customised it.
///
/// Mirrors `PRESETS` in backend models/Membership.js. Kept here rather than
/// fetched because it is only ever used to describe a role the reader is about
/// to choose — the grant that is actually saved comes back from the server
/// with the person, and that is what their own screen reads.
List<String> _presetOf(String role) {
  return switch (role) {
    'doctor' => const [
        Perm.viewPatient,
        Perm.editRecord,
        Perm.prescribe,
        Perm.chatRead,
        Perm.chatReply,
      ],
    'staff' || 'dietician' => const [
        Perm.viewPatient,
        Perm.editRecord,
        Perm.chatRead,
      ],
    'doctor_assistant' => const [
        Perm.viewPatient,
        Perm.editRecord,
        Perm.chatRead,
        Perm.chatReply,
      ],
    'lab_manager' => const [
        Perm.viewPatient,
        Perm.editRecord,
        Perm.viewAudit,
      ],
    'lab_technician' => const [Perm.viewPatient, Perm.editRecord],
    'practice_manager' => const [
        Perm.manageStaff,
        Perm.manageDepartment,
        Perm.viewAudit,
      ],
    _ => const [],
  };
}

/// What went wrong, in the server's own sentence when the server sent one.
///
/// The refusals here are written for the person holding the phone — a
/// patient's number, somebody who already works here, a practice at its
/// limit — and printing the exception wrapped each in `ApiException(CONFLICT,
/// …)`. A failure the server did not answer gets [fallback] instead.
String teamProblem(Object error, String fallback) =>
    error is ApiException && error.statusCode != null ? error.message : fallback;
