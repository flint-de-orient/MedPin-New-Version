import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../clinician/domain/patient_summary.dart';
import '../../clinician/presentation/clinician_providers.dart';
import 'widgets/profile_parts.dart';
import 'widgets/profile_tabs.dart';

/// The patient's record, on the new design (`PP-Summary` and its siblings).
///
/// ---- Four tabs, not one scroll --------------------------------------------
///
/// The canvas holds two drawings of this screen: `Patient-Profile`, one long
/// page with everything on it, and the `PP-*` set, which is the same record cut
/// into Summary, Prescriptions, Test results and Treatment plan behind a header
/// that stays put. The tabbed one is the later thought and the one built here:
/// the long page is four thousand pixels tall, and the thing a doctor wants is
/// rarely the thing at the top.
///
/// ---- The doctor's copy -----------------------------------------------------
///
/// `/clinician/patients/:id` only. The desk and the dietician keep
/// `PatientProfileScreen`, which is also where prescribing still lives — this
/// screen reads the record and hands off to the consult to change it.
class DoctorPatientProfileScreen extends ConsumerStatefulWidget {
  const DoctorPatientProfileScreen({super.key, required this.patientId, this.patientName});

  final String patientId;

  /// The name the previous screen already knew, so the header is not blank
  /// while the record loads.
  final String? patientName;

  @override
  ConsumerState<DoctorPatientProfileScreen> createState() => _DoctorPatientProfileScreenState();
}

class _DoctorPatientProfileScreenState extends ConsumerState<DoctorPatientProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _call(String phone) async {
    final number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.isEmpty) return;
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('This phone cannot place calls.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(patientSummaryProvider(widget.patientId));
    final patient = summary.valueOrNull;

    return Scaffold(
      backgroundColor: D.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              patientId: widget.patientId,
              fallbackName: widget.patientName,
              patient: patient,
              tabs: _tabs,
              onCall: patient == null ? null : () => _call(patient.phone),
            ),
            Expanded(
              child: summary.when(
                loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
                error: (_, _) => ProfileFailed(
                  onRetry: () => ref.invalidate(patientSummaryProvider(widget.patientId)),
                ),
                data: (p) => TabBarView(
                  controller: _tabs,
                  children: [
                    SummaryTab(
                      patient: p,
                      patientId: widget.patientId,
                      onOpenTab: _tabs.animateTo,
                    ),
                    PrescriptionsTab(patientId: widget.patientId),
                    TestsTab(patient: p),
                    TreatmentTab(patient: p, patientId: widget.patientId),
                  ],
                ),
              ),
            ),
            _StartConsultation(patientId: widget.patientId),
          ],
        ),
      ),
    );
  }
}

/// Who this is, and the four ways into their record.
class _Header extends StatelessWidget {
  const _Header({
    required this.patientId,
    required this.fallbackName,
    required this.patient,
    required this.tabs,
    required this.onCall,
  });

  final String patientId;
  final String? fallbackName;
  final PatientSummary? patient;
  final TabController tabs;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final name = patient?.name ?? fallbackName ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: D.card,
        border: Border(bottom: BorderSide(color: D.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(D.bar),
            child: Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.arrow_back_rounded, size: D.iconDisc),
                  color: D.ink,
                  onPressed: () => context.pop(),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Call',
                  icon: const Icon(Icons.call_outlined, size: D.iconDisc),
                  color: D.brand,
                  onPressed: onCall,
                ),
                IconButton(
                  tooltip: 'Message',
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: D.iconDisc),
                  color: D.brand,
                  onPressed: () => context.push('/clinician/patients/$patientId/thread'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert_rounded, size: D.iconDisc, color: D.ink),
                  onSelected: (value) => switch (value) {
                    'appointments' => context.push('/clinician/appointments'),
                    'prescriptions' => context.push('/clinician/patients/$patientId/prescriptions'),
                    _ => null,
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'appointments', child: Text('Book an appointment')),
                    PopupMenuItem(value: 'prescriptions', child: Text('All prescriptions')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(D.s5, 0, D.s5, D.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(
                      name: name,
                      avatarUrl: patient?.avatarUrl,
                      accent: D.brand,
                      size: D.discLg + D.s1,
                    ),
                    SizedBox(width: D.cardPad),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? ' ' : name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: D.greeting.copyWith(color: D.ink),
                          ),
                          SizedBox(height: D.s1 / 2),
                          Text(
                            patient == null ? ' ' : lineUnder(patient!),
                            style: D.body.copyWith(color: D.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (patient != null) ...[
                  SizedBox(height: D.s3),
                  Wrap(
                    spacing: D.gapTight,
                    runSpacing: D.gapTight,
                    children: [
                      for (final chip in chipsFor(patient!))
                        ProfileChip(label: chip.text, kind: chip.kind),
                    ],
                  ),
                ],
              ],
            ),
          ),
          TabBar(
            controller: tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: EdgeInsets.symmetric(horizontal: D.s5),
            labelPadding: EdgeInsets.only(right: D.s6),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorColor: D.brand,
            indicatorWeight: 2,
            dividerColor: Colors.transparent,
            labelColor: D.brand,
            unselectedLabelColor: D.inkMuted,
            labelStyle: D.subtitle.copyWith(fontWeight: FontWeight.w700),
            unselectedLabelStyle: D.subtitle.copyWith(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Summary'),
              Tab(text: 'Prescriptions'),
              Tab(text: 'Test results'),
              Tab(text: 'Treatment plan'),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one thing this screen is for, kept where the thumb is.
class _StartConsultation extends StatelessWidget {
  const _StartConsultation({required this.patientId});

  final String patientId;

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
        child: FilledButton(
          onPressed: () => context.push('/clinician/patients/$patientId/consult'),
          style: FilledButton.styleFrom(
            backgroundColor: D.brand,
            foregroundColor: D.onBrand,
            elevation: 0,
            minimumSize: Size.fromHeight(MediaQuery.textScalerOf(context).scale(D.inputH)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rCard)),
          ),
          child: Text(
            'Start consultation',
            style: D.input.copyWith(color: D.onBrand, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// "29 yrs · Female · +91 98765 43210", with whatever of it is known.
@visibleForTesting
String lineUnder(PatientSummary p) {
  final gender = (p.gender ?? '').trim();
  return [
    if (p.age != null) '${p.age} yrs',
    if (gender.isNotEmpty) '${gender[0].toUpperCase()}${gender.substring(1)}',
    if (p.phone.trim().isNotEmpty) p.phone,
  ].join(' · ');
}

/// The chips under the name: how they are doing, what they have, what they
/// must not be given.
///
/// Risk first because it is a judgement about this moment, then the diagnoses,
/// then the allergies — which are last in the row and first in importance, so
/// they carry a colour and a warning mark rather than a place in the order.
@visibleForTesting
List<({String text, ChipKind kind})> chipsFor(PatientSummary p) {
  final band = (p.riskBand ?? '').trim();
  return [
    // Only when somebody worked it out. A stored band with no computation
    // behind it is the profile's default, not a judgement about this patient.
    if (band.isNotEmpty && p.riskComputedAt != null)
      (text: '${band[0].toUpperCase()}${band.substring(1)} risk', kind: switch (band) {
        'critical' || 'high' => ChipKind.warn,
        _ => ChipKind.plain,
      }),
    for (final c in p.details.comorbidities) (text: c, kind: ChipKind.plain),
    for (final a in p.details.allergies) (text: 'Allergy: $a', kind: ChipKind.allergy),
  ];
}

/// "Today, 8:52 AM", "Yesterday", "12 Mar 2026".
@visibleForTesting
String onDay(DateTime at, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days == 0) return 'Today, ${DateFormat.jm().format(at)}';
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEEE').format(at);
  return DateFormat('d MMM yyyy').format(at);
}
