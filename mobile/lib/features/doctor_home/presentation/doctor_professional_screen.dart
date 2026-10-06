import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/error_view.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
import 'widgets/live_fields.dart';
import 'widgets/profile_parts.dart';

/// What the prescription says about the doctor (`Profile-Professional`).
///
/// ---- Every field on the board, and nothing invented --------------------
///
/// The board asks for a profession type, a council and a registration year, an
/// ABDM link, each qualification with its institution, specialisations, the
/// conditions this doctor treats, years in practice, and memberships. All of
/// them are columns now and all of them save.
///
/// ---- Except the tick ----------------------------------------------------
///
/// The board draws "Verified" beside the registration number and beside each
/// degree. Nothing in this app asks a council or a university, so there is no
/// tick: a verified mark with nothing behind it, on the credential that says
/// somebody may prescribe, is the one piece of reassurance here that could
/// hurt a patient. The ABDM id is stored and labelled as what it is — a number
/// somebody typed.
///
/// ---- Why `qualifications` survives the degrees list ----------------------
///
/// It is the line that prints. A doctor who wants "MBBS, MD (Medicine)" at the
/// top of their prescription is not served by it being rebuilt out of rows,
/// and the rows exist for a patient reading a profile, not for the letterhead.
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
  late final TextEditingController _council;
  late final TextEditingController _hpr;

  String? _professionType;
  int? _registrationYear;
  int? _practisingSince;
  late List<Degree> _degrees;
  late List<String> _specialisations;
  late List<String> _conditions;
  late List<String> _memberships;

  bool _busy = false;
  String? _failed;
  bool _dirty = false;

  List<TextEditingController> get _fields =>
      [_quals, _specialty, _registration, _council, _hpr];

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _quals = TextEditingController(text: user?.qualifications ?? '');
    _specialty = TextEditingController(text: user?.specialty ?? '');
    _registration = TextEditingController(text: user?.registrationNo ?? '');
    _council = TextEditingController(text: user?.council ?? '');
    _hpr = TextEditingController(text: user?.hprId ?? '');
    _professionType = user?.professionType;
    _registrationYear = user?.registrationYear;
    _practisingSince = user?.practisingSince;
    _degrees = [...?user?.degrees];
    _specialisations = [...?user?.specialisations];
    _conditions = [...?user?.conditionsTreated];
    _memberships = [...?user?.memberships];
    for (final c in _fields) {
      c.addListener(_touched);
    }
  }

  void _touched() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// A change made by a chip or a stepper, which has no controller to listen
  /// to. Wrapped so every one of them marks the screen dirty the same way.
  void _change(VoidCallback apply) => setState(() {
    apply();
    _dirty = true;
  });

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Years, oldest a person could plausibly have qualified in. Used by both
    // year steppers, which step by one from either end.
    const firstYear = 1950;
    final thisYear = DateTime.now().year;

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
                ChoiceField(
                  first: true,
                  label: 'Profession',
                  note: 'A psychologist sets session length and therapy '
                      'approaches; a physiotherapist can offer home visits.',
                  options: const {
                    'doctor': 'Doctor',
                    'psychologist': 'Psychologist',
                    'physiotherapist': 'Physiotherapist',
                    'dietician': 'Dietician',
                    'fitness_coach': 'Fitness coach',
                    'other': 'Other',
                  },
                  value: _professionType,
                  onChanged: (v) => _change(() => _professionType = v),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Registration ----------------------------------------
            const ProfileEyebrow(label: 'REGISTRATION'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                TextFieldRow(
                  first: true,
                  label: 'Council',
                  hint: 'West Bengal Medical Council',
                  controller: _council,
                  fieldKey: const Key('pd-council'),
                  caps: TextCapitalization.words,
                ),
                TextFieldRow(
                  label: 'Registration number',
                  hint: 'WBMC 64213',
                  controller: _registration,
                  fieldKey: const Key('pd-registration'),
                ),
                StepperField(
                  title: 'Year',
                  sub: 'When you were registered',
                  value: _registrationYear,
                  min: firstYear,
                  max: thisYear,
                  noneLabel: 'Not set',
                  onChanged: (v) => _change(() => _registrationYear = v),
                ),
              ],
            ),
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                // Said once, here, where the board shows a tick.
                'The design shows a "Verified" mark beside the number. Nothing '
                'in this app asks a council, so none is shown.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
            SizedBox(height: D.s6),

            // ---- ABDM ------------------------------------------------
            const ProfileEyebrow(label: 'ABDM'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                TextFieldRow(
                  first: true,
                  label: 'HPR ID',
                  hint: 'Healthcare Professionals Registry',
                  controller: _hpr,
                  fieldKey: const Key('pd-hpr'),
                ),
              ],
            ),
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                'Saved as typed. Nothing here checks it against the registry, '
                'so it is a record of your id and not a verification.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
            SizedBox(height: D.s6),

            // ---- Qualifications --------------------------------------
            const ProfileEyebrow(label: 'QUALIFICATIONS'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                TextFieldRow(
                  first: true,
                  label: 'As printed on your prescription',
                  hint: 'MBBS, MD (Medicine)',
                  controller: _quals,
                  fieldKey: const Key('pd-qualifications'),
                  caps: TextCapitalization.characters,
                ),
                for (final (i, degree) in _degrees.indexed)
                  ProfileRow(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(degree.name, style: D.row.copyWith(color: D.ink)),
                              if (degree.where != null)
                                Text(
                                  degree.where!,
                                  style: D.statLabel.copyWith(color: D.inkFaint),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove ${degree.name}',
                          icon: const Icon(Icons.close_rounded, size: D.iconMd),
                          color: D.inkFaint,
                          onPressed: () => _change(() => _degrees.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                ProfileLink(title: '+ Add a qualification', onTap: _addDegree),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Specialisations -------------------------------------
            const ProfileEyebrow(label: 'SPECIALISATIONS'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                TextFieldRow(
                  first: true,
                  label: 'As printed on your prescription',
                  hint: 'Consultant Physician & Diabetologist',
                  controller: _specialty,
                  fieldKey: const Key('pd-specialty'),
                  caps: TextCapitalization.words,
                ),
                TagField(
                  label: 'Each one on its own',
                  note: 'So patients can search them.',
                  values: _specialisations,
                  suggestions: const [
                    'Diabetology',
                    'Internal medicine',
                    'Cardiology',
                    'Endocrinology',
                  ],
                  onChanged: (v) => _change(() => _specialisations = v),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Conditions you treat --------------------------------
            const ProfileEyebrow(label: 'CONDITIONS YOU TREAT'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                TagField(
                  first: true,
                  label: 'What you see most',
                  note: 'Patients find you when they search these.',
                  values: _conditions,
                  suggestions: const [
                    'Type 2 diabetes',
                    'Hypertension',
                    'Thyroid disorders',
                    'PCOS',
                    'Obesity',
                  ],
                  onChanged: (v) => _change(() => _conditions = v),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Experience ------------------------------------------
            const ProfileEyebrow(label: 'EXPERIENCE'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                StepperField(
                  first: true,
                  title: 'Practising since',
                  // The board shows "2010" and "14 yrs" beside each other. One
                  // is the other, so the years are said rather than typed —
                  // and they stay right next year without anybody editing.
                  sub: _practisingSince == null
                      ? 'The year you started'
                      : '${thisYear - _practisingSince!} '
                            '${thisYear - _practisingSince! == 1 ? 'year' : 'years'}',
                  value: _practisingSince,
                  min: firstYear,
                  max: thisYear,
                  noneLabel: 'Not set',
                  onChanged: (v) => _change(() => _practisingSince = v),
                ),
              ],
            ),
            SizedBox(height: D.s6),

            // ---- Memberships and awards ------------------------------
            const ProfileEyebrow(label: 'MEMBERSHIPS AND AWARDS'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                TagField(
                  first: true,
                  label: 'Bodies you belong to',
                  values: _memberships,
                  suggestions: const ['RSSDI member', 'API member', 'IMA member'],
                  onChanged: (v) => _change(() => _memberships = v),
                ),
              ],
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

  Future<void> _addDegree() async {
    final name = TextEditingController();
    final institution = TextEditingController();
    final year = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: D.card,
        title: Text('Add a qualification', style: D.subhead.copyWith(color: D.ink)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: D.input.copyWith(color: D.ink),
                decoration: const InputDecoration(
                  labelText: 'Degree',
                  hintText: 'MBBS',
                ),
              ),
              SizedBox(height: D.s3),
              TextField(
                controller: institution,
                textCapitalization: TextCapitalization.words,
                style: D.input.copyWith(color: D.ink),
                decoration: const InputDecoration(
                  labelText: 'Institution',
                  hintText: 'Calcutta Medical College',
                ),
              ),
              SizedBox(height: D.s3),
              TextField(
                controller: year,
                keyboardType: TextInputType.number,
                style: D.input.copyWith(color: D.ink),
                decoration: const InputDecoration(
                  labelText: 'Year',
                  hintText: '2008',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: D.bodyStrong.copyWith(color: D.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Add', style: D.bodyStrong.copyWith(color: D.brand)),
          ),
        ],
      ),
    );

    final typed = name.text.trim();
    final where = institution.text.trim();
    final when = int.tryParse(year.text.trim());
    for (final c in [name, institution, year]) {
      c.dispose();
    }
    // The degree is the row. Without it there is nothing to show, and an
    // institution on its own is not a qualification.
    if (ok != true || typed.isEmpty) return;
    _change(
      () => _degrees.add(
        Degree(
          name: typed,
          institution: where.isEmpty ? null : where,
          year: when,
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
        professional: {
          // Empty is null, so a field typed by mistake can be emptied and
          // cleared rather than saved as a blank string.
          'professionType': _professionType,
          'council': _council.text.trim().isEmpty ? null : _council.text.trim(),
          'registrationYear': _registrationYear,
          'hprId': _hpr.text.trim().isEmpty ? null : _hpr.text.trim(),
          'degrees': [for (final d in _degrees) d.toJson()],
          'specialisations': _specialisations,
          'conditionsTreated': _conditions,
          'practisingSince': _practisingSince,
          'memberships': _memberships,
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
