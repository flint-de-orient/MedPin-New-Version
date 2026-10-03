import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/clinician_models.dart';
import 'package:medpin/features/clinician/domain/patient_summary.dart';
import 'package:medpin/features/doctor_home/domain/consult_draft.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_consult_screen.dart';
import 'package:medpin/features/medications/domain/med_shorthand.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// The consultation, on one page.
///
/// What is worth testing is not the layout but what leaves the screen: the
/// shorthand a dose is sent in, the allergy that must be said out loud beside
/// the medicine, the confirmation before a prescription with nothing on it, and
/// the draft — which has to come back after an interruption and be gone the
/// moment it became a prescription.

PatientSummary _patient({List<String> allergies = const []}) => PatientSummary.fromJson({
  'patient': {'id': 'p1', 'name': 'Salman Ahmed', 'phone': '+919749681391', 'age': 45},
  'details': {'allergies': allergies},
  'profile': <String, dynamic>{},
});

class _Clinic implements ClinicianRepository {
  _Clinic({PatientSummary? patient}) : patient = patient ?? _patient();

  PatientSummary patient;
  final prescribed = <Map<Symbol, dynamic>>[];
  final vitals = <Map<Symbol, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #patientSummary:
        return Future<PatientSummary>.value(patient);
      case #patientPrescriptions:
        return Future<List<PrescriptionSummary>>.value(const []);
      case #patientMedications:
        return Future<List<dynamic>>.value(const []);
      case #createPrescription:
        prescribed.add(Map<Symbol, dynamic>.from(invocation.namedArguments));
        return Future<void>.value();
      case #recordConsultVitals:
        vitals.add(Map<Symbol, dynamic>.from(invocation.namedArguments));
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Future<void> _pump(WidgetTester tester, _Clinic clinic, SharedPreferences prefs) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureStoreProvider.overrideWithValue(_NoSession()),
        apiClientProvider.overrideWithValue(ApiClient(secureStore: _NoSession())),
        imageAuthHeaderProvider.overrideWith((ref) async => {}),
        clinicianRepositoryProvider.overrideWithValue(clinic),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DoctorConsultScreen(patientId: 'p1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('a line of the prescription', () {
    test('goes to the server in the shorthand the pad is written in', () {
      const line = MedLine(
        name: 'Metformin',
        strength: '500 mg',
        frequency: DoseFrequency.bd,
        relation: MealRelation.after,
        durationDays: 30,
      );
      expect(line.toItem(), {
        'name': 'Metformin',
        'strength': '500 mg',
        'frequency': 'BD',
        'relationToMeal': 'after_meal',
        'route': 'oral',
        'durationDays': 30,
      });
    });

    test('reads back in words, because the codes are for the pad', () {
      const line = MedLine(name: 'Metformin', frequency: DoseFrequency.bd);
      expect(line.doseLine, 'Twice a day · after food');
      expect(
        const MedLine(name: 'Paracetamol', frequency: DoseFrequency.prn).doseLine,
        'As needed',
        reason: 'as-needed takes no meal relation',
      );
    });
  });

  group('the allergy beside the medicine', () {
    test('matches the word the record holds, both ways round', () {
      expect(cautionFor('Sulfasalazine', ['Sulfa drugs']), contains('Sulfa drugs'));
      expect(cautionFor('Amoxicillin', ['Penicillin (amoxicillin)']), isNotNull);
    });

    test('says nothing it cannot stand behind', () {
      // A sulfonylurea is a sulfa derivative. Nothing here knows that, and a
      // warning that looks like it does is worse than none.
      expect(cautionFor('Glimepiride', ['Sulfa drugs']), isNull);
      expect(cautionFor('Metformin', ['Sulfa drugs']), isNull);
      expect(cautionFor('Metformin', const []), isNull);
    });
  });

  group('the advice', () {
    test('keeps the doctor’s own words apart from the catalogue’s', () {
      const draft = ConsultDraft(
        advice: ['Walk 30 minutes daily'],
        ownAdvice: 'Come back sooner if the chest tightness returns.',
      );
      expect(
        draft.adviceText,
        'Walk 30 minutes daily\nCome back sooner if the chest tightness returns.',
      );
    });
  });

  test('validity counts from today, or is not claimed at all', () {
    final now = DateTime(2026, 10, 3);
    expect(const ConsultDraft().validUntil(now), isNull);
    expect(const ConsultDraft(validDays: 30).validUntil(now), DateTime(2026, 11, 2));
  });

  testWidgets('the draft comes back after an interruption', (tester) async {
    final prefs = await _prefs();
    final clinic = _Clinic();

    await _pump(tester, clinic, prefs);
    await tester.enterText(find.byKey(const Key('c-complaint')), 'Chest tightness since morning');
    await tester.pump(const Duration(seconds: 1));

    // The consult is closed and opened again — another patient, a phone call,
    // the app killed by Android.
    await _pump(tester, clinic, prefs);
    expect(find.text('Chest tightness since morning'), findsOneWidget);
    expect(find.textContaining('draft kept on this phone'), findsOneWidget);
  });

  testWidgets('a prescription with no medicines is confirmed, not refused', (tester) async {
    final prefs = await _prefs();
    final clinic = _Clinic();
    await _pump(tester, clinic, prefs);

    await tester.enterText(find.byKey(const Key('c-complaint')), 'Review');
    await tester.pump();
    await tester.tap(find.byKey(const Key('c-issue')));
    await tester.pumpAndSettle();

    expect(find.text('No medicines on this prescription'), findsOneWidget);
    expect(clinic.prescribed, isEmpty, reason: 'nothing is sent until it is confirmed');

    await tester.tap(find.text('Issue without medicines'));
    await tester.pumpAndSettle();

    expect(clinic.prescribed, hasLength(1));
    expect(clinic.prescribed.single[const Symbol('items')], isEmpty);
    // The complaint belongs to the record as well as the slip.
    expect(clinic.vitals.single[const Symbol('complaint')], 'Review');
  });

  testWidgets('what was issued is cleared from the draft', (tester) async {
    final prefs = await _prefs();
    final clinic = _Clinic();
    await _pump(tester, clinic, prefs);

    await tester.enterText(find.byKey(const Key('c-complaint')), 'Follow-up');
    await tester.pump(const Duration(seconds: 1));
    expect(ConsultDrafts(prefs).read('p1'), isNotNull);

    await tester.tap(find.byKey(const Key('c-issue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Issue without medicines'));
    await tester.pumpAndSettle();

    expect(
      ConsultDrafts(prefs).read('p1'),
      isNull,
      reason: 'a draft that outlives what it became is the one issued twice',
    );
  });
}
