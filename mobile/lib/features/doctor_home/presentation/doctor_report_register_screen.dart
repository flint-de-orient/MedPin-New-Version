import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../domain/consultation_report.dart';
import 'widgets/profile_parts.dart';
import 'widgets/report_parts.dart';

/// The lists the summary's figures were counted from.
///
/// One screen for three registers, because they are the same screen: a window,
/// a list of rows, and a line at the top saying what was counted. A doctor who
/// does not believe "286 consultations" opens this and reads them.
enum RegisterKind { consultations, prescriptions, followUps }

extension RegisterText on RegisterKind {
  String get title => switch (this) {
    RegisterKind.consultations => 'Consultation register',
    RegisterKind.prescriptions => 'Prescription register',
    RegisterKind.followUps => 'Follow-up compliance',
  };
}

class DoctorReportRegisterScreen extends ConsumerWidget {
  const DoctorReportRegisterScreen({
    super.key,
    required this.kind,
    required this.from,
    required this.to,
  });

  final RegisterKind kind;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = (from: from, to: to);

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
            Text(kind.title, style: D.screenTitle.copyWith(color: D.ink)),
            Text(
              '${DateFormat('d MMM').format(from)} – ${DateFormat('d MMM yyyy').format(to)}',
              style: D.statLabel.copyWith(color: D.inkMuted),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: switch (kind) {
          RegisterKind.consultations => _Consultations(window: window),
          RegisterKind.prescriptions => _Prescriptions(window: window),
          RegisterKind.followUps => _FollowUps(window: window),
        },
      ),
    );
  }
}

class _Consultations extends ConsumerWidget {
  const _Consultations({required this.window});

  final ({DateTime from, DateTime to}) window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(consultationRegisterProvider(window));

    return rows.when(
      loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
      error: (_, _) =>
          ProfileFailed(onRetry: () => ref.invalidate(consultationRegisterProvider(window))),
      data: (items) => items.isEmpty
          ? const ProfileEmpty(text: 'Nobody was seen in this window.')
          : ListView(
              padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.s8),
              children: [
                Padding(
                  padding: EdgeInsets.only(left: D.s1, bottom: D.s2),
                  child: ProfileEyebrow(label: '${items.length} consultations'),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: D.s4),
                  decoration: _card,
                  child: Column(
                    children: [
                      for (final (i, r) in items.indexed)
                        ProfileRow(
                          first: i == 0,
                          onTap: r.patientId == null
                              ? null
                              : () => context.push(
                                  '/clinician/patients/${r.patientId}',
                                  extra: r.patientName,
                                ),
                          child: _Line(
                            title: r.patientName,
                            detail: [
                              DateFormat('d MMM, h:mm a').format(r.at),
                              if ((r.reason ?? '').trim().isNotEmpty) r.reason!.trim(),
                              if (r.clinicName != null) r.clinicName!,
                            ].join(' · '),
                            // Null where nobody timed it — the register says
                            // nothing rather than nought minutes.
                            trailing: r.minutes == null ? null : '${r.minutes} min',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Prescriptions extends ConsumerWidget {
  const _Prescriptions({required this.window});

  final ({DateTime from, DateTime to}) window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(prescriptionRegisterProvider(window));

    return rows.when(
      loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
      error: (_, _) =>
          ProfileFailed(onRetry: () => ref.invalidate(prescriptionRegisterProvider(window))),
      data: (items) => items.isEmpty
          ? const ProfileEmpty(text: 'Nothing was prescribed in this window.')
          : ListView(
              padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.s8),
              children: [
                Padding(
                  padding: EdgeInsets.only(left: D.s1, bottom: D.s2),
                  child: ProfileEyebrow(label: '${items.length} prescriptions'),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: D.s4),
                  decoration: _card,
                  child: Column(
                    children: [
                      for (final (i, r) in items.indexed)
                        ProfileRow(
                          first: i == 0,
                          onTap: r.patientId == null
                              ? null
                              : () => context.push(
                                  '/clinician/patients/${r.patientId}?tab=prescriptions',
                                  extra: r.patientName,
                                ),
                          child: _Line(
                            title: r.patientName,
                            detail: [
                              DateFormat('d MMM').format(r.at),
                              if (r.diagnosis.isNotEmpty) r.diagnosis.join(', '),
                              '${r.medicines} medicine${r.medicines == 1 ? '' : 's'}',
                              if (r.tests > 0) '${r.tests} test${r.tests == 1 ? '' : 's'}',
                            ].join(' · '),
                            // A prescription that no longer stands is still in
                            // the register, and says which it is.
                            flag: r.stands ? null : 'No longer stands',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _FollowUps extends ConsumerWidget {
  const _FollowUps({required this.window});

  final ({DateTime from, DateTime to}) window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(followUpComplianceProvider(window));

    return data.when(
      loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
      error: (_, _) =>
          ProfileFailed(onRetry: () => ref.invalidate(followUpComplianceProvider(window))),
      data: (report) {
        if (report.items.isEmpty) {
          return const ProfileEmpty(text: 'Nobody was asked back in this window.');
        }
        final waiting = [for (final r in report.items) if (r.pending) r];
        final missed = [for (final r in report.items) if (!r.pending && !r.came) r];
        final kept = [for (final r in report.items) if (!r.pending && r.came) r];

        return ListView(
          padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.s8),
          children: [
            ReportCard(
              title: 'Came back on time',
              note: report.percent == null ? 'None due yet' : '${report.kept} of ${report.due}',
              child: report.percent == null
                  // Nobody's date has passed, so there is no compliance to
                  // report — not 0%.
                  ? Text(
                      'Nobody’s follow-up has come due yet in this window.',
                      style: D.body.copyWith(color: D.inkMuted),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${report.percent}%', style: D.metric.copyWith(color: D.ink)),
                        SizedBox(height: D.s3),
                        ClipRRect(
                          borderRadius: D.rPill,
                          child: LinearProgressIndicator(
                            value: report.percent! / 100,
                            minHeight: D.s2,
                            backgroundColor: D.track,
                            valueColor: const AlwaysStoppedAnimation(D.brand),
                          ),
                        ),
                      ],
                    ),
            ),
            SizedBox(height: D.s4),
            if (missed.isNotEmpty) ...[
              _Group(label: 'Did not come back', rows: missed, tone: D.pending),
              SizedBox(height: D.s4),
            ],
            if (waiting.isNotEmpty) ...[
              _Group(label: 'Still to come', rows: waiting, tone: D.inkMuted),
              SizedBox(height: D.s4),
            ],
            if (kept.isNotEmpty) _Group(label: 'Came back', rows: kept, tone: D.done),
          ],
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.rows, required this.tone});

  final String label;
  final List<FollowUpRow> rows;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: D.s1, bottom: D.s2),
          child: ProfileEyebrow(label: '$label · ${rows.length}', colour: tone),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: D.s4),
          decoration: _card,
          child: Column(
            children: [
              for (final (i, r) in rows.indexed)
                ProfileRow(
                  first: i == 0,
                  onTap: r.patientId == null
                      ? null
                      : () => context.push(
                          '/clinician/patients/${r.patientId}',
                          extra: r.patientName,
                        ),
                  child: _Line(
                    title: r.patientName,
                    detail: 'Due ${DateFormat('d MMM yyyy').format(r.dueOn)}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.title, required this.detail, this.trailing, this.flag});

  final String title;
  final String detail;
  final String? trailing;
  final String? flag;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
              ),
              Text(detail, style: D.statLabel.copyWith(color: D.inkFaint)),
              if (flag != null)
                Text(
                  flag!,
                  style: D.caption.copyWith(color: D.pending, fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: D.s2),
          Text(
            trailing!,
            style: D.statLabel.copyWith(color: D.inkMuted, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

final _card = BoxDecoration(
  color: D.card,
  borderRadius: BorderRadius.circular(D.rSection),
  border: Border.all(color: D.line),
  boxShadow: D.lift,
);
