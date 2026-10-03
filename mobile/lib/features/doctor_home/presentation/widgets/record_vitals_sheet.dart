import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/submission_keys.dart';
import '../../../../core/theme/doctor_tokens.dart';
import '../../../../core/utils/vitals_validators.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../clinician/data/clinician_repository.dart';
import '../../../clinician/domain/patient_summary.dart';
import '../../../clinician/presentation/clinician_providers.dart';

/// Recording what was measured, from the record rather than from a consult.
///
/// ---- Why this is not a small consult --------------------------------------
///
/// It writes through `recordConsultVitals`, the same call the consult's first
/// step makes: height and weight go to the profile, the rest becomes a vital
/// record, and a fasting sugar becomes a glucose reading like any other. One
/// path for a measurement, whoever took it — a second would mean two kinds of
/// blood pressure in one record.
///
/// ---- What it will not take -------------------------------------------------
///
/// Temperature. The artboard has a tile for it and this server has nowhere to
/// put it: no field on the vital record, nothing in the endpoint. A box that
/// accepted a temperature and dropped it would be worse than not offering one.
///
/// ---- Sent once ------------------------------------------------------------
///
/// The submission key is made when the sheet opens, so a double tap on a slow
/// connection writes one set of readings rather than two.
Future<bool> recordVitals(
  BuildContext context, {
  required String patientId,
  required PatientSummary patient,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    showDragHandle: false,
    isScrollControlled: true,
    backgroundColor: D.card,
    barrierColor: D.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
    ),
    builder: (_) => _RecordVitalsSheet(patientId: patientId, patient: patient),
  );
  return saved ?? false;
}

class _RecordVitalsSheet extends ConsumerStatefulWidget {
  const _RecordVitalsSheet({required this.patientId, required this.patient});

  final String patientId;
  final PatientSummary patient;

  @override
  ConsumerState<_RecordVitalsSheet> createState() => _RecordVitalsSheetState();
}

class _RecordVitalsSheetState extends ConsumerState<_RecordVitalsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _submission = SubmissionKeys();

  late final _systolic = TextEditingController();
  late final _diastolic = TextEditingController();
  late final _pulse = TextEditingController();
  late final _spo2 = TextEditingController();
  late final _sugar = TextEditingController();
  late final _weight = TextEditingController(
    text: widget.patient.weightKg == null ? '' : '${widget.patient.weightKg}',
  );
  // Height barely changes in an adult, so the one on file is the starting
  // point rather than a box to fill in again at every visit.
  late final _height = TextEditingController(
    text: widget.patient.heightCm == null ? '' : '${widget.patient.heightCm}',
  );
  late final _waist = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_systolic, _diastolic, _pulse, _spo2, _sugar, _weight, _height, _waist]) {
      c.dispose();
    }
    super.dispose();
  }

  void _typed() => setState(() {});

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());
  double? _double(TextEditingController c) => double.tryParse(c.text.trim());

  bool get _anything => [
    _systolic,
    _diastolic,
    _pulse,
    _spo2,
    _sugar,
    _weight,
    _height,
    _waist,
  ].any((c) => c.text.trim().isNotEmpty);

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Half a blood pressure is not a blood pressure.
    if ((_systolic.text.trim().isEmpty) != (_diastolic.text.trim().isEmpty)) {
      setState(() => _error = 'A blood pressure needs both numbers.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(clinicianRepositoryProvider)
          .recordConsultVitals(
            patientId: widget.patientId,
            heightCm: _double(_height),
            weightKg: _double(_weight),
            waistCm: _double(_waist),
            systolic: _int(_systolic),
            diastolic: _int(_diastolic),
            pulse: _int(_pulse),
            spo2: _int(_spo2),
            glucoseMgDl: _int(_sugar),
            submission: _submission,
          );
      ref.invalidate(patientSummaryProvider(widget.patientId));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorView.messageFor(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: D.s8 + D.s1,
                    height: D.s1,
                    decoration: const BoxDecoration(color: D.lineStrong, borderRadius: D.rPill),
                  ),
                ),
                SizedBox(height: D.s5),
                Text('Record vitals', style: D.screenTitle.copyWith(color: D.ink)),
                SizedBox(height: D.s2),
                Text(
                  'Only what was measured. Anything left blank is left alone.',
                  style: D.body.copyWith(color: D.inkMuted),
                ),
                SizedBox(height: D.s4),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _Box(
                                onChanged: _typed,
                                fieldKey: const Key('v-systolic'),
                                label: 'BP systolic',
                                unit: 'mmHg',
                                controller: _systolic,
                                validator: VitalsValidators.systolic,
                              ),
                            ),
                            SizedBox(width: D.s3),
                            Expanded(
                              child: _Box(
                                onChanged: _typed,
                                fieldKey: const Key('v-diastolic'),
                                label: 'BP diastolic',
                                unit: 'mmHg',
                                controller: _diastolic,
                                validator: (v) => VitalsValidators.diastolic(
                                  v,
                                  systolicText: _systolic.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: D.s3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _Box(
                                onChanged: _typed,
                                fieldKey: const Key('v-pulse'),
                                label: 'Pulse',
                                unit: 'bpm',
                                controller: _pulse,
                                validator: VitalsValidators.pulse,
                              ),
                            ),
                            SizedBox(width: D.s3),
                            Expanded(
                              child: _Box(
                                onChanged: _typed,
                                fieldKey: const Key('v-spo2'),
                                label: 'SpO₂',
                                unit: '%',
                                controller: _spo2,
                                validator: VitalsValidators.spo2,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: D.s3),
                        _Box(
                          onChanged: _typed,
                          fieldKey: const Key('v-sugar'),
                          label: 'Fasting sugar',
                          unit: 'mg/dL',
                          controller: _sugar,
                          validator: VitalsValidators.sugar,
                          // The one measurement here that is also a reading:
                          // it joins the glucose series the chart draws.
                          note: 'Goes on the fasting sugar chart',
                        ),
                        SizedBox(height: D.s3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _Box(
                                onChanged: _typed,
                                fieldKey: const Key('v-weight'),
                                label: 'Weight',
                                unit: 'kg',
                                controller: _weight,
                                decimal: true,
                                validator: VitalsValidators.weight,
                              ),
                            ),
                            SizedBox(width: D.s3),
                            Expanded(
                              child: _Box(
                                onChanged: _typed,
                                fieldKey: const Key('v-height'),
                                label: 'Height',
                                unit: 'cm',
                                controller: _height,
                                decimal: true,
                                validator: VitalsValidators.height,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: D.s3),
                        _Box(
                          onChanged: _typed,
                          fieldKey: const Key('v-waist'),
                          label: 'Waist',
                          unit: 'cm',
                          controller: _waist,
                          decimal: true,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  SizedBox(height: D.s3),
                  Text(_error!, style: D.statLabel.copyWith(color: D.danger)),
                ],
                SizedBox(height: D.s4),
                FilledButton(
                  onPressed: _saving || !_anything ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: D.brand,
                    foregroundColor: D.onBrand,
                    disabledBackgroundColor: D.line,
                    disabledForegroundColor: D.inkFaint,
                    elevation: 0,
                    minimumSize: Size.fromHeight(
                      MediaQuery.textScalerOf(context).scale(D.inputH),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(D.rCard),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: D.icon,
                          height: D.icon,
                          child: CircularProgressIndicator(strokeWidth: 2, color: D.onBrand),
                        )
                      : Text(
                          _anything ? 'Save to the record' : 'Nothing to save yet',
                          style: D.input.copyWith(fontWeight: FontWeight.w600),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One measurement: its name above, its unit inside, its complaint below.
class _Box extends StatelessWidget {
  const _Box({
    required this.fieldKey,
    required this.label,
    required this.unit,
    required this.controller,
    this.validator,
    this.decimal = false,
    this.note,
    this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String unit;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool decimal;
  final String? note;

  /// The sheet redraws as soon as something is typed: the button only offers
  /// to save once there is something to save, and it has to notice.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: D.dateLine.copyWith(color: D.ink)),
        SizedBox(height: D.s2),
        TextFormField(
          key: fieldKey,
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [
            decimal
                ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                : FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          validator: validator,
          onChanged: (_) => onChanged?.call(),
          style: D.input.copyWith(color: D.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: D.card,
            contentPadding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s3),
            suffixText: unit,
            suffixStyle: D.statLabel.copyWith(color: D.inkFaint),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(D.rCard),
              borderSide: const BorderSide(color: D.lineStrong),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(D.rCard),
              borderSide: const BorderSide(color: D.lineStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(D.rCard),
              borderSide: const BorderSide(color: D.brand, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(D.rCard),
              borderSide: const BorderSide(color: D.danger),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(D.rCard),
              borderSide: const BorderSide(color: D.danger, width: 1.5),
            ),
            errorStyle: D.statLabel.copyWith(color: D.danger),
          ),
        ),
        if (note != null) ...[
          SizedBox(height: D.s1),
          Text(note!, style: D.caption.copyWith(color: D.inkFaint)),
        ],
      ],
    );
  }
}
