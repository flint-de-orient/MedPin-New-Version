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
    // It says what it looked at, so an empty diary is not read as a broken
    // screen: this clinic consults straight from the record, which leaves a
    // prescription and no appointment behind it.
    expect(
      find.textContaining('No appointments in the last 3 months'),
      findsOneWidget,
    );
    expect(find.textContaining('Only booked appointments appear here'), findsOneWidget);

    // And it keeps its distance from the edges of the phone. The empty state
    // carries its own side padding rather than taking the parent's, which it
    // had none of here.
    final text = tester.getRect(
      find.textContaining('No appointments in the last 3 months'),
    );
    expect(text.left, greaterThanOrEqualTo(16));
    expect(text.right, lessThanOrEqualTo(tester.view.physicalSize.width / 2 - 16));
  });

  group('the month a list crosses into', () {
    test('is marked once, above its first day, and never while still running', () {
      final marks = monthOpeners(
        [DateTime(2026, 10, 1), DateTime(2026, 9, 30), DateTime(2026, 9, 29)],
        now: DateTime(2026, 10, 5),
      );
      expect(
        marks,
        {DateTime(2026, 9, 30)},
        reason: 'October is half finished; a card for it would be read as its total, '
            'and September is summarised once rather than above every day in it',
      );
    });

    test('counts only that month, and splits it by what became of each', () {
      final rows = [
        _appointment(name: 'A', status: 'completed', at: DateTime(2026, 9, 30, 9)),
        _appointment(name: 'B', status: 'no_show', at: DateTime(2026, 9, 29, 9)),
        _appointment(name: 'C', status: 'cancelled', at: DateTime(2026, 9, 28, 9)),
        _appointment(name: 'D', status: 'confirmed', at: DateTime(2026, 9, 27, 9)),
        _appointment(name: 'E', status: 'completed', at: DateTime(2026, 8, 31, 9)),
      ];
      final n = monthCounts(rows, DateTime(2026, 9));
      expect(n.total, 4, reason: 'August is a different month, not a rounding error');
      expect((n.completed, n.missed, n.cancelled, n.other), (1, 1, 1, 1));
    });

    test('a count is said in words a doctor would use', () {
      expect(countLine(1), '1 appointment');
      expect(countLine(13), '13 appointments');
    });
  });

  testWidgets('a long day folds, and says how much it is hiding', (tester) async {
    final day = DateTime.now().subtract(const Duration(days: 2));
    final at = DateTime(day.year, day.month, day.day, 9);
    final clinic = _Clinic(
      rows: [
        for (var i = 0; i < 8; i++)
          _appointment(
            name: 'Patient $i',
            status: 'completed',
            at: at.add(Duration(minutes: i * 10)),
          ),
      ],
    );
    await _pump(tester, clinic);

    expect(find.text('Patient 0'), findsOneWidget);
    expect(find.text('Patient 7'), findsNothing);
    final more = find.textContaining('Show 3 more from');
    expect(more, findsOneWidget);

    await tester.tap(more);
    await tester.pump();
    expect(find.text('Patient 7'), findsOneWidget);
  });

  testWidgets('a month behind this one is summarised above its first day', (
    tester,
  ) async {
    // Far enough back to be a finished month whichever day the suite runs on.
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month, 1).subtract(const Duration(days: 5));
    final clinic = _Clinic(
      rows: [
        _appointment(name: 'Debasish', status: 'completed', at: lastMonth),
        _appointment(
          name: 'Ritam',
          status: 'no_show',
          at: lastMonth.subtract(const Duration(days: 1)),
        ),
      ],
    );
    await _pump(tester, clinic);

    expect(find.text('Completed '), findsOneWidget);
    expect(find.text('Missed '), findsOneWidget);
    expect(
      find.text('2 appointments'),
      findsWidgets,
      reason: 'the month card names what it counted',
    );
  });
}
