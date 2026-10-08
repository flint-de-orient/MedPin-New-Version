import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/practice.dart';

/// Talks to `/practices`. The server enforces doctor-only on the write.
class PracticeRepository {
  PracticeRepository(this._client);

  final ApiClient _client;

  /// The caller's practice with its readiness, locations and head count.
  ///
  /// Returns null when the deployment has not been backfilled yet — an ordinary
  /// state with its own answer on screen, not an error.
  Future<PracticeOverview?> mine() async {
    final json = await _client.getJson('/practices/mine');
    if (json['practice'] == null) return null;
    return PracticeOverview.fromJson(json);
  }

  /// Saves changes, and answers with the practice as it now stands.
  ///
  /// ---- Why the answer is returned rather than discarded -------------------
  ///
  /// This threw the response away, and that made one failure invisible. The
  /// route validates with a zod object, which *strips* keys it does not know
  /// rather than refusing them — so a field this app has learned about and
  /// the deployed server has not is dropped in the middle, saved as nothing,
  /// and answered with 200. The screen then says "Saved".
  ///
  /// For a tagline that is a wasted tap. For a bank account it is a clinic
  /// believing MedPin knows where to send their money. The caller compares
  /// what came back against what it sent — see `_save` in
  /// doctor_payouts_screen.dart.
  ///
  /// Null when the response carries no practice, which is the same unbackfilled
  /// deployment [mine] answers null for.
  Future<PracticeOverview?> update(String id, Map<String, dynamic> changes) async {
    final json = await _client.patchJson('/practices/$id', body: changes);
    if (json['practice'] == null) return null;
    return PracticeOverview.fromJson(json);
  }
}

final practiceRepositoryProvider = Provider<PracticeRepository>(
  (ref) => PracticeRepository(ref.watch(apiClientProvider)),
);

/// Null means "no practice yet", which the screen renders deliberately.
final practiceOverviewProvider = FutureProvider.autoDispose<PracticeOverview?>(
  (ref) => ref.watch(practiceRepositoryProvider).mine(),
);
