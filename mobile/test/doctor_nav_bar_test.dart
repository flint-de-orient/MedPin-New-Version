import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/features/doctor_home/presentation/widgets/doctor_nav_bar.dart';

/// The doctor's bar in the new design.
///
/// It carries the one number a doctor acts on between consultations — patient
/// messages nobody has read — and it must say which place is lit to a screen
/// reader as well as in colour.

const _items = [
  DoctorNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
  DoctorNavItem(
    icon: Icons.people_alt_outlined,
    selectedIcon: Icons.people_alt_rounded,
    label: 'Patients',
    badge: 4,
  ),
  DoctorNavItem(
    icon: Icons.restaurant_menu_outlined,
    selectedIcon: Icons.restaurant_menu_rounded,
    label: 'Nutrition',
  ),
  DoctorNavItem(
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    label: 'More',
    showDot: true,
  ),
];

Future<void> _pump(WidgetTester tester, {int current = 0, void Function(int)? onSelected}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        bottomNavigationBar: DoctorNavBar(
          currentIndex: current,
          onSelected: onSelected ?? (_) {},
          items: _items,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('every place is named, and the one you are in is marked as such', (tester) async {
    await _pump(tester, current: 1);

    for (final label in ['Home', 'Patients', 'Nutrition', 'More']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.selected == true && w.properties.label == 'Patients, 4 unread',
      ),
      findsOneWidget,
      reason: 'the open tab must be selected to a screen reader, not only lit',
    );
  });

  testWidgets('the waiting messages are counted, not dotted', (tester) async {
    await _pump(tester);

    expect(find.text('4'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Patients, 4 unread'),
      findsOneWidget,
    );
  });

  testWidgets('a tap says which place was asked for', (tester) async {
    final taps = <int>[];
    await _pump(tester, onSelected: taps.add);

    await tester.tap(find.text('Nutrition'));
    await tester.tap(find.text('More'));

    expect(taps, [2, 3]);
  });

  testWidgets('a count above ninety-nine stops counting rather than widening the bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: DoctorNavBar(
            currentIndex: 0,
            onSelected: (_) {},
            items: const [
              DoctorNavItem(
                icon: Icons.people_alt_outlined,
                selectedIcon: Icons.people_alt_rounded,
                label: 'Patients',
                badge: 128,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('99+'), findsOneWidget);
  });
}
