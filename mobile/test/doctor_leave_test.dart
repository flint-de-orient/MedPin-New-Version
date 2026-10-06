import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/features/appointments/domain/clinic.dart';
import 'package:medpin/features/doctor_home/domain/weekly_schedule.dart';

/// Days the clinic is shut.
///
/// The field behind this — `Clinic.overrides` — has existed all along and the
/// slot endpoint already honours it; I had listed leave as unrecorded. What is
/// worth pinning is the editing: closing a range must not disturb a day that
/// was already closed for another reason, and the list must not fill up with
/// last year's holidays.

ClinicOverride closed(String date, {String? note}) =>
    ClinicOverride(date: date, isClosed: true, note: note);

void main() {
  group('which closures are shown', () {
    test('today counts as upcoming — the clinic is shut this morning', () {
      final shown = upcomingClosures(
        [closed('2026-10-06')],
        now: DateTime(2026, 10, 6, 14),
      );
      expect(shown.length, 1);
    });

    test('yesterday is dropped from the list, not from the record', () {
      final overrides = [closed('2026-10-05'), closed('2026-10-20')];
      final shown = upcomingClosures(overrides, now: DateTime(2026, 10, 6));
      expect(shown.map((o) => o.date), ['2026-10-20']);
      expect(overrides.length, 2, reason: 'the past is why last month looks as it does');
    });

    test('they read earliest first', () {
      final shown = upcomingClosures([
        closed('2026-12-25'),
        closed('2026-10-20'),
        closed('2026-11-14'),
      ], now: DateTime(2026, 10, 6));
      expect(shown.map((o) => o.date), [
        '2026-10-20',
        '2026-11-14',
        '2026-12-25',
      ]);
    });

    test('a date-specific change that is not a closure is not leave', () {
      // An override can also be special hours for one day. That is not a day
      // off and does not belong on this screen.
      final shown = upcomingClosures([
        const ClinicOverride(date: '2026-10-20', isClosed: false),
      ], now: DateTime(2026, 10, 6));
      expect(shown, isEmpty);
    });
  });

  group('closing a range', () {
    test('closes every day in it, both ends included', () {
      final next = withClosures(
        const [],
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 23),
      );
      expect(next.map((o) => o.date), [
        '2026-10-19',
        '2026-10-20',
        '2026-10-21',
        '2026-10-22',
        '2026-10-23',
      ]);
      expect(next.every((o) => o.isClosed), isTrue);
    });

    test('one day is one day', () {
      final next = withClosures(
        const [],
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 19),
      );
      expect(next.length, 1);
    });

    test('a day already in the record is left exactly as it was', () {
      // It may carry a note, or be special hours rather than a closure.
      // Overwriting it would quietly discard whichever it is.
      final existing = [closed('2026-10-20', note: 'Durga Puja')];
      final next = withClosures(
        existing,
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 21),
      );
      expect(next.length, 3);
      expect(
        next.firstWhere((o) => o.date == '2026-10-20').note,
        'Durga Puja',
      );
    });

    test('closures from another month are kept', () {
      final next = withClosures(
        [closed('2026-12-25')],
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 20),
      );
      expect(next.map((o) => o.date), [
        '2026-10-19',
        '2026-10-20',
        '2026-12-25',
      ]);
    });
  });

  test('a closed day is read the way a person says it', () {
    expect(closureLine('2026-10-19'), 'Mon, 19 Oct 2026');
    expect(
      closureLine('not a date'),
      'not a date',
      reason: 'a row that cannot be parsed shows what is on file, not a crash',
    );
  });
}
