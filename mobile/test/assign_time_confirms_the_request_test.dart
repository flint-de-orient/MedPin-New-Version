import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "Assign time" has to confirm the request, not book a second appointment.
///
/// ---- The bug this pins shut ----------------------------------------------
///
/// The doctor's Appointments screen surfaces patients waiting for a time and
/// offers "Assign time". It called `bookAgain`, and that was wrong twice:
///
///   1. A request has no clinic by construction — the server's own words at
///      POST /appointments/request are "No clinic and no time yet: the desk
///      assigns both when it confirms." The sheet gates its day picker, its
///      action button and its cancel button on `clinicId != null`, so the
///      doctor got a sheet with one sentence and nothing to press.
///   2. Had it shown a button, that button called `book` — creating a SECOND
///      appointment and leaving the original at `requested` for ever. The
///      route for this is PATCH /appointments/:id/confirm, which exists
///      precisely because book and reschedule cannot do it.
///
/// A widget test would exercise the sheet, which needs slots, a clinic list
/// and a server. These are source assertions instead: they are about which
/// call is wired to which button, which is exactly what went wrong and is not
/// something a rendering test would have caught either.
void main() {
  final sheet = File(
    'lib/features/doctor_home/presentation/widgets/appointment_manage_sheet.dart',
  ).readAsStringSync();
  final screen = File(
    'lib/features/doctor_home/presentation/doctor_appointments_screen.dart',
  ).readAsStringSync();

  test('the screen assigns with assignTime, never bookAgain', () {
    expect(screen, contains('await assignTime(context, _booking(a))'));

    // `bookAgain` is legitimate on the history screen, for a missed or
    // cancelled appointment. It must not come back here.
    final assign = screen.substring(
      screen.indexOf('Future<void> _assign('),
      screen.indexOf('Future<void> _decline('),
    );
    expect(
      assign,
      isNot(contains('bookAgain')),
      reason: 'a request confirmed through book leaves a duplicate behind',
    );
  });

  test('assign mode sends confirmRequest and nothing else', () {
    expect(sheet, contains('enum _Mode'));
    expect(sheet, contains('_Mode.assign'));

    // Anchored on the repository, not on `switch (widget.mode)` — the title
    // switches on the mode too, and slicing from the first match read the
    // wrong block entirely.
    final send = sheet.substring(
      sheet.indexOf('final repo = ref.read(appointmentRepositoryProvider);'),
      sheet.indexOf('if (mounted) Navigator.of(context).pop(true);'),
    );
    // Each mode reaches exactly one call, and assign reaches confirm.
    expect(send, contains('repo.confirmRequest('));
    expect(send, contains('repo.book('));
    expect(send, contains('repo.reschedule('));
    expect(
      send.indexOf('_Mode.assign') < send.indexOf('repo.confirmRequest('),
      isTrue,
      reason: 'assign must be the branch that confirms',
    );
    expect(
      send.indexOf('repo.confirmRequest(') < send.indexOf('_Mode.again'),
      isTrue,
      reason: 'confirm belongs to assign, not to book-again',
    );
  });

  test('assign mode asks which location, because a request carries none', () {
    expect(sheet, contains('_pickedClinicId'));
    expect(sheet, contains('class _RoomChip'));
    // One open location is not a choice and is not drawn as one.
    expect(sheet, contains('rooms.length == 1'));
    // And none at all is said plainly rather than left as a dead sheet.
    expect(sheet, contains('_assigning && rooms.isEmpty'));
  });

  test('the way to the desk is always offered, not only past three', () {
    final waiting = screen.substring(
      screen.indexOf('class _Waiting'),
      screen.indexOf('class _RequestAction'),
    );
    expect(waiting, contains("context.push('/clinician/appointments/desk')"));
    expect(
      waiting,
      isNot(contains('if (rows.length > shown.length) ...[')),
      reason: 'with one to three requests waiting there was no way out of the '
          'card at all',
    );
  });
}
