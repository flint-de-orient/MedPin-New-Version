import '../../../core/capabilities/capabilities.dart';

/// Which navigation branches this practice can see, in bar order.
///
/// ---- Why this is a function and not an `if` in the shell ---------------
///
/// `StatefulShellRoute.indexedStack` addresses its branches by index. Hiding
/// one does not renumber the rest — branch 3 is still branch 3 — so a bar
/// showing three items has to map its own 0,1,2 onto whichever branches those
/// are. Get that wrong and tapping one tab opens another, which is the kind of
/// bug that looks like a routing problem for a day.
///
/// So the mapping is one list, computed once, and testable without a widget
/// tree. [barIndexFor] is its inverse and the two are checked against each
/// other rather than being written twice.
///
/// ---- The five the design draws -----------------------------------------
///
/// Home, Patients, Messages, Reports, History. Every doctor sees all five;
/// nothing here varies any more.
///
/// Nutrition used to be the fourth, shown only where somebody could answer in
/// it. It is not a tab now, and neither is Profile — both are pages opened from
/// elsewhere: the avatar on Home opens Profile, and Profile lists Nutrition.
/// Dropping a tab must not drop the screen behind it, and this is where that
/// was nearly done.

const _home = 0;
const _care = 1;
const _messages = 2;
const _reports = 3;
const _history = 4;

List<int> visibleBranches(Capabilities caps) => const <int>[
  _home,
  _care,
  _messages,
  _reports,
  _history,
];

/// Where a branch sits in the bar, or null when the bar is not showing it.
///
/// Null is the case that matters: somebody standing on Nutrition when the
/// capability goes away is on a branch with no tab. The shell reads null as
/// "move them", rather than passing -1 to a widget that will range-check it
/// into the first item and leave them looking at Home labelled Nutrition.
int? barIndexFor(List<int> visible, int branch) {
  final at = visible.indexOf(branch);
  return at < 0 ? null : at;
}
