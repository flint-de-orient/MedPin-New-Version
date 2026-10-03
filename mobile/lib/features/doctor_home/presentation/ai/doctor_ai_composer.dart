import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../domain/doctor_ai.dart';
import 'doctor_ai_patient_sheet.dart';
import 'doctor_ai_voice_sheet.dart';

/// The bar the doctor asks from: a field, a send button and the mic.
///
/// The same bar on the front door and inside a conversation, as the design
/// draws it; `openChat` is what differs — from the front door, asking moves to
/// the thread.
class DoctorAiComposer extends ConsumerStatefulWidget {
  const DoctorAiComposer({super.key, this.openChat = true});

  /// True on the front door: the first question pushes the conversation.
  final bool openChat;

  @override
  ConsumerState<DoctorAiComposer> createState() => _DoctorAiComposerState();
}

class _DoctorAiComposerState extends ConsumerState<DoctorAiComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send({bool spoken = false}) async {
    final asked = _text.text.trim();
    if (asked.isEmpty) return;
    _text.clear();
    setState(() {});

    final question = AiQuestion(text: asked, at: DateTime.now(), spoken: spoken);
    ref.read(recentQuestionsProvider.notifier).update((list) => [question, ...list].take(20).toList());

    if (widget.openChat && context.mounted) context.push('/clinician/ai/chat');
    await ref.read(doctorAiProvider.notifier).ask(asked, spoken: spoken);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _text.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(D.s4, D.s3, D.s4, D.s3),
      decoration: const BoxDecoration(
        color: D.card,
        border: Border(top: BorderSide(color: D.line)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    // Scaled, not fixed: a constant height around text clips
                    // it the moment the reader turns their text size up.
                    height: MediaQuery.textScalerOf(context).scale(D.discLg + D.s1),
                    padding: EdgeInsets.fromLTRB(D.cardPadLg, 0, D.s2, 0),
                    decoration: BoxDecoration(
                      color: D.card,
                      borderRadius: BorderRadius.circular(D.rBar),
                      border: Border.all(color: ready ? D.brand : D.line, width: ready ? 1.5 : 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _text,
                            focusNode: _focus,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _send(),
                            textInputAction: TextInputAction.send,
                            style: D.subtitle.copyWith(color: D.ink),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Ask about a patient',
                              hintStyle: D.subtitle.copyWith(color: D.inkFaint),
                            ),
                          ),
                        ),
                        Semantics(
                          button: true,
                          label: 'Send',
                          child: InkWell(
                            onTap: ready ? _send : null,
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: D.disc - D.s2,
                              height: D.disc - D.s2,
                              decoration: BoxDecoration(
                                color: ready ? D.brand : D.ground,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.arrow_upward_rounded,
                                size: D.iconMd,
                                color: ready ? D.onBrand : D.inkFaint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: D.s2),
                Semantics(
                  button: true,
                  label: 'Speak your question',
                  child: InkWell(
                    onTap: () async {
                      final said = await askByVoice(context);
                      if (said == null || !mounted) return;
                      _text.text = said;
                      await _send(spoken: true);
                    },
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: D.discLg + D.s1,
                      height: D.discLg + D.s1,
                      decoration: BoxDecoration(
                        color: D.brand,
                        shape: BoxShape.circle,
                        boxShadow: D.liftBrand,
                      ),
                      child: const Icon(Icons.mic_none_rounded, size: D.iconDisc, color: D.onBrand),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: D.gapIcon),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Answers come from your records. Check before acting — not a diagnosis.',
                    textAlign: TextAlign.center,
                    style: D.caption.copyWith(color: D.inkFaint),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The chip above the thread: who the conversation is about.
class AiPatientChip extends ConsumerWidget {
  const AiPatientChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(doctorAiProvider);
    final name = state.patientName;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(D.s5, 0, D.s5, D.s3),
      color: D.card,
      child: Row(
        children: [
          Text('Talking about', style: D.statLabel.copyWith(color: D.inkMuted)),
          SizedBox(width: D.s2),
          Flexible(
            child: name == null
                ? OutlinedButton.icon(
                    onPressed: () => pickPatientForAi(context, ref),
                    icon: const Icon(Icons.person_add_alt_outlined, size: D.icon),
                    label: Text('Choose a patient', style: D.dateLine),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: D.brand,
                      side: const BorderSide(color: D.line),
                      shape: const StadiumBorder(),
                      padding: EdgeInsets.symmetric(horizontal: D.s3),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                : Container(
                    padding: EdgeInsets.fromLTRB(D.s1, D.s1 / 2, D.s1 / 2, D.s1 / 2),
                    decoration: const BoxDecoration(color: D.brandTint, borderRadius: D.rPill),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: D.s6,
                          height: D.s6,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: D.brand, shape: BoxShape.circle),
                          child: Text(
                            initialsOf(name),
                            style: D.badgeText.copyWith(color: D.onBrand),
                          ),
                        ),
                        SizedBox(width: D.s2),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: D.dateLine.copyWith(color: D.brand),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Clear patient',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(width: D.s6, height: D.s6),
                          padding: EdgeInsets.zero,
                          iconSize: D.iconSm,
                          color: D.brand,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => ref.read(doctorAiProvider.notifier).clearPatient(),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Two letters for the disc: a name's own, titles skipped.
@visibleForTesting
String initialsOf(String name) {
  final bare = name.trim().replaceFirst(
    RegExp(r'^(dr|prof|mr|mrs|ms|smt|shri|sri)\.?\s+', caseSensitive: false),
    '',
  );
  final parts = bare.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}
