import '../../clinician/domain/appointment.dart';

/// Today's waiting room, as the doctor works through it.
///
/// ---- Where it comes from ---------------------------------------------------
///
/// `GET /appointments/queue/today` exists and is not this: it is the feed for
/// the screen on the waiting-room wall — token numbers and masked names, only
/// the people already checked in. A doctor needs the ones who have not arrived
/// yet and the ones already seen, and needs to open each record. So this is
/// built from today's diary, which carries the id, the token, the status and
/// the times.
///
/// ---- The order is the clinic's, not the list's -----------------------------
///
/// Priority first, then token order — the same sort the server applies to the
/// wall display, so the doctor's screen and the room agree about who is next.

/// Which part of the day a patient is in.
enum QueueStage { inConsultation, waiting, notArrived, completed }

extension QueueStageText on QueueStage {
  String get title => switch (this) {
    QueueStage.inConsultation => 'In consultation',
    QueueStage.waiting => 'Waiting',
    QueueStage.notArrived => 'Not arrived yet',
    QueueStage.completed => 'Completed',
  };

  String get status => switch (this) {
    QueueStage.inConsultation => 'In consultation',
    QueueStage.waiting => 'Waiting',
    QueueStage.notArrived => 'Not arrived',
    QueueStage.completed => 'Completed',
  };
}

/// Where one appointment sits today.
QueueStage stageOf(Appointment a) => switch (a.status) {
  'in_consultation' => QueueStage.inConsultation,
  'checked_in' => QueueStage.waiting,
  'completed' => QueueStage.completed,
  _ => QueueStage.notArrived,
};

/// Only what is on today's diary and still part of today: a cancellation or a
/// no-show is not somebody the doctor is waiting for.
bool inQueue(Appointment a) =>
    a.status != 'cancelled' && a.status != 'no_show' && a.status != 'requested';

/// The day's list, in the order the room is called.
///
/// Priority first and then by token, exactly as the server sorts the wall
/// display. Anyone without a token has not arrived, so they sort by the time
/// they are booked for.
List<Appointment> queueOrder(List<Appointment> appointments) {
  final rows = [for (final a in appointments) if (inQueue(a)) a];
  rows.sort((x, y) {
    if (x.isPriority != y.isPriority) return x.isPriority ? -1 : 1;
    final a = x.queueNumber;
    final b = y.queueNumber;
    if (a != null && b != null) return a.compareTo(b);
    if (a != null) return -1;
    if (b != null) return 1;
    final at = x.scheduledFor;
    final bt = y.scheduledFor;
    if (at == null || bt == null) return 0;
    return at.compareTo(bt);
  });
  return rows;
}

/// The day in four groups, each in queue order.
Map<QueueStage, List<Appointment>> queueGroups(List<Appointment> appointments) {
  final out = {for (final s in QueueStage.values) s: <Appointment>[]};
  for (final a in queueOrder(appointments)) {
    out[stageOf(a)]!.add(a);
  }
  return out;
}

/// Who the doctor should see next: the first person waiting, once nobody is in
/// the room. While a consultation is running there is no "next" — finishing
/// the one in front of you is the next thing.
Appointment? nextUp(List<Appointment> appointments) {
  final groups = queueGroups(appointments);
  if (groups[QueueStage.inConsultation]!.isNotEmpty) return null;
  final waiting = groups[QueueStage.waiting]!;
  return waiting.isEmpty ? null : waiting.first;
}

/// "Waiting 22 min", "Started 9:14 AM · 11 min", "Booked for 11:00 AM".
///
/// Each one is a fact the row actually holds. An appointment checked in before
/// the server recorded arrival times has no wait to report, and says so by
/// saying nothing — a queue that invents "waiting 0 min" sends the doctor to
/// the wrong patient.
String? timeLine(Appointment a, {required DateTime now}) {
  switch (stageOf(a)) {
    case QueueStage.inConsultation:
      final from = a.calledAt;
      if (from == null) return null;
      return 'Started ${_clock(from)} · ${_minutes(now.difference(from))}';
    case QueueStage.waiting:
      final from = a.checkedInAt;
      if (from == null) return null;
      return 'Waiting ${_minutes(now.difference(from))}';
    case QueueStage.notArrived:
      final at = a.scheduledFor;
      return at == null ? null : 'Booked for ${_clock(at)}';
    case QueueStage.completed:
      final from = a.calledAt;
      return from == null ? null : 'Seen ${_clock(from)}';
  }
}

/// Long enough that somebody should say something about it.
bool waitingTooLong(Appointment a, {required DateTime now, int minutes = 20}) {
  final from = a.checkedInAt;
  if (stageOf(a) != QueueStage.waiting || from == null) return false;
  return now.difference(from).inMinutes >= minutes;
}

/// The average wait of everybody still waiting, or null when nobody's arrival
/// time is known — an average over the two rows that happen to have one is not
/// the clinic's average.
int? averageWait(List<Appointment> appointments, {required DateTime now}) {
  final waits = [
    for (final a in queueGroups(appointments)[QueueStage.waiting]!)
      if (a.checkedInAt != null) now.difference(a.checkedInAt!).inMinutes,
  ];
  if (waits.isEmpty) return null;
  return (waits.reduce((x, y) => x + y) / waits.length).round();
}

/// What this visit is about, from what the diary holds: why they came and how
/// they are being seen. Not their age or their conditions — the diary does not
/// carry those, and the record is one tap away.
String metaLine(Appointment a) {
  final reason = (a.reason ?? '').trim();
  return [
    if (reason.isNotEmpty) reason,
    if (a.mode == 'teleconsult') 'Video',
    if (a.isPriority) 'Priority',
  ].join(' · ');
}

String _clock(DateTime at) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
}

String _minutes(Duration d) {
  final total = d.inMinutes;
  if (total < 1) return 'just now';
  if (total < 60) return '$total min';
  final hours = total ~/ 60;
  final rest = total % 60;
  return rest == 0 ? '$hours hr' : '$hours hr $rest min';
}
