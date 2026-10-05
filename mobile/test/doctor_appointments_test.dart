import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/appointments/domain/appointment.dart';
import 'package:medpin/features/appointments/presentation/appointment_providers.dart';
import 'package:medpin/features/doctor_home/domain/appointment_book.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_appointments_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/models/paged.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// The doctor's own diary.
///
/// The questions it has to answer are narrow — who is coming, who is still
/// waiting for a time, and what may be moved — so what is worth testing is
/// that each of those is answered from the rows and not from a guess: that a
/// request is never counted as booked, that a day is named the way a doctor
/// would say it, and that nothing offers to move an appointment that has
/// already happened.

Appointment _booked({
  required String name,
  required DateTime at,
  String status = 'confirmed',
  String? clinic = 'City Care · Salt Lake',
}) => Appointment.fromJson({
  'id': '$name-${at.millisecondsSinceEpoch}',
  'patientId': name.toLowerCase(),
  'patientName': name,
  'status': status,
  'mode': 'in_clinic',
  'scheduledFor': at.toUtc().toIso8601String(),
  'doctorName': 'Dr. Sen',
  if (clinic != null) 'clinicName': clinic,
  if (clinic != null) 'clinicId': 'c1',
});

Appointment _request({
  required String name,
  required DateTime asked,
  String? reason,
  String? preferredTime,
}) => Appointment.fromJson({
  'id': 'req-$name',
  'patientId': name.toLowerCase(),
  'patientName': name,
  'status': 'requested',
  'mode': 'in_clinic',
  'createdAt': asked.toUtc().toIso8601String(),
  if (reason != null) 'reason': reason,
  if (preferredTime != null) 'preferredTime': preferredTime,
});

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

Future<void> _pump(
  WidgetTester tester, {
  List<Appointment> diary = const [],
  List<Appointment> requests = const [],
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  Paged<Appointment> page(List<Appointment> rows) => Paged(
    items: rows,
    page: 1,
    limit: 100,
    total: rows.length,
    hasMore: false,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(_NoSession()),
        apiClientProvider.overrideWithValue(ApiClient(secureStore: _NoSession())),
        appointmentDiaryProvider.overrideWith(
          (ref, q) async => page(q.status == 'requested' ? requests : diary),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DoctorAppointmentsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('what the figures count', () {
    test('a cancelled appointment is not one that is booked', () {
      final at = DateTime.now();
      final stats = diaryStats(
        [
          _booked(name: 'A', at: at),
          _booked(name: 'B', at: at, status: 'cancelled'),
          _booked(name: 'C', at: at, status: 'no_show'),
        ],
        const [],
      );
      expect(stats.booked, 1);
      expect(stats.cancelled, 1);
      expect(
        stats.waiting,
        0,
        reason: 'a missed appointment is neither booked nor cancelled',
      );
    });

    test('waiting counts requests, which have no day to be counted on', () {
      final stats = diaryStats(const [], [
        _request(name: 'Sujit', asked: DateTime.now()),
      ]);
      expect(stats.waiting, 1);
      expect(stats.booked, 0);
    });
  });

  group('the days', () {
    test('an appointment with no time is left out of the grouping', () {
      final days = diaryDays([
        _booked(name: 'A', at: DateTime(2026, 9, 30, 9)),
        _request(name: 'Sujit', asked: DateTime(2026, 9, 29)),
      ], newestFirst: false);
      expect(days.keys.toList(), [DateTime(2026, 9, 30)]);
      expect(days.values.single.length, 1);
    });

    test('read forwards while looking ahead and backwards while looking back', () {
      final rows = [
        _booked(name: 'A', at: DateTime(2026, 9, 30, 9)),
        _booked(name: 'B', at: DateTime(2026, 10, 1, 9)),
      ];
      expect(diaryDays(rows, newestFirst: false).keys.first, DateTime(2026, 9, 30));
      expect(diaryDays(rows, newestFirst: true).keys.first, DateTime(2026, 10, 1));
    });

    test('a day within a day is in time order', () {
      final days = diaryDays([
        _booked(name: 'Late', at: DateTime(2026, 9, 30, 17)),
        _booked(name: 'Early', at: DateTime(2026, 9, 30, 9)),
      ], newestFirst: false);
      expect(days.values.single.map((a) => a.patientName), ['Early', 'Late']);
    });

    test('are named the way a doctor would say them', () {
      final now = DateTime(2026, 9, 29);
      expect(diaryDayLabel(DateTime(2026, 9, 29), now: now), startsWith('Today · '));
      expect(
        diaryDayLabel(DateTime(2026, 9, 30), now: now),
        startsWith('Tomorrow · '),
      );
      expect(diaryDayLabel(DateTime(2026, 10, 5), now: now), 'Mon 5 Oct');
    });
  });

  group('the window a tab asks for', () {
    test('upcoming starts tomorrow, so nothing is in two tabs at once', () {
      final now = DateTime(2026, 9, 29, 15);
      final today = boundsFor(DiaryScope.today, now: now);
      final soon = boundsFor(DiaryScope.upcoming, now: now);
      expect(today.to!.isBefore(soon.from!), isTrue);
      expect(soon.from, DateTime(2026, 9, 30));
    });
  });

  group('a reschedule', () {
    test('offers tomorrow first, never a time today that may have passed', () {
      final days = rescheduleDays(now: DateTime(2026, 9, 29, 15), count: 3);
      expect(days.first, DateTime(2026, 9, 30));
      expect(days.length, 3);
    });
  });

  testWidgets('requests sit above the diary, oldest first', (tester) async {
    await _pump(
      tester,
      requests: [
        _request(
          name: 'Farhana Islam',
          asked: DateTime.now().subtract(const Duration(hours: 2)),
          reason: 'Follow-up on her haemoglobin report',
        ),
        _request(
          name: 'Sujit Mondal',
          asked: DateTime.now().subtract(const Duration(days: 1)),
          reason: 'Fever and body ache for 3 days',
          preferredTime: 'Any morning this week',
        ),
      ],
    );

    expect(find.text('Waiting for a time'), findsOneWidget);
    expect(find.text('Requests with no slot yet, oldest first'), findsOneWidget);
    expect(find.textContaining('Any morning this week'), findsOneWidget);

    final sujit = tester.getTopLeft(find.text('Sujit Mondal')).dy;
    final farhana = tester.getTopLeft(find.text('Farhana Islam')).dy;
    expect(
      sujit,
      lessThan(farhana),
      reason: 'the one nobody answered yesterday is the more urgent',
    );
  });

  testWidgets('a day with nothing in it says so rather than drawing an empty card', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.textContaining('Nothing booked for today'), findsOneWidget);
  });

  testWidgets('what has already happened cannot be moved', (tester) async {
    final now = DateTime.now();
    await _pump(
      tester,
      diary: [
        _booked(
          name: 'Coming Up',
          at: now.add(const Duration(hours: 3)),
        ),
        _booked(
          name: 'Already Seen',
          at: now.subtract(const Duration(hours: 3)),
          status: 'completed',
        ),
      ],
    );

    expect(find.text('Coming Up'), findsOneWidget);
    expect(find.text('Already Seen'), findsOneWidget);
    expect(
      find.text('Manage'),
      findsOneWidget,
      reason: 'only the one that has not happened yet',
    );
  });
}
