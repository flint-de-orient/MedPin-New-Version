import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../domain/doctor_ai.dart';
import '../doctor_home_screen.dart' show doctorNameOf;
import 'doctor_ai_composer.dart';
import 'doctor_ai_patient_sheet.dart';

/// The assistant's front door, from the canvas's Doctor-AI artboard.
///
/// What it offers is what the next screen can actually do. The design's five
/// suggestions include four that need a service nobody has built; they are
/// kept, because the doctor should see what is coming, and each says so the
/// moment it is tapped rather than appearing to work.
class DoctorAiScreen extends ConsumerWidget {
  const DoctorAiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final recent = ref.watch(recentQuestionsProvider);

    return Scaffold(
      backgroundColor: D.ground,
      appBar: AppBar(
        backgroundColor: D.card,
        surfaceTintColor: D.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: D.line)),
        // The bar holds two lines of text, so its height follows them.
        toolbarHeight: MediaQuery.textScalerOf(context).scale(D.bar),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded, size: D.iconDisc),
          color: D.ink,
          onPressed: () => context.pop(),
        ),
        title: Text('AI Assistant', style: D.screenTitle.copyWith(color: D.ink)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(D.s5, D.s6, D.s5, D.s6),
              children: [
                _Opening(name: doctorNameOf(user?.name, user?.role)),
                SizedBox(height: D.s6),
                const _TryAsking(),
                if (recent.isNotEmpty) ...[
                  SizedBox(height: D.s6),
                  _Recent(questions: recent),
                ],
              ],
            ),
          ),
          const DoctorAiComposer(),
        ],
      ),
    );
  }
}

class _Opening extends StatelessWidget {
  const _Opening({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: D.discLg + D.s1,
          height: D.discLg + D.s1,
          decoration: BoxDecoration(
            color: D.brand,
            borderRadius: BorderRadius.circular(D.cardPadLg),
            boxShadow: D.liftBrand,
          ),
          child: const Icon(Icons.auto_awesome_rounded, size: D.iconMark, color: D.onBrand),
        ),
        SizedBox(height: D.gapIcon),
        Text(
          'What do you need, $name?',
          textAlign: TextAlign.center,
          style: D.opening.copyWith(color: D.ink),
        ),
        SizedBox(height: D.gapIcon),
        Text(
          'Ask about a patient you have chosen. Type, or tap the mic and speak.',
          textAlign: TextAlign.center,
          style: D.subtitle.copyWith(color: D.inkMuted),
        ),
      ],
    );
  }
}

/// The design's five suggestions. Only the first is answerable today, and the
/// others say so when tapped — the honest version of a disabled row.
class _TryAsking extends ConsumerWidget {
  const _TryAsking();

  static const _prompts = <({String tag, String question, bool ready})>[
    (
      tag: 'Patient',
      question: 'Summarise a patient — health score, abnormal results, medicines',
      ready: true,
    ),
    (tag: 'Appointments', question: 'Who is next in today’s queue?', ready: false),
    (tag: 'Test results', question: 'Which patients have abnormal results this week?', ready: false),
    (tag: 'Prescriptions', question: 'Which prescriptions run out this week?', ready: false),
    (tag: 'Insights', question: 'Which patients are missing their medicines?', ready: false),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: D.s1),
          child: Text('TRY ASKING', style: D.chip.copyWith(color: D.inkFaint)),
        ),
        SizedBox(height: D.s3),
        Container(
          decoration: BoxDecoration(
            color: D.card,
            borderRadius: BorderRadius.circular(D.s6),
            border: Border.all(color: D.line),
            boxShadow: D.lift,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < _prompts.length; i++) ...[
                  if (i > 0) const Divider(height: 1, thickness: 1, indent: D.s4, endIndent: D.s4, color: D.line),
                  _PromptRow(prompt: _prompts[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PromptRow extends ConsumerWidget {
  const _PromptRow({required this.prompt});

  final ({String tag, String question, bool ready}) prompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () async {
        if (!prompt.ready) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not built yet — the assistant can only summarise a patient so far.'),
            ),
          );
          return;
        }
        final chosen = ref.read(doctorAiProvider).patientId != null
            ? true
            : await pickPatientForAi(context, ref);
        if (!chosen || !context.mounted) return;
        final name = ref.read(doctorAiProvider).patientName ?? 'this patient';
        await ref.read(doctorAiProvider.notifier).ask('Summarise $name');
        if (context.mounted) context.push('/clinician/ai/chat');
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.cardPad),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(prompt.tag, style: D.caption.copyWith(color: D.brand, fontWeight: FontWeight.w700)),
                  SizedBox(height: D.s1 - 1),
                  Text(prompt.question, style: D.subtitle.copyWith(color: D.ink)),
                ],
              ),
            ),
            SizedBox(width: D.s3),
            Icon(
              prompt.ready ? Icons.north_east_rounded : Icons.lock_outline_rounded,
              size: D.iconMd,
              color: D.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class _Recent extends ConsumerWidget {
  const _Recent({required this.questions});

  final List<AiQuestion> questions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: D.s1),
          child: Text('RECENT', style: D.chip.copyWith(color: D.inkFaint)),
        ),
        SizedBox(height: D.s3),
        for (final q in questions.take(5)) ...[
          Padding(
            padding: EdgeInsets.only(bottom: D.s2),
            child: Material(
              color: D.card,
              borderRadius: BorderRadius.circular(D.rCard),
              child: InkWell(
                borderRadius: BorderRadius.circular(D.rCard),
                onTap: () => context.push('/clinician/ai/chat'),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.cardPad),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(D.rCard),
                    border: Border.all(color: D.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: D.s1 / 2),
                            Text(askedAt(q.at), style: D.statLabel.copyWith(color: D.inkFaint)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: D.iconMd, color: D.inkFaint),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Today, 8:42 AM", "Yesterday", then the date — as the artboard writes it.
@visibleForTesting
String askedAt(DateTime at, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(clock.year, clock.month, clock.day);
  final days = (today.difference(day).inHours / 24).round();
  if (days <= 0) return 'Today, ${DateFormat.jm().format(at)}';
  if (days == 1) return 'Yesterday';
  return DateFormat('d MMM').format(at);
}
