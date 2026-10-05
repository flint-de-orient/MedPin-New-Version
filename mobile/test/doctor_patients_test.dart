import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/core/network/api_client.dart';
import 'package:medpin/core/storage/secure_store.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/clinician_models.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_patients_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';
import 'package:medpin/shared/models/paged.dart';
import 'package:medpin/shared/providers/core_providers.dart';

/// The doctor's Patients tab.
///
/// Its chips are the server's own orderings and its one real filter, because
/// the artboard's counted buckets are numbers nobody can stand behind yet. So
/// every chip has to re-ask the server rather than sift what is on screen, and
/// the line under a patient has to be the most urgent true thing about them.

final _now = DateTime(2026, 10, 3, 9);

PatientListItem _patient({
  required String name,
  String phone = '+919830000011',
  int unread = 0,
  int alerts = 0,
  String risk = 'low',
  num? reading,
  DateTime? readingAt,
  DateTime? lastMessageAt,
}) => PatientListItem.fromJson({
  'id': name.toLowerCase().replaceAll(' ', '-'),
  'name': name,
  'phone': phone,
  'unreadCount': unread,
  'openAlertCount': alerts,
  'riskBand': risk,
  'riskScore': 10,
  if (reading != null) 'lastReadingValue': reading,
  if (readingAt != null) 'lastReadingAt': readingAt.toUtc().toIso8601String(),
  if (lastMessageAt != null)
    'lastMessage': {
      'preview': 'hello',
      'role': 'user',
      'at': lastMessageAt.toUtc().toIso8601String(),
      'urgency': 'routine',
    },
});

class _Clinic implements ClinicianRepository {
  _Clinic({this.items = const [], this.total = 0});

  List<PatientListItem> items;
  int total;

  /// Every query the screen made, in order.
  final asked = <({String sort, String? riskBand, String? search})>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #patients) {
      final named = invocation.namedArguments;
      asked.add((
        sort: named[const Symbol('sort')] as String? ?? 'risk',
        riskBand: named[const Symbol('riskBand')] as String?,
        search: named[const Symbol('search')] as String?,
      ));
      return Future<Paged<PatientListItem>>.value(
        Paged<PatientListItem>(
          items: items,
          page: 1,
          limit: 100,
          total: total == 0 ? items.length : total,
          hasMore: (total == 0 ? items.length : total) > items.length,
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class _NoSession extends SecureStore {
  @override
  Future<String?> readAccessToken() async => null;
}

/// [width] in physical pixels. 720 is the clinic's phone: 360dp. Every test
/// runs at that width, because the layout bugs this screen shipped were all
/// bugs of not enough room.
Future<void> _pump(
  WidgetTester tester,
  _Clinic clinic, {
  double width = 720,
  double textScale = 1,
}) async {
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
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: const DoctorPatientsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('the line under a patient', () {
    test('an open alert outranks everything, then unread, then risk, then a reading', () {
      expect(
        flagFor(_patient(name: 'A', alerts: 2, unread: 5, risk: 'critical'))?.text,
        '2 open alerts',
      );
      expect(flagFor(_patient(name: 'B', unread: 1, risk: 'high'))?.text, '1 unread message');
      expect(flagFor(_patient(name: 'C', risk: 'critical'))?.text, 'Critical risk');
      expect(
        flagFor(_patient(name: 'D', reading: 212, readingAt: DateTime(2026, 9, 28)))?.text,
        'Last reading 212 · 28 Sep',
      );
    });

    test('a patient with nothing to say gets no line at all', () {
      expect(flagFor(_patient(name: 'E')), isNull);
    });
  });

  test('when they last wrote, in a doctor’s words', () {
    String seen(DateTime at) => lastSeenLabel(at, now: _now);
    expect(seen(_now.subtract(const Duration(hours: 2))), 'Today');
    expect(seen(_now.subtract(const Duration(days: 1))), 'Yesterday');
    expect(seen(_now.subtract(const Duration(days: 3))), 'Wed');
    expect(seen(_now.subtract(const Duration(days: 30))), '3 Sep');
  });

  test('the match line counts what the server found, not what is on screen', () {
    expect(matchesLine(2, '98765'), '2 MATCHES FOR “98765”');
    expect(matchesLine(1, 'Priya'), '1 MATCH FOR “Priya”');
  });

  testWidgets('the roll shows each patient with their number and what needs doing', (tester) async {
    await _pump(
      tester,
      _Clinic(
        items: [
          // The real clock, because the row words itself against it: pinned to
          // a fixed day, "Today" stops being today the next morning.
          _patient(
            name: 'Priya Sharma',
            phone: '+919876543210',
            alerts: 1,
            lastMessageAt: DateTime.now(),
          ),
          _patient(name: 'Rahul Das', unread: 3),
        ],
        total: 248,
      ),
    );

    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('248 patients'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('+919876543210'), findsOneWidget);
    expect(find.text('1 open alert'), findsOneWidget);
    expect(find.text('3 unread messages'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('View'), findsNWidgets(2));
    expect(find.text('Consult'), findsNWidgets(2));
  });

  testWidgets('the title keeps its width beside the button, on a 360dp phone', (tester) async {
    // What this prevents, seen on the clinic's own phone: "Add patient" asked
    // for `Size.fromHeight(52)` from the app's button theme — an infinite
    // minimum width — took the whole row, and the title came out one letter
    // per line with the button pushed off the screen.
    await _pump(tester, _Clinic(items: [_patient(name: 'Tanmoy')], total: 4));

    final title = tester.getRect(find.text('Patients'));
    expect(title.width, greaterThan(80), reason: 'the title was squeezed to a column of letters');
    // Under flutter_test's square stand-in font every glyph is as wide as it
    // is tall, so "Patients" wraps here where Figtree would not. Eight lines
    // is the failure; a line or three is this font.
    expect(title.height, lessThan(160), reason: 'one letter per line is the bug');

    final button = tester.getRect(find.text('Add patient'));
    expect(button.right, lessThanOrEqualTo(360), reason: 'pushed off the right edge');
    expect(button.left, greaterThan(title.right), reason: 'it sits beside the title, not over it');
  });

  testWidgets('every chip is on the screen, each the width of its own label', (tester) async {
    // A filter a doctor cannot see is a filter they do not use, so these five
    // wrap onto a second line rather than scrolling sideways off the edge —
    // and a chip that fills the row is the aligned-Container bug.
    await _pump(tester, _Clinic(items: [_patient(name: 'Tanmoy')]));

    for (final label in ['All', 'Unread first', 'Recent visits', 'By name', 'High risk']) {
      final chip = tester.getRect(find.text(label));
      expect(chip.right, lessThanOrEqualTo(360), reason: '$label runs off the edge');
      expect(chip.left, greaterThanOrEqualTo(0), reason: '$label starts off the edge');
    }

    final box = tester.getRect(
      find.ancestor(of: find.text('All'), matching: find.byType(Container)).first,
    );
    expect(box.width, lessThan(160), reason: 'the chip stretched to the whole row');
  });

  testWidgets('every chip re-asks the server rather than sifting what is loaded', (tester) async {
    final clinic = _Clinic(items: [_patient(name: 'Priya Sharma')]);
    await _pump(tester, clinic);

    expect(clinic.asked.last.sort, 'risk');
    expect(clinic.asked.last.riskBand, isNull);

    await tester.tap(find.text('Unread first'));
    await tester.pump();
    await tester.pump();
    expect(clinic.asked.any((q) => q.sort == 'inbox'), isTrue);

    await tester.tap(find.text('High risk'));
    await tester.pump();
    await tester.pump();
    expect(
      clinic.asked.any((q) => q.riskBand == 'high'),
      isTrue,
      reason: 'the one real filter must go to the server',
    );
  });

  testWidgets('searching narrows the same list and offers to add somebody new', (tester) async {
    final clinic = _Clinic(items: [_patient(name: 'Priya Sharma', phone: '+919876543210')], total: 1);
    await _pump(tester, clinic);

    await tester.enterText(find.byType(TextField), '98765');
    await tester.pump();
    await tester.pump();

    expect(clinic.asked.last.search, '98765');
    expect(find.text('1 MATCH FOR “98765”'), findsOneWidget);
    expect(find.textContaining('Not the patient you’re looking for?'), findsOneWidget);
    expect(find.text('Add new patient'), findsOneWidget);
  });

  testWidgets('nothing clips when the reader turns their text size up', (tester) async {
    // Every box on this screen that holds text takes its height from the
    // scaler. At 1.5 the header, the search field and a patient card all grow;
    // an overflow here is a box that was given a constant instead.
    await _pump(
      tester,
      _Clinic(items: [_patient(name: 'Tanmoy', unread: 2)], total: 4),
      textScale: 1.5,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('Search by name or mobile number'), findsOneWidget);

    // The header is taller than the phone at this size, so the roll is below
    // it — reachable, which is the whole point of the header scrolling.
    await tester.scrollUntilVisible(
      find.text('Tanmoy'),
      200,
      // The page's own scroll view, not the search field's.
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2 unread messages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty roll and a failed read each say which it is', (tester) async {
    await _pump(tester, _Clinic());
    expect(find.textContaining('No patients on your roll yet'), findsOneWidget);
  });
}
