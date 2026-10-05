import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/features/auth/domain/user.dart';
import 'package:medpin/features/doctor_home/domain/profile_completeness.dart';

/// What the doctor's profile says is unfinished.
///
/// The artboard shows a percentage and a reason ("to appear higher in patient
/// search") that this app cannot stand behind, so what is tested here is the
/// replacement: that every gap named is actually blank, that each one names a
/// consequence that is true, and that a finished profile claims nothing.

AppUser _user({
  String? qualifications,
  String? registrationNo,
  String? signatureUrl,
}) => AppUser.fromJson({
  'id': 'u1',
  'name': 'Dr. Arjun Sen',
  'phone': '+919830041275',
  'role': 'doctor',
  'language': 'en',
  if (qualifications != null) 'qualifications': qualifications,
  if (registrationNo != null) 'registrationNo': registrationNo,
  if (signatureUrl != null) 'signatureUrl': signatureUrl,
});

void main() {
  test('a profile with everything on it claims nothing is missing', () {
    final gaps = whatIsMissing(
      _user(
        qualifications: 'MBBS, MD',
        registrationNo: 'WBMC 64213',
        signatureUrl: '/assets/sig.png',
      ),
      rooms: 1,
    );
    expect(gaps, isEmpty);
  });

  test('each blank field is named once', () {
    final gaps = whatIsMissing(_user(), rooms: 0);
    expect(gaps.map((g) => g.label), [
      'Qualifications',
      'Registration number',
      'Digital signature',
      'A location',
    ]);
  });

  test('whitespace is not a filled-in field', () {
    final gaps = whatIsMissing(
      _user(qualifications: '   ', registrationNo: 'WBMC 1', signatureUrl: 'x'),
      rooms: 2,
    );
    expect(gaps.single.label, 'Qualifications');
  });

  test('every gap says what it costs and where it is filled in', () {
    for (final gap in whatIsMissing(_user(), rooms: 0)) {
      expect(gap.cost.trim(), isNotEmpty);
      expect(gap.route, startsWith('/clinician/'));
    }
  });

  test('nothing is claimed about a doctor who is not signed in', () {
    expect(whatIsMissing(null, rooms: 0), isEmpty);
  });
}
