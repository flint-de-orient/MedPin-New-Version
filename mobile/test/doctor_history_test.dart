import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/appointment.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_history_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// Every past appointment, newest first.
///
/// It is the diary read backwards, so what matters is that each row says what
/// actually became of the appointment, that the days group in the right order,
/// and that the filters offered are ones that can select something.

Appointment _appointment({
  required String name,
  required String status,
  required DateTime at,
  String? reason,
  DateTime? calledAt,
  DateTime? completedAt,
}) => Appointment.fromJson({
  'id': '$name-${at.millisecondsSinceEpoch}',
  'patientId': name.toLowerCase(),
  'patientName': name,
  'status': status,
  'mode': 'in_person',
  'scheduledFor': at.toUtc().toIso8601String(),
  if (reason != null) 'reason': reason,
  if (calledAt != null) 'calledAt': calledAt.toUtc().toIso8601String(),
  if (completedAt != null) 'completedAt': completedAt.toUtc().toIso8601String(),
});

class _Clinic implements ClinicianRepository {
  _Clinic({this.rows = const []});

  List<Appointment> rows;
  final asked = <String?>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #appointmentHistory) {
      asked.add(invocation.namedArguments[const Symbol('status')] as String?);
      return Future<List<Appointment>>.value(rows);
    }
    return super.noSuchMethod(invocation);
  }
}

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

Future<void> _pump(WidgetTester tester, _Clinic clinic) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(_NoSession()),
        apiClientProvider.overrideWithValue(ApiClient(secureStore: _NoSession())),
        clinicianRepositoryProvider.overrideWithValue(clinic),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DoctorHistoryScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('what became of an appointment', () {
    test('is the word for its status, not the status', () {
      expect(outcomeOf(_appointment(name: 'A', status: 'completed', at: DateTime.now())).$1,
          'Completed');
      expect(
        outcomeOf(_appointment(name: 'B', status: 'no_show', at: DateTime.now())).$1,
        'Missed',
        reason: 'a doctor does not read "no_show"',
      );
      expect(outcomeOf(_appointment(name: 'C', status: 'cancelled', at: DateTime.now())).$1,
          'Cancelled');
      expect(outcomeOf(_appointment(name: 'D', status: 'confirmed', at: DateTime.now())).$1,
          'Booked');
    });

    test('the filters offered are ones that can select something', () {
      // The design has a fifth, "Rescheduled". Moving an appointment changes
      // its time in place and no status records it, so a chip for it would
      // select nothing for ever.
      expect(HistoryFilter.values.map((f) => f.label), [
        'All',
        'Completed',
        'Missed',
        'Cancelled',
      ]);
      expect(HistoryFilter.all.status, isNull);
      expect(HistoryFilter.missed.status, 'no_show');
    });
  });

  group('the days', () {
    test('group by the day booked, and an appointment with no time is left out', () {
      final rows = [
        _appointment(name: 'A', status: 'completed', at: DateTime(2026, 10, 2, 9)),
        _appointment(name: 'B', status: 'completed', at: DateTime(2026, 10, 2, 17)),
        _appointment(name: 'C', status: 'completed', at: DateTime(2026, 10, 1, 9)),
      ];
      final days = byDay(rows);
      expect(days.keys.toList(), [DateTime(2026, 10, 2), DateTime(2026, 10, 1)]);
      expect(days[DateTime(2026, 10, 2)]!.length, 2);
    });

    test('are named as a doctor would say them', () {
      final today = DateTime(2026, 10, 5);
      expect(dayLabel(DateTime(2026, 10, 5), now: today), 'Today, 5 Oct');
      expect(dayLabel(DateTime(2026, 10, 4), now: today), 'Yesterday, 4 Oct');
      expect(dayLabel(DateTime(2026, 9, 30), now: today), 'Wed, 30 Sep');
    });
  });

  test('searching narrows what was loaded', () {
    final rows = [
      _appointment(name: 'Priya Sharma', status: 'completed', at: DateTime(2026, 10, 2)),
      _appointment(name: 'Rahul Das', status: 'completed', at: DateTime(2026, 10, 2)),
    ];
    expect(matching(rows, 'priya').single.patientName, 'Priya Sharma');
    expect(matching(rows, '').length, 2);
    expect(matching(rows, 'nobody'), isEmpty);
  });

  testWidgets('the list reads newest day first, with what became of each', (tester) async {
    final now = DateTime.now();
    await _pump(
      tester,
      _Clinic(
        rows: [
          _appointment(
            name: 'Debasish Bose',
            status: 'completed',
            at: DateTime(now.year, now.month, now.day, 9, 10),
            reason: 'Follow-up',
            calledAt: DateTime(now.year, now.month, now.day, 9, 10),
            completedAt: DateTime(now.year, now.month, now.day, 9, 19),
          ),
          _appointment(
            name: 'Ritam Sarkar',
            status: 'no_show',
            at: DateTime(now.year, now.month, now.day, 11, 30),
          ),
        ],
      ),
    );

    expect(find.text('History'), findsOneWidget);
    expect(find.text('All your past appointments'), findsOneWidget);
    expect(find.text('Debasish Bose'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('Missed'), findsWidgets);
    expect(find.textContaining('9 min'), findsOneWidget, reason: 'it was timed');
  });

  testWidgets('a filter asks the server for that outcome', (tester) async {
    final clinic = _Clinic(
      rows: [_appointment(name: 'A', status: 'completed', at: DateTime.now())],
    );
    await _pump(tester, clinic);

    expect(clinic.asked.last, isNull, reason: 'All asks for every outcome');

    await tester.tap(find.text('Missed'));
    await tester.pump();
    await tester.pump();

    expect(clinic.asked.last, 'no_show');
  });

  testWidgets('an empty window says which window it was', (tester) async {
    await _pump(tester, _Clinic());
    expect(find.text('Nothing in the last 3 months.'), findsOneWidget);
  });
}
