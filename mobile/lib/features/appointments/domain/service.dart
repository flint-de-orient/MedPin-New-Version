/// A consultation the practice offers, and what it charges for it.
///
/// ---- Paise, and why the screen never does the arithmetic -------------------
///
/// The amount crosses the wire as integer paise and is formatted for reading
/// once, here. A screen that divides by a hundred itself is a screen that will
/// one day print ₹499.99000000000001, and a fee is a number somebody is asked
/// to pay.
class ClinicService {
  const ClinicService({
    required this.id,
    required this.name,
    required this.mode,
    required this.amountPaise,
    this.durationMinutes,
    this.note,
    this.isActive = true,
    this.doctorId,
  });

  final String id;
  final String name;

  /// 'in_clinic', 'teleconsult' or 'both'.
  final String mode;

  final int amountPaise;
  final int? durationMinutes;
  final String? note;
  final bool isActive;

  /// One doctor's own rate, or null for the practice's.
  final String? doctorId;

  /// "₹500", "₹499.99". Zero is "Free", which is a price the clinic set.
  String get price => amountPaise == 0 ? 'Free' : '₹$rupees';

  String get rupees => amountPaise % 100 == 0
      ? '${amountPaise ~/ 100}'
      : (amountPaise / 100).toStringAsFixed(2);

  /// "In clinic", "Video", "In clinic or video".
  String get modeLabel => switch (mode) {
    'in_clinic' => 'In clinic',
    'teleconsult' => 'Video',
    _ => 'In clinic or video',
  };

  /// Whether this service can be booked for a visit of [visitMode].
  bool offeredFor(String visitMode) => mode == 'both' || mode == visitMode;

  factory ClinicService.fromJson(Map<String, dynamic> j) => ClinicService(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    mode: j['mode']?.toString() ?? 'both',
    amountPaise: (j['amountPaise'] as num?)?.toInt() ?? 0,
    durationMinutes: (j['durationMinutes'] as num?)?.toInt(),
    note: j['note']?.toString(),
    isActive: j['isActive'] != false,
    doctorId: j['doctorId']?.toString(),
  );
}

/// What an appointment costs, and whether it is settled.
///
/// ---- "not_required" is not "free" ------------------------------------------
///
/// It means the app does not collect for this visit. Every clinic here takes
/// money at the desk in cash today, so a booking with no fee on it is the
/// normal case — and a screen that printed "Free" over it would be telling the
/// patient something the desk is about to contradict.
class AppointmentFee {
  const AppointmentFee({this.amountPaise, this.status = 'not_required', this.paidAt});

  /// Null where the app does not collect for this visit.
  final int? amountPaise;

  /// 'not_required', 'pending', 'paid' or 'refunded'.
  final String status;

  final DateTime? paidAt;

  bool get owed => status == 'pending' && (amountPaise ?? 0) > 0;
  bool get paid => status == 'paid';

  /// Null where there is nothing to say, so a screen can leave the line out
  /// rather than print a reassuring blank.
  String? get line {
    final amount = amountPaise;
    if (amount == null || status == 'not_required') return null;
    final money = amount == 0
        ? 'No charge'
        : '₹${amount % 100 == 0 ? amount ~/ 100 : (amount / 100).toStringAsFixed(2)}';
    return switch (status) {
      'paid' => '$money paid',
      'pending' => amount == 0 ? money : '$money due',
      'refunded' => '$money refunded',
      _ => money,
    };
  }

  factory AppointmentFee.fromJson(Map<String, dynamic> j) => AppointmentFee(
    amountPaise: (j['amountPaise'] as num?)?.toInt(),
    status: j['status']?.toString() ?? 'not_required',
    paidAt: DateTime.tryParse(j['paidAt']?.toString() ?? '')?.toLocal(),
  );
}

/// An order this server created, for the checkout sheet to open.
///
/// The app never names the amount or the order: a client that could would name
/// a cheaper one.
class FeeOrder {
  const FeeOrder({
    required this.orderId,
    required this.amountPaise,
    required this.keyId,
  });

  final String orderId;
  final int amountPaise;

  /// Razorpay's public key id. Public by design — it names the account, not
  /// the secret that signs for it.
  final String keyId;

  factory FeeOrder.fromJson(Map<String, dynamic> j) => FeeOrder(
    orderId: j['orderId']?.toString() ?? '',
    amountPaise: (j['amountPaise'] as num?)?.toInt() ?? 0,
    keyId: j['keyId']?.toString() ?? '',
  );
}

/// What a delete actually did.
///
/// A service appointments were booked against is withdrawn, not removed —
/// their copy of the amount is a figure, and this row is what says what the
/// figure was for. The server decides which happened and says so in words the
/// screen can show.
class DeletedService {
  const DeletedService({required this.withdrawn, this.message});

  final bool withdrawn;
  final String? message;
}
