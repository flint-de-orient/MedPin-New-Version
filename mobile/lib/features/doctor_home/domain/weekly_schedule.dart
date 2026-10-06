import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../appointments/domain/clinic.dart';

/// Reading and editing a doctor's week at one location.
///
/// Pure: the screen fetches and draws, this decides what the week says and
/// what a change to it produces. The arithmetic is the part worth testing —
/// a slot count that is wrong by one is a patient turned away at the door, and
/// the preview on screen is the only place anybody checks it before a booking
/// does.
///
/// Days are the server's: 0 = Sunday … 6 = Saturday.

/// Monday first, Sunday last — the week as a clinic reads it, not as the
/// server numbers it.
const List<int> weekOrder = [1, 2, 3, 4, 5, 6, 0];

const _names = {
  0: 'Sunday',
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
};

String dayName(int day) => _names[day] ?? 'Day $day';

/// The sittings on one day, earliest first.
List<WeeklyHour> hoursOn(List<WeeklyHour> week, int day) =>
    sortedWindows([for (final w in week) if (w.dayOfWeek == day) w]);

List<WeeklyHour> sortedWindows(List<WeeklyHour> windows) =>
    [...windows]..sort((a, b) => a.start.compareTo(b.start));

/// "9:00 AM – 1:00 PM", two sittings joined, or "Closed".
///
/// Closed is said as a word rather than left blank: an empty cell beside six
/// filled ones reads as a row that failed to load.
String dayHoursLine(List<WeeklyHour> week, int day) {
  final windows = hoursOn(week, day);
  if (windows.isEmpty) return 'Closed';
  return windows.map((w) => '${clock(w.start)} – ${clock(w.end)}').join(', ');
}

/// 'HH:mm' as a clinic says it: "9:00 AM".
String clock(String hhmmValue) {
  final at = fromHhmm(hhmmValue);
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, at.hour, at.minute));
}

TimeOfDay fromHhmm(String value) {
  final parts = value.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts.first) ?? 0,
    minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
  );
}

String hhmm(TimeOfDay at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

int _minutes(String hhmmValue) {
  final at = fromHhmm(hhmmValue);
  return at.hour * 60 + at.minute;
}

/// A sitting that ends after it starts. One that does not publishes no slots,
/// and the server refuses it too.
bool endsAfterStart(WeeklyHour w) => _minutes(w.end) > _minutes(w.start);

/// The week with one day's sittings replaced.
List<WeeklyHour> withDay(List<WeeklyHour> week, int day, List<WeeklyHour> windows) => [
  for (final w in week)
    if (w.dayOfWeek != day) w,
  ...windows,
];

/// The first day of the week that is open, Monday first. Null when the whole
/// week is closed.
int? nextOpenDay(List<WeeklyHour> week) {
  for (final day in weekOrder) {
    if (hoursOn(week, day).isNotEmpty) return day;
  }
  return null;
}

/// One day's hours given to every day except Sunday.
///
/// Sunday is left as it was. A clinic that opens six days is the common case,
/// and a "copy to all" that quietly opened Sunday would publish slots on the
/// one day nobody is there.
List<WeeklyHour> copiedAcross(List<WeeklyHour> week, int from) {
  final source = hoursOn(week, from);
  return [
    for (final w in week)
      if (w.dayOfWeek == 0) w,
    for (final day in const [1, 2, 3, 4, 5, 6])
      ...source.map(
        (w) => WeeklyHour(dayOfWeek: day, start: w.start, end: w.end),
      ),
  ];
}

/// Every slot start on one day, as the server would publish them.
///
/// A sitting of 9:00–13:00 at 15 minutes is sixteen slots: the last one starts
/// at 12:45 and ends on the hour. A seventeenth starting at 13:00 would run
/// past the end of the sitting, which is the off-by-one that books somebody
/// after the doctor has gone.
List<String> slotsOn(List<WeeklyHour> week, int day, int slotMinutes) {
  if (slotMinutes <= 0) return const [];
  final out = <String>[];
  for (final w in hoursOn(week, day)) {
    for (var at = _minutes(w.start); at + slotMinutes <= _minutes(w.end); at += slotMinutes) {
      out.add(
        clock('${(at ~/ 60).toString().padLeft(2, '0')}:'
            '${(at % 60).toString().padLeft(2, '0')}'),
      );
    }
  }
  return out;
}

int countSlots(List<WeeklyHour> week, int day, int slotMinutes) =>
    slotsOn(week, day, slotMinutes).length;

/// The first few, for the preview. All of them would be a wall of chips on a
/// full day and tell the doctor nothing the count does not.
List<String> previewSlots(
  List<WeeklyHour> week,
  int day,
  int slotMinutes, {
  int show = 8,
}) => slotsOn(week, day, slotMinutes).take(show).toList();

/// "Mon – Sat · 15-min slots · up to 16 patients a day".
///
/// The patient figure is the busiest day's, not a total and not an average:
/// it is the number the doctor is checking when they change the slot length.
String summaryLine(List<WeeklyHour> week, int slotMinutes) {
  final open = [for (final day in weekOrder) if (hoursOn(week, day).isNotEmpty) day];
  if (open.isEmpty) return 'Closed all week — nobody can book a time here.';

  final busiest = open
      .map((d) => countSlots(week, d, slotMinutes))
      .fold(0, (a, b) => a > b ? a : b);
  return '${openDaysLine(open)} · $slotMinutes-min slots · '
      'up to $busiest ${busiest == 1 ? 'patient' : 'patients'} a day';
}

/// The first slot still free today, across every room that publishes hours.
///
/// ---- Why "still" is the whole job -----------------------------------------
///
/// A slot list for today includes the morning. At four in the afternoon the
/// first *available* slot in it may be nine o'clock, and a profile reading
/// "Next free slot: today, 9:00 AM" is telling the doctor about an hour that
/// has gone. So the clock is compared, not just the availability flag.
///
/// Null when nothing is left — which the screen says as itself rather than
/// falling back to the first slot of the day.
({String time, String where})? nextFreeToday(
  List<({String where, SlotDay day})> rooms, {
  required DateTime now,
}) {
  final after = now.hour * 60 + now.minute;
  ({String time, String where})? best;
  var bestAt = 1 << 30;

  for (final room in rooms) {
    for (final slot in room.day.slots) {
      if (!slot.available) continue;
      final at = _minutes(slot.time);
      if (at <= after || at >= bestAt) continue;
      bestAt = at;
      best = (time: clock(slot.time), where: room.where);
    }
  }
  return best;
}

/// "16 slots · 12 bookable online, 4 kept for walk-ins".
///
/// The board's caption, and the reason the preview exists: a doctor setting
/// walk-in places is asking how many of the day's slots patients can take.
/// Walk-ins come off the end of the sitting rather than the start — a doctor
/// who runs late loses the end of the session, not the morning — so the
/// bookable ones are the first of them.
///
/// `perSlot` above one multiplies the people, not the times: two patients per
/// slot on sixteen slots is thirty-two bookings against sixteen clock times,
/// and saying "16 slots" alone would halve what the clinic thinks it holds.
String slotPreviewLine({
  required int slots,
  required int shown,
  required int perSlot,
  required int walkIns,
}) {
  if (slots == 0) return 'Nothing published that day.';

  final places = slots * perSlot;
  final held = walkIns.clamp(0, places);
  final online = places - held;

  final head = perSlot > 1
      ? '$slots ${slots == 1 ? 'slot' : 'slots'} · $places places at $perSlot a slot'
      : '$slots ${slots == 1 ? 'slot' : 'slots'}';
  final tail = held == 0
      ? 'all bookable online'
      : '$online bookable online, $held kept for walk-ins';
  final cut = shown < slots ? ' · first $shown shown' : '';
  return '$head · $tail$cut';
}

/// "Mon – Sat", "Thu, Sat", "Mon – Wed, Fri".
///
/// Runs are collapsed because that is how a clinic says its hours, and a list
/// of six abbreviations is read as six separate facts.
String openDaysLine(List<int> openDays) {
  final short = {
    0: 'Sun',
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
  };
  final inOrder = [for (final d in weekOrder) if (openDays.contains(d)) d];
  if (inOrder.isEmpty) return 'Closed';

  final parts = <String>[];
  var runStart = 0;
  for (var i = 0; i < inOrder.length; i++) {
    final last = i == inOrder.length - 1;
    // Adjacent in reading order, not in the server's numbering: Saturday and
    // Sunday are 6 and 0, and are not a run.
    final next = last ? -1 : weekOrder.indexOf(inOrder[i + 1]);
    final here = weekOrder.indexOf(inOrder[i]);
    if (last || next != here + 1) {
      parts.add(
        runStart == i
            ? short[inOrder[i]]!
            : '${short[inOrder[runStart]]} – ${short[inOrder[i]]}',
      );
      runStart = i + 1;
    }
  }
  return parts.join(', ');
}

// ============================================================== closures ====
//
// Days a location is shut. They live beside the week because they are read
// with it: the schedule screen shows them under its hours, and the leave
// screen edits the same list.

/// Closed days from today onward, earliest first.
///
/// Past closures are dropped from the list rather than from the record: they
/// are why last month's diary looks the way it does, and a list of them going
/// back a year is not what somebody opens this screen for.
List<ClinicOverride> upcomingClosures(
  List<ClinicOverride> overrides, {
  DateTime? now,
}) {
  final today = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
  return [
    for (final o in overrides)
      if (o.isClosed && o.date.compareTo(today) >= 0) o,
  ]..sort((a, b) => a.date.compareTo(b.date));
}

/// Every day in the range closed, with the ones already closed left alone.
List<ClinicOverride> withClosures(
  List<ClinicOverride> existing,
  DateTime from,
  DateTime to,
) {
  final out = [...existing];
  final have = {for (final o in existing) o.date};
  for (var d = DateTime(from.year, from.month, from.day);
      !d.isAfter(DateTime(to.year, to.month, to.day));
      d = d.add(const Duration(days: 1))) {
    final key = DateFormat('yyyy-MM-dd').format(d);
    if (have.contains(key)) continue;
    out.add(ClinicOverride(date: key, isClosed: true));
  }
  return out..sort((a, b) => a.date.compareTo(b.date));
}

/// "Thu, 19 Oct 2026".
String closureLine(String date) {
  final at = DateTime.tryParse(date);
  return at == null ? date : DateFormat('EEE, d MMM yyyy').format(at);
}
