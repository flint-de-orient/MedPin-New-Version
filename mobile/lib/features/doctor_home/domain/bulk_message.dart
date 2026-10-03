/// One message, to several patients.
///
/// ---- Why this is a loop and not a server call ------------------------------
///
/// This server has no fan-out endpoint, and this does not add one. Each patient
/// gets a real message in their own thread, through the same
/// `clinician-message` call a single reply uses: the same practice scoping, the
/// same audit line, the same notification, the same conversation the patient is
/// already reading. A second server path for clinical messages is a second path
/// that can drift from the first — and the one that drifts is the one nobody
/// looks at.
///
/// ---- Which makes stopping half way the thing to get right -------------------
///
/// A loop can stop after four of nine. Everything here exists to make that
/// visible rather than tidy: who it reached, who it did not, and the ability to
/// send again to only the ones it missed. It sends one at a time, in the order
/// shown, so "the first four went" is a true sentence.
///
/// ---- And nobody is a group ------------------------------------------------
///
/// There is no group thread. Each patient sees a message from their clinic in
/// their own conversation and cannot see that anybody else got it, which is
/// what makes this safe to use on a list of people who share a diagnosis.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../clinician/data/clinician_repository.dart';

/// Somebody the message is going to.
class BulkRecipient {
  const BulkRecipient({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is BulkRecipient && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// What happened to one of them.
enum BulkOutcome { waiting, sending, sent, failed }

/// How far the send has got.
class BulkSend {
  const BulkSend({
    this.outcomes = const {},
    this.failures = const {},
    this.running = false,
    this.finished = false,
  });

  /// By patient id.
  final Map<String, BulkOutcome> outcomes;

  /// Why each failure failed, by patient id — shown, not swallowed.
  final Map<String, String> failures;

  final bool running;

  /// The loop has been through everybody at least once.
  final bool finished;

  int get sent => outcomes.values.where((o) => o == BulkOutcome.sent).length;
  int get failed => outcomes.values.where((o) => o == BulkOutcome.failed).length;

  /// Nothing reached anybody. Worth saying differently from "most of it went".
  bool get allFailed => finished && sent == 0 && failed > 0;

  BulkSend copyWith({
    Map<String, BulkOutcome>? outcomes,
    Map<String, String>? failures,
    bool? running,
    bool? finished,
  }) => BulkSend(
    outcomes: outcomes ?? this.outcomes,
    failures: failures ?? this.failures,
    running: running ?? this.running,
    finished: finished ?? this.finished,
  );
}

/// The most this will send in one go.
///
/// Not a technical limit — a limit on how far a mis-tap can travel. Writing to
/// everybody on the roll is not a thing a thumb should be able to do by
/// accident, and a doctor who means to can send a second batch.
const int kBulkLimit = 25;

class BulkMessageController extends StateNotifier<BulkSend> {
  BulkMessageController(this._ref) : super(const BulkSend());

  final Ref _ref;

  /// Sends [text] to each of [to], one after another.
  ///
  /// Call it again with the ones that failed to try just those.
  Future<void> send(List<BulkRecipient> to, String text) async {
    final message = text.trim();
    if (message.isEmpty || to.isEmpty || state.running) return;

    final people = to.take(kBulkLimit).toList();
    state = BulkSend(
      outcomes: {for (final p in people) p.id: BulkOutcome.waiting},
      running: true,
    );

    final repository = _ref.read(clinicianRepositoryProvider);
    for (final person in people) {
      if (!mounted) return;
      state = state.copyWith(
        outcomes: {...state.outcomes, person.id: BulkOutcome.sending},
      );
      try {
        await repository.messagePatient(patientId: person.id, content: message);
        if (!mounted) return;
        state = state.copyWith(
          outcomes: {...state.outcomes, person.id: BulkOutcome.sent},
        );
      } catch (e) {
        if (!mounted) return;
        state = state.copyWith(
          outcomes: {...state.outcomes, person.id: BulkOutcome.failed},
          failures: {...state.failures, person.id: '$e'},
        );
      }
    }

    if (!mounted) return;
    state = state.copyWith(running: false, finished: true);
  }

  /// Back to an empty slate, for a second batch.
  void reset() => state = const BulkSend();
}

final bulkMessageProvider = StateNotifierProvider.autoDispose<BulkMessageController, BulkSend>(
  BulkMessageController.new,
);

/// "Sent to 7 patients", or the truth when it is not that.
String sendSummary(BulkSend send, int asked) {
  if (send.allFailed) return 'None of them went. Nothing was sent.';
  if (send.failed > 0) {
    return '${send.sent} of $asked sent · ${send.failed} did not go';
  }
  return 'Sent to ${send.sent} patient${send.sent == 1 ? '' : 's'}';
}
