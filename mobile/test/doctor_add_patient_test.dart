import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/core/network/api_exception.dart';
import 'package:medpin/features/auth/data/auth_repository.dart';
import 'package:medpin/features/auth/presentation/auth_controller.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/patient_registration.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_add_patient_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// Adding a patient, on the new design.
///
/// The form is the thing that has to keep working: the same fields the desk's
/// own copy sends, the same refusal to send a half-filled one, and a vitals
/// section that does not drop what was typed into it when it folds away.

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

/// A number that already has a MedPin account, as the server answers it.
class _ExistingNumberAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #requestOtp) {
      return Future<OtpSent>.error(
        const ApiException(
          code: 'CONFLICT',
          message: 'An account with this phone already exists',
          statusCode: 409,
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class _Registrations implements ClinicianRepository {
  final sent = <Map<Symbol, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #createPatient) {
      sent.add(Map<Symbol, dynamic>.from(invocation.namedArguments));
      return Future<PatientRegistration>.value(
        const PatientRegistration(
          id: '',
          name: 'Farhana Islam',
          existing: false,
          consentRequired: false,
          enrollmentId: null,
          message: 'ok',
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

Future<void> _pump(WidgetTester tester, _Registrations clinic, {AuthRepository? auth}) async {
  tester.view.physicalSize = const Size(720, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(_NoSession()),
        apiClientProvider.overrideWithValue(ApiClient(secureStore: _NoSession())),
        clinicianRepositoryProvider.overrideWithValue(clinic),
        if (auth != null) authRepositoryProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DoctorAddPatientScreen(),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _fillRequired(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('f-name')), 'Farhana Islam');
  await tester.enterText(find.byKey(const Key('f-age')), '34');
  await tester.enterText(find.byKey(const Key('f-phone')), '9830122457');
  await tester.enterText(find.byKey(const Key('f-address')), '14/2 Beliaghata Main Road');
  await tester.tap(find.text('Female'));
  await tester.pump();
}

Future<void> _tapAdd(WidgetTester tester) async {
  // The button is below the fold once a section is unfolded, and a ListView
  // does not build what it is not showing.
  await tester.scrollUntilVisible(
    find.byKey(const Key('f-submit')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byKey(const Key('f-submit')));
  await tester.pump();
}

void main() {
  testWidgets('the form is the artboard’s three cards, required first', (tester) async {
    await _pump(tester, _Registrations());

    expect(find.text('Add patient'), findsOneWidget, reason: 'the bar');
    expect(
      find.text('Add and start consultation'),
      findsOneWidget,
      reason: 'the button is named for what happens next',
    );
    expect(find.text('Patient details'), findsOneWidget);
    expect(find.text('Required to add the patient'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Age'), findsOneWidget);
    expect(find.text('Gender'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Vitals'), findsOneWidget);
    expect(find.text('Complaints'), findsOneWidget);
    expect(find.text('Optional · what brings them in today'), findsOneWidget);
    // Folded away until they are wanted.
    expect(find.text('BP systolic'), findsNothing);
  });

  testWidgets('a half-filled form is not sent, and says which half', (tester) async {
    final clinic = _Registrations();
    await _pump(tester, clinic);

    await tester.enterText(find.byKey(const Key('f-name')), 'F');
    await _tapAdd(tester);

    expect(clinic.sent, isEmpty, reason: 'it went to the server anyway');
    expect(find.text('Enter the patient’s name'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget, reason: 'the age');
    expect(find.text('Choose one'), findsOneWidget, reason: 'the gender has no field of its own');
    expect(find.text('Enter a valid 10-digit number'), findsOneWidget);
    expect(find.text('Enter the address'), findsOneWidget);
  });

  testWidgets('what was typed is what is sent, vitals included once folded away', (tester) async {
    final clinic = _Registrations();
    await _pump(tester, clinic);

    await _fillRequired(tester);

    await tester.tap(find.text('Vitals'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('f-bp-systolic')), '128');
    await tester.enterText(find.byKey(const Key('f-bp-diastolic')), '84');
    await tester.enterText(find.byKey(const Key('f-fasting-sugar')), '112');
    await tester.pump();

    // Folded away again: hiding a field must never drop what is in it.
    await tester.ensureVisible(find.text('Vitals'));
    await tester.pump();
    await tester.tap(find.text('Vitals'));
    await tester.pump();
    expect(
      find.byKey(const Key('f-bp-systolic')),
      findsNothing,
      reason: 'the section did not actually fold',
    );
    expect(
      find.byKey(const Key('f-bp-systolic'), skipOffstage: false),
      findsOneWidget,
      reason: 'the fold keeps its fields mounted, so what was typed is still sent',
    );

    await _tapAdd(tester);
    // The unverified number is confirmed before anything is sent.
    expect(find.text('Add without verifying?'), findsOneWidget);
    await tester.tap(find.text('Add anyway'));
    await tester.pump();
    await tester.pump();

    expect(clinic.sent, hasLength(1));
    final sent = clinic.sent.single;
    expect(sent[const Symbol('name')], 'Farhana Islam');
    expect(sent[const Symbol('age')], 34);
    expect(sent[const Symbol('gender')], 'female');
    expect(sent[const Symbol('phone')], '+919830122457');
    expect(sent[const Symbol('address')], '14/2 Beliaghata Main Road');
    expect(sent[const Symbol('systolic')], 128);
    expect(sent[const Symbol('diastolic')], 84);
    expect(sent[const Symbol('glucoseMgDl')], 112);
    expect(sent[const Symbol('phoneToken')], isNull, reason: 'it was never verified');
  });

  testWidgets('a number that already has an account is told, not refused', (tester) async {
    final clinic = _Registrations();
    await _pump(tester, clinic, auth: _ExistingNumberAuth());

    await _fillRequired(tester);
    await tester.tap(find.text('Verify'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('already has a MedPin account'), findsOneWidget);

    await _tapAdd(tester);
    expect(
      find.text('Add without verifying?'),
      findsNothing,
      reason: 'they can already sign in; the code confirms the clinic, not the number',
    );
    expect(clinic.sent, hasLength(1));
  });
}
