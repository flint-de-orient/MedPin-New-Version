import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/features/appointments/domain/clinic.dart';
import 'package:medpin/features/doctor_home/domain/weekly_schedule.dart';

/// A doctor's week at one location.
///
/// The slot arithmetic is the part that matters: a count wrong by one is a
/// patient booked after the doctor has gone home, and the preview on this
/// screen is the only place anybody checks it before a booking does.

WeeklyHour at(int day, String start, String end) =>
    WeeklyHour(dayOfWeek: day, start: start, end: end);

void main() {
  group('the week as a clinic reads it', () {
    test('starts on Monday and ends on Sunday', () {
      expect(weekOrder, [1, 2, 3, 4, 5, 6, 0]);
    });

    test('a day with nothing on it is Closed, said as a word', () {
      expect(dayHoursLine(const [], 1), 'Closed');
    });

    test('two sittings are both shown, earliest first', () {
      final week = [at(1, '16:00', '19:00'), at(1, '09:00', '13:00')];
      expect(dayHoursLine(week, 1), '9:00 AM – 1:00 PM, 4:00 PM – 7:00 PM');
    });

    test('runs of days collapse the way a clinic says them', () {
      expect(openDaysLine(const [1, 2, 3, 4, 5, 6]), 'Mon – Sat');
      expect(openDaysLine(const [4, 6]), 'Thu, Sat');
      expect(openDaysLine(const [1, 2, 3, 5]), 'Mon – Wed, Fri');
      expect(
        openDaysLine(const [6, 0]),
        'Sat – Sun',
        reason: 'the run is in reading order, not in the numbering: Saturday '
            'is 6 and Sunday is 0, and a weekend clinic says "Sat – Sun"',
      );
      expect(
        openDaysLine(const [0, 1]),
        'Mon, Sun',
        reason: 'Sunday and Monday are the two ends of the week, not a run — '
            'the numbering would have made them one',
      );
      expect(openDaysLine(const []), 'Closed');
    });
  });

  group('the slots a sitting publishes', () {
    test('the last one ends on the hour, and there is no one after it', () {
      final week = [at(1, '09:00', '13:00')];
      final slots = slotsOn(week, 1, 15);
      expect(slots.length, 16);
      expect(slots.first, '9:00 AM');
      expect(
        slots.last,
        '12:45 PM',
        reason: 'a slot starting at 1:00 PM would run past the end of the '
            'sitting — that is the booking made after the doctor has gone',
      );
    });

    test('a slot that does not fit is not published', () {
      // 9:00–9:50 at twenty minutes is two slots, not two and a half.
      expect(countSlots([at(1, '09:00', '09:50')], 1, 20), 2);
    });

    test('both sittings of a split day count', () {
      final week = [at(1, '09:00', '11:00'), at(1, '16:00', '18:00')];
      expect(countSlots(week, 1, 30), 8);
    });

    test('a closed day publishes nothing', () {
      expect(slotsOn([at(1, '09:00', '13:00')], 0, 15), isEmpty);
    });

    test('a nonsense slot length publishes nothing rather than looping', () {
      expect(slotsOn([at(1, '09:00', '13:00')], 1, 0), isEmpty);
    });

    test('the preview shows the first few and the count says the rest', () {
      final week = [at(1, '09:00', '13:00')];
      expect(previewSlots(week, 1, 15).length, 8);
      expect(countSlots(week, 1, 15), 16);
    });
  });

  group('editing it', () {
    test('a sitting that ends before it starts is refused', () {
      expect(endsAfterStart(at(1, '13:00', '09:00')), isFalse);
      expect(endsAfterStart(at(1, '09:00', '09:00')), isFalse);
      expect(endsAfterStart(at(1, '09:00', '09:15')), isTrue);
    });

    test('replacing a day leaves every other day alone', () {
      final week = [at(1, '09:00', '13:00'), at(2, '10:00', '12:00')];
      final next = withDay(week, 1, [at(1, '08:00', '11:00')]);
      expect(dayHoursLine(next, 1), '8:00 AM – 11:00 AM');
      expect(dayHoursLine(next, 2), '10:00 AM – 12:00 PM');
    });

    test('clearing a day closes it', () {
      final next = withDay([at(1, '09:00', '13:00')], 1, const []);
      expect(dayHoursLine(next, 1), 'Closed');
    });

    test('copying across opens Monday to Saturday and leaves Sunday shut', () {
      final next = copiedAcross([at(1, '09:00', '13:00')], 1);
      for (final day in const [1, 2, 3, 4, 5, 6]) {
        expect(dayHoursLine(next, day), '9:00 AM – 1:00 PM', reason: 'day $day');
      }
      expect(
        dayHoursLine(next, 0),
        'Closed',
        reason: 'publishing slots on the one day nobody is there',
      );
    });

    test('copying a split day copies both of its sittings', () {
      final week = [at(1, '09:00', '11:00'), at(1, '16:00', '18:00')];
      final next = copiedAcross(week, 1);
      expect(hoursOn(next, 3).length, 2);
    });
  });

  group('the summary under the week', () {
    test('names the days, the slot length and the busiest day', () {
      final week = [
        for (final d in const [1, 2, 3, 4, 5]) at(d, '09:00', '13:00'),
        at(6, '09:00', '11:30'),
      ];
      expect(summaryLine(week, 15), 'Mon – Sat · 15-min slots · up to 16 patients a day');
    });

    test('a week with nothing open says so instead of counting nothing', () {
      expect(
        summaryLine(const [], 15),
        'Closed all week — nobody can book a time here.',
      );
    });
  });

  group('clock reading', () {
    test('is what a clinic writes, not twenty-four hours', () {
      expect(clock('09:00'), '9:00 AM');
      expect(clock('13:05'), '1:05 PM');
      expect(clock('00:30'), '12:30 AM');
    });

    test('survives a round trip through the picker', () {
      expect(hhmm(fromHhmm('09:05')), '09:05');
      expect(hhmm(fromHhmm('23:59')), '23:59');
    });
  });

  group('the next free slot today', () {
    SlotDay day(List<(String, bool)> slots) => SlotDay(
      clinicId: 'c1',
      date: '2026-10-06',
      slotMinutes: 15,
      slots: [
        for (final (time, free) in slots)
          Slot(time: time, iso: '2026-10-06T$time:00Z', available: free),
      ],
    );

    test('is the first one still ahead, not the first one free', () {
      // At four in the afternoon the morning is still in the list and still
      // marked available. Reporting 9:00 AM is reporting an hour that is gone.
      final next = nextFreeToday(
        [(where: 'Salt Lake', day: day([('09:00', true), ('16:30', true)]))],
        now: DateTime(2026, 10, 6, 16),
      );
      expect(next?.time, '4:30 PM');
    });

    test('skips the ones already taken', () {
      final next = nextFreeToday(
        [(where: 'Salt Lake', day: day([('09:00', false), ('09:15', true)]))],
        now: DateTime(2026, 10, 6, 8),
      );
      expect(next?.time, '9:15 AM');
    });

    test('takes the earliest across rooms, and says which room', () {
      final next = nextFreeToday(
        [
          (where: 'Salt Lake', day: day([('12:15', true)])),
          (where: 'New Town', day: day([('10:00', true)])),
        ],
        now: DateTime(2026, 10, 6, 9),
      );
      expect(next?.time, '10:00 AM');
      expect(next?.where, 'New Town');
    });

    test('nothing left today is null, never the first slot of the morning', () {
      final next = nextFreeToday(
        [(where: 'Salt Lake', day: day([('09:00', true), ('09:15', false)]))],
        now: DateTime(2026, 10, 6, 17),
      );
      expect(next, isNull);
    });

    test('a day with no rooms at all is null, not a crash', () {
      expect(nextFreeToday(const [], now: DateTime(2026, 10, 6)), isNull);
    });
  });

  group('the line under the slot preview', () {
    test('names the split the walk-in places make', () {
      expect(
        slotPreviewLine(slots: 16, shown: 16, perSlot: 1, walkIns: 4),
        '16 slots · 12 bookable online, 4 kept for walk-ins',
      );
    });

    test('with none held back it says so rather than printing "0 kept"', () {
      expect(
        slotPreviewLine(slots: 16, shown: 16, perSlot: 1, walkIns: 0),
        '16 slots · all bookable online',
      );
    });

    test('two to a slot is twice the people, not twice the times', () {
      // Saying "16 slots" alone would halve what the clinic thinks it holds.
      expect(
        slotPreviewLine(slots: 16, shown: 8, perSlot: 2, walkIns: 4),
        '16 slots · 32 places at 2 a slot · 28 bookable online, '
        '4 kept for walk-ins · first 8 shown',
      );
    });

    test('holding back more than the day has leaves nothing bookable, not a negative', () {
      expect(
        slotPreviewLine(slots: 4, shown: 4, perSlot: 1, walkIns: 50),
        '4 slots · 0 bookable online, 4 kept for walk-ins',
      );
    });

    test('a day with nothing published says that instead of counting nothing', () {
      expect(
        slotPreviewLine(slots: 0, shown: 0, perSlot: 1, walkIns: 0),
        'Nothing published that day.',
      );
    });

    test('one slot is a slot', () {
      expect(
        slotPreviewLine(slots: 1, shown: 1, perSlot: 1, walkIns: 0),
        '1 slot · all bookable online',
      );
    });
  });
}
