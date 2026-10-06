import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two profile screens against the boards they were drawn from.
///
/// ---- Why a source scan ----------------------------------------------------
///
/// Four rows drifted in without anybody noticing: Nutrition and Clinical cards
/// on the Profile tab, Departments and Practice on the hub. Each was a
/// reasonable thing to add on the day — every one opens a real screen that
/// would otherwise have no way in — and the result was two lists that no
/// longer matched the design and read as leftovers from the old app.
///
/// So the lists are written down here, from the boards, and a row added or
/// removed on either screen fails the build until this file is changed too.
/// That is the point: the change is cheap, deciding it is not.
///
/// ---- Where these came from ------------------------------------------------
///
/// `project/Profile.dc.html` — the Clinic tools group, nine rows.
/// `project/Doctor-MyProfile.dc.html` — five groups, twenty-one rows.
///
/// Rows the board has that nothing can save yet are still rows: they are drawn
/// inert and marked "Not on file yet". See widgets/not_on_file.dart.

/// Clinic tools on the Profile tab, in the board's order.
const _clinicTools = [
  'Practice',
  'Plan and billing',
  'Daily report',
  'Clinical alerts',
  'People',
  'Export data',
  'Chat review',
  'Knowledge base',
  'Patient feedback',
];

/// The settings hub, group by group, in the board's order.
const _hub = {
  'ABOUT YOU': [
    'Professional details',
    'ABDM · HPR ID',
    'About and photo',
    'Languages',
  ],
  'PRACTICE': [
    'Locations',
    'Schedules and slots',
    'Services and fees',
    'Leave and holidays',
  ],
  'PATIENTS AND CARE': [
    'Booking rules',
    'Follow-up reminders',
    'Chat and urgent messages',
    'Prescription letterhead and signature',
  ],
  'TEAM': ['Staff and assistants', 'Colleagues you work with'],
  'ACCOUNT': [
    'Notifications',
    'Payouts and bank account',
    'Plan and billing',
    'Privacy and data',
    'App language',
    'Help and support',
    'Log out',
  ],
};

/// `title: '…'` — and never `subtitle:`, which ends in the same six letters
/// and swallowed every second line the first time this was written.
final _title = RegExp(r"(?<![a-z])title: '([^']+)'");

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the Profile tab offers the board\'s nine clinic tools, in its order', () {
    final src = _read('lib/features/clinician/presentation/clinician_more_screen.dart');
    final block = src.substring(
      src.indexOf('CLINIC TOOLS'),
      src.indexOf('PRESCRIPTION LETTERHEAD'),
    );
    final rows = [for (final m in _title.allMatches(block)) m.group(1)!];

    expect(
      rows,
      _clinicTools,
      reason: 'Nutrition and Clinical cards were here and are not on the board. '
          'If a row belongs, add it to the board first, then to this list.',
    );
  });

  test('the hub is the board\'s five groups and twenty-one rows', () {
    final src = _read(
      'lib/features/doctor_home/presentation/doctor_my_profile_screen.dart',
    );
    // The build method only; the widgets beneath it have titles of their own.
    final body = src.substring(0, src.indexOf('/// The disc, the name'));

    final found = <String, List<String>>{};
    String? group;
    final pattern = RegExp(
      r"ProfileEyebrow\(label: '([^']+)'\)"
      r"|(?<![a-z])title: '([^']+)'"
      r"|\n\s+'(Log out)',",
    );
    for (final m in pattern.allMatches(body)) {
      if (m.group(1) != null) {
        group = m.group(1);
        found[group!] = [];
      } else if (group != null) {
        found[group]!.add(m.group(2) ?? m.group(3)!);
      }
    }

    expect(found.keys, _hub.keys, reason: 'the board\'s own group headings');
    for (final entry in _hub.entries) {
      expect(found[entry.key], entry.value, reason: entry.key);
    }
  });

  test('the scan reads something, so a passing run means something', () {
    // Both assertions above iterate what this finds. On an empty match they
    // would pass against an empty screen.
    final src = _read(
      'lib/features/doctor_home/presentation/doctor_my_profile_screen.dart',
    );
    expect(_title.allMatches(src).length, greaterThan(10));
  });
}
