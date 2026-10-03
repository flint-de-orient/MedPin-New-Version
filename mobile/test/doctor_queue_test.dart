import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/appointments/domain/clinic.dart';
import 'package:medpin/features/appointments/presentation/appointment_providers.dart';
import 'package:medpin/features/clinician/domain/appointment.dart';
import 'package:medpin/features/doctor_home/domain/patient_queue.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_queue_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// Today's waiting room.
///
/// The order is the clinic's — priority, then token — and every time on the
/// screen is one the row actually holds. A queue that invents "waiting 0 min"
/// for somebody whose arrival was never recorded sends the doctor to the wrong
/// patient, so the absence has to survive all the way to the screen.

final _now = DateTime(2026, 10, 3, 9, 40);

Appointment _appointment({
  required String name,
  required String status,
  int? token,
  bool priority = false,
  DateTime? checkedInAt,
  DateTime? calledAt,
  DateTime? scheduledFor,
  String? reason,
}) => Appointment.fromJson({
  'id': name.toLowerCase(),
  'patientId': '${name.toLowerCase()}-id',
  'patientName': name,
  'status': status,
  'mode': 'in_person',
  if (token != null) 'queueNumber': token,
  'isPriority': priority,
  if (checkedInAt != null) 'checkedInAt': checkedInAt.toUtc().toIso8601String(),
  if (calledAt != null) 'calledAt': calledAt.toUtc().toIso8601String(),
  if (scheduledFor != null) 'scheduledFor': scheduledFor.toUtc().toIso8601String(),
  if (reason != null) 'reason': reason,
});

class _Clinic implements ClinicianRepository {
  _Clinic({this.today = const []});

  List<Appointment> today;
  final moved = <({String id, String status})>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #appointmentsToday:
        return Future<List<Appointment>>.value(today);
      case #setAppointmentStatus:
        moved.add((
          id: invocation.namedArguments[const Symbol('appointmentId')] as String,
          status: invocation.namedArguments[const Symbol('status')] as String,
        ));
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

Future<void> _pump(WidgetTester tester, _Clinic clinic) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // One practice, one room: the queue never asks which. Overridden so the
        // test does not reach for the network — and so its timeouts do not
        // outlive the test.
        clinicsProvider.overrideWith((ref) async => <Clinic>[]),
        secureStoreProvider.overrideWithValue(_NoSession()),
        apiClientProvider.overrideWithValue(ApiClient(secureStore: _NoSession())),
        clinicianRepositoryProvider.overrideWithValue(clinic),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DoctorQueueScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('the order the room is called in', () {
    test('priority first, then the token', () {
      final rows = queueOrder([
        _appointment(name: 'Rahul', status: 'checked_in', token: 5),
        _appointment(name: 'Aisha', status: 'checked_in', token: 6),
        _appointment(name: 'Sujit', status: 'checked_in', token: 7, priority: true),
      ]);
      expect(rows.map((a) => a.patientName), ['Sujit', 'Rahul', 'Aisha']);
    });

    test('somebody who has not arrived has no token, and sorts by their slot', () {
      final rows = queueOrder([
        _appointment(
          name: 'Later',
          status: 'confirmed',
          scheduledFor: DateTime(2026, 10, 3, 11, 30),
        ),
        _appointment(
          name: 'Sooner',
          status: 'confirmed',
          scheduledFor: DateTime(2026, 10, 3, 11),
        ),
        _appointment(name: 'Here', status: 'checked_in', token: 5),
      ]);
      expect(rows.map((a) => a.patientName), ['Here', 'Sooner', 'Later']);
    });

    test('a cancellation is not somebody the doctor is waiting for', () {
      final rows = queueOrder([
        _appointment(name: 'Gone', status: 'cancelled', token: 4),
        _appointment(name: 'Missed', status: 'no_show', token: 5),
        _appointment(name: 'Here', status: 'checked_in', token: 6),
      ]);
      expect(rows.map((a) => a.patientName), ['Here']);
    });
  });

  group('who is next', () {
    test('the first waiting, once the room is empty', () {
      final day = [
        _appointment(name: 'Rahul', status: 'checked_in', token: 5),
        _appointment(name: 'Aisha', status: 'checked_in', token: 6),
      ];
      expect(nextUp(day)?.patientName, 'Rahul');
    });

    test('nobody, while somebody is still in the room', () {
      final day = [
        _appointment(name: 'Priya', status: 'in_consultation', token: 4),
        _appointment(name: 'Rahul', status: 'checked_in', token: 5),
      ];
      expect(nextUp(day), isNull, reason: 'the next thing is finishing this one');
    });
  });

  group('the time on each row', () {
    test('says what it knows: waiting, started, booked, seen', () {
      expect(
        timeLine(
          _appointment(
            name: 'Rahul',
            status: 'checked_in',
            checkedInAt: _now.subtract(const Duration(minutes: 22)),
          ),
          now: _now,
        ),
        'Waiting 22 min',
      );
      expect(
        timeLine(
          _appointment(
            name: 'Priya',
            status: 'in_consultation',
            calledAt: DateTime(2026, 10, 3, 9, 14),
          ),
          now: _now,
        ),
        'Started 9:14 AM · 26 min',
      );
      expect(
        timeLine(
          _appointment(
            name: 'Moumita',
            status: 'confirmed',
            scheduledFor: DateTime(2026, 10, 3, 11),
          ),
          now: _now,
        ),
        'Booked for 11:00 AM',
      );
    });

    test('an arrival nobody recorded reports no wait at all', () {
      // Checked in before the server kept the time. "Waiting 0 min" would send
      // the doctor to the wrong patient.
      final old = _appointment(name: 'Rahul', status: 'checked_in', token: 5);
      expect(timeLine(old, now: _now), isNull);
      expect(waitingTooLong(old, now: _now), isFalse);
      expect(averageWait([old], now: _now), isNull);
    });

    test('the average is of the waits it actually has', () {
      final day = [
        _appointment(
          name: 'A',
          status: 'checked_in',
          checkedInAt: _now.subtract(const Duration(minutes: 20)),
        ),
        _appointment(
          name: 'B',
          status: 'checked_in',
          checkedInAt: _now.subtract(const Duration(minutes: 10)),
        ),
        _appointment(name: 'C', status: 'checked_in'),
      ];
      expect(averageWait(day, now: _now), 15);
    });
  });

  testWidgets('the room reads top to bottom, with the next one marked', (tester) async {
    await _pump(
      tester,
      _Clinic(
        today: [
          _appointment(
            name: 'Priya Sharma',
            status: 'in_consultation',
            token: 4,
            calledAt: DateTime.now().subtract(const Duration(minutes: 11)),
          ),
          _appointment(name: 'Rahul Das', status: 'checked_in', token: 5),
          _appointment(name: 'Moumita Roy', status: 'confirmed'),
          _appointment(name: 'Debasish Bose', status: 'completed', token: 3),
        ],
      ),
    );

    expect(find.text('In consultation'), findsWidgets);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Start consultation'), findsOneWidget);
    // The group headings are the design's uppercase eyebrows; the pill on the
    // row says the status in sentence case.
    expect(find.text('NOT ARRIVED YET'), findsOneWidget);
    expect(find.text('Not arrived'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
    // Somebody is in the room, so nobody is "next".
    expect(find.text('NEXT'), findsNothing);
  });

  testWidgets('starting a consultation moves them, then opens it', (tester) async {
    final clinic = _Clinic(
      today: [_appointment(name: 'Rahul Das', status: 'checked_in', token: 5)],
    );
    await _pump(tester, clinic);

    expect(find.text('NEXT'), findsOneWidget, reason: 'the room is empty');

    await tester.tap(find.text('Start consultation'));
    await tester.pump();
    await tester.pump();

    expect(clinic.moved, hasLength(1));
    expect(clinic.moved.single.status, 'in_consultation');
  });

  testWidgets('an empty day says so', (tester) async {
    await _pump(tester, _Clinic());
    expect(find.text('Nobody on today’s list yet.'), findsOneWidget);
  });
}
