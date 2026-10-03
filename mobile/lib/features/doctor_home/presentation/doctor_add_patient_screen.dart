import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/area.dart';
import '../../../core/theme/doctor_tokens.dart';
import '../../../core/utils/auth_validators.dart';
import '../../../core/utils/vitals_validators.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/otp_field.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../clinician/data/clinician_repository.dart';
import '../../clinician/domain/patient_registration.dart';
import '../../clinician/presentation/clinician_providers.dart';
import '../../clinician/presentation/widgets/consent_code_dialog.dart';

/// Registering a walk-in, drawn to the new design (`Add-Patient`).
///
/// ---- Why a second screen and not a repaint ---------------------------------
///
/// The desk has the same form at `/staff/patients/new`, and the desk's screens
/// are not being redesigned. `AddPatientScreen` is left exactly as it is and
/// keeps that route; this one serves the doctor's `/clinician/patients/new`.
/// The two must stay the same *form* — the same fields, the same validation,
/// the same proof of the number, the same consent — so anything changed in one
/// belongs in the other.
///
/// ---- What the artboard draws, and what this clinic actually has -------------
///
/// The artboard's vitals are blood pressure, pulse, weight and fasting sugar.
/// This server records height and SpO₂ as well, and keeps systolic and
/// diastolic as two numbers rather than the artboard's single "128/84" — so
/// the grid holds seven fields in the artboard's shape rather than four in its
/// exact list. Dropping the other three would quietly stop recording them.
class DoctorAddPatientScreen extends ConsumerStatefulWidget {
  const DoctorAddPatientScreen({super.key});

  @override
  ConsumerState<DoctorAddPatientScreen> createState() => _DoctorAddPatientScreenState();
}

class _DoctorAddPatientScreenState extends ConsumerState<DoctorAddPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  var _autovalidate = AutovalidateMode.disabled;

  final _name = TextEditingController();
  final _age = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  final _pulse = TextEditingController();
  final _sugar = TextEditingController();
  final _spo2 = TextEditingController();
  final _complaints = TextEditingController();
  final _code = TextEditingController();

  String? _gender;
  bool _submitting = false;
  bool _vitalsOpen = false;
  bool _complaintsOpen = false;

  // ---- proving the number ---------------------------------------------------
  //
  // The patient is standing at the counter, so the code goes to their phone and
  // they read it out. Sign-in is a code texted to this number: a digit mistyped
  // here is an account the patient can never get into, found out weeks later,
  // by them, with nothing to say why.
  //
  // Not compulsory. A flat battery or no signal in the building must not stop a
  // patient being registered. Unverified is allowed and said out loud, never
  // allowed silently.
  bool _codeSent = false;
  bool _verifying = false;
  String? _phoneToken;
  String? _phoneError;
  OtpSent? _sent;

  bool get _phoneVerified => _phoneToken != null;

  /// The number already has a MedPin account. Registering it texts the patient
  /// a code to add them to this practice; there is nothing to verify here.
  bool _existingAccount = false;

  /// The number the token was issued for, so editing the field after verifying
  /// drops the proof instead of carrying it onto a different patient.
  String? _verifiedNumber;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name,
      _age,
      _phone,
      _address,
      _height,
      _weight,
      _systolic,
      _diastolic,
      _pulse,
      _sugar,
      _spo2,
      _complaints,
      _code,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());
  double? _double(TextEditingController c) => double.tryParse(c.text.trim());

  Future<void> _sendCode() async {
    if (!AuthValidators.isValidPhone(_phone.text)) {
      setState(() => _phoneError = 'Enter a valid 10-digit number');
      return;
    }
    setState(() {
      _verifying = true;
      _phoneError = null;
    });

    final result = await ref
        .read(authControllerProvider.notifier)
        .requestOtp(phone: AuthValidators.toE164(_phone.text), purpose: 'register');

    if (!mounted) return;
    setState(() => _verifying = false);

    final error = result.error;
    if (error != null) {
      setState(() {
        // An existing account is not a dead end: registering it sends the
        // patient their own code, and the enrolment waits for that.
        if (error.code == 'CONFLICT') {
          _existingAccount = true;
          _phoneError = null;
        } else {
          _phoneError = ErrorView.messageFor(context, error);
        }
      });
      return;
    }
    setState(() {
      _sent = result.sent;
      _code.clear();
      _codeSent = true;
    });
  }

  Future<void> _verifyCode() async {
    if (_code.text.length < 6) {
      setState(() => _phoneError = 'Enter all 6 digits');
      return;
    }
    setState(() {
      _verifying = true;
      _phoneError = null;
    });
    try {
      final token = await ref
          .read(authRepositoryProvider)
          .verifyRegisterOtp(phone: AuthValidators.toE164(_phone.text), code: _code.text);
      if (!mounted) return;
      setState(() {
        _phoneToken = token;
        _verifiedNumber = _phone.text.trim();
        _codeSent = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _phoneError = ErrorView.messageFor(context, e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// Drops the proof when the number is edited after being verified.
  void _onPhoneChanged() {
    if (_existingAccount) setState(() => _existingAccount = false);
    if (!_phoneVerified && !_codeSent) return;
    if (_phone.text.trim() == _verifiedNumber) return;
    setState(_forgetNumber);
  }

  void _forgetNumber() {
    _existingAccount = false;
    _phoneToken = null;
    _verifiedNumber = null;
    _codeSent = false;
    _code.clear();
    _phoneError = null;
  }

  /// Confirms before creating a patient whose number was never proved.
  ///
  /// Stated as the consequence rather than as a warning: "unverified" means
  /// nothing at a busy desk, "may not be able to sign in" is the thing the
  /// person at the counter can act on.
  Future<bool> _confirmUnverified() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add without verifying?'),
        content: const Text(
          'The patient signs in with a code texted to this number. If it is '
          'wrong they will not be able to sign in, and nobody will know until '
          'they try.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add anyway'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    // No "they may not be able to sign in" for an existing account: they
    // already can, and the patient confirms the number with the code.
    if (!_phoneVerified && !_existingAccount && !await _confirmUnverified()) return;
    if (!mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(clinicianRepositoryProvider)
          .createPatient(
            name: _name.text.trim(),
            phone: AuthValidators.toE164(_phone.text),
            phoneToken: _phoneToken,
            age: _int(_age),
            gender: _gender,
            address: _address.text.trim(),
            complaints: _complaints.text.trim(),
            heightCm: _double(_height),
            weightKg: _double(_weight),
            systolic: _int(_systolic),
            diastolic: _int(_diastolic),
            pulse: _int(_pulse),
            spo2: _int(_spo2),
            glucoseMgDl: _int(_sugar),
          );
      // The roll must show the new patient the moment we return to it.
      ref.invalidate(patientsProvider);
      if (!mounted) return;

      // Registering a number that already has an account does not enrol it:
      // the enrolment is written PENDING and grants nothing until the patient
      // reads back a code sent to their own handset. Every clinical list is
      // scoped to active enrolments, so until then they are correctly
      // invisible — which is why this cannot just say "added" and walk in.
      var id = result.id;
      var sharingLine = '';
      if (result.consentRequired) {
        final confirmation = await _takeConsentCode(result);
        if (!mounted) return;
        if (confirmation == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_name.text.trim()} is waiting on their code. They will not '
                'appear in the list until it is entered — add them again to '
                'send a fresh one.',
              ),
              duration: const Duration(seconds: 6),
            ),
          );
          context.pop();
          return;
        }
        ref.invalidate(patientsProvider);
        ref.invalidate(pendingEnrolmentsProvider);
        id = confirmation.patientId ?? '';
        sharingLine = ' ${confirmation.sharingSummary}';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_name.text.trim()} added.$sharingLine')));
      // Replace the form with the record just created, so Back lands on the
      // roll rather than an empty form.
      if (id.isNotEmpty) {
        context.pushReplacement('${areaPrefix(ref)}/patients/$id', extra: _name.text.trim());
      } else {
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorView.messageFor(context, e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The code the patient was texted, and their answers about what this clinic
  /// may see, taken in the same step. See [showConsentCodeDialog].
  ///
  /// The artboard draws this as a sheet with the six boxes alone. The dialog
  /// also puts the two sharing questions to the patient standing there, and
  /// their answers travel with the code — so the dialog stays, rather than a
  /// prettier sheet that records less.
  Future<EnrolmentConfirmation?> _takeConsentCode(PatientRegistration result) async {
    final id = result.enrollmentId;
    // Nothing to confirm against. The server sends this whenever consent is
    // required, so its absence is a server that has changed shape.
    if (id == null || id.isEmpty) return null;

    return showConsentCodeDialog(
      context,
      enrollmentId: id,
      title: 'Ask them to read out the code',
      message: result.message.isEmpty
          ? 'This number already has a MedPin account. We have texted it a code — ask the '
                'patient to read it out.'
          : result.message,
    );
  }

  /// How many vitals have been typed, so a section somebody has already filled
  /// in never looks skipped once it is folded away.
  int get _vitalsFilled => [
    _height,
    _weight,
    _systolic,
    _diastolic,
    _pulse,
    _spo2,
    _sugar,
  ].where((c) => c.text.trim().isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: D.ground,
      appBar: AppBar(
        backgroundColor: D.ground,
        surfaceTintColor: D.ground,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: MediaQuery.textScalerOf(context).scale(D.bar),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded, size: D.iconDisc),
          color: D.ink,
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Text('Add patient', style: D.screenTitle.copyWith(color: D.ink)),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidate,
          child: ListView(
            padding: EdgeInsets.fromLTRB(D.s5, D.s2, D.s5, D.s8),
            children: [
              _Card(
                title: 'Patient details',
                subtitle: 'Required to add the patient',
                children: [
                  _Labelled(
                    label: 'Full name',
                    child: _Field(
                      fieldKey: const Key('f-name'),
                      controller: _name,
                      hint: 'As it should appear on the prescription',
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v == null || v.trim().length < 2) ? 'Enter the patient’s name' : null,
                    ),
                  ),
                  SizedBox(height: D.s4),
                  _Labelled(
                    label: 'Age',
                    child: SizedBox(
                      // The artboard's 144: wide enough for three digits and
                      // "years", and narrow enough to read as a number field.
                      width: D.tileMin + D.s8,
                      child: _Field(
                        fieldKey: const Key('f-age'),
                        controller: _age,
                        suffix: 'years',
                        keyboardType: TextInputType.number,
                        formatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null) return 'Required';
                          if (n < 0 || n > 120) return '0–120';
                          return null;
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: D.s4),
                  _Labelled(
                    label: 'Gender',
                    child: _Gender(
                      value: _gender,
                      onChanged: (v) => setState(() => _gender = v),
                      // The form asks for it, so a blank one has to say so
                      // somewhere: the segmented control cannot carry a field
                      // error of its own.
                      error: _autovalidate != AutovalidateMode.disabled && _gender == null
                          ? 'Choose one'
                          : null,
                    ),
                  ),
                  SizedBox(height: D.s4),
                  _Labelled(label: 'Phone number', child: _phoneField(context)),
                  SizedBox(height: D.s4),
                  _Labelled(
                    label: 'Address',
                    child: _Field(
                      fieldKey: const Key('f-address'),
                      controller: _address,
                      hint: 'Street, area, city and PIN',
                      lines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Enter the address' : null,
                    ),
                  ),
                ],
              ),
              SizedBox(height: D.s4),
              _Fold(
                title: 'Vitals',
                subtitle: _vitalsFilled > 0
                    ? '$_vitalsFilled filled in · the doctor sees these before the visit'
                    : 'Optional · the doctor sees these before the visit',
                open: _vitalsOpen,
                onTap: () => setState(() => _vitalsOpen = !_vitalsOpen),
                children: [
                  _Pair(
                    left: _vital(_systolic, 'BP systolic', 'mmHg', VitalsValidators.systolic),
                    right: _vital(
                      _diastolic,
                      'BP diastolic',
                      'mmHg',
                      (v) => VitalsValidators.diastolic(v, systolicText: _systolic.text),
                    ),
                  ),
                  SizedBox(height: D.s4),
                  _Pair(
                    left: _vital(_pulse, 'Pulse', 'bpm', VitalsValidators.pulse),
                    right: _vital(_spo2, 'SpO₂', '%', VitalsValidators.spo2),
                  ),
                  SizedBox(height: D.s4),
                  _Pair(
                    left: _vital(_height, 'Height', 'cm', VitalsValidators.height, decimal: true),
                    right: _vital(_weight, 'Weight', 'kg', VitalsValidators.weight, decimal: true),
                  ),
                  SizedBox(height: D.s4),
                  _Pair(
                    left: _vital(_sugar, 'Fasting sugar', 'mg/dL', VitalsValidators.sugar),
                    right: null,
                  ),
                ],
              ),
              SizedBox(height: D.s4),
              _Fold(
                title: 'Complaints',
                subtitle: _complaints.text.trim().isEmpty
                    ? 'Optional · what brings them in today'
                    : 'Written down',
                open: _complaintsOpen,
                onTap: () => setState(() => _complaintsOpen = !_complaintsOpen),
                children: [
                  _Field(
                    fieldKey: const Key('f-complaints'),
                    controller: _complaints,
                    hint: 'e.g. increased thirst and fatigue for 2 weeks',
                    lines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              if (_error != null) ...[
                SizedBox(height: D.s4),
                Container(
                  padding: EdgeInsets.all(D.cardPad),
                  decoration: BoxDecoration(
                    color: D.dangerGround,
                    borderRadius: BorderRadius.circular(D.rCard),
                    border: Border.all(color: D.dangerLine),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: D.iconLg, color: D.danger),
                      SizedBox(width: D.s3),
                      Expanded(
                        child: Text(_error!, style: D.body.copyWith(color: D.danger)),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: D.s5),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(D.rCard),
                  boxShadow: _submitting ? const [] : D.liftBrand,
                ),
                child: FilledButton(
                  key: const Key('f-submit'),
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: D.brand,
                    foregroundColor: D.onBrand,
                    elevation: 0,
                    minimumSize: Size.fromHeight(
                      MediaQuery.textScalerOf(context).scale(D.inputH),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(D.rCard),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: D.icon,
                          height: D.icon,
                          child: CircularProgressIndicator(strokeWidth: 2, color: D.onBrand),
                        )
                      : Text(
                          'Add patient',
                          style: D.input.copyWith(
                            color: D.onBrand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The number, the proof of it, and whatever is true about it right now.
  Widget _phoneField(BuildContext context) {
    final locked = _codeSent || _phoneVerified;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Field(
                fieldKey: const Key('f-phone'),
                controller: _phone,
                enabled: !locked,
                prefix: '+91',
                keyboardType: TextInputType.phone,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                trailing: _phoneVerified
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_rounded, size: D.iconMd, color: D.done),
                          SizedBox(width: D.gapTight),
                          Text('Verified', style: D.dateLine.copyWith(color: D.done)),
                        ],
                      )
                    : null,
                onChanged: (_) => _onPhoneChanged(),
                validator: (v) => AuthValidators.isValidPhone(v ?? '')
                    ? null
                    : 'Enter a valid 10-digit number',
              ),
            ),
            if (!_phoneVerified && !_codeSent) ...[
              SizedBox(width: D.s2),
              FilledButton(
                onPressed: _verifying ? null : _sendCode,
                style: FilledButton.styleFrom(
                  backgroundColor: D.brandTint,
                  foregroundColor: D.brand,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(horizontal: D.s4),
                  minimumSize: Size(0, MediaQuery.textScalerOf(context).scale(D.inputH)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(D.rCard),
                  ),
                ),
                child: _verifying
                    ? const SizedBox(
                        width: D.icon,
                        height: D.icon,
                        child: CircularProgressIndicator(strokeWidth: 2, color: D.brand),
                      )
                    : Text(
                        'Verify',
                        style: D.subtitle.copyWith(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ],
        ),
        if (_codeSent) ...[
          SizedBox(height: D.s3),
          Text(
            'Ask the patient for the 6-digit code just texted to them.',
            style: D.statLabel.copyWith(color: D.inkFaint),
          ),
          SizedBox(height: D.s2),
          OtpCodeField(
            controller: _code,
            enabled: !_verifying,
            hasError: _phoneError != null,
            // Not autofocused: the number is still being read back, and a
            // keyboard over the form is in the way.
            autofocus: false,
            onCompleted: (_) => _verifyCode(),
          ),
          SizedBox(height: D.s2),
          Row(
            children: [
              TextButton(
                onPressed: _verifying ? null : () => setState(_forgetNumber),
                style: TextButton.styleFrom(minimumSize: D.hug),
                child: Text('Wrong number?', style: D.dateLine.copyWith(color: D.inkMuted)),
              ),
              SizedBox(width: D.s2),
              Expanded(
                child: FilledButton(
                  onPressed: _verifying ? null : _verifyCode,
                  style: FilledButton.styleFrom(
                    backgroundColor: D.brand,
                    foregroundColor: D.onBrand,
                    elevation: 0,
                    minimumSize: Size(0, MediaQuery.textScalerOf(context).scale(D.tap)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(D.s3),
                    ),
                  ),
                  child: Text('Confirm', style: D.dateLine),
                ),
              ),
            ],
          ),
          if (_sent?.simulated ?? false)
            Padding(
              padding: EdgeInsets.only(top: D.s2),
              child: Text(
                'SMS is not set up on this server, so no message was sent. The code is in '
                'the server log.',
                style: D.statLabel.copyWith(color: D.pending),
              ),
            ),
        ],
        SizedBox(height: D.s2),
        Text(
          _phoneError ??
              (_existingAccount
                  ? 'This number already has a MedPin account. Tap Add patient — we will '
                        'text them a code to add them to your clinic.'
                  : _phoneVerified
                  ? 'Confirmed. The patient’s app will use this number.'
                  : 'The patient signs in with a code texted here. Verify it while they '
                        'are standing in front of you.'),
          style: D.statLabel.copyWith(
            color: _phoneError != null
                ? D.danger
                : _existingAccount
                ? D.brand
                : D.inkFaint,
          ),
        ),
      ],
    );
  }

  Widget _vital(
    TextEditingController c,
    String label,
    String unit,
    String? Function(String?) validator, {
    bool decimal = false,
  }) {
    return _Labelled(
      label: label,
      child: _Field(
        fieldKey: Key('f-${label.toLowerCase().replaceAll(' ', '-')}'),
        controller: c,
        suffix: unit,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        formatters: [
          decimal
              ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              : FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        validator: validator,
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

/// A white card with a heading: the form's one surface level.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(title, style: D.screenTitle.copyWith(color: D.ink)),
          SizedBox(height: D.s1 / 2),
          Text(subtitle, style: D.body.copyWith(color: D.inkMuted)),
          SizedBox(height: D.s4),
          ...children,
        ],
      ),
    );
  }
}

/// A section that folds away, in the same card as everything else.
///
/// The children stay mounted while it is closed, so a value typed and then
/// folded away is still validated and still submitted — hiding a field must
/// never quietly drop what is in it.
class _Fold extends StatelessWidget {
  const _Fold({
    required this.title,
    required this.subtitle,
    required this.open,
    required this.onTap,
    required this.children,
  });

  final String title;
  final String subtitle;
  final bool open;
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(D.rSection),
              child: Padding(
                padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.s4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: D.screenTitle.copyWith(color: D.ink)),
                          SizedBox(height: D.s1 / 2),
                          Text(subtitle, style: D.body.copyWith(color: D.inkMuted)),
                        ],
                      ),
                    ),
                    SizedBox(width: D.s3),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        size: D.iconLg,
                        color: D.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Visibility(
            visible: open,
            maintainState: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(D.s5, 0, D.s5, D.s5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label over its field, as the artboard sets every one of them.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: D.dateLine.copyWith(color: D.ink)),
        SizedBox(height: D.s2),
        child,
      ],
    );
  }
}

/// Two fields across, or one that keeps its half of the row.
class _Pair extends StatelessWidget {
  const _Pair({required this.left, required this.right});

  final Widget left;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: D.s3),
        Expanded(child: right ?? const SizedBox.shrink()),
      ],
    );
  }
}

/// The artboard's field: 56 tall, one hairline, the value set a size up.
///
/// Drawn rather than themed because the app's global `InputDecoration` is the
/// old design's — floating labels, filled grey, its own radius. The label here
/// sits above the box ([_Labelled]), which is what the artboard draws and what
/// stops a long label from being clipped into the border.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    this.fieldKey,
    this.hint,
    this.prefix,
    this.suffix,
    this.trailing,
    this.enabled = true,
    this.lines = 1,
    this.keyboardType,
    this.formatters,
    this.validator,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;

  /// On the TextField itself, so a test can reach one field of seven.
  final Key? fieldKey;

  final String? hint;

  /// The dialling code, in its own cell with a rule between.
  final String? prefix;

  /// A unit, after the value: "years", "mmHg".
  final String? suffix;

  /// Anything else that belongs inside the box — the green tick.
  final Widget? trailing;

  final bool enabled;
  final int lines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // One line is the artboard's 56; more lines grow from it. Scaled, because
    // a constant height around text clips it the moment somebody turns their
    // text size up.
    final height = scaler.scale(lines == 1 ? D.inputH : D.inputH + (lines - 1) * D.s6);

    return FormField<String>(
      initialValue: controller.text,
      validator: validator == null ? null : (_) => validator!(controller.text),
      builder: (field) {
        final failed = field.errorText != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: height,
              decoration: BoxDecoration(
                color: enabled ? D.card : D.ground,
                borderRadius: BorderRadius.circular(D.rCard),
                border: Border.all(color: failed ? D.danger : D.lineStrong),
              ),
              child: Row(
                crossAxisAlignment: lines == 1
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  if (prefix != null)
                    Container(
                      height: height,
                      padding: EdgeInsets.fromLTRB(D.s4, 0, D.s3, 0),
                      decoration: const BoxDecoration(
                        border: Border(right: BorderSide(color: D.line)),
                      ),
                      child: Align(
                        widthFactor: 1,
                        child: Text(
                          prefix!,
                          style: D.input.copyWith(
                            color: D.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        prefix == null ? D.s4 : D.s3,
                        lines == 1 ? 0 : D.cardPad,
                        D.s3,
                        lines == 1 ? 0 : D.cardPad,
                      ),
                      child: TextField(
                        key: fieldKey,
                        controller: controller,
                        enabled: enabled,
                        minLines: lines,
                        maxLines: lines,
                        keyboardType: keyboardType,
                        inputFormatters: formatters,
                        textCapitalization: textCapitalization,
                        style: D.input.copyWith(color: enabled ? D.ink : D.inkMuted),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: hint,
                          hintStyle: D.input.copyWith(color: D.inkFaint),
                        ),
                        onChanged: (v) {
                          field.didChange(v);
                          onChanged?.call(v);
                        },
                      ),
                    ),
                  ),
                  if (suffix != null)
                    Padding(
                      padding: EdgeInsets.only(right: D.s4),
                      child: Text(suffix!, style: D.statLabel.copyWith(color: D.inkFaint)),
                    ),
                  if (trailing != null)
                    Padding(padding: EdgeInsets.only(right: D.s4), child: trailing!),
                ],
              ),
            ),
            if (failed)
              Padding(
                padding: EdgeInsets.only(top: D.gapTight, left: D.s1),
                child: Text(field.errorText!, style: D.statLabel.copyWith(color: D.danger)),
              ),
          ],
        );
      },
    );
  }
}

/// Female · Male · Other, in a sunken track — the artboard's own control.
class _Gender extends StatelessWidget {
  const _Gender({required this.value, required this.onChanged, this.error});

  final String? value;
  final ValueChanged<String> onChanged;
  final String? error;

  static const _options = [('female', 'Female'), ('male', 'Male'), ('other', 'Other')];

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.textScalerOf(context).scale(D.tap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(D.s1),
          decoration: BoxDecoration(
            color: D.track,
            borderRadius: BorderRadius.circular(D.rCard),
            border: error == null ? null : Border.all(color: D.danger),
          ),
          child: Row(
            children: [
              for (final (code, label) in _options) ...[
                if (code != _options.first.$1) SizedBox(width: D.s1),
                Expanded(
                  child: Semantics(
                    inMutuallyExclusiveGroup: true,
                    selected: code == value,
                    button: true,
                    child: InkWell(
                      onTap: () => onChanged(code),
                      borderRadius: BorderRadius.circular(D.s3),
                      child: Container(
                        height: height,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: code == value ? D.card : null,
                          borderRadius: BorderRadius.circular(D.s3),
                          boxShadow: code == value ? D.lift : null,
                        ),
                        child: Text(
                          label,
                          style: D.subtitle.copyWith(
                            color: code == value ? D.ink : D.inkMuted,
                            fontWeight: code == value ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: EdgeInsets.only(top: D.gapTight, left: D.s1),
            child: Text(error!, style: D.statLabel.copyWith(color: D.danger)),
          ),
      ],
    );
  }
}
