import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../clinician/data/prescription_document.dart';
import '../../../clinician/domain/clinician_models.dart';
import '../../../clinician/domain/patient_summary.dart';
import '../../../clinician/presentation/clinician_providers.dart';
import '../../../medications/domain/medication.dart';
import 'profile_parts.dart';
import 'record_vitals_sheet.dart';

/// The four tabs of the patient's record.
///
/// Each one answers from what the server actually holds. Where the artboard
/// draws something this clinic does not record — a target line, a dose-by-dose
/// week, a split between this clinic's prescriptions and another's — the tab
/// says what it has instead of filling the shape with a guess.

// =============================================================== Summary ====

class SummaryTab extends ConsumerWidget {
  const SummaryTab({
    super.key,
    required this.patient,
    required this.patientId,
    required this.onOpenTab,
  });

  final PatientSummary patient;
  final String patientId;

  /// Where a source lives: tapping one in the sources sheet opens the tab that
  /// holds it, rather than naming a record the doctor then has to go and find.
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abnormal = abnormalFindings(patient.labResults);
    final context_ = (patient.aiContext ?? '').trim();
    final open = [for (final a in patient.alerts) if (a.status == 'open') a];
    final medicines = ref.watch(patientMedicationsProvider(patientId)).valueOrNull ?? const [];
    final current = [for (final m in medicines) if (m.isActive) m];

    return ListView(
      padding: EdgeInsets.fromLTRB(D.s5, D.s5, D.s5, D.s8),
      children: [
        // Not on the artboard, and kept because its absence is the dangerous
        // half: an alert nobody closed, on the screen the doctor opens before
        // seeing the patient.
        if (open.isNotEmpty) ...[
          ProfileCard(
            title: open.length == 1 ? 'Open alert' : '${open.length} open alerts',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, a) in open.indexed)
                  ProfileRow(
                    first: i == 0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          a.severity == 'emergency'
                              ? Icons.emergency_outlined
                              : Icons.warning_amber_rounded,
                          size: D.iconLg,
                          color: a.severity == 'emergency' ? D.danger : D.pending,
                        ),
                        SizedBox(width: D.s3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title, style: D.bodyStrong.copyWith(color: D.ink)),
                              if ((a.detail ?? '').trim().isNotEmpty)
                                Text(
                                  a.detail!.trim(),
                                  style: D.statLabel.copyWith(color: D.inkMuted),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: D.s4),
        ],
        if (context_.isNotEmpty || abnormal.isNotEmpty) ...[
          ProfileCard(
            lifted: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: D.icon, color: D.brand),
                    SizedBox(width: D.gapTight),
                    const ProfileEyebrow(label: 'AI summary', colour: D.brand),
                  ],
                ),
                if (context_.isNotEmpty) ...[
                  SizedBox(height: D.s4),
                  Text(context_, style: D.input.copyWith(color: D.ink, height: 1.55)),
                ],
                if (abnormal.isNotEmpty) ...[
                  SizedBox(height: D.s5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          'Abnormal findings',
                          style: D.subhead.copyWith(color: D.ink),
                        ),
                      ),
                      Text(
                        fromReports(abnormal.length, patient.labResults.length),
                        style: D.statLabel.copyWith(color: D.inkFaint),
                      ),
                    ],
                  ),
                  SizedBox(height: D.s2),
                  for (final (i, f) in abnormal.indexed)
                    ProfileRow(
                      first: i == 0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.analyte.label,
                                  style: D.subtitle.copyWith(
                                    color: D.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  refLine(f),
                                  style: D.statLabel.copyWith(color: D.inkFaint),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: D.s3),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                valueOf(f.analyte),
                                style: D.subtitle.copyWith(
                                  color: D.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                flagWord(f.analyte.flag),
                                style: D.caption.copyWith(
                                  color: f.analyte.flag == 'critical' ? D.danger : D.pending,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
                if (patient.labResults.isNotEmpty) ...[
                  SizedBox(height: D.s5),
                  _AiGroup(
                    label: 'Test reports',
                    count: patient.labResults.length,
                    onMore: () => onOpenTab(2),
                    rows: [
                      for (final r in patient.labResults.take(3))
                        (
                          title: r.testName.trim().isEmpty ? 'Test report' : r.testName,
                          detail: reportLine(r),
                        ),
                    ],
                  ),
                ],
                if (current.isNotEmpty) ...[
                  SizedBox(height: D.s5),
                  _AiGroup(
                    label: 'Medicines',
                    count: current.length,
                    onMore: () => onOpenTab(3),
                    rows: [
                      for (final m in current.take(3))
                        (
                          title: [
                            m.name,
                            m.strength,
                          ].where((t) => t.trim().isNotEmpty).join(' '),
                          detail: doseLine(m),
                        ),
                    ],
                  ),
                ],
                SizedBox(height: D.s3),
                Padding(
                  padding: EdgeInsets.only(top: D.s3),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: D.line)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(top: D.s3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              'Written by AI from ${first(patient.name)}’s shared records. '
                              'Check the source before acting.',
                              style: D.statLabel.copyWith(color: D.inkFaint, height: 1.4),
                            ),
                          ),
                          SizedBox(width: D.s2),
                          TextButton(
                            onPressed: () => showAiSources(
                              context,
                              patient: patient,
                              medicines: current,
                              onOpenTab: onOpenTab,
                            ),
                            style: TextButton.styleFrom(
                              minimumSize: D.hug,
                              padding: EdgeInsets.symmetric(horizontal: D.s2),
                            ),
                            child: Text(
                              'Sources',
                              style: D.dateLine.copyWith(color: D.brand),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: D.s4),
        ],
        ProfileCard(
          title: 'Vitals',
          subtitle: 'The latest recorded at this practice',
          action: TextButton(
            onPressed: () async {
              final saved = await recordVitals(
                context,
                patientId: patientId,
                patient: patient,
              );
              if (saved && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Recorded.')),
                );
              }
            },
            style: TextButton.styleFrom(
              minimumSize: D.hug,
              padding: EdgeInsets.symmetric(horizontal: D.s2),
            ),
            child: Text('Record', style: D.dateLine.copyWith(color: D.brand)),
          ),
          child: _Vitals(patient: patient),
        ),
      ],
    );
  }
}

/// A short list inside the AI card: what it read, and the way to all of it.
class _AiGroup extends StatelessWidget {
  const _AiGroup({
    required this.label,
    required this.count,
    required this.rows,
    required this.onMore,
  });

  final String label;
  final int count;
  final List<({String title, String detail})> rows;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final hidden = count - rows.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: ProfileEyebrow(label: label)),
            Text('$count', style: D.statLabel.copyWith(color: D.inkFaint)),
          ],
        ),
        SizedBox(height: D.s2),
        for (final (i, row) in rows.indexed)
          ProfileRow(
            first: i == 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title,
                        style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
                      ),
                      if (row.detail.trim().isNotEmpty)
                        Text(row.detail, style: D.statLabel.copyWith(color: D.inkFaint)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(minimumSize: D.hug, padding: EdgeInsets.zero),
              child: Text(
                '$hidden more',
                style: D.dateLine.copyWith(color: D.brand),
              ),
            ),
          ),
      ],
    );
  }
}

/// What the summary was written from.
///
/// The server composes `aiContext` from a fixed set of records — the profile
/// and its targets, glucose readings, the latest HbA1c, the latest vitals, the
/// current medicines, the next appointment, the latest prescription with its
/// advice and tests, the reports on file and the diet plan. This sheet names
/// those, with what is actually on this patient's record beside each, and opens
/// the tab that holds it.
///
/// It does not claim a sentence came from a particular record. The summary is
/// prose written over all of it; what can be said truthfully is what it was
/// allowed to read, and a doctor checking a claim needs that list and a way in.
Future<void> showAiSources(
  BuildContext context, {
  required PatientSummary patient,
  required List<Medication> medicines,
  required ValueChanged<int> onOpenTab,
}) {
  final sources = sourcesOf(patient, medicines);

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
        padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s6),
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
            Text('What this was written from', style: D.screenTitle.copyWith(color: D.ink)),
            SizedBox(height: D.s2),
            Text(
              'The assistant reads these records for ${first(patient.name)}, as this practice '
              'can see them. It is prose over all of it, so check the record itself before '
              'acting on a number.',
              style: D.body.copyWith(color: D.inkMuted),
            ),
            SizedBox(height: D.s4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, source) in sources.indexed)
                    ProfileRow(
                      first: i == 0,
                      onTap: source.tab == null
                          ? null
                          : () {
                              Navigator.of(sheet).pop();
                              onOpenTab(source.tab!);
                            },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(source.icon, size: D.iconLg, color: D.inkFaint),
                          SizedBox(width: D.s3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  source.label,
                                  style: D.subtitle.copyWith(
                                    color: D.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  source.detail,
                                  style: D.statLabel.copyWith(color: D.inkFaint),
                                ),
                              ],
                            ),
                          ),
                          if (source.tab != null)
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: D.iconLg,
                              color: D.inkFaint,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One kind of record the summary may draw on, and what is on file.
typedef AiSource = ({String label, String detail, IconData icon, int? tab});

/// The records behind the summary, each with what this patient actually has.
///
/// Every row says what is there — including "none on file", because a doctor
/// reading "no blood sugar readings recorded" in the summary needs to see that
/// the assistant looked and found nothing, not that it never looked.
@visibleForTesting
List<AiSource> sourcesOf(PatientSummary p, List<Medication> medicines) {
  final reports = p.labResults.length;
  final newest = p.labResults.isNotEmpty ? p.labResults.first.createdAt : null;

  return [
    (
      label: 'Profile and targets',
      detail: [
        if ((p.diabetesType ?? '').trim().isNotEmpty) p.diabetesType!.trim(),
        if (p.details.comorbidities.isNotEmpty)
          '${p.details.comorbidities.length} other condition'
              '${p.details.comorbidities.length == 1 ? '' : 's'}',
        if (p.details.allergies.isNotEmpty) '${p.details.allergies.length} allergy noted',
      ].join(' · ').ifEmpty('On file'),
      icon: Icons.badge_outlined,
      tab: null,
    ),
    (
      label: 'Test reports',
      detail: reports == 0
          ? 'None on file'
          : '$reports on file${newest == null ? '' : ' · newest ${DateFormat('d MMM yyyy').format(newest)}'}',
      icon: Icons.science_outlined,
      tab: reports == 0 ? null : 2,
    ),
    (
      label: 'Medicines',
      detail: medicines.isEmpty ? 'None active' : '${medicines.length} active',
      icon: Icons.medication_outlined,
      tab: medicines.isEmpty ? null : 3,
    ),
    (
      label: 'Prescriptions',
      detail: 'The latest one, with its diagnosis, advice and tests',
      icon: Icons.description_outlined,
      tab: 1,
    ),
    (
      label: 'Blood sugar readings',
      detail: p.glucoseDaily.isEmpty
          ? 'None recorded'
          : '${p.glucoseDaily.length} days logged'
                '${p.glucoseAverage == null ? '' : ' · avg ${p.glucoseAverage}'}',
      icon: Icons.show_chart_rounded,
      tab: null,
    ),
    (
      label: 'HbA1c',
      detail: p.lastHba1c == null ? 'None on record' : 'Latest ${p.lastHba1c}%',
      icon: Icons.bloodtype_outlined,
      tab: null,
    ),
    (
      label: 'Vitals',
      detail: p.systolic == null && p.weightKg == null
          ? 'None recorded'
          : 'The latest recorded at this practice',
      icon: Icons.monitor_heart_outlined,
      tab: null,
    ),
    if (p.nutritionCare != null)
      (
        label: 'Diet plan',
        detail: 'From the dietician looking after them',
        icon: Icons.restaurant_outlined,
        tab: null,
      ),
  ];
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

/// "18 Jul 2026 · SRL Diagnostics" — whatever the report says about itself.
@visibleForTesting
String reportLine(LabReport r) {
  final flagged = [for (final a in r.analytes) if (a.abnormal) a];
  return [
    if (r.createdAt != null) DateFormat('d MMM yyyy').format(r.createdAt!),
    if (flagged.isNotEmpty)
      flagLabel(flagged)
    else if (r.analytes.isNotEmpty)
      'Nothing flagged'
    else if (r.note.trim().isNotEmpty)
      r.note.trim()
    else
      'Not read yet',
  ].join(' · ');
}

class _Vitals extends StatelessWidget {
  const _Vitals({required this.patient});

  final PatientSummary patient;

  @override
  Widget build(BuildContext context) {
    final tiles = vitalsOf(patient);

    return LayoutBuilder(
      builder: (context, c) {
        // Two across wherever two will fit. The card's own border takes two
        // pixels off the width, which is how eight tiles came out in one
        // column on a 360dp phone.
        final columns = c.maxWidth >= 260 ? 2 : 1;
        final width = (c.maxWidth - D.s2 * (columns - 1)) / columns;
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
    );
  }
}

/// Every measurement this practice records, in the artboard's order — with
/// the ones nobody has taken still on the grid.
///
/// A missing blood pressure is itself a finding: the doctor is about to see
/// this patient and nobody measured it. Dropping the tile makes that invisible,
/// which is the opposite of what an empty state is for.
///
/// Temperature is not here. The artboard has a tile for it, and this server
/// has no field for it on a vital record — so there is nothing to show and
/// nothing the Record sheet could save.
List<({String label, String value, String? unit, String? band, Color colour})> vitalsOf(
  PatientSummary p,
) {
  final bmi = p.bmi;
  String n(num? v, {int places = 0}) => v == null ? '' : v.toStringAsFixed(places);

  return [
    (
      label: 'Blood pressure',
      value: p.systolic == null || p.diastolic == null ? '' : '${p.systolic}/${p.diastolic}',
      unit: 'mmHg',
      band: p.systolic == null || p.diastolic == null
          ? null
          : bpBand(p.systolic!, p.diastolic!),
      colour: p.systolic != null && p.diastolic != null && bpBand(p.systolic!, p.diastolic!) == 'Normal'
          ? D.done
          : D.pending,
    ),
    (label: 'Pulse', value: n(p.pulse), unit: 'bpm', band: null, colour: D.inkMuted),
    (label: 'SpO₂', value: n(p.spo2), unit: '%', band: null, colour: D.inkMuted),
    (
      label: 'Fasting sugar',
      value: n(p.lastFasting),
      unit: 'mg/dL',
      band: p.lastFastingAt == null ? null : DateFormat('d MMM').format(p.lastFastingAt!),
      colour: D.inkMuted,
    ),
    (
      label: 'BMI',
      value: bmi == null ? '' : bmi.toStringAsFixed(1),
      unit: null,
      band: bmi == null ? null : bmiBand(bmi),
      colour: bmi != null && bmiBand(bmi) == 'Normal' ? D.done : D.pending,
    ),
    (label: 'Weight', value: n(p.weightKg, places: 1), unit: 'kg', band: null, colour: D.inkMuted),
    (label: 'Height', value: n(p.heightCm), unit: 'cm', band: null, colour: D.inkMuted),
    (label: 'Waist', value: n(p.waistCm), unit: 'cm', band: null, colour: D.inkMuted),
  ];
}

// ========================================================= Prescriptions ====

class PrescriptionsTab extends ConsumerStatefulWidget {
  const PrescriptionsTab({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<PrescriptionsTab> createState() => _PrescriptionsTabState();
}

class _PrescriptionsTabState extends ConsumerState<PrescriptionsTab> {
  /// all | here | shared
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(patientPrescriptionsProvider(widget.patientId));

    return list.when(
      loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
      error: (_, _) => ProfileFailed(
        onRetry: () => ref.invalidate(patientPrescriptionsProvider(widget.patientId)),
      ),
      data: (all) {
        final shared = [for (final r in all) if (isShared(r)) r];
        final here = [for (final r in all) if (!isShared(r)) r];
        final shown = switch (_filter) {
          'here' => here,
          'shared' => shared,
          _ => all,
        };

        return ListView(
          padding: EdgeInsets.fromLTRB(D.s5, D.s5, D.s5, D.s8),
          children: [
            Wrap(
              spacing: D.s2,
              runSpacing: D.s2,
              children: [
                _Filter(
                  label: 'All · ${all.length}',
                  on: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                // Not "this clinic": the server does not say which practice
                // composed a prescription, only whether it was written in
                // MedPin or scanned in by the patient.
                _Filter(
                  label: 'Written here · ${here.length}',
                  on: _filter == 'here',
                  onTap: () => setState(() => _filter = 'here'),
                ),
                _Filter(
                  label: 'Uploaded · ${shared.length}',
                  on: _filter == 'shared',
                  onTap: () => setState(() => _filter = 'shared'),
                ),
              ],
            ),
            SizedBox(height: D.s3),
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: D.icon, color: D.inkFaint),
                SizedBox(width: D.s2),
                Expanded(
                  child: Text(
                    'Includes prescriptions the patient chose to share.',
                    style: D.statLabel.copyWith(color: D.inkFaint),
                  ),
                ),
              ],
            ),
            SizedBox(height: D.s4),
            if (shown.isEmpty)
              const ProfileEmpty(
                text: 'Nothing here yet.',
                icon: Icons.description_outlined,
              )
            else
              for (final (i, r) in shown.indexed) ...[
                _PrescriptionCard(prescription: r, latest: i == 0 && _filter == 'all'),
                SizedBox(height: D.s3),
              ],
          ],
        );
      },
    );
  }
}

class _PrescriptionCard extends ConsumerStatefulWidget {
  const _PrescriptionCard({required this.prescription, required this.latest});

  final PrescriptionSummary prescription;
  final bool latest;

  @override
  ConsumerState<_PrescriptionCard> createState() => _PrescriptionCardState();
}

class _PrescriptionCardState extends ConsumerState<_PrescriptionCard> {
  bool _busy = false;

  /// The document itself, cached. Null when this prescription has none.
  Future<String?> _file() =>
      prescriptionDocumentPath(ref.read(apiClientProvider), widget.prescription);

  Future<void> _open() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final path = await _file();
      if (path == null) return;
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'No app on this phone opens a '
              '${widget.prescription.documentExtension.toUpperCase()} file.',
            ),
          ),
        );
      }
    } catch (e) {
      // What went wrong, not that something did. "Could not open the
      // prescription" sent a doctor to ask why, and the answer — the server
      // could not find the file — was sitting in the exception.
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(ErrorView.messageFor(context, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saving it, which on a phone is the share sheet: "Save to Files" and
  /// "Download" both live in there, next to sending it on.
  Future<void> _save() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final path = await _file();
      if (path == null) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: prescriptionMimeType(widget.prescription))],
          subject: 'Prescription ${widget.prescription.referenceNo ?? ''}'.trim(),
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(ErrorView.messageFor(context, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.prescription;
    final latest = widget.latest;
    final ended = r.endedLabel;
    final hasFile = (r.documentUrl ?? '').isNotEmpty;

    return ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.issuedOn == null
                      ? 'Undated'
                      : DateFormat('d MMM yyyy').format(r.issuedOn!),
                  style: D.cardTitle.copyWith(color: D.ink),
                ),
              ),
              if (ended != null)
                ProfileChip(label: ended, kind: ChipKind.warn)
              else if (isShared(r))
                const ProfileChip(label: 'Uploaded by patient', kind: ChipKind.brand)
              else if (latest)
                const ProfileChip(label: 'Latest'),
            ],
          ),
          SizedBox(height: D.s1),
          Text(byLine(r), style: D.body.copyWith(color: D.inkMuted)),
          if (summaryLine(r).isNotEmpty) ...[
            SizedBox(height: D.s3),
            Text(summaryLine(r), style: D.subtitle.copyWith(color: D.ink, height: 1.5)),
          ],
          SizedBox(height: D.s2),
          Text(metaLine(r), style: D.statLabel.copyWith(color: D.inkFaint)),
          SizedBox(height: D.s3),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: hasFile && !_busy ? _open : null,
                  icon: _busy
                      ? const SizedBox(
                          width: D.icon,
                          height: D.icon,
                          child: CircularProgressIndicator(strokeWidth: 2, color: D.brand),
                        )
                      : const Icon(Icons.visibility_outlined, size: D.iconMd),
                  label: Text(
                    'View',
                    style: D.subtitle.copyWith(fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: D.brandTint,
                    foregroundColor: D.brand,
                    disabledBackgroundColor: D.ground,
                    disabledForegroundColor: D.inkFaint,
                    elevation: 0,
                    minimumSize: Size.fromHeight(
                      MediaQuery.textScalerOf(context).scale(D.disc),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(D.s3),
                    ),
                  ),
                ),
              ),
              SizedBox(width: D.s2),
              // The artboard's square beside it. On a phone "download" is the
              // share sheet: Save to Files and Download both live in there.
              Semantics(
                button: true,
                label: 'Save or send this prescription',
                child: SizedBox(
                  width: MediaQuery.textScalerOf(context).scale(D.disc),
                  height: MediaQuery.textScalerOf(context).scale(D.disc),
                  child: OutlinedButton(
                    onPressed: hasFile && !_busy ? _save : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: D.brand,
                      disabledForegroundColor: D.inkFaint,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      side: const BorderSide(color: D.lineStrong),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(D.s3),
                      ),
                    ),
                    child: const Icon(Icons.download_rounded, size: D.iconLg),
                  ),
                ),
              ),
            ],
          ),
          if (!hasFile) ...[
            SizedBox(height: D.s2),
            Text(
              r.source == 'composed'
                  ? 'No PDF was generated for this one.'
                  : 'No file was uploaded with this one.',
              style: D.statLabel.copyWith(color: D.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? D.brand : D.card,
      borderRadius: D.rPill,
      child: InkWell(
        onTap: onTap,
        borderRadius: D.rPill,
        child: Container(
          constraints: BoxConstraints(
            minHeight: MediaQuery.textScalerOf(context).scale(D.tap),
          ),
          padding: EdgeInsets.symmetric(horizontal: D.s4),
          decoration: BoxDecoration(
            borderRadius: D.rPill,
            border: Border.all(color: on ? D.brand : D.lineStrong),
          ),
          child: Align(
            widthFactor: 1,
            child: Text(
              label,
              style: D.dateLine.copyWith(color: on ? D.onBrand : D.inkMuted),
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================= Tests ====

class TestsTab extends StatelessWidget {
  const TestsTab({super.key, required this.patient});

  final PatientSummary patient;

  @override
  Widget build(BuildContext context) {
    final reports = patient.labResults;
    final abnormal = [for (final r in reports) if (hasAbnormal(r)) r];
    final rest = [for (final r in reports) if (!hasAbnormal(r)) r];

    return ListView(
      padding: EdgeInsets.fromLTRB(D.s5, D.s5, D.s5, D.s8),
      children: [
        Row(
          children: [
            const Icon(Icons.shield_outlined, size: D.icon, color: D.inkFaint),
            SizedBox(width: D.s2),
            Expanded(
              child: Text(
                'Reports the patient has shared. Abnormal first.',
                style: D.statLabel.copyWith(color: D.inkFaint),
              ),
            ),
          ],
        ),
        SizedBox(height: D.s4),
        if (reports.isEmpty)
          const ProfileEmpty(
            text: 'No test reports on this record yet.',
            icon: Icons.science_outlined,
          ),
        if (abnormal.isNotEmpty) ...[
          ProfileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProfileEyebrow(label: 'Abnormal findings', colour: D.pending),
                SizedBox(height: D.s3),
                for (final (i, r) in abnormal.indexed)
                  ProfileRow(first: i == 0, child: _Report(report: r)),
              ],
            ),
          ),
          SizedBox(height: D.s4),
        ],
        if (rest.isNotEmpty)
          ProfileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Not "within normal range": a report with no values read off
                // it is not a normal result, it is an unread one.
                ProfileEyebrow(
                  label: reports.any(hasAnalytes) ? 'Nothing flagged' : 'Reports on file',
                ),
                SizedBox(height: D.s3),
                for (final (i, r) in rest.indexed)
                  ProfileRow(first: i == 0, child: _Report(report: r)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.report});

  final LabReport report;

  @override
  Widget build(BuildContext context) {
    final flagged = [for (final a in report.analytes) if (a.abnormal) a];
    final when = report.createdAt;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      report.testName.trim().isEmpty ? 'Test report' : report.testName,
                      style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (flagged.isNotEmpty)
                    ProfileChip(label: flagLabel(flagged), kind: ChipKind.warn)
                  else if (hasAnalytes(report))
                    const ProfileChip(label: 'Nothing flagged'),
                ],
              ),
              if (flagged.isNotEmpty) ...[
                SizedBox(height: D.s1 / 2),
                Text(
                  [for (final a in flagged.take(3)) '${a.label} ${valueOnly(a)}'].join(' · '),
                  style: D.dateLine.copyWith(color: D.pending),
                ),
              ],
              SizedBox(height: D.s1 / 2),
              Text(
                [
                  if (when != null) DateFormat('d MMM yyyy').format(when),
                  if (report.note.trim().isNotEmpty) report.note.trim(),
                ].join(' · '),
                style: D.statLabel.copyWith(color: D.inkFaint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================= Treatment ====

class TreatmentTab extends ConsumerWidget {
  const TreatmentTab({super.key, required this.patient, required this.patientId});

  final PatientSummary patient;
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meds = ref.watch(patientMedicationsProvider(patientId));
    final latest = ref.watch(patientPrescriptionsProvider(patientId)).valueOrNull;
    final plan = (latest ?? const <PrescriptionSummary>[]).firstOrNull;

    return ListView(
      padding: EdgeInsets.fromLTRB(D.s5, D.s5, D.s5, D.s8),
      children: [
        if (plan != null) ...[
          ProfileCard(
            lifted: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ProfileEyebrow(label: 'The plan in force'),
                SizedBox(height: D.s1),
                Text(
                  plan.doctorName?.trim().isNotEmpty == true ? plan.doctorName! : 'This practice',
                  style: D.screenTitle.copyWith(color: D.ink),
                ),
                SizedBox(height: D.s1 / 2),
                Text(planLine(plan), style: D.body.copyWith(color: D.inkMuted)),
              ],
            ),
          ),
          SizedBox(height: D.s4),
        ],
        ProfileCard(
          title: 'Adherence',
          subtitle: 'Last 30 days',
          child: _Adherence(patient: patient),
        ),
        SizedBox(height: D.s4),
        meds.when(
          loading: () => Padding(
            padding: EdgeInsets.symmetric(vertical: D.s8),
            child: const Center(child: CircularProgressIndicator(color: D.brand)),
          ),
          error: (_, _) => ProfileFailed(
            onRetry: () => ref.invalidate(patientMedicationsProvider(patientId)),
          ),
          data: (list) => _Medicines(medicines: list, perMed: patient.adherencePerMed),
        ),
        if (plan != null && adviceOf(plan).isNotEmpty) ...[
          SizedBox(height: D.s4),
          ProfileCard(
            title: 'Instructions & advice',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, line) in adviceOf(plan).indexed)
                  ProfileRow(
                    first: i == 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ProfileEyebrow(label: line.label),
                        SizedBox(height: D.s1),
                        Text(line.text, style: D.subtitle.copyWith(color: D.ink, height: 1.5)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Adherence extends StatelessWidget {
  const _Adherence({required this.patient});

  final PatientSummary patient;

  @override
  Widget build(BuildContext context) {
    final percent = patient.adherencePercent;
    if (percent == null) {
      return const ProfileEmpty(text: 'No doses have been due yet.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$percent%', style: D.metric.copyWith(color: D.ink)),
            SizedBox(width: D.s3),
            // The honest form behind the percentage: a number nobody can
            // argue with, under one that is a ratio of two counts.
            if (patient.adherenceTaken != null && patient.adherenceExpected != null)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: D.s1),
                  child: Text(
                    '${patient.adherenceTaken} of ${patient.adherenceExpected} doses',
                    style: D.statLabel.copyWith(color: D.inkMuted),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: D.s3),
        ClipRRect(
          borderRadius: D.rPill,
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: D.s2,
            backgroundColor: D.line,
            valueColor: const AlwaysStoppedAnimation(D.brand),
          ),
        ),
        if ((patient.adherenceMissed ?? 0) > 0) ...[
          SizedBox(height: D.s3),
          Container(
            padding: EdgeInsets.symmetric(horizontal: D.cardPad, vertical: D.s3),
            decoration: BoxDecoration(
              color: D.pendingGround,
              borderRadius: BorderRadius.circular(D.s3),
            ),
            child: Text(
              '${patient.adherenceMissed} doses missed in the last 30 days.',
              style: D.body.copyWith(color: D.ink),
            ),
          ),
        ],
      ],
    );
  }
}

class _Medicines extends StatelessWidget {
  const _Medicines({required this.medicines, required this.perMed});

  final List<Medication> medicines;
  final List<MedAdherence> perMed;

  @override
  Widget build(BuildContext context) {
    final mine = [for (final m in medicines) if (m.changeableByYou != false) m];
    final others = [for (final m in medicines) if (m.changeableByYou == false) m];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileCard(
          title: 'Current medicines',
          child: mine.isEmpty
              ? const ProfileEmpty(text: 'Nothing is prescribed at the moment.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, m) in mine.indexed)
                      ProfileRow(first: i == 0, child: _Medicine(medicine: m, perMed: perMed)),
                  ],
                ),
        ),
        if (others.isNotEmpty) ...[
          SizedBox(height: D.s4),
          ProfileCard(
            title: 'From other doctors',
            subtitle: 'Shared by the patient · you cannot change these',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, m) in others.indexed)
                  ProfileRow(first: i == 0, child: _Medicine(medicine: m, perMed: perMed)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Medicine extends StatelessWidget {
  const _Medicine({required this.medicine, required this.perMed});

  final Medication medicine;
  final List<MedAdherence> perMed;

  @override
  Widget build(BuildContext context) {
    final taken = adherenceOf(medicine.name, perMed);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [medicine.name, medicine.strength].where((s) => s.trim().isNotEmpty).join(' '),
                style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: D.s1 / 2),
              Text(doseLine(medicine), style: D.body.copyWith(color: D.ink)),
              if (sinceLine(medicine).isNotEmpty)
                Text(sinceLine(medicine), style: D.statLabel.copyWith(color: D.inkFaint)),
            ],
          ),
        ),
        SizedBox(width: D.s3),
        Text(
          taken == null ? 'Not tracked' : '$taken%',
          style: taken == null
              ? D.statLabel.copyWith(color: D.inkFaint)
              : D.subtitle.copyWith(
                  color: taken >= 80 ? D.done : D.pending,
                  fontWeight: FontWeight.w700,
                ),
        ),
      ],
    );
  }
}

// =============================================================== reading ====

/// An abnormal value, and the report it came off.
typedef Finding = ({Analyte analyte, LabReport report});

/// Every value outside its reference range, worst first.
/// Also read by the consult's snapshot, which shows the same findings.
List<Finding> abnormalFindings(List<LabReport> reports) {
  final found = <Finding>[
    for (final r in reports)
      for (final a in r.analytes)
        if (a.abnormal && a.hasValue) (analyte: a, report: r),
  ];
  found.sort((x, y) {
    int rank(String f) => switch (f) { 'critical' => 0, 'high' || 'low' => 1, _ => 2 };
    final byFlag = rank(x.analyte.flag).compareTo(rank(y.analyte.flag));
    if (byFlag != 0) return byFlag;
    final a = x.report.createdAt;
    final b = y.report.createdAt;
    if (a == null || b == null) return 0;
    return b.compareTo(a);
  });
  return found;
}

@visibleForTesting
bool hasAnalytes(LabReport r) => r.analytes.isNotEmpty;

@visibleForTesting
bool hasAbnormal(LabReport r) => r.analytes.any((a) => a.abnormal);

@visibleForTesting
String valueOf(Analyte a) =>
    [a.value, if ((a.unit ?? '').isNotEmpty) a.unit].join(' ').trim();

String valueOnly(Analyte a) => a.hasValue ? '${a.value}' : '—';

@visibleForTesting
String flagWord(String flag) => switch (flag) {
  'critical' => 'Critical',
  'high' => 'High',
  'low' => 'Low',
  _ => '',
};

/// "2 high", "1 high · 1 low" — what a report is flagged for.
@visibleForTesting
String flagLabel(List<Analyte> flagged) {
  final high = flagged.where((a) => a.flag == 'high' || a.flag == 'critical').length;
  final low = flagged.where((a) => a.flag == 'low').length;
  return [if (high > 0) '$high high', if (low > 0) '$low low'].join(' · ');
}

@visibleForTesting
String refLine(Finding f) {
  final range = f.analyte.rangeText;
  final name = f.report.testName.trim();
  final when = f.report.createdAt;
  return [
    if (range.isNotEmpty) 'Ref $range',
    if (name.isNotEmpty) name,
    if (when != null) DateFormat('d MMM yyyy').format(when),
  ].join(' · ');
}

@visibleForTesting
String fromReports(int findings, int reports) =>
    '$findings from $reports report${reports == 1 ? '' : 's'}';

@visibleForTesting
String first(String name) => name.trim().split(' ').first;

/// A prescription the patient brought in rather than one written here.
@visibleForTesting
bool isShared(PrescriptionSummary r) =>
    r.source != 'composed' || (r.uploadedByName ?? '').trim().isNotEmpty;

@visibleForTesting
String byLine(PrescriptionSummary r) {
  final by = (r.doctorName ?? '').trim();
  final uploaded = (r.uploadedByName ?? '').trim();
  return [
    if (by.isNotEmpty) by,
    if (uploaded.isNotEmpty) 'Uploaded by $uploaded',
    if (by.isEmpty && uploaded.isEmpty) 'This practice',
  ].join(' · ');
}

@visibleForTesting
String summaryLine(PrescriptionSummary r) {
  if (r.diagnosis.isNotEmpty) return r.diagnosis.join(', ');
  return (r.complaint ?? '').trim();
}

@visibleForTesting
String metaLine(PrescriptionSummary r) => [
  '${r.itemCount} medicine${r.itemCount == 1 ? '' : 's'}',
  if (r.labTestsAdvised.isNotEmpty)
    '${r.labTestsAdvised.length} test${r.labTestsAdvised.length == 1 ? '' : 's'}',
  if (r.followUpOn != null) 'Follow-up ${DateFormat('d MMM').format(r.followUpOn!)}',
].join(' · ');

@visibleForTesting
String planLine(PrescriptionSummary r) => [
  if (r.issuedOn != null) 'Written ${DateFormat('d MMM yyyy').format(r.issuedOn!)}',
  if (r.followUpOn != null) 'Next visit ${DateFormat('d MMM').format(r.followUpOn!)}',
].join(' · ');

/// The advice on the plan, as the server stores it.
///
/// The artboard splits this into Diet, Activity, Monitoring, Before next visit
/// and Come in immediately if. This server keeps one block of general advice
/// and the list of tests ordered — so those two are what appear, under their
/// own names. Inventing the other three headings would mean deciding which
/// sentence of a doctor's advice was about diet.
@visibleForTesting
List<({String label, String text})> adviceOf(PrescriptionSummary r) {
  final advice = (r.generalAdvice ?? '').trim();
  return [
    if (advice.isNotEmpty) (label: 'Advice', text: advice),
    if (r.labTestsAdvised.isNotEmpty)
      (label: 'Before the next visit', text: r.labTestsAdvised.join(', ')),
  ];
}

@visibleForTesting
String doseLine(Medication m) {
  final times = m.schedule.length;
  return [
    if (m.dose.trim().isNotEmpty) m.dose.trim(),
    if (m.asNeeded) 'As needed' else if (times > 0) '$times a day',
    if (m.instructions?.trim().isNotEmpty == true) m.instructions!.trim(),
  ].join(' · ');
}

@visibleForTesting
String sinceLine(Medication m) {
  final start = m.startDate;
  final end = m.endDate;
  return [
    if (start != null) 'Since ${DateFormat('d MMM yyyy').format(start)}',
    if (end != null) 'until ${DateFormat('d MMM').format(end)}',
  ].join(' ');
}

/// This medicine's own adherence, matched by name — null when nothing has been
/// due for it, which is not the same as nobody taking it.
@visibleForTesting
int? adherenceOf(String name, List<MedAdherence> perMed) {
  for (final m in perMed) {
    if (m.name.toLowerCase().trim() == name.toLowerCase().trim()) {
      return m.expected == 0 ? null : m.percentage;
    }
  }
  return null;
}

@visibleForTesting
String bpBand(int systolic, int diastolic) {
  if (systolic >= 140 || diastolic >= 90) return 'High';
  if (systolic < 90 || diastolic < 60) return 'Low';
  return 'Normal';
}

@visibleForTesting
String bmiBand(double bmi) {
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Normal';
  if (bmi < 30) return 'Overweight';
  return 'Obese';
}
