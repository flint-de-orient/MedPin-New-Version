import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/clinician_models.dart';
import 'package:medpin/features/clinician/domain/patient_summary.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_patient_profile_screen.dart';
import 'package:medpin/features/doctor_home/presentation/widgets/profile_tabs.dart';
import 'package:medpin/features/medications/domain/medication.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// The doctor's patient record, on the new design.
///
/// Four tabs over one patient. What is worth testing is not that the cards
/// appear but that each one is true: a risk band nobody computed is not shown,
/// an abnormal value is named with the range it broke, a medicine nothing has
/// been due for says "not tracked" rather than 0%, and advice the server does
/// not hold is not invented under a heading.

PatientSummary _patient({
  Map<String, dynamic>? extra,
  List<Map<String, dynamic>> labs = const [],
}) => PatientSummary.fromJson({
  'patient': {
    'id': 'p1',
    'name': 'Priya Sharma',
    'phone': '+919876543210',
    'gender': 'female',
    'age': 29,
  },
  'details': {'comorbidities': ['Type 2 diabetes'], 'allergies': ['Sulfa drugs']},
  'profile': <String, dynamic>{},
  'labResults': labs,
  ...?extra,
});

Map<String, dynamic> _lab({
  required String name,
  required List<Map<String, dynamic>> analytes,
  String at = '2026-07-18T06:00:00.000Z',
}) => {
  'id': name,
  'testName': name,
  'note': '',
  'createdAt': at,
  'analytes': analytes,
};

class _Clinic implements ClinicianRepository {
  _Clinic({required this.patient, this.prescriptions = const [], this.medicines = const []});

  PatientSummary patient;
  List<PrescriptionSummary> prescriptions;
  List<Medication> medicines;

  @override
  dynamic noSuchMethod(Invocation invocation) => switch (invocation.memberName) {
    #patientSummary => Future<PatientSummary>.value(patient),
    #patientPrescriptions => Future<List<PrescriptionSummary>>.value(prescriptions),
    #patientMedications => Future<List<Medication>>.value(medicines),
    _ => super.noSuchMethod(invocation),
  };
}

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

Future<void> _pump(WidgetTester tester, _Clinic clinic) async {
  // Wider than the phone so all four tab labels are on screen at once: under
  // flutter_test's square stand-in font they run much wider than in Figtree.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(_NoSession()),
        apiClientProvider.overrideWithValue(ApiClient(secureStore: _NoSession())),
        imageAuthHeaderProvider.overrideWith((ref) async => {}),
        clinicianRepositoryProvider.overrideWithValue(clinic),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DoctorPatientProfileScreen(patientId: 'p1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('the line under the name', () {
    test('says only what is known', () {
      expect(lineUnder(_patient()), '29 yrs · Female · +919876543210');
    });
  });

  group('the chips', () {
    test('a risk band nobody worked out is not a judgement, so it is not shown', () {
      final stored = _patient(extra: {'profile': {'riskBand': 'high'}});
      expect(chipsFor(stored).map((c) => c.text), isNot(contains('High risk')));
    });

    test('a computed band leads, then the diagnoses, then the allergies', () {
      final p = _patient(
        extra: {
          'profile': {
            'riskBand': 'high',
            'lastRiskComputedAt': '2026-10-01T06:00:00.000Z',
            'comorbidities': ['Type 2 diabetes'],
            'allergies': ['Sulfa drugs'],
          },
        },
      );
      expect(
        chipsFor(p).map((c) => c.text),
        ['High risk', 'Type 2 diabetes', 'Allergy: Sulfa drugs'],
      );
    });
  });

  group('what the labs say', () {
    final labs = [
      _lab(
        name: 'Lipid profile',
        analytes: [
          {'code': 'ldl', 'label': 'LDL cholesterol', 'value': 162, 'unit': 'mg/dL', 'refHigh': 100, 'flag': 'high'},
          {'code': 'hdl', 'label': 'HDL', 'value': 48, 'unit': 'mg/dL', 'refLow': 40, 'flag': 'normal'},
        ],
      ),
      _lab(
        name: 'Diabetes panel',
        analytes: [
          {'code': 'hba1c', 'label': 'HbA1c', 'value': 7.2, 'unit': '%', 'refHigh': 7, 'flag': 'critical'},
        ],
      ),
    ];

    test('only the values outside their range, worst first', () {
      final found = abnormalFindings([
        for (final l in labs) LabReport.fromJson(l),
      ]);
      expect(found.map((f) => f.analyte.label), ['HbA1c', 'LDL cholesterol']);
    });

    test('each one carries the range it broke and the report it came off', () {
      final found = abnormalFindings([LabReport.fromJson(labs.first)]);
      expect(refLine(found.single), 'Ref <100 · Lipid profile · 18 Jul 2026');
      expect(valueOf(found.single.analyte), '162 mg/dL');
      expect(flagWord(found.single.analyte.flag), 'High');
    });

    test('a report with no values read off it is not called normal', () {
      final unread = LabReport.fromJson(_lab(name: 'Scan', analytes: []));
      expect(hasAnalytes(unread), isFalse);
      expect(hasAbnormal(unread), isFalse);
    });
  });

  group('the treatment plan', () {
    test('a medicine nothing has been due for is not 0%', () {
      const perMed = [
        MedAdherence(name: 'Metformin', taken: 0, expected: 0, percentage: 0),
        MedAdherence(name: 'Glimepiride', taken: 8, expected: 10, percentage: 80),
      ];
      expect(adherenceOf('Metformin', perMed), isNull);
      expect(adherenceOf('Glimepiride', perMed), 80);
      expect(adherenceOf('Atorvastatin', perMed), isNull);
    });

    test('advice is only what the plan holds, under its own name', () {
      final plan = PrescriptionSummary(
        id: 'r1',
        generalAdvice: 'Walk 30 minutes daily.',
        labTestsAdvised: const ['HbA1c', 'Lipid profile'],
      );
      expect(adviceOf(plan).map((a) => a.label), ['Advice', 'Before the next visit']);
      expect(adviceOf(plan).last.text, 'HbA1c, Lipid profile');
      expect(adviceOf(PrescriptionSummary(id: 'r2')), isEmpty);
    });

    test('the meta line counts what the prescription actually carries', () {
      final r = PrescriptionSummary(
        id: 'r1',
        itemCount: 3,
        labTestsAdvised: const ['HbA1c'],
        followUpOn: DateTime(2026, 10, 29),
      );
      expect(metaLine(r), '3 medicines · 1 test · Follow-up 29 Oct');
    });
  });

  testWidgets('the record opens on the summary, with the patient in the header', (tester) async {
    await _pump(
      tester,
      _Clinic(
        patient: _patient(
          extra: {
            'aiContext': 'Type 2 diabetes since Jun 2025. Sugar control has drifted.',
            'latestVitals': {'systolic': 128, 'diastolic': 82, 'pulse': 78},
          },
          labs: [
            _lab(
              name: 'Diabetes panel',
              analytes: [
                {'code': 'hba1c', 'label': 'HbA1c', 'value': 7.2, 'unit': '%', 'refHigh': 7, 'flag': 'high'},
              ],
            ),
          ],
        ),
      ),
    );

    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('29 yrs · Female · +919876543210'), findsOneWidget);
    expect(find.text('Type 2 diabetes'), findsOneWidget);
    expect(find.text('Allergy: Sulfa drugs'), findsOneWidget);

    expect(find.text('AI SUMMARY'), findsOneWidget);
    expect(find.textContaining('Check the source before acting'), findsOneWidget);
    expect(find.text('Abnormal findings'), findsOneWidget);
    expect(find.text('HbA1c'), findsOneWidget);
    expect(find.text('7.2 %'), findsOneWidget, reason: 'the value with its unit');
    expect(find.text('Blood pressure'), findsOneWidget);
    expect(find.textContaining('128/82'), findsOneWidget);

    expect(find.text('Start consultation'), findsOneWidget);
  });

  testWidgets('each tab is its own answer, and an empty one says so', (tester) async {
    await _pump(tester, _Clinic(patient: _patient()));

    await tester.tap(find.text('Prescriptions'));
    await tester.pumpAndSettle();
    expect(find.text('All · 0'), findsOneWidget);
    expect(find.text('Nothing here yet.'), findsOneWidget);

    await tester.tap(find.text('Test results'));
    await tester.pumpAndSettle();
    expect(find.text('No test reports on this record yet.'), findsOneWidget);

    await tester.tap(find.text('Treatment plan'));
    await tester.pumpAndSettle();
    expect(find.text('No doses have been due yet.'), findsOneWidget);
    expect(find.text('Nothing is prescribed at the moment.'), findsOneWidget);
  });
}
