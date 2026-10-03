import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/patient_summary.dart';
import 'package:medpin/features/doctor_home/domain/doctor_ai.dart';
import 'package:medpin/features/doctor_home/presentation/ai/doctor_ai_chat_screen.dart';
import 'package:medpin/features/doctor_home/presentation/ai/doctor_ai_composer.dart';
import 'package:medpin/features/doctor_home/presentation/ai/doctor_ai_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// The doctor's assistant.
///
/// There is no assistant service for clinicians on the server. The one thing
/// this build answers — a patient, assembled from their own record — must be
/// real and must say where every line came from; everything else must say it
/// is not built rather than look as though it worked.

PatientSummary _summary() => PatientSummary.fromJson({
  'patient': {
    'id': 'p1',
    'name': 'Priya Sharma',
    'phone': '+919830000011',
    'age': 29,
    'gender': 'female',
  },
  'profile': {'diabetesType': 'Type 2 diabetes'},
  'healthScore': {'score': 74, 'band': 'Fair'},
  'adherence': {
    'taken': 47,
    'expected': 58,
    'percentage': 81,
    'perMedication': [
      {'name': 'Metformin 500 mg', 'taken': 39, 'expected': 50, 'percentage': 78},
      {'name': 'Vitamin D3', 'taken': 8, 'expected': 8, 'percentage': 100},
    ],
  },
  'labResults': [
    {
      'id': 'l1',
      'testName': 'Lipid profile',
      'createdAt': '2026-03-12T00:00:00.000Z',
      'analytes': [
        {'code': 'ldl', 'label': 'LDL cholesterol', 'value': 162, 'unit': 'mg/dL', 'flag': 'high'},
        {'code': 'hdl', 'label': 'HDL cholesterol', 'value': 48, 'unit': 'mg/dL', 'flag': 'normal'},
      ],
    },
  ],
});

class _Clinic implements ClinicianRepository {
  int summaries = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #patientSummary) {
      summaries += 1;
      return Future<PatientSummary>.value(_summary());
    }
    return super.noSuchMethod(invocation);
  }
}

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

ProviderContainer _container(_Clinic clinic) {
  final container = ProviderContainer(
    overrides: [
      secureStoreProvider.overrideWithValue(_NoSession()),
      clinicianRepositoryProvider.overrideWithValue(clinic),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _app(Widget child, _Clinic clinic) => ProviderScope(
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
    home: child,
  ),
);

void main() {
  group('which questions this build can answer', () {
    test('a summary is recognised however a doctor phrases it', () {
      for (final asked in [
        'Summarise Priya Sharma',
        'summary of this patient',
        'Tell me about her',
        'catch me up on Priya',
        'What’s going on with Rahul?',
      ]) {
        expect(asksForASummary(asked), isTrue, reason: asked);
      }
      for (final asked in [
        'Who is next in today’s queue?',
        'Which prescriptions run out this week?',
        'Draft a prescription for metformin',
      ]) {
        expect(asksForASummary(asked), isFalse, reason: asked);
      }
    });

    test('a summary with a patient chosen reads that patient’s record', () async {
      final clinic = _Clinic();
      final container = _container(clinic);
      final ai = container.read(doctorAiProvider.notifier);

      ai.about(id: 'p1', name: 'Priya Sharma');
      await ai.ask('Summarise Priya Sharma');

      final answer = container.read(doctorAiProvider).turns.single.answer;
      expect(answer, isA<PatientAnswer>());
      expect(clinic.summaries, 1);
      expect((answer! as PatientAnswer).summary.name, 'Priya Sharma');
    });

    test('a summary with nobody chosen asks for a patient, and reads no record', () async {
      final clinic = _Clinic();
      final container = _container(clinic);

      await container.read(doctorAiProvider.notifier).ask('Summarise this patient');

      final answer = container.read(doctorAiProvider).turns.single.answer;
      expect(answer, isA<UnansweredAnswer>());
      expect((answer! as UnansweredAnswer).needsPatient, isTrue);
      expect(clinic.summaries, 0, reason: 'nothing should be fetched without a patient');
    });

    test('anything else says it is not built, rather than being answered by this app', () async {
      final clinic = _Clinic();
      final container = _container(clinic);
      final ai = container.read(doctorAiProvider.notifier);

      ai.about(id: 'p1', name: 'Priya Sharma');
      await ai.ask('Which prescriptions run out this week?');

      final answer = container.read(doctorAiProvider).turns.single.answer;
      expect(answer, isA<UnansweredAnswer>());
      expect((answer! as UnansweredAnswer).needsPatient, isFalse);
      expect(clinic.summaries, 0);
    });
  });

  group('what the answer shows', () {
    test('only results outside their range, and where each came from', () {
      final answer = PatientAnswer(summary: _summary(), at: DateTime.now());

      expect(answer.abnormal.map((p) => p.$2.label), ['LDL cholesterol']);
      expect(answer.medicines.map((m) => m.name), ['Metformin 500 mg', 'Vitamin D3']);
      expect(answer.provenance, contains('1 lab report'));
      expect(answer.provenance, contains('2 medicines on file'));
      expect(answer.provenance, contains('not written by a model'));
    });
  });

  testWidgets('the front door offers only what it can do, and says so about the rest', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const DoctorAiScreen(), _Clinic()));
    await tester.pump();

    expect(find.text('TRY ASKING'), findsOneWidget);
    expect(find.textContaining('Summarise a patient'), findsOneWidget);
    expect(find.textContaining('not a diagnosis'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('Which prescriptions run out'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.textContaining('Which prescriptions run out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Not built yet'), findsOneWidget);
  });

  testWidgets('the conversation shows the patient card with its provenance', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final clinic = _Clinic();
    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(_NoSession()),
        apiClientProvider.overrideWithValue(ApiClient(secureStore: _NoSession())),
        imageAuthHeaderProvider.overrideWith((ref) async => {}),
        clinicianRepositoryProvider.overrideWithValue(clinic),
      ],
    );
    addTearDown(container.dispose);

    container.read(doctorAiProvider.notifier).about(id: 'p1', name: 'Priya Sharma');
    await container.read(doctorAiProvider.notifier).ask('Summarise Priya Sharma');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DoctorAiChatScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Summarise Priya Sharma'), findsOneWidget);
    expect(find.text('MedPin AI'), findsOneWidget);
    expect(find.text('Priya Sharma, 29 F'), findsOneWidget);
    expect(find.text('74'), findsOneWidget, reason: 'the health score');
    expect(find.text('LDL cholesterol'), findsOneWidget);
    expect(find.text('HDL cholesterol'), findsNothing, reason: 'in range — not an abnormal result');
    expect(find.textContaining('78% taken'), findsOneWidget);
    expect(find.textContaining('Assembled from the record'), findsOneWidget);
  });

  test('the chip’s initials skip a title', () {
    expect(initialsOf('Priya Sharma'), 'PS');
    expect(initialsOf('Dr. Meera Sen'), 'MS');
    expect(initialsOf('Rahul'), 'R');
  });
}
