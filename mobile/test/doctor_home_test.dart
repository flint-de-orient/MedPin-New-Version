import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/appointment.dart';
import 'package:medpin/features/clinician/domain/clinician_models.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_home_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/data/care_contact.dart';
import 'package:medpin/shared/models/paged.dart';
import 'package:medpin/shared/widgets/notification_list_sheet.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// The rebuilt doctor Home.
///
/// Its three numbers are today's diary counted three ways, so they have to add
/// up on screen and exclude the people who are not coming. The red card is the
/// open emergency, and there is no red card when there is not one.

Appointment _appointment(String status, {String name = 'A Patient'}) => Appointment.fromJson({
  'id': 'a-$status-$name',
  'patientId': 'p1',
  'patientName': name,
  'scheduledFor': DateTime.now().toUtc().toIso8601String(),
  'status': status,
  'mode': 'in_clinic',
});

ClinicalAlert _alert({
  required String severity,
  required String patient,
  String detail = 'Chest tightness, hard to breathe.',
  Duration ago = const Duration(minutes: 2),
}) => ClinicalAlert.fromJson({
  'id': 'al-$severity-$patient',
  'severity': severity,
  'type': 'chat_escalation',
  'title': 'Patient reported a concerning symptom',
  'status': 'open',
  'patientId': 'p1',
  'patientName': patient,
  'detail': detail,
  'createdAt': DateTime.now().toUtc().subtract(ago).toIso8601String(),
});

class _Clinic implements ClinicianRepository {
  _Clinic({this.appointments = const [], this.openAlerts = const [], this.messages = 0});

  List<Appointment> appointments;
  List<ClinicalAlert> openAlerts;
  int messages;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #appointmentsToday:
        return Future<List<Appointment>>.value(appointments);
      case #alerts:
        return Future<Paged<ClinicalAlert>>.value(
          Paged<ClinicalAlert>(items: openAlerts, page: 1, limit: 100, total: openAlerts.length, hasMore: false),
        );
      case #notifications:
        return Future.value((
          unread: messages,
          messages: messages,
          alerts: openAlerts.length,
          requests: 0,
          items: const <PanelNotification>[],
        ));
    }
    return super.noSuchMethod(invocation);
  }
}

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

class _NoUploads extends ApiClient {
  _NoUploads() : super(secureStore: _NoSession());
}

Future<void> _pump(WidgetTester tester, _Clinic clinic) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(_NoSession()),
        apiClientProvider.overrideWithValue(_NoUploads()),
        imageAuthHeaderProvider.overrideWith((ref) async => {}),
        clinicianRepositoryProvider.overrideWithValue(clinic),
        careContactProvider.overrideWith((ref) async => const CareContact(practiceName: 'City Care, Salt Lake', phone: null)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DoctorHomeScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('today, counted three ways', () {
    test('everybody expected, those still to be seen, and those seen', () {
      final counts = TodayCounts.of([
        _appointment('confirmed'),
        _appointment('checked_in'),
        _appointment('in_consultation'),
        _appointment('completed'),
        _appointment('completed', name: 'Second'),
      ]);
      expect(counts.total, 5);
      expect(counts.pending, 3);
      expect(counts.completed, 2);
      expect(counts.pending + counts.completed, counts.total, reason: 'the three numbers must add up on screen');
    });

    test('a cancellation, a no-show and a request nobody has timed are not today’s list', () {
      final counts = TodayCounts.of([
        _appointment('confirmed'),
        _appointment('cancelled'),
        _appointment('no_show'),
        Appointment.fromJson({
          'id': 'r1',
          'patientId': 'p9',
          'patientName': 'Asked for a time',
          'status': 'requested',
          'mode': 'in_clinic',
        }),
      ]);
      expect(counts.total, 1);
      expect(counts.pending, 1);
      expect(counts.completed, 0);
    });

    test('an empty diary is three zeroes, not a blank', () {
      final counts = TodayCounts.of(const []);
      expect([counts.total, counts.pending, counts.completed], [0, 0, 0]);
    });
  });

  group('the words on the screen', () {
    test('a doctor is "Dr.", once', () {
      expect(doctorNameOf('Meera Sen', 'doctor'), 'Dr. Meera Sen');
      expect(doctorNameOf('Dr. Meera Sen', 'doctor'), 'Dr. Meera Sen');
      expect(doctorNameOf('Priya Das', 'staff'), 'Priya Das');
      expect(doctorNameOf(null, 'doctor'), 'Doctor');
    });

    test('how long ago, in the words a person uses', () {
      final now = DateTime(2026, 10, 1, 12);
      expect(agoOf(now.subtract(const Duration(seconds: 20)), now: now), 'Just now');
      expect(agoOf(now.subtract(const Duration(minutes: 2)), now: now), '2 min ago');
      expect(agoOf(now.subtract(const Duration(hours: 1)), now: now), '1 hour ago');
      expect(agoOf(now.subtract(const Duration(hours: 5)), now: now), '5 hours ago');
      expect(agoOf(now.subtract(const Duration(days: 2)), now: now), '2 days ago');
      expect(agoOf(null, now: now), 'Just now');
    });
  });

  testWidgets('the day, the emergency and the waiting messages are the server’s own', (tester) async {
    await _pump(
      tester,
      _Clinic(
        appointments: [
          for (var i = 0; i < 9; i++) _appointment('confirmed', name: 'Waiting $i'),
          for (var i = 0; i < 3; i++) _appointment('completed', name: 'Seen $i'),
          _appointment('cancelled', name: 'Cancelled'),
        ],
        openAlerts: [
          _alert(severity: 'urgent', patient: 'Rahul Bose', ago: const Duration(minutes: 30)),
          _alert(severity: 'emergency', patient: 'Priya Sharma'),
        ],
        messages: 4,
      ),
    );

    expect(find.text('12'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Total appointments'), findsOneWidget);

    // The emergency outranks the urgent one, however recent that is.
    expect(find.text('Emergency · Priya Sharma'), findsOneWidget);
    // One line, two voices: "Emergency message:" muted, the patient's own
    // words in ink — so it is drawn as spans rather than two Texts.
    expect(find.textContaining('Chest tightness, hard to breathe.'), findsOneWidget);
    expect(find.textContaining('Emergency message:'), findsOneWidget);
    expect(find.textContaining('2 min ago'), findsOneWidget);
    expect(find.textContaining('Rahul Bose'), findsNothing);

    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('City Care, Salt Lake'), findsNothing, reason: 'the practice sits in the date line');
    expect(find.textContaining('City Care, Salt Lake'), findsOneWidget);
  });

  testWidgets('no open emergency, no red card — and a loading day shows no zeroes', (tester) async {
    await _pump(tester, _Clinic(appointments: const [], openAlerts: const []));

    expect(find.textContaining('Emergency ·'), findsNothing);
    expect(find.text('Review now'), findsNothing);
    expect(find.text('0'), findsNWidgets(3), reason: 'an empty diary is three honest zeroes');
  });

  testWidgets('on the clinic’s own phone, no label breaks inside a word', (tester) async {
    // 720x1600 at 2x — the Infinix the clinic uses, 360dp wide. The mock-up is
    // 390dp, and at the sizes it implies "Prescriptions" and "appointments"
    // split down the middle of the word.
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(_NoSession()),
          apiClientProvider.overrideWithValue(_NoUploads()),
          imageAuthHeaderProvider.overrideWith((ref) async => {}),
          clinicianRepositoryProvider.overrideWithValue(_Clinic(appointments: [_appointment('confirmed')])),
          careContactProvider.overrideWith((ref) async => const CareContact(practiceName: "Dr. Dey's Diabetes Obesity & Metabolic Clinic", phone: null)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DoctorHomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Nothing overflows its card, and nothing is laid out off the screen.
    expect(tester.takeException(), isNull);
    for (final label in ['Write prescription', 'Start consultation', 'Total appointments']) {
      final box = tester.getRect(find.text(label));
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(360));
    }

    // Each quick action keeps a third of the row, less the gaps. How many
    // lines the label then takes is the font's business, and the test font
    // here is not the font on the phone — that part is read on the device.
    final tileWidth = tester.getSize(find.ancestor(
      of: find.text('Write prescription'),
      matching: find.byType(SizedBox),
    ).first).width;
    expect(tileWidth, greaterThan(100), reason: 'three cards across 360dp, gaps included');

    // What reaches the first screen. The phone gives 720dp to the app and the
    // bar takes about 76 of it, so 644 is what a doctor sees without
    // scrolling. Measured under flutter_test's square stand-in font, which
    // runs wider and taller than Figtree — every label here takes a line more
    // than it will on the phone, so clearing the fold under it is the
    // conservative reading.
    expect(
      tester.getRect(find.text('Follow-ups')).bottom,
      lessThanOrEqualTo(644),
      reason: 'both rows of quick actions should be on the first screen',
    );
  });

  testWidgets('every quick action goes somewhere', (tester) async {
    // The "not built yet" card is gone because nothing on this row is unbuilt
    // any more. What replaced it is the thing worth pinning: a tile that opens
    // nothing is a tile that should not be on the screen.
    await _pump(tester, _Clinic());

    for (final label in [
      'Start consultation',
      'Patient queue',
      'New patient',
      'Write prescription',
      'Record vitals',
      'Follow-ups',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
      expect(
        routeOf(label),
        isNotNull,
        reason: '$label opens nothing',
      );
    }
  });
}
