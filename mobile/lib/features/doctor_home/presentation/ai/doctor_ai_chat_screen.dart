import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../clinician/domain/patient_summary.dart';
import '../../domain/doctor_ai.dart';
import 'doctor_ai_composer.dart';

/// The conversation, from the canvas's Doctor-AI-Chat artboard.
///
/// The doctor's questions on the right in brand blue, the answers as cards.
/// One kind of answer is real today — a patient assembled from their own
/// record — and every one of them carries where its lines came from. The rest
/// say they are not built rather than being written by this app and labelled
/// as the assistant's.
class DoctorAiChatScreen extends ConsumerWidget {
  const DoctorAiChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(doctorAiProvider);

    return Scaffold(
      backgroundColor: D.ground,
      appBar: AppBar(
        backgroundColor: D.card,
        surfaceTintColor: D.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: D.line)),
        toolbarHeight: D.bar,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded, size: D.iconDisc),
          color: D.ink,
          onPressed: () => context.pop(),
        ),
        title: Text('AI Assistant', style: D.screenTitle.copyWith(color: D.ink)),
        actions: [
          IconButton(
            tooltip: 'New conversation',
            icon: const Icon(Icons.edit_outlined, size: D.iconLg),
            color: D.ink,
            onPressed: () => ref.read(doctorAiProvider.notifier).startOver(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(D.disc),
          child: const AiPatientChip(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: state.turns.isEmpty
                ? const _Empty()
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(D.s4, D.s5, D.s4, D.s5),
                    itemCount: state.turns.length,
                    separatorBuilder: (_, _) => SizedBox(height: D.s4),
                    itemBuilder: (context, i) => _Turn(turn: state.turns[i]),
                  ),
          ),
          const DoctorAiComposer(openChat: false),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(D.s6),
        child: Text(
          'Ask about the patient you have chosen.',
          textAlign: TextAlign.center,
          style: D.body.copyWith(color: D.inkMuted),
        ),
      ),
    );
  }
}

class _Turn extends StatelessWidget {
  const _Turn({required this.turn});

  final AiTurn turn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Asked(question: turn.question),
        SizedBox(height: D.s4),
        switch (turn.answer) {
          null => const _Thinking(),
          final PatientAnswer a => _PatientCard(answer: a),
          final FailedAnswer a => _PlainCard(text: a.message),
          final UnansweredAnswer a => _NotBuiltCard(needsPatient: a.needsPatient),
        },
      ],
    );
  }
}

class _Asked extends StatelessWidget {
  const _Asked({required this.question});

  final AiQuestion question;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s3),
              decoration: const BoxDecoration(
                color: D.brand,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(D.rCardLg),
                  topRight: Radius.circular(D.rCardLg),
                  bottomLeft: Radius.circular(D.rCardLg),
                  bottomRight: Radius.circular(D.gapTight),
                ),
              ),
              child: Text(question.text, style: D.subtitle.copyWith(color: D.onBrand, height: 1.45)),
            ),
            SizedBox(height: D.s1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (question.spoken) ...[
                  const Icon(Icons.mic_none_rounded, size: D.s3, color: D.inkFaint),
                  SizedBox(width: D.s1),
                  Text('Spoken · ', style: D.caption.copyWith(color: D.inkFaint)),
                ],
                Text(DateFormat.jm().format(question.at), style: D.caption.copyWith(color: D.inkFaint)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The card every answer sits in, with the assistant's own mark on it.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.cardPadLg),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.s6),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: D.s8 - D.s1,
                height: D.s8 - D.s1,
                decoration: BoxDecoration(
                  color: D.brandTint,
                  borderRadius: BorderRadius.circular(D.gapIcon),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: D.icon, color: D.brand),
              ),
              SizedBox(width: D.gapIcon),
              Text('MedPin AI', style: D.bodyStrong.copyWith(color: D.ink, fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: D.s4),
          ...children,
        ],
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return _AnswerCard(
      children: [
        Row(
          children: [
            const SizedBox(
              width: D.icon,
              height: D.icon,
              child: CircularProgressIndicator(strokeWidth: 2, color: D.brand),
            ),
            SizedBox(width: D.s3),
            Text('Reading the record…', style: D.body.copyWith(color: D.inkMuted)),
          ],
        ),
      ],
    );
  }
}

class _PlainCard extends StatelessWidget {
  const _PlainCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _AnswerCard(children: [Text(text, style: D.body.copyWith(color: D.ink))]);
  }
}

/// What the assistant cannot do yet, said once and plainly.
class _NotBuiltCard extends ConsumerWidget {
  const _NotBuiltCard({required this.needsPatient});

  final bool needsPatient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AnswerCard(
      children: [
        Text(
          needsPatient
              ? 'Choose a patient first and I can summarise them.'
              : 'I cannot answer that yet.',
          style: D.cardTitle.copyWith(color: D.ink),
        ),
        SizedBox(height: D.s2),
        Text(
          needsPatient
              ? 'Their health score, abnormal results and current medicines, assembled from their own record.'
              : 'Today I can summarise a patient you have chosen — their health score, abnormal results and '
                  'current medicines, assembled from their record. Questions across patients, appointments and '
                  'prescriptions need the assistant service, which is not built yet.',
          style: D.body.copyWith(color: D.inkMuted),
        ),
      ],
    );
  }
}

/// A patient, as the artboard lays them out: who they are and their score,
/// what is out of range, what they are taking, and where it all came from.
class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.answer});

  final PatientAnswer answer;

  @override
  Widget build(BuildContext context) {
    final s = answer.summary;
    final who = [
      if (s.age != null) '${s.age}',
      if (s.gender != null && s.gender!.isNotEmpty) s.gender![0].toUpperCase(),
    ].join(' ');

    return _AnswerCard(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    who.isEmpty ? s.name : '${s.name}, $who',
                    style: D.cardTitle.copyWith(color: D.ink),
                  ),
                  if (s.diabetesType != null && s.diabetesType!.isNotEmpty) ...[
                    SizedBox(height: D.s1),
                    Text(s.diabetesType!, style: D.body.copyWith(color: D.inkMuted)),
                  ],
                ],
              ),
            ),
            if (s.healthScore != null) ...[
              SizedBox(width: D.s3),
              _ScoreBox(score: s.healthScore!, band: s.healthBand),
            ],
          ],
        ),
        if (answer.abnormal.isNotEmpty) ...[
          SizedBox(height: D.s4),
          _Block(
            title: 'Abnormal results',
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(D.rCard),
                border: Border.all(color: D.line),
              ),
              padding: EdgeInsets.symmetric(horizontal: D.cardPad),
              child: Column(
                children: [
                  for (var i = 0; i < answer.abnormal.length && i < 6; i++) ...[
                    if (i > 0) const Divider(height: 1, color: D.line),
                    _Finding(report: answer.abnormal[i].$1, analyte: answer.abnormal[i].$2),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (answer.medicines.isNotEmpty) ...[
          SizedBox(height: D.s4),
          _Block(
            title: 'Current medicines',
            child: Column(
              children: [
                for (final m in answer.medicines.take(6))
                  Padding(
                    padding: EdgeInsets.only(bottom: D.s2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(m.name, style: D.body.copyWith(color: D.ink, fontWeight: FontWeight.w600)),
                        ),
                        SizedBox(width: D.gapIcon),
                        if (m.percentage != null)
                          Text(
                            '${m.percentage}% taken',
                            style: D.caption.copyWith(
                              color: m.percentage! >= 80 ? D.done : D.pending,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        SizedBox(height: D.s4),
        const Divider(height: 1, color: D.line),
        SizedBox(height: D.s3),
        Text(answer.provenance, style: D.caption.copyWith(color: D.inkFaint, height: 1.4)),
        SizedBox(height: D.s3),
        // Wrapped, not a Row: at a large text size "Open profile" and "Copy"
        // together are wider than the card, and a Row would push one of them
        // off the edge where nothing would be drawn at all.
        Wrap(
          spacing: D.s2,
          runSpacing: D.s2,
          children: [
            FilledButton(
              onPressed: () => context.push('/clinician/patients/${s.id}'),
              style: FilledButton.styleFrom(
                backgroundColor: D.brandTint,
                foregroundColor: D.brand,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
              ),
              child: Text('Open profile', style: D.dateLine),
            ),
            OutlinedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _asText(answer)));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: D.ink,
                side: const BorderSide(color: D.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
              ),
              child: Text('Copy', style: D.dateLine),
            ),
          ],
        ),
      ],
    );
  }

  static String _asText(PatientAnswer a) {
    final s = a.summary;
    final lines = <String>[
      s.name,
      if (s.healthScore != null) 'Health score: ${s.healthScore}${s.healthBand == null ? '' : ' (${s.healthBand})'}',
      if (a.abnormal.isNotEmpty) 'Abnormal results:',
      for (final (report, analyte) in a.abnormal.take(6))
        '  ${analyte.label}: ${analyte.value}${analyte.unit ?? ''} (${analyte.flag}) — ${report.testName}',
      if (a.medicines.isNotEmpty) 'Medicines:',
      for (final m in a.medicines.take(6))
        '  ${m.name}${m.percentage == null ? '' : ' — ${m.percentage}% taken'}',
      a.provenance,
    ];
    return lines.join('\n');
  }
}

class _ScoreBox extends StatelessWidget {
  const _ScoreBox({required this.score, required this.band});

  final int score;
  final String? band;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      padding: EdgeInsets.symmetric(vertical: D.gapIcon),
      decoration: BoxDecoration(
        color: D.ground,
        borderRadius: BorderRadius.circular(D.rCard),
        border: Border.all(color: D.line),
      ),
      child: Column(
        children: [
          Text('$score', style: D.score.copyWith(color: D.ink)),
          SizedBox(height: D.s1 / 2),
          Text('Health score', style: D.badgeText.copyWith(color: D.inkMuted, fontWeight: FontWeight.w400)),
          if (band != null)
            Text(band!, style: D.badgeText.copyWith(color: D.done)),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: D.statLabel.copyWith(color: D.inkMuted, fontWeight: FontWeight.w700)),
        SizedBox(height: D.s2),
        child,
      ],
    );
  }
}

class _Finding extends StatelessWidget {
  const _Finding({required this.report, required this.analyte});

  final LabReport report;
  final Analyte analyte;

  @override
  Widget build(BuildContext context) {
    final colour = analyte.flag == 'low' ? D.pending : D.danger;
    final when = report.createdAt == null ? '' : ' · ${DateFormat('d MMM').format(report.createdAt!)}';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: D.gapIcon),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(analyte.label, style: D.body.copyWith(color: D.ink, fontWeight: FontWeight.w600)),
                Text('${report.testName}$when', style: D.caption.copyWith(color: D.inkFaint)),
              ],
            ),
          ),
          SizedBox(width: D.gapIcon),
          // The value over its word, not beside it: a long reading and a long
          // flag ("Critical") together are wider than the card, and the two
          // side by side pushed the flag off the right edge.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${analyte.value}${analyte.unit == null ? '' : ' ${analyte.unit}'}',
                textAlign: TextAlign.right,
                style: D.body.copyWith(color: colour, fontWeight: FontWeight.w700),
              ),
              Text(
                analyte.flag == 'low' ? 'Low' : (analyte.flag == 'critical' ? 'Critical' : 'High'),
                textAlign: TextAlign.right,
                style: D.caption.copyWith(color: colour, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
