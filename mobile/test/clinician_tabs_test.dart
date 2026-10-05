import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/capabilities/capabilities.dart';
import 'package:medpin/features/clinician/presentation/clinician_tabs.dart';

/// The bar's indices and the router's branch indices are different numbers.
///
/// `StatefulShellRoute.indexedStack` addresses branches by index, so the bar
/// has to map its own positions onto whichever branches those are. Getting it
/// wrong means tapping one tab and landing on another — which reads as a
/// routing bug for a day before anybody suspects arithmetic.
///
/// So the mapping is a pure function, and this is why it is one.
///
/// ---- What changed ----------------------------------------------------------
///
/// The bar is the design's five: Home, Patients, Messages, Reports, History.
/// Nutrition was the fourth and was shown only where somebody could answer in
/// it; Profile was the fifth. Neither is a tab now — Home's avatar opens
/// Profile, and Profile lists Nutrition — so the gating this file used to pin
/// is gone, and what it pins instead is that nothing varies.
Capabilities _caps(
  Set<String> effective, {
  bool hasDietician = false,
  String? practiceType,
}) => Capabilities(
  practiceType: practiceType,
  specialty: null,
  plan: null,
  practice: effective,
  effective: effective,
  role: 'doctor',
  isOwner: false,
  resolved: true,
  hasDietician: hasDietician,
);

void main() {
  group('what the bar shows', () {
    test('the same five, whatever the practice has', () {
      // Home, Patients, Messages, Reports, History.
      expect(visibleBranches(_caps({Cap.aiAssistant})), [0, 1, 2, 3, 4]);
      expect(visibleBranches(_caps({})), [0, 1, 2, 3, 4]);
      expect(
        visibleBranches(_caps({}, hasDietician: true)),
        [0, 1, 2, 3, 4],
        reason: 'a dietician no longer adds a tab, because Nutrition is not one',
      );
    });
  });

  group('the bar position of a branch', () {
    test('is where it sits in the list', () {
      final visible = visibleBranches(_caps({Cap.aiAssistant}));
      for (var branch = 0; branch < 5; branch++) {
        expect(barIndexFor(visible, branch), branch);
      }
    });

    test('is null for a branch the bar is not showing', () {
      // Nothing is hidden today, but the shell still has to answer this: a
      // branch with no tab must read as "move them", not as the first item.
      expect(barIndexFor(const [0, 1, 2], 4), isNull);
      expect(barIndexFor(const [0, 1, 2, 3, 4], 9), isNull);
    });
  });
}
