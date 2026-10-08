import 'package:flutter/foundation.dart';

/// One thing the practice has not filled in, and what it costs.
///
/// [prints] is the point of this class. "Registration number: missing" is a
/// form validation message; "prints under the signature, where the council
/// number must appear" tells a doctor why they should stop and fix it. The
/// server supplies the sentence because the rule is clinical, not visual.
@immutable
class PracticeGap {
  const PracticeGap({
    required this.key,
    required this.label,
    required this.prints,
    required this.blocking,
  });

  final String key;
  final String label;
  final String prints;

  /// True when a prescription is not a valid document without it.
  final bool blocking;

  factory PracticeGap.fromJson(Map<String, dynamic> json) => PracticeGap(
    key: json['key'] as String? ?? '',
    label: json['label'] as String? ?? '',
    prints: json['prints'] as String? ?? '',
    blocking: json['blocking'] as bool? ?? false,
  );
}

/// One place the practice sees patients.
@immutable
class PracticeLocation {
  const PracticeLocation({
    required this.id,
    required this.name,
    required this.city,
    required this.isActive,
    required this.overridesBrand,
    required this.weeklyHourCount,
  });

  final String id;
  final String name;
  final String? city;
  final bool isActive;

  /// This location prints its own name or logo rather than the practice's.
  /// Surfaced so a doctor can tell why two branches look different.
  final bool overridesBrand;

  final int weeklyHourCount;

  factory PracticeLocation.fromJson(Map<String, dynamic> json) => PracticeLocation(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    city: json['city'] as String?,
    isActive: json['isActive'] as bool? ?? true,
    overridesBrand: json['overridesBrand'] as bool? ?? false,
    weeklyHourCount: (json['weeklyHourCount'] as num?)?.toInt() ?? 0,
  );
}

/// The practice, its readiness, its places and its people.
@immutable
/// How patients may book, be reminded, and reach the clinic.
///
/// One set for the practice, not per location: a patient who may cancel two
/// hours before at Salt Lake and not at New Town is a patient who will ring
/// the desk to ask which.
///
/// Every default here is what the server already does, so a practice that has
/// never opened the screen reads as today's behaviour rather than as nothing.
class PracticeRules {
  const PracticeRules({
    this.onlineBooking = true,
    this.bookingWindowDays,
    this.cancelCutoffHours,
    this.reminderDaysBefore = 3,
    this.reminderChannels = const ['app'],
    this.messagingAlways = true,
    this.messagingFrom,
    this.messagingTo,
    this.urgentAlways = true,
  });

  /// False closes online booking without touching the published hours.
  final bool onlineBooking;

  /// How far ahead a slot may be taken. Null is no limit.
  final int? bookingWindowDays;

  /// How close to the appointment a patient may still call it off. Null is
  /// any time, which is what cancel does today.
  final int? cancelCutoffHours;

  final int reminderDaysBefore;

  /// 'app', 'whatsapp', 'sms'. The app is the one channel that always exists.
  final List<String> reminderChannels;

  final bool messagingAlways;

  /// 'HH:mm', when [messagingAlways] is false.
  final String? messagingFrom;
  final String? messagingTo;

  /// Urgent messages ignore the hours. A patient who says they cannot breathe
  /// is not waiting for nine o'clock.
  final bool urgentAlways;

  /// "Any time", "7 days ahead".
  String get windowLine =>
      bookingWindowDays == null ? 'Any time' : '$bookingWindowDays days ahead';

  /// "Any time", "4 hours before".
  String get cancelLine => cancelCutoffHours == null
      ? 'Any time'
      : '$cancelCutoffHours ${cancelCutoffHours == 1 ? 'hour' : 'hours'} before';

  /// "All day", "9:00 AM – 6:00 PM".
  String get messagingLine =>
      messagingAlways || messagingFrom == null || messagingTo == null
      ? 'All day'
      : '$messagingFrom – $messagingTo';

  factory PracticeRules.fromJson(Map<String, dynamic> p) {
    final booking = p['booking'] as Map<String, dynamic>? ?? const {};
    final reminder = p['followUpReminder'] as Map<String, dynamic>? ?? const {};
    final messaging = p['patientMessaging'] as Map<String, dynamic>? ?? const {};
    return PracticeRules(
      onlineBooking: booking['online'] != false,
      bookingWindowDays: (booking['windowDays'] as num?)?.toInt(),
      cancelCutoffHours: (booking['cancelCutoffHours'] as num?)?.toInt(),
      reminderDaysBefore: (reminder['daysBefore'] as num?)?.toInt() ?? 3,
      reminderChannels: [
        for (final c in (reminder['channels'] as List? ?? const ['app']))
          if (c != null) c.toString(),
      ],
      messagingAlways: messaging['always'] != false,
      messagingFrom: messaging['from']?.toString(),
      messagingTo: messaging['to']?.toString(),
      urgentAlways: messaging['urgentAlways'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    'booking': {
      'online': onlineBooking,
      'windowDays': bookingWindowDays,
      'cancelCutoffHours': cancelCutoffHours,
    },
    'followUpReminder': {
      'daysBefore': reminderDaysBefore,
      'channels': reminderChannels,
    },
    'patientMessaging': {
      'always': messagingAlways,
      'from': messagingFrom,
      'to': messagingTo,
      'urgentAlways': urgentAlways,
    },
  };

  PracticeRules copyWith({
    bool? onlineBooking,
    int? Function()? bookingWindowDays,
    int? Function()? cancelCutoffHours,
    int? reminderDaysBefore,
    List<String>? reminderChannels,
    bool? messagingAlways,
    String? Function()? messagingFrom,
    String? Function()? messagingTo,
    bool? urgentAlways,
  }) => PracticeRules(
    onlineBooking: onlineBooking ?? this.onlineBooking,
    // A function, not a value: null has to mean "no limit" as well as "leave
    // it alone", and a plain nullable cannot say both.
    bookingWindowDays: bookingWindowDays == null
        ? this.bookingWindowDays
        : bookingWindowDays(),
    cancelCutoffHours: cancelCutoffHours == null
        ? this.cancelCutoffHours
        : cancelCutoffHours(),
    reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
    reminderChannels: reminderChannels ?? this.reminderChannels,
    messagingAlways: messagingAlways ?? this.messagingAlways,
    messagingFrom: messagingFrom == null ? this.messagingFrom : messagingFrom(),
    messagingTo: messagingTo == null ? this.messagingTo : messagingTo(),
    urgentAlways: urgentAlways ?? this.urgentAlways,
  );
}

class PracticeOverview {
  const PracticeOverview({
    required this.id,
    required this.name,
    required this.tagline,
    required this.doctorDisplayName,
    required this.registrationNo,
    this.emergencyPhone,
    required this.logoLightUrl,
    required this.verification,
    required this.gaps,
    required this.canPrintPrescription,
    required this.locations,
    required this.doctors,
    required this.staff,
    required this.dieticians,
    this.rules = const PracticeRules(),
    this.payout = const PayoutAccount(),
  });

  final String id;
  final String name;
  final String? tagline;
  final String? doctorDisplayName;
  final String? registrationNo;

  /// The number this practice's patients ring, or null when it has not set
  /// one. The practice's own — never a location's standing in for it.
  final String? emergencyPhone;

  final String? logoLightUrl;
  final String verification;

  final List<PracticeGap> gaps;
  final bool canPrintPrescription;
  final List<PracticeLocation> locations;
  final int doctors;
  final int staff;
  final int dieticians;

  /// How patients may book, be reminded, and reach the clinic.
  final PracticeRules rules;

  /// Where this practice's share of the online fees is sent.
  final PayoutAccount payout;

  bool get isComplete => gaps.isEmpty;

  /// The gaps that stop a prescription being valid, worst first.
  List<PracticeGap> get blockingGaps => gaps.where((g) => g.blocking).toList();
  List<PracticeGap> get minorGaps => gaps.where((g) => !g.blocking).toList();

  factory PracticeOverview.fromJson(Map<String, dynamic> json) {
    final p = json['practice'] as Map<String, dynamic>? ?? const {};
    final r = json['readiness'] as Map<String, dynamic>? ?? const {};
    final people = json['people'] as Map<String, dynamic>? ?? const {};

    return PracticeOverview(
      id: p['id'] as String? ?? '',
      name: p['name'] as String? ?? '',
      tagline: p['tagline'] as String?,
      doctorDisplayName: p['doctorDisplayName'] as String?,
      registrationNo: p['registrationNo'] as String?,
      emergencyPhone: p['emergencyPhone'] as String?,
      logoLightUrl: p['logoLightUrl'] as String?,
      verification: p['verification'] as String? ?? 'unverified',
      gaps:
          (r['missing'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(PracticeGap.fromJson)
              .toList(),
      canPrintPrescription: r['canPrintPrescription'] as bool? ?? true,
      locations:
          (json['locations'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(PracticeLocation.fromJson)
              .toList(),
      doctors: (people['doctors'] as num?)?.toInt() ?? 0,
      staff: (people['staff'] as num?)?.toInt() ?? 0,
      dieticians: (people['dieticians'] as num?)?.toInt() ?? 0,
      rules: PracticeRules.fromJson(p),
      payout: PayoutAccount.fromJson(p['payout']),
    );
  }
}

/// Where a practice's money is sent, as much of it as leaves the server.
///
/// ---- Why there is no account number here --------------------------------
///
/// The server never sends one. It is stored `select: false` and only the last
/// four digits come back — see the note on `payout` in models/Practice.js. A
/// clinic checking they typed the right account reads four digits; nobody
/// needs the whole number back, and a number that can be read is a number
/// that ends up in a log or a screenshot.
///
/// So changing the account means typing it again, and this class has no field
/// to pre-fill a box with. That is the design, not a gap.
class PayoutAccount {
  const PayoutAccount({
    this.accountName,
    this.accountLast4,
    this.ifsc,
    this.bankName,
    this.upiId,
    this.verifiedAt,
    this.updatedAt,
    this.onFile = false,
  });

  final String? accountName;

  /// The last four digits of the account number, for checking against a
  /// passbook. Null on a UPI-only arrangement.
  final String? accountLast4;

  final String? ifsc;
  final String? bankName;
  final String? upiId;

  /// When MedPin last confirmed a transfer actually reached it.
  ///
  /// Set by an operator and never by the clinic: a practice that could mark
  /// its own account verified could mark a wrong one verified.
  final DateTime? verifiedAt;

  final DateTime? updatedAt;

  /// Whether there is anywhere to send money at all.
  final bool onFile;

  /// The account in one line, for a row that shows it rather than edits it.
  String get line {
    if (!onFile) return 'Not set';
    final bank = [
      if ((bankName ?? '').isNotEmpty) bankName!,
      if ((accountLast4 ?? '').isNotEmpty) '••••$accountLast4',
    ].join(' ');
    if (bank.isNotEmpty) return bank;
    return upiId ?? 'Not set';
  }

  factory PayoutAccount.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return const PayoutAccount();
    DateTime? at(String key) =>
        DateTime.tryParse(raw[key]?.toString() ?? '')?.toLocal();
    String? text(String key) {
      final v = raw[key]?.toString();
      return (v == null || v.isEmpty) ? null : v;
    }

    return PayoutAccount(
      accountName: text('accountName'),
      accountLast4: text('accountLast4'),
      ifsc: text('ifsc'),
      bankName: text('bankName'),
      upiId: text('upiId'),
      verifiedAt: at('verifiedAt'),
      updatedAt: at('updatedAt'),
      onFile: raw['onFile'] == true,
    );
  }
}
