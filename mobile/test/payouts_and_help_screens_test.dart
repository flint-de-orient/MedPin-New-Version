import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medpin/core/network/api_exception.dart';
import 'package:medpin/core/theme/app_theme.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/data/practice_repository.dart';
import 'package:medpin/features/clinician/domain/practice.dart';
import 'package:medpin/features/clinician/domain/support_request.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_help_screen.dart';
import 'package:medpin/features/doctor_home/presentation/doctor_payouts_screen.dart';
import 'package:medpin/l10n/gen/app_localizations.dart';

/// The two screens that close the last of the "Not on file yet" rows.
///
/// ---- What is worth a test here -------------------------------------------
///
/// Not that a form submits. Three things that would each be a real defect and
/// that a clean analyzer says nothing about:
///
///   · the payouts screen cannot be made to send a bank account with no
///     number behind it, because the app does not hold the number and the
///     server would clear the account;
///   · the account number is never put into a box, however the screen is
///     opened — the one thing the whole `select: false` arrangement exists
///     for would be undone by a single pre-filled field;
///   · nothing on either screen overflows at a raised text scale, which is
///     where three layout bugs have shipped in this repo.

PracticeOverview _practice({PayoutAccount payout = const PayoutAccount()}) =>
    PracticeOverview(
      id: 'p1',
      name: 'City Care',
      tagline: null,
      doctorDisplayName: null,
      registrationNo: 'WBMC 1234',
      logoLightUrl: null,
      verification: 'verified',
      gaps: const [],
      canPrintPrescription: true,
      locations: const [],
      doctors: 1,
      staff: 1,
      dieticians: 0,
      payout: payout,
    );

/// What was sent to PATCH /practices/:id.
class _Practices implements PracticeRepository {
  final sent = <Map<String, dynamic>>[];
  Object? fails;

  @override
  Future<PracticeOverview> update(String id, Map<String, dynamic> body) async {
    if (fails != null) throw fails!;
    sent.add(body);
    return _practice();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Support implements ClinicianRepository {
  _Support([this.rows = const []]);

  final List<SupportRequest> rows;
  final asked = <({String topic, String message})>[];

  @override
  Future<List<SupportRequest>> supportRequests() async => rows;

  @override
  Future<SupportRequest> askForHelp({
    required String topic,
    required String message,
  }) async {
    asked.add((topic: topic, message: message));
    return SupportRequest(
      id: 's1',
      reference: 'A1B2C3',
      topic: topic,
      message: message,
      state: 'open',
      replies: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Practices practices;

  setUp(() => practices = _Practices());

  Future<void> openPayouts(
    WidgetTester tester, {
    PayoutAccount payout = const PayoutAccount(),
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceOverviewProvider.overrideWith(
            (ref) async => _practice(payout: payout),
          ),
          practiceRepositoryProvider.overrideWithValue(practices),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          // ErrorView.messageFor reads the localisations, so a harness
          // without them throws on the one path these tests are here for.
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: const DoctorPayoutsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('payouts', () {
    testWidgets('an empty practice opens ready to type, and says what is '
        'settled here', (tester) async {
      await openPayouts(tester);

      expect(find.text('What is settled here'), findsOneWidget);
      // The distinction a doctor has to be able to read: desk cash is not ours.
      expect(find.textContaining('never passes through us'), findsOneWidget);
      // Nothing to replace, so the number box is already open.
      expect(find.text('Account number'), findsOneWidget);
      expect(find.text('Not set'), findsWidgets);
    });

    testWidgets('an account on file is shown by its last four, and the box is '
        'closed', (tester) async {
      await openPayouts(
        tester,
        payout: const PayoutAccount(
          accountName: 'City Care Clinic',
          accountLast4: '7890',
          ifsc: 'HDFC0001234',
          bankName: 'HDFC, Salt Lake',
          onFile: true,
        ),
      );

      expect(find.text('HDFC, Salt Lake ••••7890'), findsOneWidget);
      expect(find.text('••••••7890'), findsOneWidget);
      // The whole point: no field anywhere holds a number to be edited.
      for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(
          field.controller?.text ?? '',
          isNot(contains('7890')),
          reason: 'the account number must never be pre-filled into a box',
        );
      }
    });

    testWidgets('changing only the bank name is refused, with what to do '
        'instead', (tester) async {
      await openPayouts(
        tester,
        payout: const PayoutAccount(
          accountName: 'City Care Clinic',
          accountLast4: '7890',
          ifsc: 'HDFC0001234',
          bankName: 'HDFC, Salt Lake',
          onFile: true,
        ),
      );

      await tester.enterText(find.byType(TextField).at(1), 'HDFC, Sector V');
      await tester.pumpAndSettle();
      final save = find.text('Save account');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(
        practices.sent,
        isEmpty,
        reason: 'the account would have been cleared',
      );
      expect(find.textContaining('type it again'), findsOneWidget);
    });

    testWidgets('a bank account with no IFSC is refused before it is sent', (
      tester,
    ) async {
      await openPayouts(tester);

      await tester.enterText(find.byType(TextField).first, 'City Care Clinic');
      await tester.enterText(find.byType(TextField).at(1), '50100234567890');
      await tester.pumpAndSettle();
      final save = find.text('Save account');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(practices.sent, isEmpty);
      expect(find.textContaining('needs its IFSC'), findsOneWidget);
    });

    testWidgets('a malformed IFSC is caught on the field', (tester) async {
      await openPayouts(tester);

      await tester.enterText(find.byType(TextField).first, 'City Care Clinic');
      await tester.enterText(find.byType(TextField).at(1), '50100234567890');
      await tester.enterText(find.byType(TextField).at(2), 'HDFC1001234');
      await tester.pumpAndSettle();
      final save = find.text('Save account');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(practices.sent, isEmpty);
      expect(find.textContaining('four letters, a zero'), findsOneWidget);
    });

    testWidgets('a whole account is sent, number and all', (tester) async {
      await openPayouts(tester);

      await tester.enterText(find.byType(TextField).first, 'City Care Clinic');
      await tester.enterText(find.byType(TextField).at(1), '50100234567890');
      await tester.enterText(find.byType(TextField).at(2), 'hdfc0001234');
      await tester.pumpAndSettle();
      final save = find.text('Save account');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(practices.sent, hasLength(1));
      final payout = practices.sent.single['payout'] as Map<String, dynamic>;
      expect(payout['accountNumber'], '50100234567890');
      // Kept in the case the bank prints it, whatever the keyboard did.
      expect(payout['ifsc'], 'HDFC0001234');
    });

    testWidgets('UPI alone is enough to save', (tester) async {
      await openPayouts(tester);

      // The UPI field is the last one on the form.
      await tester.enterText(find.byType(TextField).last, 'citycare@okaxis');
      await tester.pumpAndSettle();
      final save = find.text('Save account');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(practices.sent, hasLength(1));
      final payout = practices.sent.single['payout'] as Map<String, dynamic>;
      expect(payout['upiId'], 'citycare@okaxis');
      expect(payout['accountNumber'], isNull);
    });

    testWidgets('the server’s refusal is shown in its own words', (tester) async {
      practices.fails = const ApiException(
        code: 'VALIDATION_ERROR',
        message: 'That is not an IFSC code',
        statusCode: 400,
      );
      await openPayouts(tester);

      await tester.enterText(find.byType(TextField).last, 'citycare@okaxis');
      await tester.pumpAndSettle();
      final save = find.text('Save account');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.textContaining('IFSC'), findsWidgets);
      expect(find.textContaining('ApiException'), findsNothing);
    });

    testWidgets('nothing overflows at twice the text size', (tester) async {
      await openPayouts(
        tester,
        payout: const PayoutAccount(
          accountName: 'City Care Clinic',
          accountLast4: '7890',
          ifsc: 'HDFC0001234',
          bankName: 'HDFC Bank, Salt Lake Sector V',
          upiId: 'citycare.saltlake@okaxis',
          onFile: true,
        ),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      for (final box in tester.renderObjectList<RenderBox>(find.byType(Text))) {
        expect(box.size.width, lessThanOrEqualTo(360 + 0.5));
      }
    });
  });

  group('help', () {
    Future<void> openHelp(
      WidgetTester tester,
      _Support support, {
      TextScaler textScaler = TextScaler.noScaling,
    }) async {
      tester.view.physicalSize = const Size(1080, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [clinicianRepositoryProvider.overrideWithValue(support)],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
            home: const DoctorHelpScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('leads with answers, and says nothing has been asked yet', (
      tester,
    ) async {
      await openHelp(tester, _Support());

      expect(find.text('ANSWERS'), findsOneWidget);
      expect(find.text('Nothing yet.'), findsOneWidget);
      expect(find.text('Ask MedPin for help'), findsOneWidget);
      // The line that matters most on the screen.
      expect(find.text('Not sent'), findsOneWidget);
      expect(find.text('Anything about a patient'), findsOneWidget);
    });

    testWidgets('an answer opens and offers the screen it is about', (
      tester,
    ) async {
      await openHelp(tester, _Support());

      final question = find.text('A colleague cannot sign in');
      await tester.ensureVisible(question);
      await tester.tap(question);
      await tester.pumpAndSettle();

      expect(find.textContaining('nobody sets a colleague'), findsOneWidget);
      expect(find.text('Open People'), findsOneWidget);
    });

    testWidgets('a request MedPin replied to is marked as needing the clinic', (
      tester,
    ) async {
      await openHelp(
        tester,
        _Support([
          SupportRequest(
            id: 's1',
            reference: 'A1B2C3',
            topic: 'scheduling',
            message: 'A patient cannot book with me on Tuesdays.',
            state: 'answered',
            replies: const [
              SupportReply(text: 'Which location?', fromMedPin: true),
            ],
          ),
        ]),
      );

      expect(find.text('Appointments and the queue'), findsOneWidget);
      expect(find.text('MedPin replied'), findsOneWidget);
    });

    testWidgets('asking needs more than a word, and sends the topic chosen', (
      tester,
    ) async {
      final support = _Support();
      await openHelp(tester, support);

      await tester.tap(find.text('Ask MedPin for help'));
      await tester.pumpAndSettle();

      // Too short to act on, so Send does nothing.
      await tester.enterText(find.byType(TextField).last, 'broken');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(support.asked, isEmpty);

      await tester.enterText(
        find.byType(TextField).last,
        'Tapping Print on a prescription does nothing at all.',
      );
      await tester.pumpAndSettle();
      final billing = find.text('Plan, invoices or payouts');
      await tester.ensureVisible(billing);
      await tester.tap(billing);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(support.asked, hasLength(1));
      expect(support.asked.single.topic, 'billing');
      // And the reference comes back, because the next thing is often a call.
      expect(find.textContaining('A1B2C3'), findsOneWidget);
    });

    testWidgets('nothing overflows at twice the text size', (tester) async {
      await openHelp(
        tester,
        _Support([
          SupportRequest(
            id: 's1',
            reference: 'A1B2C3',
            topic: 'prescribing',
            message: 'Tapping Print does nothing.',
            state: 'answered',
            replies: const [
              SupportReply(text: 'Which printer?', fromMedPin: true),
            ],
          ),
        ]),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
      for (final box in tester.renderObjectList<RenderBox>(find.byType(Text))) {
        expect(box.size.width, lessThanOrEqualTo(360 + 0.5));
      }
    });
  });
}
