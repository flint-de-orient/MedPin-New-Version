import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../clinician/data/medicine_brand_repository.dart';
import '../../../medications/domain/med_shorthand.dart';
import '../../domain/consult_draft.dart';

/// Writing one line of a prescription.
///
/// The dose is the part a patient follows for a month, so it is chosen rather
/// than typed: the shorthand a doctor already writes (OD, BD, TDS…) as chips,
/// and the meal relation only where the frequency takes one — "as needed" and
/// "immediately" do not, and offering "after food" beside them invites a
/// contradiction onto the pad.
///
/// The name is looked up against the clinic's dictionary as it is typed, which
/// is also where the strength comes from: a doctor who picks "Metformin 500 mg"
/// should not then type 500 again.
Future<MedLine?> editMedicine(
  BuildContext context, {
  MedLine? existing,
  String? initialName,
  required List<String> allergies,
}) {
  return showModalBottomSheet<MedLine>(
    context: context,
    useRootNavigator: true,
    showDragHandle: false,
    isScrollControlled: true,
    backgroundColor: D.card,
    barrierColor: D.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
    ),
    builder: (_) => _MedicineSheet(
      existing: existing,
      initialName: initialName,
      allergies: allergies,
    ),
  );
}

class _MedicineSheet extends ConsumerStatefulWidget {
  const _MedicineSheet({
    required this.existing,
    required this.initialName,
    required this.allergies,
  });

  final MedLine? existing;
  final String? initialName;
  final List<String> allergies;

  @override
  ConsumerState<_MedicineSheet> createState() => _MedicineSheetState();
}

class _MedicineSheetState extends ConsumerState<_MedicineSheet> {
  late final _name = TextEditingController(
    text: widget.existing?.name ?? widget.initialName ?? '',
  );
  late final _strength = TextEditingController(text: widget.existing?.strength ?? '');
  late final _duration = TextEditingController(
    text: widget.existing?.durationDays?.toString() ?? '',
  );
  late final _instructions = TextEditingController(text: widget.existing?.instructions ?? '');

  late DoseFrequency _frequency = widget.existing?.frequency ?? DoseFrequency.od;
  late MealRelation _relation = widget.existing?.relation ?? MealRelation.after;
  late MedRoute _route = widget.existing?.route ?? MedRoute.oral;

  @override
  void dispose() {
    for (final c in [_name, _strength, _duration, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final name = _name.text.trim();
    final caution = cautionFor(name, widget.allergies);
    final matches = name.length < 2
        ? const AsyncValue<List<MedicineBrand>>.data([])
        : ref.watch(medicineBrandSearchProvider(name));

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
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
              Text(
                widget.existing == null ? 'Add medicine' : 'Edit medicine',
                style: D.screenTitle.copyWith(color: D.ink),
              ),
              SizedBox(height: D.s4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Label('Medicine'),
                      _Box(
                        fieldKey: const Key('m-name'),
                        controller: _name,
                        hint: 'Name as you write it',
                        onChanged: (_) => setState(() {}),
                      ),
                      // The dictionary, as it is typed. Picking one fills the
                      // strength too, so nobody types 500 twice.
                      matches.maybeWhen(
                        data: (brands) => brands.isEmpty || brands.first.name == name
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: EdgeInsets.only(top: D.s2),
                                child: Wrap(
                                  spacing: D.s2,
                                  runSpacing: D.s2,
                                  children: [
                                    for (final b in brands.take(6))
                                      ActionChip(
                                        label: Text(
                                          b.strengthWithUnit.trim().isEmpty
                                              ? b.name
                                              : '${b.name} ${b.strengthWithUnit}',
                                          style: D.statLabel.copyWith(color: D.brand),
                                        ),
                                        backgroundColor: D.brandTint,
                                        side: BorderSide.none,
                                        // The dictionary writes the strength as
                                        // it should be written — "500/1" for a
                                        // combination — so it is taken whole
                                        // rather than retyped.
                                        onPressed: () => setState(() {
                                          _name.text = b.name;
                                          if (b.strengthWithUnit.trim().isNotEmpty) {
                                            _strength.text = b.strengthWithUnit;
                                          }
                                        }),
                                      ),
                                  ],
                                ),
                              ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                      if (caution != null) ...[
                        SizedBox(height: D.s3),
                        _Caution(text: caution),
                      ],
                      SizedBox(height: D.s4),
                      _Label('Strength'),
                      _Box(
                        fieldKey: const Key('m-strength'),
                        controller: _strength,
                        hint: 'e.g. 500 mg',
                      ),
                      SizedBox(height: D.s4),
                      _Label('How often'),
                      Wrap(
                        spacing: D.s2,
                        runSpacing: D.s2,
                        children: [
                          for (final f in DoseFrequency.values)
                            _Pick(
                              label: f.code,
                              detail: f.plain,
                              on: f == _frequency,
                              onTap: () => setState(() => _frequency = f),
                            ),
                        ],
                      ),
                      if (_frequency.takesMealRelation) ...[
                        SizedBox(height: D.s4),
                        _Label('With food'),
                        Wrap(
                          spacing: D.s2,
                          runSpacing: D.s2,
                          children: [
                            for (final r in MealRelation.values)
                              _Pick(
                                label: r.plain,
                                on: r == _relation,
                                onTap: () => setState(() => _relation = r),
                              ),
                          ],
                        ),
                      ],
                      SizedBox(height: D.s4),
                      _Label('For how long'),
                      _Box(
                        fieldKey: const Key('m-duration'),
                        controller: _duration,
                        hint: 'Days — leave blank for ongoing',
                        digits: true,
                      ),
                      SizedBox(height: D.s4),
                      _Label('Route'),
                      Wrap(
                        spacing: D.s2,
                        runSpacing: D.s2,
                        children: [
                          for (final r in MedRoute.values)
                            _Pick(
                              label: r.plain,
                              on: r == _route,
                              onTap: () => setState(() => _route = r),
                            ),
                        ],
                      ),
                      SizedBox(height: D.s4),
                      _Label('Anything else on the label'),
                      _Box(
                        fieldKey: const Key('m-instructions'),
                        controller: _instructions,
                        hint: 'e.g. with plenty of water',
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: D.s4),
              FilledButton(
                onPressed: name.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                        MedLine(
                          name: name,
                          strength: _strength.text.trim(),
                          frequency: _frequency,
                          relation: _relation,
                          route: _route,
                          durationDays: int.tryParse(_duration.text.trim()),
                          instructions: _instructions.text.trim(),
                        ),
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: D.brand,
                  foregroundColor: D.onBrand,
                  disabledBackgroundColor: D.line,
                  disabledForegroundColor: D.inkFaint,
                  elevation: 0,
                  minimumSize: Size.fromHeight(
                    MediaQuery.textScalerOf(context).scale(D.inputH),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rCard)),
                ),
                child: Text(
                  name.isEmpty ? 'Name the medicine' : 'Add to the prescription',
                  style: D.input.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the record says about this patient and this name.
class _Caution extends StatelessWidget {
  const _Caution({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.s3, vertical: D.s3),
      decoration: BoxDecoration(
        color: D.pendingGround,
        borderRadius: BorderRadius.circular(D.s3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: D.icon, color: D.pending),
          SizedBox(width: D.s2),
          Expanded(child: Text(text, style: D.statLabel.copyWith(color: D.ink, height: 1.45))),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: D.s2),
    child: Text(text, style: D.dateLine.copyWith(color: D.ink)),
  );
}

class _Box extends StatelessWidget {
  const _Box({
    required this.fieldKey,
    required this.controller,
    this.hint,
    this.digits = false,
    this.onChanged,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String? hint;
  final bool digits;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.textScalerOf(context).scale(D.inputH),
      ),
      padding: EdgeInsets.symmetric(horizontal: D.s4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(D.rCard),
        border: Border.all(color: D.lineStrong),
      ),
      child: Align(
        child: TextField(
          key: fieldKey,
          controller: controller,
          keyboardType: digits ? TextInputType.number : null,
          inputFormatters: digits
              ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)]
              : null,
          textCapitalization: TextCapitalization.sentences,
          onChanged: onChanged,
          style: D.input.copyWith(color: D.ink),
          decoration: D.bareField(
            hint: hint,
            hintStyle: D.input.copyWith(color: D.inkFaint),
          ),
        ),
      ),
    );
  }
}

/// One of a small set of choices, with what it means underneath.
class _Pick extends StatelessWidget {
  const _Pick({required this.label, required this.on, required this.onTap, this.detail});

  final String label;
  final String? detail;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? D.brand : D.card,
        borderRadius: BorderRadius.circular(D.s3),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(D.s3),
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(D.tap),
            ),
            padding: EdgeInsets.symmetric(horizontal: D.s3, vertical: D.s1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.s3),
              border: Border.all(color: on ? D.brand : D.lineStrong),
            ),
            child: Align(
              widthFactor: 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: D.dateLine.copyWith(color: on ? D.onBrand : D.ink),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: D.caption.copyWith(color: on ? D.onBrandProse : D.inkFaint),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
