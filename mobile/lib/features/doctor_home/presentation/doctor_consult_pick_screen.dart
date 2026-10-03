import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../clinician/domain/appointment.dart';
import '../../clinician/domain/clinician_models.dart';
import '../../clinician/presentation/clinician_providers.dart';
import '../domain/patient_queue.dart';
import 'widgets/profile_parts.dart';

/// "Who are you consulting?" (`Consult-Pick`).
///
/// ---- Why a screen and not a jump -------------------------------------------
///
/// Start consultation, Record vitals and Write prescription are all the same
/// sentence with the patient missing. Home used to answer it by opening the
/// appointment diary, which is a different question — a diary is about when,
/// and this is about who is in front of you now.
///
/// So: the people waiting in the room, the ones seen recently, a search over
/// the whole roll, and the way to add somebody who is not on it yet. Choosing
/// any of them opens the consultation for that patient.
class DoctorConsultPickScreen extends ConsumerStatefulWidget {
  const DoctorConsultPickScreen({super.key});

  @override
  ConsumerState<DoctorConsultPickScreen> createState() => _DoctorConsultPickScreenState();
}

class _DoctorConsultPickScreenState extends ConsumerState<DoctorConsultPickScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(String patientId, String name) =>
      context.push('/clinician/patients/$patientId/consult', extra: name);

  @override
  Widget build(BuildContext context) {
    final typed = _search.text.trim();
    final searching = typed.isNotEmpty;

    final today = ref.watch(appointmentsTodayProvider).valueOrNull ?? const <Appointment>[];
    final waiting = queueGroups(today)[QueueStage.waiting]!;

    final roll = ref.watch(
      patientsProvider((
        riskBand: null,
        search: searching ? typed : null,
        sort: 'recent',
        pages: 1,
      )),
    );

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
            Text('No patient selected', style: D.statLabel.copyWith(color: D.inkMuted)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.s8),
          children: [
            ProfileCard(
              lifted: true,
              title: 'Who are you consulting?',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: MediaQuery.textScalerOf(context).scale(D.inputH),
                    padding: EdgeInsets.symmetric(horizontal: D.s4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(D.rCard),
                      border: Border.all(
                        color: searching ? D.brand : D.lineStrong,
                        width: searching ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, size: D.iconLg, color: D.inkFaint),
                        SizedBox(width: D.gapIcon),
                        Expanded(
                          child: TextField(
                            key: const Key('p-search'),
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            style: D.input.copyWith(color: D.ink),
                            decoration: D.bareField(
                              hint: 'Name or phone number',
                              hintStyle: D.input.copyWith(color: D.inkFaint),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!searching && waiting.isNotEmpty) ...[
                    SizedBox(height: D.s4),
                    const ProfileEyebrow(label: 'Waiting now'),
                    SizedBox(height: D.s2),
                    for (final (i, a) in waiting.indexed)
                      ProfileRow(
                        first: i == 0,
                        onTap: () => _open(a.patientId, a.patientName),
                        child: _WaitingRow(appointment: a),
                      ),
                  ],
                  SizedBox(height: D.s4),
                  ProfileEyebrow(label: searching ? 'Matches' : 'Seen recently'),
                  SizedBox(height: D.s2),
                  roll.when(
                    loading: () => Padding(
                      padding: EdgeInsets.symmetric(vertical: D.s6),
                      child: const Center(child: CircularProgressIndicator(color: D.brand)),
                    ),
                    error: (_, _) => ProfileEmpty(
                      text: searching
                          ? 'The search did not run.'
                          : 'The roll did not load.',
                    ),
                    data: (page) => page.items.isEmpty
                        ? ProfileEmpty(
                            text: searching
                                ? 'Nobody matches that.'
                                : 'Nobody on your roll yet.',
                          )
                        : Column(
                            children: [
                              for (final (i, p) in page.items.take(8).indexed)
                                ProfileRow(
                                  first: i == 0,
                                  onTap: () => _open(p.id, p.name),
                                  child: _PatientRow(patient: p),
                                ),
                            ],
                          ),
                  ),
                  SizedBox(height: D.s4),
                  OutlinedButton.icon(
                    key: const Key('p-add'),
                    onPressed: () => context.push('/clinician/patients/new'),
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: D.iconMd),
                    label: Text(
                      'Add new patient',
                      style: D.subtitle.copyWith(fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: D.brand,
                      side: const BorderSide(color: D.lineStrong),
                      minimumSize: Size.fromHeight(
                        MediaQuery.textScalerOf(context).scale(D.disc),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(D.s3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: D.s4),
            // The steps that are waiting on a name, as the artboard greys them.
            ProfileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, step) in const [
                    'Vitals',
                    'Chief complaint',
                    'Diagnosis',
                    'Medicines',
                    'Lab tests',
                    'Advice',
                    'Validity & follow-up',
                  ].indexed)
                    ProfileRow(
                      first: i == 0,
                      child: Row(
                        children: [
                          Container(
                            width: MediaQuery.textScalerOf(context).scale(D.s6),
                            height: MediaQuery.textScalerOf(context).scale(D.s6),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: D.track,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              i == 0 ? '·' : '$i',
                              style: D.caption.copyWith(
                                color: D.inkFaint,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(width: D.s3),
                          Expanded(
                            child: Text(
                              step,
                              style: D.subtitle.copyWith(
                                color: D.inkFaint,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: D.s3),
                  Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: D.icon, color: D.inkFaint),
                      SizedBox(width: D.s2),
                      Expanded(
                        child: Text(
                          'Choose or add a patient to start.',
                          style: D.statLabel.copyWith(color: D.inkFaint),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final waited = timeLine(a, now: DateTime.now());

    return Row(
      children: [
        Container(
          width: MediaQuery.textScalerOf(context).scale(D.disc - D.s2),
          height: MediaQuery.textScalerOf(context).scale(D.disc - D.s2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: D.track,
            borderRadius: BorderRadius.circular(D.s3),
          ),
          child: Text(
            a.queueNumber == null ? '—' : '${a.queueNumber}',
            style: D.subhead.copyWith(color: D.ink),
          ),
        ),
        SizedBox(width: D.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.patientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
              ),
              Text(
                [metaLine(a), if (waited != null) waited].where((s) => s.isNotEmpty).join(' · '),
                style: D.statLabel.copyWith(color: D.inkFaint),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, size: D.iconLg, color: D.inkFaint),
      ],
    );
  }
}

class _PatientRow extends StatelessWidget {
  const _PatientRow({required this.patient});

  final PatientListItem patient;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        UserAvatar(
          name: patient.name,
          avatarUrl: patient.avatarUrl,
          accent: D.brand,
          size: D.disc - D.s2,
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
                style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
              ),
              Text(patient.phone, style: D.statLabel.copyWith(color: D.inkFaint)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, size: D.iconLg, color: D.inkFaint),
      ],
    );
  }
}
