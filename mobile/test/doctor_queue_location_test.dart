import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medpin/features/appointments/domain/clinic.dart';
import 'package:medpin/features/clinician/domain/appointment.dart';
import 'package:medpin/features/doctor_home/presentation/widgets/queue_location_sheet.dart';

/// Which waiting room the doctor is in.
///
/// One room is not a choice and is never asked about. Two are, and the answer
/// holds for the day — but only for the day, because tomorrow they may be in
/// the other one.

Clinic _clinic({
  required String id,
  required String name,
  bool active = true,
  List<WeeklyHour> hours = const [],
}) => Clinic.fromJson({
  'id': id,
  'name': name,
  'isActive': active,
  'weeklyHours': [for (final h in hours) h.toJson()],
});

Appointment _appointment({
  required String clinicId,
  required String status,
  int? token,
}) => Appointment.fromJson({
  'id': '$clinicId-$status-${token ?? 0}',
  'patientId': 'p',
  'patientName': 'Patient',
  'status': status,
  'mode': 'in_person',
  'clinic': {'id': clinicId, 'name': 'Room $clinicId'},
  if (token != null) 'queueNumber': token,
});

void main() {
  group('the rooms offered', () {
    test('each carries its own day’s numbers, not the practice’s', () {
      final rooms = locationsOf(
        [_clinic(id: 'a', name: 'Salt Lake'), _clinic(id: 'b', name: 'New Town')],
        [
          _appointment(clinicId: 'a', status: 'checked_in', token: 1),
          _appointment(clinicId: 'a', status: 'checked_in', token: 2),
          _appointment(clinicId: 'a', status: 'completed', token: 3),
          _appointment(clinicId: 'b', status: 'confirmed'),
          _appointment(clinicId: 'b', status: 'cancelled'),
        ],
        now: DateTime(2026, 10, 5, 10),
      );

      final a = rooms.firstWhere((r) => r.id == 'a');
      expect(a.booked, 3, reason: 'two waiting and one seen');
      expect(a.waiting, 2);

      final b = rooms.firstWhere((r) => r.id == 'b');
      expect(b.booked, 1, reason: 'the cancellation is not somebody to see');
      expect(b.waiting, 0);
    });

    test('a closed location is still offered, and says it is closed', () {
      // Monday, and this room only opens on Thursday.
      final rooms = locationsOf(
        [
          _clinic(
            id: 'c',
            name: 'Gariahat',
            hours: const [WeeklyHour(dayOfWeek: 4, start: '17:00', end: '20:00')],
          ),
        ],
        const [],
        now: DateTime(2026, 10, 5, 10),
      );
      expect(rooms.single.status.open, isFalse);
      expect(rooms.single.hours, 'Closed today');
    });

    test('a room that is closed for good is not offered at all', () {
      final rooms = locationsOf(
        [_clinic(id: 'd', name: 'Old chamber', active: false)],
        const [],
        now: DateTime(2026, 10, 5, 10),
      );
      expect(rooms, isEmpty);
    });
  });

  group('what the doctor said', () {
    test('is remembered, and only for the day they said it', () async {
      SharedPreferences.setMockInitialValues({});
      final room = QueueRoom(await SharedPreferences.getInstance());
      final monday = DateTime(2026, 10, 5);
      final tuesday = DateTime(2026, 10, 6);

      expect(room.clinicId, isNull);
      expect(room.settledFor(monday), isFalse);

      await room.choose('a', stopAsking: true, day: monday);
      expect(room.clinicId, 'a');
      expect(room.settledFor(monday), isTrue);
      expect(
        room.settledFor(tuesday),
        isFalse,
        reason: 'tomorrow they may be in the other room',
      );
    });

    test('asking again tomorrow does not forget where they were', () async {
      SharedPreferences.setMockInitialValues({});
      final room = QueueRoom(await SharedPreferences.getInstance());
      await room.choose('a', stopAsking: false, day: DateTime(2026, 10, 5));
      expect(room.clinicId, 'a', reason: 'it is still the last room they chose');
      expect(room.settledFor(DateTime(2026, 10, 5)), isFalse);
    });
  });
}
