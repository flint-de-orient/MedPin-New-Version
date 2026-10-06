/// Matches the `User` object in API_CONTRACT.md §1.
/// One qualification, as the design lists them: the degree, where it was
/// taken, and when.
///
/// Separate from the printed `qualifications` line on purpose — a doctor who
/// wants "MBBS, MD (Medicine)" on their prescription is not served by it being
/// rebuilt out of rows.
class Degree {
  const Degree({required this.name, this.institution, this.year});

  final String name;
  final String? institution;
  final int? year;

  /// "Calcutta Medical College · 2008", or whichever half is on file.
  String? get where {
    final parts = [
      if ((institution ?? '').trim().isNotEmpty) institution!.trim(),
      if (year != null) '$year',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  factory Degree.fromJson(Map<String, dynamic> j) => Degree(
    name: j['name']?.toString() ?? '',
    institution: j['institution']?.toString(),
    year: (j['year'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'institution': institution,
    'year': year,
  };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    required this.language,
    this.email,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.avatarUrl,
    this.qualifications,
    this.specialty,
    this.registrationNo,
    this.signatureUrl,
    this.professionType,
    this.council,
    this.registrationYear,
    this.hprId,
    this.degrees = const [],
    this.specialisations = const [],
    this.conditionsTreated = const [],
    this.practisingSince,
    this.memberships = const [],
    this.bio,
    this.languages = const [],
    this.consent = const AccountConsent(),
    this.createdAt,
  });

  final String id;
  final String name;
  final String phone;
  final String? email;

  /// `patient` | `doctor` | `staff` (contract does not enumerate exhaustively;
  /// treated as an opaque string).
  final String role;

  /// `en` | `bn` | `hi`.
  final String language;

  final DateTime? dateOfBirth;

  /// `male` | `female` | `other`.
  final String? gender;

  /// The patient's home address — editable in Edit Profile.
  final String? address;

  /// Relative `/api/v1/uploads/:id/raw` path of the profile photo, or null.
  final String? avatarUrl;

  /// Doctor letterhead fields (null for patients/staff). `qualifications` like
  /// "MBBS, MD"; `registrationNo` the medical-council number; `signatureUrl` the
  /// uploaded signature image, embedded into prescription PDFs.
  final String? qualifications;
  final String? specialty;
  final String? registrationNo;
  final String? signatureUrl;

  /// The structured professional profile (`Profile-Professional`).
  ///
  /// `qualifications` above stays the line that prints on a prescription;
  /// these are read differently — a patient searching for "Type 2 diabetes"
  /// matches [conditionsTreated], not a sentence.
  final String? professionType;
  final String? council;
  final int? registrationYear;

  /// The ABDM Healthcare Professionals Registry id. A number somebody typed:
  /// nothing in this app asks the registry, so it is never shown as verified.
  final String? hprId;

  final List<Degree> degrees;
  final List<String> specialisations;
  final List<String> conditionsTreated;
  final int? practisingSince;
  final List<String> memberships;

  /// What a patient reads before booking.
  final String? bio;

  /// The languages this clinician consults in.
  final List<String> languages;

  /// What this account has agreed to, and when.
  final AccountConsent consent;

  final DateTime? createdAt;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email'] as String?,
      role: json['role']?.toString() ?? 'patient',
      language: json['language']?.toString() ?? 'en',
      dateOfBirth: _parseDate(json['dateOfBirth']),
      gender: json['gender'] as String?,
      address: json['address'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      qualifications: json['qualifications'] as String?,
      specialty: json['specialty'] as String?,
      registrationNo: json['registrationNo'] as String?,
      signatureUrl: json['signatureUrl'] as String?,
      professionType: json['professionType'] as String?,
      council: json['council'] as String?,
      registrationYear: (json['registrationYear'] as num?)?.toInt(),
      hprId: json['hprId'] as String?,
      degrees: [
        for (final d in (json['degrees'] as List? ?? const []))
          if (d is Map<String, dynamic>) Degree.fromJson(d),
      ],
      specialisations: _strings(json['specialisations']),
      conditionsTreated: _strings(json['conditionsTreated']),
      practisingSince: (json['practisingSince'] as num?)?.toInt(),
      memberships: _strings(json['memberships']),
      bio: json['bio'] as String?,
      languages: _strings(json['languages']),
      consent: AccountConsent.fromJson(json['consent']),
      createdAt: _parseDate(json['createdAt']),
    );
  }

  /// A list of strings from a server that may not have the field at all.
  static List<String> _strings(dynamic value) => [
    for (final v in (value as List? ?? const []))
      if (v != null && v.toString().trim().isNotEmpty) v.toString(),
  ];

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  AppUser copyWith({String? language, String? avatarUrl}) {
    return AppUser(
      id: id,
      name: name,
      phone: phone,
      role: role,
      language: language ?? this.language,
      email: email,
      dateOfBirth: dateOfBirth,
      gender: gender,
      address: address,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      qualifications: qualifications,
      specialty: specialty,
      registrationNo: registrationNo,
      signatureUrl: signatureUrl,
      createdAt: createdAt,
    );
  }
}

/// The three agreements an account carries, and the day each was given.
///
/// ---- Why these are shown rather than only stored ------------------------
///
/// They exist because the law requires a record of consent, and a record only
/// the database can read is one nobody can check. Every one of them is a date
/// or nothing: there is no "accepted" boolean to fall back on, so a missing
/// date is said as "not recorded" rather than guessed from the fact that the
/// person is clearly using the app.
class AccountConsent {
  const AccountConsent({this.terms, this.dataProcessing, this.aiDisclaimer});

  final DateTime? terms;
  final DateTime? dataProcessing;

  /// That answers from the assistant are not a diagnosis.
  final DateTime? aiDisclaimer;

  /// True when the server recorded none of the three — an account from before
  /// the field existed, which is not the same as somebody who refused.
  bool get isEmpty =>
      terms == null && dataProcessing == null && aiDisclaimer == null;

  factory AccountConsent.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return const AccountConsent();
    DateTime? at(String key) =>
        DateTime.tryParse(raw[key]?.toString() ?? '')?.toLocal();
    return AccountConsent(
      terms: at('termsAcceptedAt'),
      dataProcessing: at('dataProcessingAcceptedAt'),
      aiDisclaimer: at('aiDisclaimerAcceptedAt'),
    );
  }
}
