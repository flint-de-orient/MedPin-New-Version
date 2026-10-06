import 'package:medpin/core/network/api_exception.dart';
import 'package:medpin/core/theme/app_theme.dart';
import 'package:medpin/core/theme/doctor_tokens.dart';
import 'package:medpin/features/auth/data/auth_repository.dart';
import 'package:medpin/features/auth/presentation/auth_controller.dart';
import 'package:medpin/features/clinician/data/clinician_repository.dart';
import 'package:medpin/features/clinician/domain/team_member.dart';
import 'package:medpin/features/clinician/presentation/clinician_providers.dart';
import 'package:medpin/features/clinician/presentation/team_add_screen.dart';
import 'package:medpin/features/clinician/presentation/team_member_screen.dart';
import 'package:medpin/features/clinician/presentation/team_screen.dart';
import 'package:medpin/features/clinician/presentation/widgets/team_parts.dart';
import 'package:medpin/features/clinician/presentation/widgets/team_pickers.dart';
import 'package:medpin/features/clinician/presentation/widgets/verified_phone_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The People screens show everybody the server says works here.
///
/// It drew doctors, the desk and dieticians, and counted everyone else in the
/// "11 of 12 people" above a list that never showed them. It could hire into
/// three roles of seven. It could not add anybody who already used MedPin,
/// because it asked for a registration code, which the server refuses for a
/// number with an account. And opening somebody who had left and saving any
/// change sent them back in.
///
/// ---- Three screens, not a list and two sheets ---------------------------
///
/// The canvas draws People, People — add and People — member as three screens
/// with their own headers, and the forms are too long to sit in a sheet with
/// the keyboard up. So these tests drive a router: tapping a person has to
/// reach a screen, which is the half a sheet never had to prove.
///
/// The group blurbs the list used to carry are gone with the redesign. What
/// they said — "they do not prescribe" — is now the grant itself, ticked and
/// crossed on the member screen, which is both more precise and in the place
/// somebody reads before changing a role.

TeamMember _member(
  String name,
  String role, {
  String status = 'active',
  bool isOwner = false,
  int? version,
  List<String> permissions = const [],
  List<String> locationIds = const [],
  DateTime? startedOn,
}) => TeamMember(
  id: 'm-$name',
  userId: 'u-$name',
  name: name,
  phone: '+919830000000',
  role: role,
  isOwner: isOwner,
  status: status,
  permissions: permissions,
  usingPreset: true,
  locationIds: locationIds,
  startedOn: startedOn,
  version: version,
);

TeamRoster _roster(
  List<TeamMember> people, {
  List<({String id, String name})> locations = const [],
  int? staffCap,
  String? plan,
}) => TeamRoster(
  items: people,
  canManage: true,
  departments: const [],
  locations: locations,
  staffCap: staffCap,
  staffUsed: people.length,
  plan: plan,
);

/// The seven roles, as these screens name them.
const _roleNames = [
  'Doctor',
  'Front desk',
  'Dietician',
  'Doctor’s assistant',
  'Laboratory manager',
  'Laboratory technician',
  'Practice manager',
];

/// The team routes, recorded.
class _Team implements ClinicianRepository {
  final sentTo = <String>[];
  final checked = <(String, String)>[];
  final hired =
      <({String role, String name, String phoneToken, List<String> locationIds})>[];
  final updates = <({
    String id,
    String? role,
    String? status,
    int? version,
    List<String>? locationIds,
  })>[];

  /// What `POST /team` says about the number: true when it already had an
  /// account and this practice was added to it.
  bool existing = false;
  Object? hireFails;
  Object? updateFails;

  @override
  Future<void> requestHireCode(String phone) async => sentTo.add(phone);

  @override
  Future<String> verifyHireCode(String phone, String code) async {
    checked.add((phone, code));
    return 'hire-token-for-$phone';
  }

  @override
  Future<bool> hire({
    required String role,
    required String name,
    required String phoneToken,
    String? departmentId,
    String? locationId,
    List<String> locationIds = const [],
    String? qualifications,
    String? registrationNo,
  }) async {
    if (hireFails != null) throw hireFails!;
    hired.add((
      role: role,
      name: name,
      phoneToken: phoneToken,
      locationIds: locationIds,
    ));
    return existing;
  }

  @override
  Future<void> updateMember(
    String membershipId, {
    String? role,
    Object? departmentId,
    Object? locationId,
    List<String>? locationIds,
    String? status,
    int? version,
  }) async {
    if (updateFails != null) throw updateFails!;
    updates.add((
      id: membershipId,
      role: role,
      status: status,
      version: version,
      locationIds: locationIds,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Registration's codes, recorded — which the add form must no longer use.
class _Registration implements AuthRepository {
  final requested = <(String, String)>[];
  final verified = <(String, String)>[];

  @override
  Future<OtpSent> requestOtp({
    required String phone,
    required String purpose,
  }) async {
    requested.add((phone, purpose));
    return const OtpSent(
      expiresInSeconds: 600,
      resendAfterSeconds: 45,
      simulated: true,
    );
  }

  @override
  Future<String> verifyRegisterOtp({
    required String phone,
    required String code,
  }) async {
    verified.add((phone, code));
    return 'register-token';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // The app's own face for everything that takes it from the theme, so raised
  // text is laid out with real glyph widths. The role chips' labels do not
  // take it, and stay in the test font — whose glyphs are a full em wide, so
  // a name that fits here fits on a phone.
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await inter.load();
  });

  late _Team team;
  late _Registration registration;

  setUp(() {
    team = _Team();
    registration = _Registration();
  });

  Future<void> open(
    WidgetTester tester,
    TeamRoster roster, {
    TextScaler textScaler = TextScaler.noScaling,
    String at = '/clinician/team',
  }) async {
    // A 360dp phone, tall enough that the whole roster is laid out at once.
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // The app's own three paths, in the app's own order — so `add` matching
    // `:id` would fail here rather than in somebody's hands.
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(
          path: '/clinician/team',
          builder: (_, _) => const TeamScreen(),
        ),
        GoRoute(
          path: '/clinician/team/add',
          builder: (_, _) => const TeamAddScreen(),
        ),
        GoRoute(
          path: '/clinician/team/:id',
          builder: (_, state) =>
              TeamMemberScreen(membershipId: state.pathParameters['id'] ?? ''),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teamProvider.overrideWith((ref) async => roster),
          clinicianRepositoryProvider.overrideWithValue(team),
          authRepositoryProvider.overrideWithValue(registration),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAddForm(WidgetTester tester) async {
    await tester.tap(find.text('Add someone'));
    await tester.pumpAndSettle();
  }

  Future<void> openMember(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  Future<void> tapOn(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> chooseRole(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(TeamChip, label);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  /// Sends a code to 98300 12345 and reads 123456 back.
  Future<void> verifyNumber(WidgetTester tester) async {
    final fields = find.descendant(
      of: find.byType(VerifiedPhoneField),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, '9830012345');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(fields.last, '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
  }

  /// Every role is offered, as a chip, all of it on the phone.
  void expectEveryRole(WidgetTester tester) {
    expect(find.byType(TeamChip), findsNWidgets(_roleNames.length));
    for (final name in _roleNames) {
      final chip = find.widgetWithText(TeamChip, name);
      expect(chip, findsOneWidget, reason: name);
      final rect = tester.getRect(chip);
      // A tap target, and all of it on the phone: wrapped, not cut off.
      expect(rect.height, greaterThanOrEqualTo(D.tap), reason: name);
      expect(rect.left, greaterThanOrEqualTo(0), reason: name);
      expect(rect.right, lessThanOrEqualTo(360), reason: name);
    }
  }

  group('the roster', () {
    testWidgets('shows a laboratory technician and a practice manager', (
      tester,
    ) async {
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member('Bina Sen', 'lab_technician'),
          _member('Paresh Roy', 'practice_manager'),
        ]),
      );

      expect(find.text('LABORATORY TECHNICIANS'), findsOneWidget);
      expect(find.text('Bina Sen'), findsOneWidget);
      expect(find.text('PRACTICE MANAGERS'), findsOneWidget);
      expect(find.text('Paresh Roy'), findsOneWidget);
      // The head carries the one pill a row can hold.
      expect(find.text('Owner'), findsOneWidget);
    });

    testWidgets('hides the extra groups nobody holds, and keeps the first three', (
      tester,
    ) async {
      await open(tester, _roster([_member('Amit Dey', 'doctor', isOwner: true)]));

      for (final heading in [
        'DOCTOR’S ASSISTANTS',
        'LABORATORY MANAGERS',
        'LABORATORY TECHNICIANS',
        'PRACTICE MANAGERS',
      ]) {
        expect(find.text(heading), findsNothing, reason: heading);
      }

      expect(find.text('DOCTORS'), findsOneWidget);
      expect(find.text('FRONT DESK'), findsOneWidget);
      expect(find.text('DIETICIANS'), findsOneWidget);
      // Nobody on the desk and no dietician are facts worth stating.
      expect(find.text('Nobody yet.'), findsNWidgets(2));
    });

    testWidgets('gives a role it has no heading for a heading of its own, named', (
      tester,
    ) async {
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member('Mitali Das', 'ward_nurse'),
        ]),
      );

      // Not swept into "Others" and not dropped: their own heading, made
      // readable out of the role the server sent.
      expect(find.text('WARD NURSE'), findsOneWidget);
      expect(find.text('Mitali Das'), findsOneWidget);
    });

    testWidgets('says where somebody works, and that an unnarrowed row is '
        'every location', (tester) async {
      await open(
        tester,
        _roster(
          [
            _member('Amit Dey', 'doctor', isOwner: true),
            _member('Rina Paul', 'staff', locationIds: ['c1']),
          ],
          locations: [(id: 'c1', name: 'Salt Lake'), (id: 'c2', name: 'New Town')],
        ),
      );

      expect(find.text('All locations'), findsOneWidget);
      expect(find.text('Salt Lake'), findsOneWidget);
    });

    testWidgets('counts the seats against the plan, by name', (tester) async {
      await open(
        tester,
        _roster(
          [
            _member('Amit Dey', 'doctor', isOwner: true),
            _member('Rina Paul', 'staff'),
          ],
          staffCap: 8,
          // The server's key, not a display name — the screen is what turns
          // one into the other, and a test that passed the finished word would
          // never notice if it stopped.
          plan: 'professional',
        ),
      );

      expect(
        find.text('2 of 8 people on the Professional plan'),
        findsOneWidget,
      );
    });

    testWidgets('counts without naming a tier where the practice is on none', (
      tester,
    ) async {
      await open(
        tester,
        _roster([_member('Amit Dey', 'doctor', isOwner: true)], staffCap: 8),
      );

      expect(find.text('1 of 8 people'), findsOneWidget);
      expect(find.textContaining('plan'), findsNothing);
    });
  });

  group('the role pickers', () {
    testWidgets('the add form offers all seven, and only a doctor is asked '
        'for qualifications', (tester) async {
      await open(tester, _roster([_member('Amit Dey', 'doctor', isOwner: true)]));
      await openAddForm(tester);

      expectEveryRole(tester);

      // Front desk is chosen to begin with.
      expect(find.text('Qualifications'), findsNothing);
      await chooseRole(tester, 'Laboratory manager');
      expect(find.text('Qualifications'), findsNothing);

      await chooseRole(tester, 'Doctor');
      expect(find.text('Qualifications'), findsOneWidget);
      expect(find.text('Registration number'), findsOneWidget);
    });

    testWidgets('the add form says what the chosen role will be allowed to do', (
      tester,
    ) async {
      await open(tester, _roster([_member('Amit Dey', 'doctor', isOwner: true)]));
      await openAddForm(tester);

      expect(find.text('Permissions come from the role'), findsOneWidget);
      await chooseRole(tester, 'Doctor');
      expect(
        find.textContaining('Doctor: view patients, edit records, prescribe'),
        findsOneWidget,
      );
    });

    testWidgets('the member screen offers all seven, and says what a new role '
        'does to permissions', (tester) async {
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member('Rina Paul', 'staff'),
        ]),
      );
      await openMember(tester, 'Rina Paul');

      final menu = tester.widget<DropdownButton<String?>>(
        find.byType(DropdownButton<String?>).first,
      );
      expect(menu.value, 'staff');
      // The menu's own items, not the tree: a closed dropdown mounts only the
      // chosen one, so a widget search would pass for whichever role happens
      // to be selected and say nothing about the other six.
      expect(
        menu.items!.map((i) => (i.child as Text).data).toList(),
        _roleNames,
      );

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laboratory technician').last);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Their permissions will change to the defaults for a laboratory '
          'technician.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a long role name wraps inside its chip at twice the text size', (
      tester,
    ) async {
      await open(
        tester,
        _roster([_member('Amit Dey', 'doctor', isOwner: true)]),
        textScaler: const TextScaler.linear(2),
      );
      await openAddForm(tester);

      // Chosen, so the filled chip is measured too.
      await chooseRole(tester, 'Laboratory technician');

      for (final name in _roleNames) {
        final chipFinder = find.widgetWithText(TeamChip, name);
        final labelFinder = find.descendant(
          of: chipFinder,
          matching: find.text(name),
        );
        final chip = tester.getRect(chipFinder);
        final text = tester.getRect(labelFinder);
        final label = tester.renderObject<RenderParagraph>(labelFinder);

        // All of the name: no line dropped, none cut off by the chip's height,
        // and every line inside the chip on the phone.
        expect(label.didExceedMaxLines, isFalse, reason: name);
        expect(
          label.size.height,
          greaterThanOrEqualTo(
            label.getMaxIntrinsicHeight(label.size.width) - 0.5,
          ),
          reason: name,
        );
        expect(text.top, greaterThanOrEqualTo(chip.top - 0.5), reason: name);
        expect(text.bottom, lessThanOrEqualTo(chip.bottom + 0.5), reason: name);
        expect(chip.right, lessThanOrEqualTo(360), reason: name);
        expect(chip.height, greaterThanOrEqualTo(D.tap), reason: name);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('the member screen', () {
    testWidgets('reads the grant out as ticks and crosses, and says whose it is', (
      tester,
    ) async {
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member(
            'Rohit Saha',
            'doctor_assistant',
            permissions: const [
              'VIEW_PATIENT',
              'EDIT_RECORD',
              'CHAT_READ',
              'CHAT_REPLY',
            ],
          ),
        ]),
      );
      await openMember(tester, 'Rohit Saha');

      expect(find.text('What this role can do'), findsOneWidget);
      expect(find.text('Set by the Doctor’s assistant role'), findsOneWidget);
      // Nine grants, every one of them stated — four held, five refused.
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(4));
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(5));
      expect(find.text('Prescribe'), findsOneWidget);
    });

    testWidgets('names the person and when they joined this practice', (
      tester,
    ) async {
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member(
            'Rohit Saha',
            'doctor_assistant',
            startedOn: DateTime(2026, 3, 11),
          ),
        ]),
      );
      await openMember(tester, 'Rohit Saha');

      expect(find.text('Rohit Saha'), findsOneWidget);
      expect(find.text('+919830000000 · Joined Mar 2026'), findsOneWidget);
    });

    testWidgets('the head cannot be demoted or suspended from the app', (
      tester,
    ) async {
      await open(tester, _roster([_member('Amit Dey', 'doctor', isOwner: true)]));
      await openMember(tester, 'Amit Dey');

      expect(find.text('This is the practice’s head'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      // Drawn as what it is, rather than taking the tap and dropping it: a
      // control that moves nothing when tapped reads as broken.
      expect(
        tester
            .widget<DropdownButton<String?>>(
              find.byType(DropdownButton<String?>).first,
            )
            .onChanged,
        isNull,
      );
      // Save is dead: there is nothing on this screen they may change.
      await tapOn(tester, 'Save');
      expect(team.updates, isEmpty);
    });

    testWidgets('says so rather than drawing a form over somebody who has gone', (
      tester,
    ) async {
      await open(
        tester,
        _roster([_member('Amit Dey', 'doctor', isOwner: true)]),
        at: '/clinician/team/m-Nobody',
      );

      expect(
        find.text('This person is not on the practice’s list any more.'),
        findsOneWidget,
      );
      expect(find.text('What this role can do'), findsNothing);
    });

    testWidgets('somebody who left opens suspended, and says how to bring them '
        'back', (tester) async {
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member('Rina Paul', 'staff', status: 'left'),
        ]),
      );
      await openMember(tester, 'Rina Paul');

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(
        find.text(
          'They left this practice. Turn this off to give them their access '
          'back.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('somebody suspended opens suspended, with nothing about leaving', (
      tester,
    ) async {
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member('Rina Paul', 'staff', status: 'suspended'),
        ]),
      );
      await openMember(tester, 'Rina Paul');

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.textContaining('They left this practice.'), findsNothing);
    });

    testWidgets('saving another change does not send somebody who left back in', (
      tester,
    ) async {
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member('Rina Paul', 'staff', status: 'left'),
        ]),
      );
      await openMember(tester, 'Rina Paul');

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doctor’s assistant').last);
      await tester.pumpAndSettle();
      await tapOn(tester, 'Save');

      expect(team.updates, hasLength(1));
      expect(team.updates.single.role, 'doctor_assistant');
      // Not `active` — and nothing about status at all, since the switch was
      // never moved.
      expect(team.updates.single.status, isNull);
    });

    testWidgets('turning the switch off is what gives their access back', (
      tester,
    ) async {
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member('Rina Paul', 'staff', status: 'left'),
        ]),
      );
      await openMember(tester, 'Rina Paul');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        find.text('They left this practice. Saving gives them their access back.'),
        findsOneWidget,
      );

      await tapOn(tester, 'Save');
      expect(team.updates.single.status, 'active');
    });

    testWidgets('narrowing somebody to one location sends that location', (
      tester,
    ) async {
      await open(
        tester,
        _roster(
          [
            _member('Amit Dey', 'doctor', isOwner: true),
            _member('Rina Paul', 'staff'),
          ],
          locations: [(id: 'c1', name: 'Salt Lake'), (id: 'c2', name: 'New Town')],
        ),
      );
      await openMember(tester, 'Rina Paul');

      // Opens on every location, because an empty list is every location.
      expect(find.byType(TeamLocations), findsOneWidget);
      await tapOn(tester, 'New Town');
      await tapOn(tester, 'Save');

      expect(team.updates.single.locationIds, ['c2']);
    });

    testWidgets('saving sends the version of the row the screen opened with', (
      tester,
    ) async {
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member('Rina Paul', 'staff', version: 3),
        ]),
      );
      await openMember(tester, 'Rina Paul');

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doctor’s assistant').last);
      await tester.pumpAndSettle();
      await tapOn(tester, 'Save');

      expect(team.updates.single.version, 3);
    });

    testWidgets('a colleague’s change made meanwhile is reported, and nothing '
        'is saved over it', (tester) async {
      team.updateFails = const ApiException(
        code: 'MEMBER_CHANGED',
        message:
            'Somebody else changed this person’s role or access a moment ago. '
            'Open them again to see what it is now.',
        statusCode: 409,
      );
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member('Rina Paul', 'staff', version: 3),
        ]),
      );
      await openMember(tester, 'Rina Paul');

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doctor’s assistant').last);
      await tester.pumpAndSettle();
      await tapOn(tester, 'Save');

      expect(
        find.textContaining('Somebody else changed this person’s role or access'),
        findsOneWidget,
      );
      expect(team.updates, isEmpty);
      // Still open, so the manager reads it before anything else happens.
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('a practice at its limit is told so in the server’s words', (
      tester,
    ) async {
      team.updateFails = const ApiException(
        code: 'CONFLICT',
        message: 'This practice is at its limit of 12 people.',
        statusCode: 409,
      );
      await open(
        tester,
        _roster([
          _member('Amit Dey', 'doctor', isOwner: true),
          _member('Rina Paul', 'staff', status: 'left'),
        ]),
      );
      await openMember(tester, 'Rina Paul');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tapOn(tester, 'Save');

      expect(
        find.text('This practice is at its limit of 12 people.'),
        findsOneWidget,
      );
      expect(find.textContaining('ApiException'), findsNothing);
    });
  });

  group('hiring', () {
    testWidgets('offers no password, for any role — nobody sets a colleague’s', (
      tester,
    ) async {
      await open(tester, _roster([_member('Amit Dey', 'doctor', isOwner: true)]));
      await openAddForm(tester);

      for (final role in _roleNames) {
        await chooseRole(tester, role);
        expect(find.text('Set a password'), findsNothing, reason: role);
        expect(find.text('Password'), findsNothing, reason: role);
        expect(find.byType(Switch), findsNothing, reason: role);
        // The promise that went with it had no screen behind it.
        expect(
          find.textContaining('change it after signing in'),
          findsNothing,
          reason: role,
        );
      }
      expect(
        find.textContaining('They sign in with a code texted to this number.'),
        findsOneWidget,
      );
    });

    testWidgets('sends and checks the code through the team, not registration', (
      tester,
    ) async {
      await open(tester, _roster([_member('Amit Dey', 'doctor', isOwner: true)]));
      await openAddForm(tester);

      await verifyNumber(tester);

      expect(team.sentTo, ['+919830012345']);
      expect(team.checked, [('+919830012345', '123456')]);
      expect(registration.requested, isEmpty);
      expect(registration.verified, isEmpty);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });

    testWidgets('somebody who already uses MedPin is added, and told they keep '
        'their account', (tester) async {
      team.existing = true;
      await open(tester, _roster([_member('Amit Dey', 'doctor', isOwner: true)]));
      await openAddForm(tester);

      expect(
        find.textContaining(
          'If they already use MedPin, they keep their account and sign in as '
          'before.',
        ),
        findsOneWidget,
      );

      await chooseRole(tester, 'Doctor');
      await verifyNumber(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Asha Roy');
      await tapOn(tester, 'Add to team');

      expect(team.hired.single.role, 'doctor');
      expect(team.hired.single.name, 'Asha Roy');
      expect(team.hired.single.phoneToken, 'hire-token-for-+919830012345');
      // The form has gone, and the screen behind it says what happened.
      expect(find.text('Add to team'), findsNothing);
      expect(
        find.text(
          'They already use MedPin, so they keep their account and now work '
          'here too.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a new account is added without that message', (tester) async {
      await open(tester, _roster([_member('Amit Dey', 'doctor', isOwner: true)]));
      await openAddForm(tester);

      await verifyNumber(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Rina Paul');
      await tapOn(tester, 'Add to team');

      expect(team.hired.single.role, 'staff');
      expect(find.text('Add to team'), findsNothing);
      expect(find.textContaining('already use MedPin, so'), findsNothing);
    });

    testWidgets('a refusal is shown in the server’s own sentence', (tester) async {
      team.hireFails = const ApiException(
        code: 'CONFLICT',
        message:
            'This number belongs to a patient, so it cannot be added as staff.',
        statusCode: 409,
      );
      await open(tester, _roster([_member('Amit Dey', 'doctor', isOwner: true)]));
      await openAddForm(tester);

      await verifyNumber(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Rina Paul');
      await tapOn(tester, 'Add to team');

      expect(
        find.text(
          'This number belongs to a patient, so it cannot be added as staff.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('ApiException'), findsNothing);
      // Still on the form, where it can be put right.
      expect(find.text('Add to team'), findsOneWidget);
    });

    testWidgets('a practice at its limit is told before it fills the form in', (
      tester,
    ) async {
      await open(
        tester,
        _roster(
          [
            _member('Amit Dey', 'doctor', isOwner: true),
            _member('Rina Paul', 'staff'),
          ],
          staffCap: 2,
        ),
      );
      await tapOn(tester, 'Add someone');

      expect(
        find.textContaining('at its limit of 2 people'),
        findsOneWidget,
      );
      // And the form never opened.
      expect(find.text('Add to team'), findsNothing);
    });
  });

  group('VerifiedPhoneField without callbacks', () {
    testWidgets('still asks registration for the code, exactly as before', (
      tester,
    ) async {
      String? token;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(registration)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: VerifiedPhoneField(onToken: (t) => token = t),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await verifyNumber(tester);

      expect(registration.requested, [('+919830012345', 'register')]);
      expect(registration.verified, [('+919830012345', '123456')]);
      expect(token, 'register-token');
      expect(team.sentTo, isEmpty);
    });
  });
}
