import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/doctor_home/domain/consultation_report.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_reports_screen.dart';
import 'package:medpin/features/doctor_home/presentation/widgets/report_parts.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// The consultation MIS.
///
/// Every figure on this tab is a count the doctor could check against the
/// diary, so what is worth testing is the arithmetic around them: what a change
/// is called, what is said when there is nothing to compare against, and the
/// two things this system cannot report at all.

ConsultationSummary _summary({
  int consultations = 286,
  int previousConsultations = 255,
  int prescriptions = 271,
  int missed = 21,
  int? averageMinutes,
  int averageFrom = 0,
  List<Map<String, dynamic>> perDay = const [],
  List<Map<String, dynamic>> byLocation = const [],
  List<Map<String, dynamic>> byDiagnosis = const [],
}) => ConsultationSummary.fromJson({
  'from': '2026-09-01',
  'to': '2026-09-30',
  'previous': {'from': '2026-08-02', 'to': '2026-08-31'},
  'kpis': {
    'consultations': {'value': consultations, 'previous': previousConsultations},
    'newPatients': {'value': 64, 'previous': 55},
    'missed': {'value': missed, 'previous': 18},
    'prescriptions': {'value': prescriptions, 'previous': 240},
    'averageMinutes': {'value': averageMinutes, 'from': averageFrom},
  },
  'perDay': perDay,
  'byLocation': byLocation,
  'byDiagnosis': byDiagnosis,
});

class _Clinic implements ClinicianRepository {
  _Clinic({required this.summary});

  ConsultationSummary summary;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.memberName == #consultationSummary
      ? Future<ConsultationSummary>.value(summary)
      : super.noSuchMethod(invocation);
}

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

Future<void> _pump(WidgetTester tester, _Clinic clinic) async {
  tester.view.physicalSize = const Size(900, 2600);
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
        home: const DoctorReportsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('what a change is called', () {
    test('a percentage once there is enough of it to mean one', () {
      expect(
        deltaLine(const ReportCount(value: 286, previous: 255), 'before'),
        '+12% vs before',
      );
      expect(
        deltaLine(const ReportCount(value: 200, previous: 255), 'before'),
        '−22% vs before',
      );
    });

    test('a count when the window before was small', () {
      // 1 became 3: "+200%" is true and useless.
      expect(deltaLine(const ReportCount(value: 3, previous: 1), 'before'), '+2 vs before');
    });

    test('nothing to compare against says that, rather than a percentage', () {
      expect(
        deltaLine(const ReportCount(value: 12, previous: 0), 'before'),
        'Nothing to compare',
      );
      expect(
        deltaLine(const ReportCount(value: 0, previous: 0), 'before'),
        'None before either',
      );
    });

    test('a figure that did not move is not dressed up as a change', () {
      expect(
        deltaLine(const ReportCount(value: 50, previous: 50), 'before'),
        'Same as before',
      );
      expect(toneOf(const ReportCount(value: 50, previous: 50), moreIsBetter: true),
          DeltaTone.flat);
    });

    test('more is better for consultations and worse for missed ones', () {
      expect(
        toneOf(const ReportCount(value: 10, previous: 5), moreIsBetter: true),
        DeltaTone.good,
      );
      expect(
        toneOf(const ReportCount(value: 10, previous: 5), moreIsBetter: false),
        DeltaTone.bad,
      );
    });
  });

  group('shares of nothing', () {
    test('no consultations means no prescribing share, not 0%', () {
      expect(_summary(consultations: 0, prescriptions: 0).prescribedShare, isNull);
      expect(_summary().prescribedShare, 95);
    });

    test('nobody due back means no compliance figure', () {
      const none = FollowUpCompliance(items: [], kept: 0, due: 0);
      expect(none.percent, isNull);
      expect(const FollowUpCompliance(items: [], kept: 3, due: 4).percent, 75);
    });
  });

  group('the window', () {
    test('counts back from today, not from the start of the week', () {
      final week = windowFor(ReportRange.week);
      expect(week.to.difference(week.from).inDays, 6);
      final month = windowFor(ReportRange.month);
      expect(month.to.difference(month.from).inDays, 29);
      final today = windowFor(ReportRange.today);
      expect(today.from, today.to);
    });
  });

  testWidgets('the tab reads as counted figures with the window named', (tester) async {
    await _pump(
      tester,
      _Clinic(
        summary: _summary(
          perDay: [
            {'date': '2026-09-01', 'count': 0},
            {'date': '2026-09-02', 'count': 12},
          ],
          byLocation: [
            {'clinicId': 'a', 'name': 'City Care · Salt Lake', 'count': 168},
          ],
          byDiagnosis: [
            {'name': 'Type 2 diabetes', 'count': 92},
          ],
        ),
      ),
    );

    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Your consultation MIS'), findsOneWidget);
    expect(find.textContaining('compared with'), findsOneWidget);
    expect(find.text('286'), findsOneWidget);
    expect(find.text('+12% vs before'), findsOneWidget);
    expect(find.text('95% of consultations'), findsOneWidget);
    expect(find.text('City Care · Salt Lake'), findsOneWidget);
    expect(find.text('Type 2 diabetes'), findsOneWidget);

    // The two the app does not record, said once rather than shown as zero.
    // It sits at the foot of the tab, below what a phone shows at once.
    await tester.scrollUntilVisible(
      find.textContaining('Fees and referrals are not on this report'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Fees and referrals are not on this report'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
  });

  testWidgets('an untimed month shows no average, and says why', (tester) async {
    await _pump(tester, _Clinic(summary: _summary()));

    expect(find.text('—'), findsOneWidget);
    expect(find.text('Not timed yet'), findsOneWidget);
  });

  testWidgets('a timed month says how many it was worked out from', (tester) async {
    await _pump(tester, _Clinic(summary: _summary(averageMinutes: 11, averageFrom: 180)));

    expect(find.text('11 min'), findsOneWidget);
    expect(find.text('From 180 timed'), findsOneWidget);
  });

  testWidgets('a window with nobody in it says so instead of a wall of noughts', (tester) async {
    await _pump(
      tester,
      _Clinic(
        summary: _summary(
          consultations: 0,
          previousConsultations: 0,
          prescriptions: 0,
          missed: 0,
        ),
      ),
    );

    expect(find.text('Nobody was seen in this window.'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
