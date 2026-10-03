import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../clinician/domain/patient_summary.dart';
import '../../clinician/data/clinician_repository.dart';

/// The doctor's conversation with the assistant.
///
/// ---- What answers today, and what does not ---------------------------------
///
/// There is no assistant service for clinicians on the server: the one that
/// exists answers patients, in their own thread, from approved clinical
/// guidance. So this screen answers the one question it can answer honestly
/// from records the doctor may already read — "summarise this patient" — by
/// assembling their own summary, and says plainly that it cannot do the rest.
///
/// It would be easy to make the rest look like it works. A card that says
/// "handled by AI" over a sentence this app wrote itself is the one thing a
/// clinical product must never do, so every answer here carries where it came
/// from, and the ones nobody can answer yet say so.

/// A turn in the conversation: what the doctor asked, and how.
@immutable
class AiQuestion {
  const AiQuestion({required this.text, required this.at, this.spoken = false});

  final String text;
  final DateTime at;

  /// Said out loud rather than typed. The thread marks it, as the design does.
  final bool spoken;
}

/// What came back. One of three shapes, so the screen never has to guess.
sealed class AiAnswer {
  const AiAnswer({required this.at});

  final DateTime at;
}

/// A patient, assembled from their own record.
class PatientAnswer extends AiAnswer {
  const PatientAnswer({required this.summary, required super.at});

  final PatientSummary summary;

  /// The results outside their reference range, newest report first.
  List<(LabReport, Analyte)> get abnormal => [
    for (final report in summary.labResults)
      for (final analyte in report.analytes)
        if (analyte.abnormal && analyte.hasValue) (report, analyte),
  ];

  /// What they are taking, with how much of it they have actually taken.
  List<MedAdherence> get medicines => summary.adherencePerMed;

  /// Where every line above came from. Counted, never rounded up.
  String get provenance {
    final reports = summary.labResults.length;
    final meds = summary.adherencePerMed.length;
    final parts = [
      if (reports > 0) '$reports lab report${reports == 1 ? '' : 's'}',
      if (meds > 0) '$meds medicine${meds == 1 ? '' : 's'} on file',
    ];
    if (parts.isEmpty) return 'From this patient’s record. Not a diagnosis.';
    return 'From ${parts.join(' and ')}. Assembled from the record, not written by a model. Not a diagnosis.';
  }
}

/// A question this build cannot answer, said plainly.
class UnansweredAnswer extends AiAnswer {
  const UnansweredAnswer({required super.at, required this.needsPatient});

  /// True when the question looks like it is about a patient and none is
  /// chosen — the one case the doctor can fix themselves, right now.
  final bool needsPatient;
}

/// The question failed on the way to the server.
class FailedAnswer extends AiAnswer {
  const FailedAnswer({required super.at, required this.message});

  final String message;
}

@immutable
class AiTurn {
  const AiTurn({required this.question, this.answer});

  final AiQuestion question;

  /// Null while the answer is being put together.
  final AiAnswer? answer;

  AiTurn withAnswer(AiAnswer a) => AiTurn(question: question, answer: a);
}

@immutable
class DoctorAiState {
  const DoctorAiState({
    this.turns = const [],
    this.patientId,
    this.patientName,
    this.thinking = false,
  });

  final List<AiTurn> turns;

  /// The patient the conversation is about, as the design's chip shows.
  final String? patientId;
  final String? patientName;

  final bool thinking;

  DoctorAiState copyWith({
    List<AiTurn>? turns,
    String? patientId,
    String? patientName,
    bool? thinking,
    bool clearPatient = false,
  }) => DoctorAiState(
    turns: turns ?? this.turns,
    patientId: clearPatient ? null : (patientId ?? this.patientId),
    patientName: clearPatient ? null : (patientName ?? this.patientName),
    thinking: thinking ?? this.thinking,
  );
}

/// Whether a question is the one this build can answer: "summarise", "tell me
/// about", "what's going on with" — about a patient who has been chosen.
@visibleForTesting
bool asksForASummary(String question) {
  final q = question.toLowerCase();
  return RegExp(
    r'\b(summar\w+|overview|brief\w*|tell me about|catch me up|what.s (going on|happening) with|recap)\b',
  ).hasMatch(q);
}

class DoctorAiController extends StateNotifier<DoctorAiState> {
  DoctorAiController(this._ref) : super(const DoctorAiState());

  final Ref _ref;

  /// Who the conversation is about. The design keeps this in a chip above the
  /// thread, and every answer is read against it.
  void about({required String id, required String name}) {
    state = state.copyWith(patientId: id, patientName: name);
  }

  void clearPatient() => state = state.copyWith(clearPatient: true);

  void startOver() => state = const DoctorAiState();

  /// Asks, and answers from the record where it can.
  Future<void> ask(String text, {bool spoken = false}) async {
    final asked = text.trim();
    if (asked.isEmpty || state.thinking) return;

    final question = AiQuestion(text: asked, at: DateTime.now(), spoken: spoken);
    state = state.copyWith(turns: [...state.turns, AiTurn(question: question)], thinking: true);

    final answer = await _answer(asked);
    state = state.copyWith(
      turns: [
        for (final turn in state.turns)
          if (identical(turn.question, question)) turn.withAnswer(answer) else turn,
      ],
      thinking: false,
    );
  }

  Future<AiAnswer> _answer(String asked) async {
    final now = DateTime.now();
    final patientId = state.patientId;

    if (!asksForASummary(asked) || patientId == null) {
      return UnansweredAnswer(at: now, needsPatient: patientId == null && asksForASummary(asked));
    }
    try {
      final summary = await _ref.read(clinicianRepositoryProvider).patientSummary(patientId);
      return PatientAnswer(summary: summary, at: now);
    } catch (_) {
      return FailedAnswer(at: now, message: 'That patient’s record did not load. Try again.');
    }
  }
}

final doctorAiProvider = StateNotifierProvider<DoctorAiController, DoctorAiState>(
  DoctorAiController.new,
);

/// The questions this doctor has asked on this phone, newest first.
///
/// Kept in memory for now: a conversation history belongs on the server, with
/// the answers and who asked, and there is no service for it yet. Writing it
/// to the handset instead would put clinical questions in a place nobody can
/// audit or delete.
final recentQuestionsProvider = StateProvider<List<AiQuestion>>((ref) => const []);
