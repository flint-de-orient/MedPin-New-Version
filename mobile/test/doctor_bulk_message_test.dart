import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/caseload_panels.dart';
import 'package:medpin/features/clinician/domain/clinician_models.dart';
import 'package:medpin/features/doctor_home/domain/bulk_message.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_bulk_message_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/models/paged.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// One message to several patients.
///
/// It is a loop over the ordinary reply, so the thing worth testing is what
/// happens when the loop does not finish: every patient it reached, every one
/// it did not, and no claim of a send that never happened.

PatientListItem _patient(String name) => PatientListItem.fromJson({
  'id': name.toLowerCase(),
  'name': name,
  'phone': '+919830000011',
  'unreadCount': 0,
  'riskBand': 'low',
  'riskScore': 1,
});

class _Clinic implements ClinicianRepository {
  _Clinic({this.items = const [], this.refuse = const {}, this.due});

  List<PatientListItem> items;

  /// Patient ids the server will not take a message for.
  Set<String> refuse;

  FollowUps? due;

  final messaged = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #patients:
        return Future<Paged<PatientListItem>>.value(
          Paged<PatientListItem>(
            items: items,
            page: 1,
            limit: 100,
            total: items.length,
            hasMore: false,
          ),
        );
      case #messagePatient:
        final id = invocation.namedArguments[const Symbol('patientId')] as String;
        if (refuse.contains(id)) {
          return Future<void>.error(StateError('the server said no'));
        }
        messaged.add(id);
        return Future<void>.value();
      case #followUps:
        return Future<FollowUps>.value(
          due ??
              const FollowUps(days: 7, overdue: [], overdueTotal: 0, due: [], dueTotal: 0),
        );
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

Future<void> _pump(WidgetTester tester, _Clinic clinic) async {
  tester.view.physicalSize = const Size(720, 1600);
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
        home: const DoctorBulkMessageScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('each patient is written to once, in the order they were chosen', () async {
    final clinic = _Clinic();
    final container = _container(clinic);

    await container.read(bulkMessageProvider.notifier).send(const [
      BulkRecipient(id: 'a', name: 'Priya'),
      BulkRecipient(id: 'b', name: 'Rahul'),
      BulkRecipient(id: 'c', name: 'Amit'),
    ], 'Your follow-up is due.');

    expect(clinic.messaged, ['a', 'b', 'c']);
    final send = container.read(bulkMessageProvider);
    expect(send.sent, 3);
    expect(send.failed, 0);
    expect(send.finished, isTrue);
    expect(sendSummary(send, 3), 'Sent to 3 patients');
  });

  test('one that refuses does not stop the rest, and is named', () async {
    final clinic = _Clinic(refuse: {'b'});
    final container = _container(clinic);

    await container.read(bulkMessageProvider.notifier).send(const [
      BulkRecipient(id: 'a', name: 'Priya'),
      BulkRecipient(id: 'b', name: 'Rahul'),
      BulkRecipient(id: 'c', name: 'Amit'),
    ], 'Your follow-up is due.');

    expect(clinic.messaged, ['a', 'c'], reason: 'the other two still went');
    final send = container.read(bulkMessageProvider);
    expect(send.outcomes['b'], BulkOutcome.failed);
    expect(send.failures['b'], isNotNull, reason: 'the reason is kept, not swallowed');
    expect(sendSummary(send, 3), '2 of 3 sent · 1 did not go');
  });

  test('when nothing reaches anybody it says so, not “2 of 3”', () async {
    final clinic = _Clinic(refuse: {'a', 'b'});
    final container = _container(clinic);

    await container.read(bulkMessageProvider.notifier).send(const [
      BulkRecipient(id: 'a', name: 'Priya'),
      BulkRecipient(id: 'b', name: 'Rahul'),
    ], 'Hello');

    expect(clinic.messaged, isEmpty);
    expect(sendSummary(container.read(bulkMessageProvider), 2), 'None of them went. Nothing was sent.');
  });

  test('an empty message is never sent, however many are chosen', () async {
    final clinic = _Clinic();
    final container = _container(clinic);

    await container
        .read(bulkMessageProvider.notifier)
        .send(const [BulkRecipient(id: 'a', name: 'Priya')], '   ');

    expect(clinic.messaged, isEmpty);
    expect(container.read(bulkMessageProvider).finished, isFalse);
  });

  test('a mis-tap cannot reach the whole roll', () async {
    final clinic = _Clinic();
    final container = _container(clinic);

    await container.read(bulkMessageProvider.notifier).send([
      for (var i = 0; i < 40; i++) BulkRecipient(id: '$i', name: 'Patient $i'),
    ], 'Hello');

    expect(clinic.messaged, hasLength(kBulkLimit));
  });

  testWidgets('nobody is chosen until they are tapped, and the button says so', (tester) async {
    await _pump(tester, _Clinic(items: [_patient('Priya Sharma'), _patient('Rahul Das')]));

    expect(find.text('Choose who it goes to'), findsOneWidget);
    expect(find.text('NOBODY CHOSEN YET'), findsOneWidget);

    await tester.tap(find.text('Priya Sharma'));
    await tester.pump();

    expect(find.text('1 CHOSEN · UP TO $kBulkLimit'), findsOneWidget);
    expect(find.text('Send to 1 patient'), findsOneWidget);
  });

  testWidgets('the follow-up window fills the choice from the server’s own list', (tester) async {
    final clinic = _Clinic(
      items: [_patient('Priya Sharma')],
      due: FollowUps(
        days: 7,
        overdue: [PanelPatient(id: 'x', name: 'Rahul Das', at: DateTime(2026, 10, 1))],
        overdueTotal: 1,
        due: [PanelPatient(id: 'y', name: 'Amit Pal', at: DateTime(2026, 10, 6))],
        dueTotal: 1,
      ),
    );
    await _pump(tester, clinic);

    await tester.tap(find.text('Follow-ups due this week'));
    await tester.pump();
    await tester.pump();

    expect(find.text('2 CHOSEN · UP TO $kBulkLimit'), findsOneWidget);
    expect(find.text('Send to 2 patients'), findsOneWidget);
    // They are not on the loaded roll, so the screen keeps them visible rather
    // than sending to somebody it cannot show.
    expect(find.text('Rahul Das'), findsOneWidget);
    expect(find.text('Amit Pal'), findsOneWidget);
  });

  testWidgets('the message is confirmed before it goes, and it says to how many', (tester) async {
    final clinic = _Clinic(items: [_patient('Priya Sharma')]);
    await _pump(tester, clinic);

    await tester.tap(find.text('Priya Sharma'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Please come fasting on Friday.');
    await tester.pump();

    await tester.tap(find.text('Send to 1 patient'));
    await tester.pumpAndSettle();

    expect(find.text('Send to 1 patient?'), findsOneWidget);
    expect(find.textContaining('They will not see who else it went to'), findsOneWidget);
    expect(clinic.messaged, isEmpty, reason: 'nothing goes before it is confirmed');

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(clinic.messaged, ['priya sharma']);
    expect(find.text('Sent to 1 patient'), findsOneWidget);
  });
}
