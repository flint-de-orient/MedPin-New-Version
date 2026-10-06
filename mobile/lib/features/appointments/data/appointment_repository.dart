import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/submission_keys.dart';
import '../../../shared/models/paged.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/appointment.dart';
import '../domain/service.dart';

/// Talks to `/appointments`. Patients see and act on their own; clinicians see
/// the whole diary (the server scopes it by role).
class AppointmentRepository {
  AppointmentRepository(this._client);

  final ApiClient _client;

  /// The `Idempotency-Key` for one appointment write.
  ///
  /// A write whose answer is lost — a timeout, a phone reconnecting, a token
  /// refreshed and the request sent again — reaches the server a second time.
  /// With the same key the server answers with what the first attempt did
  /// instead of doing it again: no second booking, no second message to the
  /// patient. See backend/src/middleware/idempotentWrite.js.
  ///
  /// [submission] is the screen's, where the same form can be sent again: tapped
  /// again with nothing changed, it is the same key. Without one the call still
  /// has a key of its own, which covers the retry this client makes by itself
  /// after refreshing an expired token.
  static Map<String, String> _keyed(
    String purpose,
    Object? body,
    SubmissionKeys? submission,
  ) => {'Idempotency-Key': (submission ?? SubmissionKeys()).keyFor(purpose, body)};

  Future<Paged<Appointment>> list({
    DateTime? from,
    DateTime? to,
    String? status,
    String? clinicId,
    String? patientId,
    int page = 1,
    int limit = 50,
  }) async {
    final json = await _client.getJson(
      '/appointments',
      query: {
        'page': page,
        'limit': limit,
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        if (status != null) 'status': status,
        if (clinicId != null) 'clinicId': clinicId,
        if (patientId != null) 'patientId': patientId,
      },
    );
    return Paged.fromJson(json, Appointment.fromJson);
  }

  /// Book a slot. [scheduledForIso] is the absolute ISO instant from the chosen
  /// [Slot]; the server re-validates it against the live schedule.
  /// Books a slot.
  ///
  /// [patientId] is for the front desk booking on somebody's behalf — the
  /// receptionist taking a call, or a walk-in at the window. A patient booking
  /// for themselves leaves it null and the server uses their own id; it ignores
  /// the field for patient callers anyway, so this cannot be used to book into
  /// another person's name.
  ///
  /// [clinicId] is null where the practice has no open location: the visit is
  /// at no location, and the server checks the doctor's own diary instead of a
  /// published schedule. Staff only — a patient books from published hours.
  Future<Appointment> book({
    required String? clinicId,
    required String scheduledForIso,
    String mode = 'in_clinic',
    String? reason,
    String? patientId,
    /// Which of the practice's services, where it charges for them. The amount
    /// is deliberately not sent: the server reads it off its own row, so a
    /// client cannot name a cheaper price.
    String? serviceId,
    SubmissionKeys? submission,
  }) async {
    final body = {
      if (clinicId != null) 'clinicId': clinicId,
      'scheduledFor': scheduledForIso,
      'mode': mode,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      if (patientId != null) 'patientId': patientId,
      if (serviceId != null) 'serviceId': serviceId,
    };
    final json = await _client.postJson(
      '/appointments',
      body: body,
      headers: _keyed('book', body, submission),
    );
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  /// Move a booking. The server keeps the original, cancelled, and returns the
  /// replacement — a confirmed booking with its own id.
  ///
  /// [clinicId] moves it to another of the practice's locations as well; null
  /// keeps it where it is.
  Future<Appointment> reschedule(
    String id,
    String scheduledForIso, {
    String? clinicId,
    SubmissionKeys? submission,
  }) async {
    final body = {
      'scheduledFor': scheduledForIso,
      if (clinicId != null) 'clinicId': clinicId,
    };
    final json = await _client.patchJson(
      '/appointments/$id/reschedule',
      body: body,
      headers: _keyed('move:$id', body, submission),
    );
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  Future<Appointment> cancel(
    String id, {
    String? reason,
    SubmissionKeys? submission,
  }) async {
    final body = {if (reason != null && reason.isNotEmpty) 'reason': reason};
    final json = await _client.patchJson(
      '/appointments/$id/cancel',
      body: body,
      headers: _keyed('cancel:$id', body, submission),
    );
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  /// What the practice charges, for a screen about to book or about to pay.
  ///
  /// An empty list is the normal state and not a failure: every clinic here
  /// takes money at the desk today, and nothing in the app has ever recorded
  /// it. See backend/src/routes/services.js.
  Future<List<ClinicService>> services({bool includeWithdrawn = false}) async {
    final json = await _client.getJson(
      '/doctor/services',
      query: {if (includeWithdrawn) 'includeWithdrawn': '1'},
    );
    return [
      for (final r in (json['items'] as List? ?? const []))
        if (r is Map<String, dynamic>) ClinicService.fromJson(r),
    ];
  }

  Future<ClinicService> saveService({
    String? id,
    required String name,
    required String mode,
    required int amountPaise,
    int? durationMinutes,
    String? note,
    bool? isActive,
    SubmissionKeys? submission,
  }) async {
    final body = {
      'name': name,
      'mode': mode,
      'amountPaise': amountPaise,
      // Sent only when there is one. A null here means "clear it", and the
      // only screen that saves a service has no field for a duration — so
      // sending null unasked would wipe one set anywhere else.
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
      // Null on purpose where the note was emptied: that is the clear.
      'note': note,
      if (isActive != null) 'isActive': isActive,
    };
    final json = id == null
        ? await _client.postJson(
            '/doctor/services',
            body: body,
            headers: _keyed('service', body, submission),
          )
        : await _client.patchJson(
            '/doctor/services/$id',
            body: body,
            headers: _keyed('service:$id', body, submission),
          );
    return ClinicService.fromJson(json['service'] as Map<String, dynamic>);
  }

  /// Removes it, or withdraws it where appointments were booked against it.
  ///
  /// The server decides which: a service a booking refers to is kept, because
  /// the booking's own copy of the amount is a figure and the row is what says
  /// what the figure was for. [DeletedService.message] carries its words.
  Future<DeletedService> deleteService(String id) async {
    final json = await _client.deleteJson('/doctor/services/$id');
    return DeletedService(
      withdrawn: json['withdrawn'] == true,
      message: json['message']?.toString(),
    );
  }

  /// Start a payment for an appointment's fee.
  ///
  /// Asked twice, the server answers with the order the first call made — two
  /// live orders for one appointment is how somebody pays twice.
  Future<FeeOrder> feeOrder(String appointmentId) async {
    final json = await _client.postJson('/appointments/$appointmentId/fee/order');
    return FeeOrder.fromJson(json);
  }

  /// Hand the checkout's three fields back for the signature to be checked.
  ///
  /// Nothing is paid until this returns: the SDK reporting success on a phone
  /// is not money, and the server believes the signature rather than the app.
  Future<Appointment> verifyFee(
    String appointmentId, {
    required String paymentId,
    required String signature,
    String? orderId,
  }) async {
    final json = await _client.postJson(
      '/appointments/$appointmentId/fee/verify',
      body: {
        'paymentId': paymentId,
        'signature': signature,
        if (orderId != null) 'orderId': orderId,
      },
    );
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  /// Ask to be told when a slot frees up on a day that is currently full.
  /// [dateKey] is `yyyy-MM-dd`; the server records the request and pushes the
  /// patient the moment a slot on that day opens.
  Future<void> joinWaitlist({
    required String clinicId,
    required String dateKey,
  }) async {
    await _client.postJson(
      '/appointments/waitlist',
      body: {'clinicId': clinicId, 'date': dateKey},
    );
  }

  /// Clinician-only: advance the appointment's status (confirm, complete, …)
  /// and optionally attach consultation notes.
  /// Ask the clinic for an appointment without choosing a slot.
  ///
  /// The other path — picking a free time from the published schedule —
  /// confirms immediately. This one creates a request the desk answers, for
  /// the patient who would rather say "Tuesday" than read a timetable.
  Future<Appointment> requestAppointment({
    required DateTime preferredFor,
    /// 'HH:mm', or null for "any time" — which is a real answer, and the one
    /// most patients mean. The desk still picks from the doctor's real hours;
    /// this only says which end of the day to look at first.
    String? preferredTime,
    String reason = '',
    SubmissionKeys? submission,
  }) async {
    final body = {
      // Date only, at local midnight. Sending the instant would shift the
      // day across the timezone boundary for anyone asking late at night.
      'preferredFor':
          DateTime(
            preferredFor.year,
            preferredFor.month,
            preferredFor.day,
          ).toIso8601String(),
      if (preferredTime != null) 'preferredTime': preferredTime,
      if (reason.isNotEmpty) 'reason': reason,
    };
    final json = await _client.postJson(
      '/appointments/request',
      body: body,
      headers: _keyed('ask', body, submission),
    );
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  /// Turn a request into a booking: give it a clinic and a time.
  ///
  /// One call, not reschedule-then-set-status. Reschedule validates the time
  /// against the appointment's existing clinic, and a request has none — so
  /// that route would skip slot validation and leave the row `requested` with a
  /// time on it, which is the state that holds a slot without being a booking.
  Future<Appointment> confirmRequest(
    String id, {
    /// Null where the practice has no open location to give.
    required String? clinicId,
    required DateTime scheduledFor,
    /// Sent only on a second attempt, after the desk has been shown that this
    /// patient already has a slot that day and has chosen to go ahead.
    bool allowSameDay = false,
    SubmissionKeys? submission,
  }) async {
    final body = {
      if (clinicId != null) 'clinicId': clinicId,
      'scheduledFor': scheduledFor.toUtc().toIso8601String(),
      if (allowSameDay) 'allowSameDay': true,
    };
    final json = await _client.patchJson(
      '/appointments/$id/confirm',
      body: body,
      headers: _keyed('confirm:$id', body, submission),
    );
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  Future<Appointment> setStatus(
    String id,
    String status, {
    String? consultationNotes,
  }) async {
    final json = await _client.patchJson(
      '/appointments/$id/status',
      body: {
        'status': status,
        if (consultationNotes != null && consultationNotes.isNotEmpty)
          'consultationNotes': consultationNotes,
      },
    );
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }
}

final Provider<AppointmentRepository> appointmentRepositoryProvider =
    Provider<AppointmentRepository>((ref) {
      return AppointmentRepository(ref.watch(apiClientProvider));
    });
