import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../appointments/domain/clinic.dart';
import '../../appointments/presentation/appointment_providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/practice_repository.dart';
import '../domain/team_member.dart';
import 'clinician_providers.dart';

/// Everything a clinician's screens read that can be changed by somebody else.
///
/// ---- Why this exists in one place ----------------------------------------
///
/// This app has no real-time channel. No socket, no server-sent events — a
/// screen knows what it knew when it last asked, and most of the clinician's
/// screens ask once and never again. So a location added by a script, a
/// colleague suspended at the front desk, or a practice phone changed on
/// another handset simply does not appear until the app is killed and
/// reopened.
///
/// Two places now ask again — a pull on the profile screen, and the app
/// coming back to the foreground — and if each kept its own list they would
/// drift the first time a provider was added. They call this.
///
/// ---- What is deliberately not here ---------------------------------------
///
/// Anything a screen already owns. The queue re-asks itself every thirty
/// seconds, the dashboard every twenty, and each editor invalidates what it
/// has just written. Adding them here would make a pull refresh the whole app
/// rather than the screen in front of somebody, and turn one gesture into a
/// dozen requests on a clinic's phone connection.
///
/// Patient data is not here either. Which patients a doctor can see does not
/// change because the app came back to the foreground, and re-reading a
/// caseload on every resume is a cost paid all day for a change that happens
/// monthly.
/// Takes a [WidgetRef] rather than a [Ref]: both callers are widgets — the
/// profile screen's pull and the app shell's resume hook — and the two types
/// have no common supertype to accept instead.
Future<void> refreshClinicianContext(WidgetRef ref) async {
  // The account first, and awaited, because the profile screen's "1 thing to
  // finish" is read off it and a half-refreshed header is worse than a stale
  // one.
  await ref.read(authControllerProvider.notifier).refreshUser();

  // The rest together. Each is a different endpoint and none depends on
  // another, so they are invalidated in one go and the screens rebuild as
  // each lands.
  ref.invalidate(practiceOverviewProvider);
  ref.invalidate(clinicsProvider);
  ref.invalidate(teamProvider);

  // Awaited so a pull-to-refresh spinner lasts as long as the work does.
  // Without this the gesture ends immediately and the screen changes under
  // the reader a second later, which reads as the pull having failed.
  //
  // Failures are swallowed on purpose: each of these screens already draws
  // its own error state from the provider, and a refresh that throws would
  // put a second, louder one on top of it.
  await Future.wait([
    ref.read(practiceOverviewProvider.future).catchError((_) => null),
    ref.read(clinicsProvider.future).catchError((_) => <Clinic>[]),
    ref.read(teamProvider.future).catchError((_) => TeamRoster.empty),
  ]);
}
