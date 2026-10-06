import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Profile screen's sections and rows, written down.
///
/// ---- Why a source scan ----------------------------------------------------
///
/// Four rows drifted in once without anybody noticing — Nutrition, Clinical
/// cards, Departments, Practice — each reasonable on the day, and together a
/// screen that no longer matched the design. The list lives here so that
/// adding or removing a row fails the build until this file is changed too.
/// The change is cheap; deciding it is not.
///
/// ---- Two boards, one screen ------------------------------------------------
///
/// The design draws this across `project/Profile.dc.html` (the account and the
/// clinic's tools) and `project/Doctor-MyProfile.dc.html` (the doctor as a
/// doctor). They were two screens and the second was somewhere nobody went, so
/// both are here now. Where the boards overlapped — Plan and billing, the
/// letterhead, the language, the sign-out, the people — the row appears once.
///
/// Rows the boards have that nothing can save yet are still rows: drawn inert
/// and marked "Not on file yet". See widgets/not_on_file.dart.

const _profile = {
  'ABOUT YOU': [
    'Edit profile', // l10n.profileEditProfile
    'Professional details',
    'ABDM · HPR ID',
    'About and photo',
    'Languages',
  ],
  // Not on either board — see the comment on the group in the screen.
  'THE DIARY': ['Appointments', 'Patient queue', 'Follow-ups'],
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
  // One row, by decision: the other seven are how you run the clinic, not
  // who you are. See the comment on the group in the screen.
  'CLINIC TOOLS': ['Plan and billing'],
  'SECURITY': ['App lock'],
  'CLINIC': ['Patient call number'],
  'ACCOUNT': [
    'Notifications',
    'Payouts and bank account',
    'Privacy and data',
    'App language',
    'Help and support',
  ],
  'ABOUT': ['App version'],
};

const _screen = 'lib/features/clinician/presentation/clinician_more_screen.dart';

/// `title: '…'` — and never `subtitle:`, which ends in the same six letters
/// and swallowed every second line the first time this was written.
final _title = RegExp(r"(?<![a-z])title: '([^']+)'");

void main() {
  late String body;

  setUpAll(() {
    final src = File(_screen).readAsStringSync();
    // The build method only; the widgets beneath it have titles of their own.
    body = src.substring(0, src.indexOf('// ------------------------------------------------------------- actions'));
  });

  test('the scan reads something, so a passing run means something', () {
    // Every assertion below iterates what this finds. On an empty match they
    // would all pass against an empty screen.
    expect(_title.allMatches(body).length, greaterThan(20));
  });

  test('the sections are the two boards merged, in one order', () {
    final headings = [
      for (final m in RegExp(
        r"ProfileEyebrow\(label: (?:'([^']+)'|l10n\.(\w+))",
      ).allMatches(body))
        m.group(1) ?? _fromL10n(m.group(2)!),
    ];
    expect(headings, _profile.keys.toList());
  });

  test('every section carries the rows it is supposed to', () {
    final found = <String, List<String>>{};
    String? group;
    final pattern = RegExp(
      r"ProfileEyebrow\(label: (?:'([^']+)'|l10n\.(\w+))"
      r"|(?<![a-z])title: '([^']+)'"
      r"|title: l10n\.(profileEditProfile)"
      r"|l10n\.(profileAppLock),"
      r"|const _Version\(",
    );
    for (final m in pattern.allMatches(body)) {
      if (m.group(1) != null || m.group(2) != null) {
        group = m.group(1) ?? _fromL10n(m.group(2)!);
        found[group] = [];
      } else if (group != null) {
        found[group]!.add(
          m.group(3) ??
              (m.group(4) != null
                  ? 'Edit profile'
                  : m.group(5) != null
                  ? 'App lock'
                  : 'App version'),
        );
      }
    }

    for (final entry in _profile.entries) {
      expect(found[entry.key], entry.value, reason: entry.key);
    }
  });

  test('there is one Profile screen, not two', () {
    // The hub was a second screen that opened from this one. Bringing it back
    // means bringing back the row nobody tapped.
    expect(
      File('lib/features/doctor_home/presentation/doctor_my_profile_screen.dart')
          .existsSync(),
      isFalse,
    );
    expect(body, isNot(contains("'My profile'")));
  });

  test('no row appears twice', () {
    final all = <String>[];
    for (final rows in _profile.values) {
      all.addAll(rows);
    }
    expect(
      all.length,
      all.toSet().length,
      reason: 'the boards overlap; the screen must not. Plan and billing, the '
          'letterhead, the language and the people were each on both.',
    );
  });
}

/// The l10n keys this screen uses for a heading, as they render in English.
String _fromL10n(String key) => switch (key) {
  'profileSecurity' => 'SECURITY',
  'profileClinic' => 'CLINIC',
  'profileAccount' => 'ACCOUNT',
  'profileLanguage' => 'LANGUAGE',
  _ => key,
};
