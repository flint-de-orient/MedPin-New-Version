import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../appointments/domain/appointment.dart';

/// Reading the diary, for the doctor's own Appointments screen.
///
/// ---- Why this is not the desk's screen -------------------------------------
///
/// The front desk already has one, and it is the one that runs the day:
/// requests, calls, messages, walk-ins. A doctor opening their own diary is
/// asking a narrower question — who is coming, in what order, and can I move
/// somebody — so the same data is read a second way rather than the desk's
/// screen being bent to serve two readers.
///
/// Everything here is pure. The screen fetches and draws; this decides what
/// the rows mean, which is the part worth testing.

/// Which slice of the booked diary is on screen.
enum DiaryScope { today, upcoming, past }

extension DiaryScopeText on DiaryScope {
  String get label => switch (this) {
    DiaryScope.today => 'Today',
    DiaryScope.upcoming => 'Upcoming',
    DiaryScope.past => 'Past',
  };
}

/// The dates a scope asks the server for.
///
/// "Upcoming" starts tomorrow rather than now, because today is its own tab
/// and an appointment at four o'clock should not be in two lists at once.
({DateTime? from, DateTime? to}) boundsFor(DiaryScope scope, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final endOfToday = DateTime(at.year, at.month, at.day, 23, 59, 59);
  return switch (scope) {
    DiaryScope.today => (from: today, to: endOfToday),
    DiaryScope.upcoming => (
      from: today.add(const Duration(days: 1)),
      to: today.add(const Duration(days: 60)),
    ),
    DiaryScope.past => (from: today.subtract(const Duration(days: 60)), to: today),
  };
}

/// The appointments in a scope, grouped by the day they are for.
///
/// Oldest day first while looking forwards, newest first while looking back —
/// either way the next thing to read is at the top.
Map<DateTime, List<Appointment>> diaryDays(
  List<Appointment> all, {
  required bool newestFirst,
}) {
  final out = <DateTime, List<Appointment>>{};
  for (final a in all) {
    final at = a.scheduledFor?.toLocal();
    if (at == null) continue;
    (out[DateTime(at.year, at.month, at.day)] ??= []).add(a);
  }
  for (final rows in out.values) {
    rows.sort((x, y) => x.scheduledFor!.compareTo(y.scheduledFor!));
  }
  final days = out.keys.toList()
    ..sort((x, y) => newestFirst ? y.compareTo(x) : x.compareTo(y));
  return {for (final d in days) d: out[d]!};
}

/// The three figures above the list.
///
/// The artboard's third is "Freed up", which claims a slot reopened. That is
/// only true of a cancellation still in the future, so what is counted and
/// named here is the thing that is true in every tab: it was cancelled.
({int booked, int waiting, int cancelled}) diaryStats(
  List<Appointment> scoped,
  List<Appointment> requests,
) {
  var booked = 0, cancelled = 0;
  for (final a in scoped) {
    if (a.status == 'cancelled') {
      cancelled++;
    } else if (a.status != 'no_show') {
      booked++;
    }
  }
  return (booked: booked, waiting: requests.length, cancelled: cancelled);
}

/// What a row's status is called, and the colours that carry the word.
(String, Color, Color) bookingState(Appointment a) => switch (a.status) {
  'requested' => ('Waiting for a time', D.pendingGround, D.pending),
  'confirmed' => ('Confirmed', D.doneGround, D.done),
  'checked_in' => ('Checked in', D.brandTint, D.brand),
  'in_consultation' => ('In consultation', D.brandTint, D.brand),
  'completed' => ('Completed', D.doneGround, D.done),
  'cancelled' => ('Cancelled', D.track, D.inkMuted),
  'no_show' => ('Missed', D.dangerGround, D.danger),
  _ => ('Booked', D.track, D.inkMuted),
};

/// "Today · Tue 29 Sep", "Wed 30 Sep".
String diaryDayLabel(DateTime day, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final days = DateTime(at.year, at.month, at.day).difference(day).inDays;
  final written = DateFormat('EEE d MMM').format(day);
  if (days == 0) return 'Today · $written';
  if (days == 1) return 'Yesterday · $written';
  if (days == -1) return 'Tomorrow · $written';
  return written;
}

/// "Dr. Sen · Salt Lake", from whatever the row actually carries.
///
/// An appointment with no location is left saying only who it is with: a
/// clinic name invented to fill the line is a clinic the patient will turn up
/// at.
String whereLine(Appointment a) => [
  if ((a.doctorName ?? '').trim().isNotEmpty) a.doctorName!.trim(),
  if ((a.clinicName ?? '').trim().isNotEmpty) a.clinicName!.trim(),
].join(' · ');

/// "Asked today, 8:15 AM" — when the request came in.
String askedLine(Appointment a, {DateTime? now}) {
  final at = a.createdAt?.toLocal();
  if (at == null) return 'Asked recently';
  final today = DateTime.now();
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  final clock = DateFormat('h:mm a').format(at);
  if (days == 0) return 'Asked today, $clock';
  if (days == 1) return 'Asked yesterday, $clock';
  return 'Asked ${DateFormat('d MMM').format(at)}, $clock';
}

/// What the patient asked for, in their own words where they gave any.
String? preferenceLine(Appointment a) {
  final day = a.preferredFor?.toLocal();
  final time = (a.preferredTime ?? '').trim();
  if (day == null && time.isEmpty) return null;
  return [
    if (day != null) DateFormat('EEE d MMM').format(day),
    if (time.isNotEmpty) time,
  ].join(' · ');
}

/// The days a reschedule offers, starting tomorrow.
///
/// Today is left out on purpose: moving somebody to a slot that may already
/// have passed is a booking the clinic then has to apologise for.
List<DateTime> rescheduleDays({DateTime? now, int count = 14}) {
  final at = now ?? DateTime.now();
  final first = DateTime(at.year, at.month, at.day).add(const Duration(days: 1));
  return [for (var i = 0; i < count; i++) first.add(Duration(days: i))];
}

/// 'yyyy-MM-dd', the key the slot endpoint takes.
String dateKey(DateTime day) => DateFormat('yyyy-MM-dd').format(day);
