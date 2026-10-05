import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/caseload_panels.dart';
import 'package:medpin/features/doctor_home/presentation/follow_ups_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// Follow-ups: who the doctor asked to come back, and when they were due.
///
/// The server names the first few in each group and counts the rest, so the
/// screen must say what it is not showing — a list that quietly stops is a
/// list a doctor trusts for the wrong number.

final _now = DateTime(2026, 10, 3, 9);

/// Dates are counted from the real clock, not from [_now].
///
/// The screen words these against `DateTime.now()`, so a fixture pinned to a
/// fixed day says "23 days overdue" only while that day is today — these two
/// tests failed the morning the date rolled over, for no reason but that.
/// [_now] stays for the pure tests below, which pass their own clock in.
FollowUps _followUps({int days = 7, int overdueTotal = 2, int dueTotal = 2}) {
  final today = DateTime.now();
  return FollowUps.fromJson({
  'days': days,
  'overdue': [
    {
      'patientId': 'p1',
      'name': 'Kaushik Paul',
      'followUpOn': today.subtract(const Duration(days: 23)).toUtc().toIso8601String(),
      'doctorName': 'Dr. Sen',
    },
    {
      'patientId': 'p2',
      'name': 'Shreya Basu',
      'followUpOn': today.subtract(const Duration(days: 1)).toUtc().toIso8601String(),
      'doctorName': 'Dr. Sen',
    },
  ],
  'overdueTotal': overdueTotal,
  'due': [
    {
      'patientId': 'p3',
      'name': 'Moumita Roy',
      'followUpOn': today.toUtc().toIso8601String(),
      'doctorName': 'Dr. Sen',
    },
    {
      'patientId': 'p4',
      'name': 'Tapas Kar',
      'followUpOn': today.add(const Duration(days: 3)).toUtc().toIso8601String(),
      'doctorName': 'Dr. Mitra',
    },
  ],
  'dueTotal': dueTotal,
  });
}

class _Clinic implements ClinicianRepository {
  _Clinic({this.data});

  FollowUps? data;
  final asked = <int>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #followUps) {
      final days = invocation.namedArguments[const Symbol('days')] as int? ?? 7;
      asked.add(days);
      final answer = data;
      if (answer == null) return Future<FollowUps>.error(StateError('no'));
      return Future<FollowUps>.value(answer);
    }
    return super.noSuchMethod(invocation);
  }
}

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

Future<void> _pump(WidgetTester tester, _Clinic clinic) async {
  tester.view.physicalSize = const Size(720, 1600);
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
        home: const FollowUpsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('how a date reads', () {
    String label(DateTime at, {required bool overdue}) =>
        dueLabel(at, overdue: overdue, now: _now);

    test('overdue counts the days, due names the day', () {
      expect(label(_now.subtract(const Duration(days: 23)), overdue: true), '23 days overdue');
      expect(label(_now.subtract(const Duration(days: 1)), overdue: true), '1 day overdue');
      expect(label(_now, overdue: false), 'Due today');
      expect(label(_now.add(const Duration(days: 1)), overdue: false), 'Due tomorrow');
      expect(label(_now.add(const Duration(days: 3)), overdue: false), 'Due Tue, 6 Oct');
    });

    test('a follow-up with no date says only what is known', () {
      expect(dueLabel(null, overdue: true, now: _now), 'Overdue');
      expect(dueLabel(null, overdue: false, now: _now), 'Due');
    });
  });

  testWidgets('both groups are shown, worded as the artboard words them', (tester) async {
    await _pump(tester, _Clinic(data: _followUps()));

    expect(find.text('Follow-ups'), findsOneWidget);
    expect(find.text('Patients you asked to come back'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Kaushik Paul'), findsOneWidget);
    expect(find.text('23 days overdue'), findsOneWidget);
    expect(find.text('Moumita Roy'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.textContaining('Advised by Dr. Mitra'), findsOneWidget);
  });

  testWidgets('what the server counted but did not name is said, not hidden', (tester) async {
    await _pump(tester, _Clinic(data: _followUps(overdueTotal: 6, dueTotal: 9)));

    expect(find.text('6 patients'), findsOneWidget);
    expect(find.text('4 more not shown'), findsOneWidget, reason: 'six counted, two named');
    expect(find.text('7 more not shown'), findsOneWidget, reason: 'nine counted, two named');
  });

  testWidgets('the window is a real question to the server', (tester) async {
    final clinic = _Clinic(data: _followUps());
    await _pump(tester, clinic);

    expect(clinic.asked, [7]);
    await tester.tap(find.text('This month'));
    await tester.pump();
    await tester.pump();

    expect(clinic.asked, contains(30), reason: 'the list must be re-read, not filtered on the phone');
  });

  testWidgets('an empty window says so rather than showing an empty card', (tester) async {
    await _pump(
      tester,
      _Clinic(
        data: FollowUps.fromJson({
          'days': 7,
          'overdue': [],
          'overdueTotal': 0,
          'due': [],
          'dueTotal': 0,
        }),
      ),
    );

    expect(find.textContaining('Nobody is due back'), findsOneWidget);
    expect(find.text('Overdue'), findsNothing);
  });

  testWidgets('a failed read offers to try again instead of showing nothing', (tester) async {
    await _pump(tester, _Clinic());

    expect(find.textContaining('did not load'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
