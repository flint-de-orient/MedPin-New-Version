import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/submission_keys.dart';
import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/providers/core_providers.dart';
import '../../../shared/widgets/error_view.dart';
import '../../clinician/data/clinician_repository.dart';
import '../../clinician/presentation/clinician_providers.dart';
import '../domain/consult_draft.dart';
import 'widgets/consult_medicine_sheet.dart';
import 'widgets/consult_sections.dart';
import 'widgets/profile_parts.dart';
import 'widgets/record_vitals_sheet.dart';

/// The consultation, on one page (`Consult-Page`).
///
/// ---- One page, not seven steps ---------------------------------------------
///
/// `ConsultScreen` walks the doctor through vitals, complaint, diagnosis,
/// medicines, tests, advice and follow-up, one at a time. The artboard puts all
/// six on one scroll with the record above them, and that is what this is: a
/// follow-up where nothing has changed is then four taps rather than seven
/// screens, and a doctor who wants only the medicines never passes a step that
/// does not concern them.
///
/// What the steps were enforcing is kept, because it was not about the steps:
/// a prescription with no medicines is confirmed before it is issued, a
/// medicine that matches a recorded allergy is called out beside it, and the
/// whole thing is sent once under a submission key.
///
/// ---- The doctor's copy ------------------------------------------------------
///
/// `/clinician/patients/:id/consult`. The desk does not prescribe.
class DoctorConsultScreen extends ConsumerStatefulWidget {
  const DoctorConsultScreen({super.key, required this.patientId, this.patientName});

  final String patientId;
  final String? patientName;

  @override
  ConsumerState<DoctorConsultScreen> createState() => _DoctorConsultScreenState();
}

class _DoctorConsultScreenState extends ConsumerState<DoctorConsultScreen> {
  final _submission = SubmissionKeys();
  final _started = DateTime.now();

  final _complaint = TextEditingController();
  final _ownAdvice = TextEditingController();

  ConsultDraft _draft = const ConsultDraft();
  Timer? _saveSoon;
  DateTime? _savedAt;
  bool _submitting = false;
  String? _error;

  ConsultDrafts get _drafts => ConsultDrafts(ref.read(sharedPreferencesProvider));

  @override
  void initState() {
    super.initState();
    final saved = _drafts.read(widget.patientId);
    if (saved != null) {
      _draft = saved;
      _complaint.text = saved.complaint;
      _ownAdvice.text = saved.ownAdvice;
    }
    _complaint.addListener(() => _edit(_draft.copyWith(complaint: _complaint.text)));
    _ownAdvice.addListener(() => _edit(_draft.copyWith(ownAdvice: _ownAdvice.text)));
  }

  @override
  void dispose() {
    _saveSoon?.cancel();
    _complaint.dispose();
    _ownAdvice.dispose();
    super.dispose();
  }

  /// Every change to the consult goes through here, so none of them can be the
  /// one that was not kept.
  void _edit(ConsultDraft next) {
    setState(() => _draft = next);
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    await _drafts.write(widget.patientId, _draft);
    if (mounted) setState(() => _savedAt = DateTime.now());
  }

  Future<void> _addMedicine({MedLine? existing, int? at, String? name}) async {
    final patient = ref.read(patientSummaryProvider(widget.patientId)).valueOrNull;
    final line = await editMedicine(
      context,
      existing: existing,
      initialName: name,
      allergies: patient?.details.allergies ?? const [],
    );
    if (line == null) return;
    final meds = [..._draft.medicines];
    if (at == null) {
      meds.add(line);
    } else {
      meds[at] = line;
    }
    _edit(_draft.copyWith(medicines: meds));
  }

  Future<void> _issue() async {
    if (_submitting) return;

    // The one rail the steps were really carrying: a prescription with nothing
    // on it. Named for its consequence, because "Confirm" does not say what is
    // being confirmed and this is a hurried tap.
    if (_draft.medicines.isEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No medicines on this prescription'),
          content: const Text(
            'It will be issued with the diagnosis, tests and advice only. The '
            'patient gets no medicines from it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Issue without medicines'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Add a medicine'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!mounted) return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final repo = ref.read(clinicianRepositoryProvider);
      final complaint = _draft.complaint.trim();

      // The complaint belongs to the record as well as to the prescription:
      // the profile carries what brought them in today, and the consult is
      // where that is set.
      if (complaint.isNotEmpty) {
        await repo.recordConsultVitals(
          patientId: widget.patientId,
          complaint: complaint,
          submission: _submission,
        );
      }

      await repo.createPrescription(
        patientId: widget.patientId,
        items: [for (final m in _draft.medicines) m.toItem()],
        complaint: complaint.isEmpty ? null : complaint,
        diagnosis: _draft.diagnoses,
        labTestsAdvised: _draft.labs,
        generalAdvice: _draft.adviceText,
        followUpOn: _draft.followUpOn,
        validUntil: _draft.validUntil(DateTime.now()),
        submission: _submission,
      );

      // The draft became the prescription. A draft that outlives what it became
      // is the one somebody issues twice.
      await _drafts.clear(widget.patientId);

      ref.invalidate(patientPrescriptionsProvider(widget.patientId));
      ref.invalidate(patientSummaryProvider(widget.patientId));
      ref.invalidate(patientMedicationsProvider(widget.patientId));
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prescription issued.')));
      // The list, where the PDF can be opened and handed over.
      context.pushReplacement(
        '/clinician/patients/${widget.patientId}/prescriptions',
        extra: widget.patientName,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorView.messageFor(context, e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(patientSummaryProvider(widget.patientId));
    final patient = summary.valueOrNull;

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Consultation', style: D.screenTitle.copyWith(color: D.ink)),
            Text(
              draftLine(_started, _savedAt),
              style: D.statLabel.copyWith(color: D.inkMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _draft.isEmpty ? null : _save,
            style: TextButton.styleFrom(minimumSize: D.hug),
            child: Text(
              'Save draft',
              style: D.dateLine.copyWith(color: _draft.isEmpty ? D.inkFaint : D.brand),
            ),
          ),
          SizedBox(width: D.s2),
        ],
      ),
      body: SafeArea(
        top: false,
        child: summary.when(
          loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
          error: (e, _) => ProfileFailed(
        error: e,
            onRetry: () => ref.invalidate(patientSummaryProvider(widget.patientId)),
          ),
          data: (p) => ListView(
            padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.s8),
            children: [
              ConsultPatientCard(patient: p, patientId: widget.patientId),
              SizedBox(height: D.s4),
              ConsultSnapshot(patient: p, patientId: widget.patientId),
              SizedBox(height: D.s4),
              ConsultVitals(
                patient: p,
                onRecord: () async {
                  final saved = await recordVitals(
                    context,
                    patientId: widget.patientId,
                    patient: p,
                  );
                  if (saved && mounted) setState(() {});
                },
              ),
              SizedBox(height: D.s4),
              ConsultComplaint(controller: _complaint),
              SizedBox(height: D.s4),
              ConsultDiagnosis(
                chosen: _draft.diagnoses,
                past: pastDiagnoses(
                  ref.watch(patientPrescriptionsProvider(widget.patientId)).valueOrNull,
                  _draft.diagnoses,
                ),
                onChanged: (list) => _edit(_draft.copyWith(diagnoses: list)),
              ),
              SizedBox(height: D.s4),
              ConsultMedicines(
                medicines: _draft.medicines,
                allergies: p.details.allergies,
                onAdd: ({String? name}) => _addMedicine(name: name),
                onEdit: (i) => _addMedicine(existing: _draft.medicines[i], at: i),
                onRemove: (i) => _edit(
                  _draft.copyWith(medicines: [..._draft.medicines]..removeAt(i)),
                ),
              ),
              SizedBox(height: D.s4),
              ConsultLabs(
                chosen: _draft.labs,
                alreadyAdvised: p.advisedTests,
                onChanged: (list) => _edit(_draft.copyWith(labs: list)),
              ),
              SizedBox(height: D.s4),
              ConsultAdvice(
                chosen: _draft.advice,
                ownAdvice: _ownAdvice,
                onChanged: (list) => _edit(_draft.copyWith(advice: list)),
              ),
              SizedBox(height: D.s4),
              ConsultValidity(
                validDays: _draft.validDays,
                followUpOn: _draft.followUpOn,
                onValidity: (days) => _edit(
                  days == null
                      ? _draft.copyWith(clearValidity: true)
                      : _draft.copyWith(validDays: days),
                ),
                onFollowUp: (date) => _edit(
                  date == null
                      ? _draft.copyWith(clearFollowUp: true)
                      : _draft.copyWith(followUpOn: date),
                ),
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
                      Expanded(child: Text(_error!, style: D.body.copyWith(color: D.danger))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: patient == null
          ? null
          : ConsultActions(
              draft: _draft,
              patientName: patient.name,
              submitting: _submitting,
              onIssue: _issue,
            ),
    );
  }
}

/// "Started 9:14 AM · draft kept on this phone".
///
/// Not "draft saved". There is no draft on the server — a prescription exists
/// when it is issued and nothing before that — so the line says where the work
/// actually is, because a doctor who believes a half-written consult is on the
/// server will reach for it from another phone.
@visibleForTesting
String draftLine(DateTime started, DateTime? savedAt) => [
  'Started ${DateFormat.jm().format(started)}',
  if (savedAt != null) 'draft kept on this phone',
].join(' · ');

/// What this patient has been diagnosed with before, newest first.
///
/// The artboard offers diagnoses "suggested from complaint and reports", which
/// would be the assistant reading today's words. Nothing here does that, so
/// what is offered is what the record already holds: the diagnoses on their own
/// past prescriptions. A repeat visit is most of this clinic's work, and the
/// right answer is usually on the last slip.
@visibleForTesting
List<String> pastDiagnoses(List<dynamic>? prescriptions, List<String> already) {
  final seen = <String>{};
  final out = <String>[];
  for (final rx in prescriptions ?? const []) {
    for (final d in (rx.diagnosis as List<String>? ?? const <String>[])) {
      final name = d.trim();
      if (name.isEmpty || already.contains(name) || !seen.add(name.toLowerCase())) continue;
      out.add(name);
    }
  }
  return out;
}
