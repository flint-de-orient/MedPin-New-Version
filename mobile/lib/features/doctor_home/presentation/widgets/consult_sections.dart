import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../clinician/domain/advice_catalog.dart';
import '../../../clinician/domain/diagnosis_catalog.dart';
import '../../../clinician/domain/lab_catalog.dart';
import '../../../clinician/domain/patient_summary.dart';
import '../../domain/consult_draft.dart';
import 'profile_parts.dart';
import 'profile_tabs.dart';

/// The six numbered sections of the consultation, and the three cards above
/// them that say who is being seen.
///
/// They are widgets rather than methods on the screen so each one can be read
/// on its own: the screen then says what a consultation is made of, in order,
/// and nothing else.

/// A card with a number on it, as the artboard numbers the steps.
class ConsultSection extends StatelessWidget {
  const ConsultSection({
    super.key,
    required this.step,
    required this.title,
    this.trailing,
    required this.child,
  });

  final int step;
  final String title;
  final Widget? trailing;
  final Widget child;

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
          Row(
            children: [
              Container(
                width: MediaQuery.textScalerOf(context).scale(D.s6 + 2),
                height: MediaQuery.textScalerOf(context).scale(D.s6 + 2),
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: D.brand, shape: BoxShape.circle),
                child: Text('$step', style: D.statLabel.copyWith(
                  color: D.onBrand,
                  fontWeight: FontWeight.w700,
                )),
              ),
              SizedBox(width: D.gapIcon),
              Expanded(child: Text(title, style: D.screenTitle.copyWith(color: D.ink))),
              if (trailing != null) trailing!,
            ],
          ),
          SizedBox(height: D.s3),
          child,
        ],
      ),
    );
  }
}

/// Who is being seen, and what must not be forgotten about them.
class ConsultPatientCard extends StatelessWidget {
  const ConsultPatientCard({super.key, required this.patient, required this.patientId});

  final PatientSummary patient;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.s5, vertical: D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rCardLg),
        border: Border.all(color: D.line),
        boxShadow: D.liftBrand,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                name: patient.name,
                avatarUrl: patient.avatarUrl,
                accent: D.brand,
                size: D.disc,
              ),
              SizedBox(width: D.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: D.cardTitle.copyWith(color: D.ink),
                    ),
                    Text(
                      [
                        if (patient.age != null) '${patient.age}',
                        if ((patient.gender ?? '').isNotEmpty)
                          patient.gender![0].toUpperCase(),
                      ].join(' '),
                      style: D.body.copyWith(color: D.inkMuted),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.pop(),
                style: TextButton.styleFrom(minimumSize: D.hug),
                child: Text('Profile', style: D.dateLine.copyWith(color: D.brand)),
              ),
            ],
          ),
          if (patient.details.allergies.isNotEmpty ||
              patient.details.comorbidities.isNotEmpty) ...[
            SizedBox(height: D.s3),
            Wrap(
              spacing: D.gapTight,
              runSpacing: D.gapTight,
              children: [
                // Allergies first here, unlike the record's header: this is the
                // screen where somebody is about to prescribe.
                for (final a in patient.details.allergies)
                  ProfileChip(label: 'Allergy: $a', kind: ChipKind.allergy),
                for (final c in patient.details.comorbidities) ProfileChip(label: c),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The record, as far as it bears on today: what the assistant made of it, what
/// is out of range, and what they are already taking.
class ConsultSnapshot extends StatelessWidget {
  const ConsultSnapshot({super.key, required this.patient, required this.patientId});

  final PatientSummary patient;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final context_ = (patient.aiContext ?? '').trim();
    final abnormal = abnormalFindings(patient.labResults);

    // A patient added five minutes ago has no record, and the card says that
    // rather than vanishing — a section that is missing reads as a section
    // that failed to load.
    if (context_.isEmpty && abnormal.isEmpty) {
      return Container(
        padding: EdgeInsets.all(D.s5),
        decoration: BoxDecoration(
          color: D.card,
          borderRadius: BorderRadius.circular(D.rSection),
          border: Border.all(color: D.lineStrong, style: BorderStyle.solid),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient snapshot', style: D.screenTitle.copyWith(color: D.ink)),
            SizedBox(height: D.s2),
            Text(
              'Nothing on file yet. The summary, out-of-range results and '
              'current medicines appear here once ${first(patient.name)} has a '
              'record with this practice.',
              style: D.subtitle.copyWith(color: D.inkMuted, height: 1.5),
            ),
          ],
        ),
      );
    }

    return ProfileCard(
      title: 'Patient snapshot',
      subtitle: 'From the record, not from today',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (context_.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: D.icon, color: D.brand),
                SizedBox(width: D.gapTight),
                const ProfileEyebrow(label: 'AI summary', colour: D.brand),
              ],
            ),
            SizedBox(height: D.s2),
            Text(
              context_,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: D.subtitle.copyWith(color: D.ink, height: 1.5),
            ),
          ],
          if (abnormal.isNotEmpty) ...[
            SizedBox(height: D.s4),
            const ProfileEyebrow(label: 'Out of range'),
            SizedBox(height: D.s2),
            Wrap(
              spacing: D.gapTight,
              runSpacing: D.gapTight,
              children: [
                for (final f in abnormal.take(6))
                  ProfileChip(
                    label: '${f.analyte.label} ${valueOnly(f.analyte)}'
                        '${f.analyte.flag == 'low' ? ' ↓' : ' ↑'}',
                    kind: ChipKind.warn,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// What was measured before the doctor sat down.
class ConsultVitals extends StatelessWidget {
  const ConsultVitals({super.key, required this.patient, required this.onRecord});

  final PatientSummary patient;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final t in vitalsOf(patient))
        if (t.value.isNotEmpty) t,
    ];

    return ProfileCard(
      title: 'Vitals',
      subtitle: tiles.isEmpty
          ? 'Not recorded at the desk. Enter what you measure.'
          : 'The latest recorded at this practice',
      action: TextButton(
        onPressed: onRecord,
        style: TextButton.styleFrom(
          minimumSize: D.hug,
          padding: EdgeInsets.symmetric(horizontal: D.s2),
        ),
        child: Text(
          tiles.isEmpty ? 'Record' : 'Edit',
          style: D.dateLine.copyWith(color: D.brand),
        ),
      ),
      child: tiles.isEmpty
          ? const ProfileEmpty(text: 'Record them and they print on the record, not the slip.')
          : LayoutBuilder(
              builder: (context, c) {
                final width = (c.maxWidth - D.s2 * 2) / 3;
                return Wrap(
                  spacing: D.s2,
                  runSpacing: D.s2,
                  children: [
                    for (final t in tiles)
                      SizedBox(
                        width: width,
                        child: VitalTile(
                          label: t.label,
                          value: t.value,
                          unit: t.unit,
                          band: t.band,
                          bandColour: t.colour,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

/// 1 — why they came.
class ConsultComplaint extends StatelessWidget {
  const ConsultComplaint({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ConsultSection(
      step: 1,
      title: 'Chief complaint',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.rCard),
              border: Border.all(color: D.lineStrong),
            ),
            child: TextField(
              key: const Key('c-complaint'),
              controller: controller,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              style: D.input.copyWith(color: D.ink),
              decoration: D.bareField(
                hint: 'What brings them in today',
                hintStyle: D.input.copyWith(color: D.inkFaint),
              ),
            ),
          ),
          SizedBox(height: D.s2),
          Text(
            'This is kept on the record as well as printed on the slip.',
            style: D.statLabel.copyWith(color: D.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// 2 — what it is.
class ConsultDiagnosis extends StatefulWidget {
  const ConsultDiagnosis({
    super.key,
    required this.chosen,
    required this.past,
    required this.onChanged,
  });

  final List<String> chosen;

  /// What this patient has been diagnosed with before.
  final List<String> past;

  final ValueChanged<List<String>> onChanged;

  @override
  State<ConsultDiagnosis> createState() => _ConsultDiagnosisState();
}

class _ConsultDiagnosisState extends State<ConsultDiagnosis> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _add(String name) {
    final value = name.trim();
    if (value.isEmpty || widget.chosen.contains(value)) return;
    widget.onChanged([...widget.chosen, value]);
    _typed.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final typed = _typed.text.trim().toLowerCase();
    final fromCatalogue = [
      for (final o in kDiagnosisCatalog)
        if (typed.length > 1 &&
            !widget.chosen.contains(o.label) &&
            (o.label.toLowerCase().contains(typed) || o.code.toLowerCase().contains(typed)))
          o,
    ];

    return ConsultSection(
      step: 2,
      title: 'Diagnosis',
      trailing: widget.chosen.isEmpty
          ? null
          : Text('${widget.chosen.length}', style: D.body.copyWith(color: D.inkMuted)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final d in widget.chosen)
            Padding(
              padding: EdgeInsets.only(bottom: D.s2),
              child: Container(
                padding: EdgeInsets.fromLTRB(D.cardPad, D.s2, D.s1, D.s2),
                decoration: BoxDecoration(
                  color: D.brandTint,
                  borderRadius: BorderRadius.circular(D.s3),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        d,
                        style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove $d',
                      icon: const Icon(Icons.close_rounded, size: D.iconMd, color: D.inkMuted),
                      onPressed: () =>
                          widget.onChanged([...widget.chosen]..remove(d)),
                    ),
                  ],
                ),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(D.inputH),
            ),
            padding: EdgeInsets.only(left: D.s4, right: D.s1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.rCard),
              border: Border.all(color: D.lineStrong),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('c-diagnosis'),
                    controller: _typed,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: _add,
                    style: D.input.copyWith(color: D.ink),
                    decoration: D.bareField(
                      hint: 'Type a diagnosis',
                      hintStyle: D.input.copyWith(color: D.inkFaint),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add',
                  icon: const Icon(Icons.add_rounded, size: D.iconLg, color: D.brand),
                  onPressed: _typed.text.trim().isEmpty ? null : () => _add(_typed.text),
                ),
              ],
            ),
          ),
          if (fromCatalogue.isNotEmpty) ...[
            SizedBox(height: D.s3),
            const ProfileEyebrow(label: 'In the clinic’s list'),
            SizedBox(height: D.s2),
            Wrap(
              spacing: D.s2,
              runSpacing: D.s2,
              children: [
                for (final o in fromCatalogue.take(6))
                  _AddChip(label: o.label, onTap: () => _add(o.label)),
              ],
            ),
          ],
          if (widget.past.isNotEmpty) ...[
            SizedBox(height: D.s4),
            // Not "suggested from today's complaint" — nothing here reads the
            // complaint. This is what is already on their own past slips.
            const ProfileEyebrow(label: 'From their past prescriptions'),
            SizedBox(height: D.s2),
            Wrap(
              spacing: D.s2,
              runSpacing: D.s2,
              children: [
                for (final d in widget.past.take(6)) _AddChip(label: d, onTap: () => _add(d)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 3 — what to take.
class ConsultMedicines extends StatelessWidget {
  const ConsultMedicines({
    super.key,
    required this.medicines,
    required this.allergies,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final List<MedLine> medicines;
  final List<String> allergies;
  final void Function({String? name}) onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return ConsultSection(
      step: 3,
      title: 'Medicines',
      trailing: medicines.isEmpty
          ? null
          : Text('${medicines.length} added', style: D.body.copyWith(color: D.inkMuted)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, m) in medicines.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: D.s2),
              child: _MedCard(
                line: m,
                caution: cautionFor(m.name, allergies),
                onEdit: () => onEdit(i),
                onRemove: () => onRemove(i),
              ),
            ),
          FilledButton.icon(
            key: const Key('c-add-medicine'),
            onPressed: () => onAdd(),
            icon: const Icon(Icons.add_rounded, size: D.iconMd),
            label: Text(
              medicines.isEmpty ? 'Add the first medicine' : 'Add another',
              style: D.subtitle.copyWith(fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: D.brandTint,
              foregroundColor: D.brand,
              elevation: 0,
              minimumSize: Size.fromHeight(MediaQuery.textScalerOf(context).scale(D.disc)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedCard extends StatelessWidget {
  const _MedCard({
    required this.line,
    required this.caution,
    required this.onEdit,
    required this.onRemove,
  });

  final MedLine line;
  final String? caution;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(D.s4, D.s3, D.s1, D.s3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(D.rCard),
        border: Border.all(color: D.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.title,
                      style: D.subhead.copyWith(color: D.ink),
                    ),
                    SizedBox(height: D.s1 / 2),
                    Text(line.doseLine, style: D.body.copyWith(color: D.ink)),
                    if (line.metaLine.isNotEmpty)
                      Text(line.metaLine, style: D.statLabel.copyWith(color: D.inkFaint)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit ${line.title}',
                icon: const Icon(Icons.edit_outlined, size: D.iconMd, color: D.inkMuted),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Remove ${line.title}',
                icon: const Icon(Icons.close_rounded, size: D.iconMd, color: D.inkMuted),
                onPressed: onRemove,
              ),
            ],
          ),
          if (caution != null) ...[
            SizedBox(height: D.s2),
            Container(
              margin: EdgeInsets.only(right: D.s3),
              padding: EdgeInsets.all(D.s3),
              decoration: BoxDecoration(
                color: D.pendingGround,
                borderRadius: BorderRadius.circular(D.s3),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: D.icon, color: D.pending),
                  SizedBox(width: D.s2),
                  Expanded(
                    child: Text(
                      caution!,
                      style: D.statLabel.copyWith(color: D.ink, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 4 — what to test.
class ConsultLabs extends StatelessWidget {
  const ConsultLabs({
    super.key,
    required this.chosen,
    required this.alreadyAdvised,
    required this.onChanged,
  });

  final List<String> chosen;

  /// Tests still outstanding from an earlier prescription, so the same panel is
  /// not ordered twice in a fortnight without the doctor meaning it.
  final List<String> alreadyAdvised;

  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final groups = labCatalogByCategory();

    return ConsultSection(
      step: 4,
      title: 'Lab tests',
      trailing: chosen.isEmpty
          ? null
          : Text('${chosen.length} selected', style: D.body.copyWith(color: D.inkMuted)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alreadyAdvised.isNotEmpty) ...[
            Container(
              padding: EdgeInsets.all(D.s3),
              decoration: BoxDecoration(
                color: D.brandTint,
                borderRadius: BorderRadius.circular(D.s3),
              ),
              child: Text(
                'Already advised and not yet done: ${alreadyAdvised.join(', ')}',
                style: D.statLabel.copyWith(color: D.brand, height: 1.45),
              ),
            ),
            SizedBox(height: D.s3),
          ],
          for (final entry in groups.entries) ...[
            ProfileEyebrow(label: entry.key),
            SizedBox(height: D.s2),
            Wrap(
              spacing: D.s2,
              runSpacing: D.s2,
              children: [
                for (final panel in entry.value)
                  _ToggleChip(
                    label: panel.name,
                    on: chosen.contains(panel.name),
                    onTap: () => onChanged(
                      chosen.contains(panel.name)
                          ? ([...chosen]..remove(panel.name))
                          : [...chosen, panel.name],
                    ),
                  ),
              ],
            ),
            SizedBox(height: D.s4),
          ],
        ],
      ),
    );
  }
}

/// 5 — what to do about it.
class ConsultAdvice extends StatelessWidget {
  const ConsultAdvice({
    super.key,
    required this.chosen,
    required this.ownAdvice,
    required this.onChanged,
  });

  final List<String> chosen;
  final TextEditingController ownAdvice;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AdviceSnippet>>{};
    for (final s in kAdviceCatalog) {
      (groups[s.category] ??= []).add(s);
    }

    return ConsultSection(
      step: 5,
      title: 'Advice',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in groups.entries) ...[
            ProfileEyebrow(label: entry.key),
            SizedBox(height: D.s2),
            Wrap(
              spacing: D.s2,
              runSpacing: D.s2,
              children: [
                for (final s in entry.value)
                  _ToggleChip(
                    label: s.text,
                    on: chosen.contains(s.text),
                    onTap: () => onChanged(
                      chosen.contains(s.text)
                          ? ([...chosen]..remove(s.text))
                          : [...chosen, s.text],
                    ),
                  ),
              ],
            ),
            SizedBox(height: D.s4),
          ],
          Container(
            padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.rCard),
              border: Border.all(color: D.lineStrong),
            ),
            child: TextField(
              key: const Key('c-advice'),
              controller: ownAdvice,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: D.input.copyWith(color: D.ink),
              decoration: D.bareField(
                hint: 'Anything in your own words',
                hintStyle: D.input.copyWith(color: D.inkFaint),
              ),
            ),
          ),
          SizedBox(height: D.s2),
          Text(
            'Picked lines print first, then your own.',
            style: D.statLabel.copyWith(color: D.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// 6 — how long it stands, and when to come back.
class ConsultValidity extends StatelessWidget {
  const ConsultValidity({
    super.key,
    required this.validDays,
    required this.followUpOn,
    required this.onValidity,
    required this.onFollowUp,
  });

  final int? validDays;
  final DateTime? followUpOn;
  final ValueChanged<int?> onValidity;
  final ValueChanged<DateTime?> onFollowUp;

  static const _windows = [7, 14, 30, 90];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return ConsultSection(
      step: 6,
      title: 'Validity & follow-up',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Prescription valid for',
            style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: D.s2),
          Wrap(
            spacing: D.s2,
            runSpacing: D.s2,
            children: [
              for (final days in _windows)
                _ToggleChip(
                  label: '$days days',
                  on: validDays == days,
                  onTap: () => onValidity(validDays == days ? null : days),
                ),
            ],
          ),
          SizedBox(height: D.s2),
          Text(
            validDays == null
                ? 'Not set — the server’s own default stands.'
                : 'Valid till ${DateFormat('EEE, d MMM yyyy').format(DateTime(now.year, now.month, now.day + validDays!))}',
            style: D.statLabel.copyWith(color: D.inkFaint),
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: D.s4),
            child: const Divider(height: 1, color: D.line),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Follow-up visit',
                  style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: followUpOn != null,
                activeThumbColor: D.onBrand,
                activeTrackColor: D.brand,
                onChanged: (on) => onFollowUp(
                  on ? DateTime(now.year, now.month, now.day + 30) : null,
                ),
              ),
            ],
          ),
          if (followUpOn != null) ...[
            SizedBox(height: D.s2),
            Wrap(
              spacing: D.s2,
              runSpacing: D.s2,
              children: [
                for (final days in [7, 14, 30, 90])
                  _ToggleChip(
                    label: 'In $days days',
                    on: followUpOn!.difference(DateTime(now.year, now.month, now.day)).inDays ==
                        days,
                    onTap: () =>
                        onFollowUp(DateTime(now.year, now.month, now.day + days)),
                  ),
              ],
            ),
            SizedBox(height: D.s3),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: followUpOn!,
                  firstDate: now,
                  lastDate: DateTime(now.year + 2),
                );
                if (picked != null) onFollowUp(picked);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: D.iconMd),
              label: Text(
                'Follow-up on ${DateFormat('EEE, d MMM yyyy').format(followUpOn!)}',
                style: D.subtitle.copyWith(color: D.ink),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: D.ink,
                side: const BorderSide(color: D.lineStrong),
                minimumSize: Size.fromHeight(
                  MediaQuery.textScalerOf(context).scale(D.inputH),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rCard)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Preview, and the one button that issues.
class ConsultActions extends StatelessWidget {
  const ConsultActions({
    super.key,
    required this.draft,
    required this.patientName,
    required this.submitting,
    required this.onIssue,
  });

  final ConsultDraft draft;
  final String patientName;
  final bool submitting;
  final VoidCallback onIssue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s3),
      decoration: const BoxDecoration(
        color: D.card,
        border: Border(top: BorderSide(color: D.line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => showConsultPreview(context, draft: draft, name: patientName),
                style: OutlinedButton.styleFrom(
                  foregroundColor: D.ink,
                  side: const BorderSide(color: D.lineStrong),
                  minimumSize: Size.fromHeight(
                    MediaQuery.textScalerOf(context).scale(D.inputH),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rCard)),
                ),
                child: Text('Preview', style: D.input.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
            SizedBox(width: D.s2),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const Key('c-issue'),
                onPressed: submitting ? null : onIssue,
                style: FilledButton.styleFrom(
                  backgroundColor: D.brand,
                  foregroundColor: D.onBrand,
                  elevation: 0,
                  minimumSize: Size.fromHeight(
                    MediaQuery.textScalerOf(context).scale(D.inputH),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rCard)),
                ),
                child: submitting
                    ? const SizedBox(
                        width: D.icon,
                        height: D.icon,
                        child: CircularProgressIndicator(strokeWidth: 2, color: D.onBrand),
                      )
                    : Text(
                        'Generate prescription',
                        style: D.input.copyWith(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exactly what is about to be sent, before it is.
///
/// Not a rendering of the PDF: there is no PDF until the prescription exists,
/// and a mock-up of one would be a picture of a document that has not been
/// issued. This is the consult read back — every line of it, in the order the
/// patient will read it.
Future<void> showConsultPreview(
  BuildContext context, {
  required ConsultDraft draft,
  required String name,
}) {
  final now = DateTime.now();

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: false,
    isScrollControlled: true,
    backgroundColor: D.card,
    barrierColor: D.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
    ),
    builder: (sheet) => SafeArea(
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
            Text('What will be issued', style: D.screenTitle.copyWith(color: D.ink)),
            SizedBox(height: D.s1),
            Text('For $name', style: D.body.copyWith(color: D.inkMuted)),
            SizedBox(height: D.s4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _PreviewBlock(
                    label: 'Complaint',
                    lines: [if (draft.complaint.trim().isNotEmpty) draft.complaint.trim()],
                  ),
                  _PreviewBlock(label: 'Diagnosis', lines: draft.diagnoses),
                  _PreviewBlock(
                    label: 'Medicines',
                    lines: [
                      for (final m in draft.medicines)
                        '${m.title} — ${m.doseLine}'
                            '${m.metaLine.isEmpty ? '' : ' · ${m.metaLine}'}',
                    ],
                  ),
                  _PreviewBlock(label: 'Tests', lines: draft.labs),
                  _PreviewBlock(
                    label: 'Advice',
                    lines: draft.adviceText.isEmpty ? const [] : draft.adviceText.split('\n'),
                  ),
                  _PreviewBlock(
                    label: 'Dates',
                    lines: [
                      if (draft.validDays != null)
                        'Valid till ${DateFormat('d MMM yyyy').format(draft.validUntil(now)!)}',
                      if (draft.followUpOn != null)
                        'Follow-up on ${DateFormat('d MMM yyyy').format(draft.followUpOn!)}',
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: D.s4),
            FilledButton(
              onPressed: () => Navigator.of(sheet).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: D.brand,
                foregroundColor: D.onBrand,
                elevation: 0,
                minimumSize: Size.fromHeight(
                  MediaQuery.textScalerOf(context).scale(D.inputH),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rCard)),
              ),
              child: Text('Keep editing', style: D.input.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({required this.label, required this.lines});

  final String label;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: D.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileEyebrow(label: label),
          SizedBox(height: D.s1),
          if (lines.isEmpty)
            Text('Nothing', style: D.body.copyWith(color: D.inkFaint))
          else
            for (final line in lines)
              Padding(
                padding: EdgeInsets.only(bottom: D.s1 / 2),
                child: Text(line, style: D.subtitle.copyWith(color: D.ink, height: 1.45)),
              ),
        ],
      ),
    );
  }
}

/// A choice that is on or off.
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? D.brandTint : D.card,
        borderRadius: D.rPill,
        child: InkWell(
          onTap: onTap,
          borderRadius: D.rPill,
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(D.tap),
            ),
            padding: EdgeInsets.symmetric(horizontal: D.s3, vertical: D.s1),
            decoration: BoxDecoration(
              borderRadius: D.rPill,
              border: Border.all(color: on ? D.brand : D.lineStrong),
            ),
            child: Align(
              widthFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    on ? Icons.check_rounded : Icons.add_rounded,
                    size: D.icon,
                    color: on ? D.brand : D.inkFaint,
                  ),
                  SizedBox(width: D.s1),
                  Flexible(
                    child: Text(
                      label,
                      style: D.dateLine.copyWith(color: on ? D.brand : D.inkMuted),
                    ),
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

/// A suggestion waiting to be taken.
class _AddChip extends StatelessWidget {
  const _AddChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      _ToggleChip(label: label, on: false, onTap: onTap);
}
