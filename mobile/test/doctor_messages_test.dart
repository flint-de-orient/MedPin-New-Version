import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/clinician_models.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_messages_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/models/paged.dart';
import 'package:medpin/shared/providers/core_providers.dart';
import 'package:medpin/shared/widgets/notification_list_sheet.dart';

/// The doctor's Messages tab.
///
/// It is the server's own inbox ordering, so this screen and the Patients tab
/// cannot disagree. An urgent message is lifted out of the list in red, the
/// clinic's own last word is prefixed "You:", and the colleague half — whose
/// table was retired from this server — says so instead of showing a list that
/// reads as silence.

final _now = DateTime(2026, 10, 3, 10);

PatientListItem _chat({
  required String name,
  String? preview,
  String role = 'user',
  String urgency = 'routine',
  int unread = 0,
  DateTime? at,
  String? mediaType,
}) => PatientListItem.fromJson({
  'id': name.toLowerCase().replaceAll(' ', '-'),
  'name': name,
  'phone': '+919830000011',
  'unreadCount': unread,
  'riskBand': 'low',
  'riskScore': 1,
  if (preview != null || mediaType != null)
    'lastMessage': {
      'preview': preview ?? '',
      if (mediaType != null) 'mediaType': mediaType,
      'role': role,
      'at': (at ?? _now).toUtc().toIso8601String(),
      'urgency': urgency,
    },
});

class _Clinic implements ClinicianRepository {
  _Clinic({this.items = const [], this.unreadTotal = 0});

  List<PatientListItem> items;
  int unreadTotal;
  final sorts = <String?>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #patients:
        sorts.add(invocation.namedArguments[const Symbol('sort')] as String?);
        return Future<Paged<PatientListItem>>.value(
          Paged<PatientListItem>(
            items: items,
            page: 1,
            limit: 100,
            total: items.length,
            hasMore: false,
          ),
        );
      case #notifications:
        return Future.value((
          unread: unreadTotal,
          messages: unreadTotal,
          alerts: 0,
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

Future<void> _pump(WidgetTester tester, _Clinic clinic, {double width = 720}) async {
  tester.view.physicalSize = Size(width, 1600);
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
        home: const DoctorMessagesScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('what a row says', () {
    test('the clinic’s own last word is marked, the patient’s is not', () {
      expect(
        previewOf(MessagePreview.fromJson({'preview': 'Please come fasting', 'role': 'clinician'})),
        'You: Please come fasting',
      );
      expect(
        previewOf(MessagePreview.fromJson({'preview': 'My sugar is 212', 'role': 'user'})),
        'My sugar is 212',
      );
    });

    test('a message with no words is named for what it is', () {
      expect(
        previewOf(MessagePreview.fromJson({'preview': '', 'role': 'user', 'mediaType': 'image'})),
        'Photo',
      );
      expect(
        previewOf(MessagePreview.fromJson({'preview': '', 'role': 'user', 'mediaType': 'audio'})),
        'Voice message',
      );
    });

    test('the time reads as today, yesterday, the weekday, then the date', () {
      String at(DateTime t) => atLabel(t, now: _now);
      // Formatted by intl, which separates the hour from AM/PM with a narrow
      // no-break space — compared as it formats, not as it is typed.
      expect(at(_now.subtract(const Duration(hours: 1))), DateFormat.jm().format(_now.subtract(const Duration(hours: 1))));
      expect(at(_now.subtract(const Duration(days: 1))), 'Yesterday');
      expect(at(_now.subtract(const Duration(days: 3))), 'Wed');
      expect(at(_now.subtract(const Duration(days: 20))), '13 Sep');
    });

    test('urgent and emergency are both urgent; routine is not', () {
      expect(isUrgent(_chat(name: 'A', preview: 'x', urgency: 'urgent')), isTrue);
      expect(isUrgent(_chat(name: 'B', preview: 'x', urgency: 'emergency')), isTrue);
      expect(isUrgent(_chat(name: 'C', preview: 'x')), isFalse);
      expect(urgentCount([
        _chat(name: 'A', preview: 'x', urgency: 'urgent'),
        _chat(name: 'C', preview: 'x'),
      ]), 1);
    });
  });

  testWidgets('an urgent conversation is lifted out of the list, in red', (tester) async {
    await _pump(
      tester,
      _Clinic(
        unreadTotal: 4,
        items: [
          _chat(
            name: 'Priya Sharma',
            preview: 'Chest tightness, hard to breathe.',
            urgency: 'urgent',
            unread: 2,
          ),
          _chat(name: 'Amit Pal', preview: 'Please come fasting', role: 'clinician'),
        ],
      ),
    );

    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('4 unread · 1 urgent'), findsOneWidget);
    expect(find.text('URGENT · PATIENT'), findsOneWidget);
    expect(find.text('Chest tightness, hard to breathe.'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'its unread count');
    expect(find.text('You: Please come fasting'), findsOneWidget);
  });

  testWidgets('Unread shows only what is unread', (tester) async {
    final clinic = _Clinic(
      unreadTotal: 1,
      items: [
        _chat(name: 'Priya Sharma', preview: 'hello', unread: 1),
        _chat(name: 'Amit Pal', preview: 'thanks'),
      ],
    );
    await _pump(tester, clinic, width: 1400);

    expect(find.text('Amit Pal'), findsOneWidget);
    await tester.tap(find.text('Unread'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Amit Pal'), findsNothing);
    expect(clinic.sorts, everyElement('inbox'), reason: 'always the server’s inbox ordering');
  });

  testWidgets('the colleague half says it is not built, rather than looking empty', (tester) async {
    await _pump(tester, _Clinic(items: [_chat(name: 'Priya Sharma', preview: 'hello')]), width: 1400);

    await tester.tap(find.text('Colleagues'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Messaging colleagues is not built yet'), findsOneWidget);
    expect(find.text('New chat'), findsNothing, reason: 'nothing to start there');
  });

  testWidgets('no conversations says so', (tester) async {
    await _pump(tester, _Clinic());
    expect(find.text('No conversations yet.'), findsOneWidget);
  });
}
