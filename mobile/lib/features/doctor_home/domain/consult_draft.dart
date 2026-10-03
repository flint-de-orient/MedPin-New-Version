import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../medications/domain/med_shorthand.dart';

/// What a consultation is, before it becomes a prescription.
///
/// ---- Why this is data and not a screen -------------------------------------
///
/// The consult writes a prescription: the one act in this app that a patient
/// takes home and follows for a month. Everything about what gets sent — which
/// medicines, in what shorthand, which tests, how long it stands for — is here,
/// away from the widgets, so it can be tested without pumping a screen and so
/// the draft can be written to disk and read back as itself.
///
/// ---- The draft is on this phone, and says so -------------------------------
///
/// The artboard's header says "draft saved". This server has no draft: a
/// prescription exists when it is issued, and nothing before that. So the draft
/// is kept in this phone's own storage, per patient, and the screen says where
/// it is. A doctor interrupted mid-consult gets their work back; a doctor who
/// picks up another phone does not, and is not told otherwise.

/// One line of a prescription.
class MedLine {
  const MedLine({
    required this.name,
    this.strength = '',
    this.frequency = DoseFrequency.od,
    this.relation = MealRelation.after,
    this.route = MedRoute.oral,
    this.durationDays,
    this.instructions = '',
  });

  final String name;
  final String strength;
  final DoseFrequency frequency;
  final MealRelation relation;
  final MedRoute route;
  final int? durationDays;
  final String instructions;

  MedLine copyWith({
    String? name,
    String? strength,
    DoseFrequency? frequency,
    MealRelation? relation,
    MedRoute? route,
    int? durationDays,
    bool clearDuration = false,
    String? instructions,
  }) => MedLine(
    name: name ?? this.name,
    strength: strength ?? this.strength,
    frequency: frequency ?? this.frequency,
    relation: relation ?? this.relation,
    route: route ?? this.route,
    durationDays: clearDuration ? null : (durationDays ?? this.durationDays),
    instructions: instructions ?? this.instructions,
  );

  /// The title on the card: what is being prescribed.
  String get title => [name.trim(), strength.trim()].where((s) => s.isNotEmpty).join(' ');

  /// "Twice a day · after food" — how to take it, in words rather than codes,
  /// because the codes are for the pad and this is for reading back.
  String get doseLine => [
    frequency.plain,
    if (frequency.takesMealRelation) relation.plain,
  ].join(' · ');

  /// "30 days · oral" — how long, and by what route when it is not the usual.
  String get metaLine => [
    if (durationDays != null) '$durationDays days',
    if (route != MedRoute.oral) route.plain,
    if (instructions.trim().isNotEmpty) instructions.trim(),
  ].join(' · ');

  /// What goes to the server, in the shape `createPrescription` sends.
  Map<String, dynamic> toItem() => {
    'name': name.trim(),
    if (strength.trim().isNotEmpty) 'strength': strength.trim(),
    'frequency': frequency.apiFrequency,
    'relationToMeal': relation.api,
    'route': route.api,
    if (durationDays != null) 'durationDays': durationDays,
    if (instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
  };

  Map<String, dynamic> toJson() => {
    'name': name,
    'strength': strength,
    'frequency': frequency.name,
    'relation': relation.name,
    'route': route.name,
    'durationDays': durationDays,
    'instructions': instructions,
  };

  factory MedLine.fromJson(Map<String, dynamic> j) => MedLine(
    name: j['name']?.toString() ?? '',
    strength: j['strength']?.toString() ?? '',
    frequency: DoseFrequency.values.firstWhere(
      (f) => f.name == j['frequency'],
      orElse: () => DoseFrequency.od,
    ),
    relation: MealRelation.values.firstWhere(
      (r) => r.name == j['relation'],
      orElse: () => MealRelation.after,
    ),
    route: MedRoute.values.firstWhere(
      (r) => r.name == j['route'],
      orElse: () => MedRoute.oral,
    ),
    durationDays: (j['durationDays'] as num?)?.toInt(),
    instructions: j['instructions']?.toString() ?? '',
  );
}

/// The whole consultation, as it stands.
class ConsultDraft {
  const ConsultDraft({
    this.complaint = '',
    this.diagnoses = const [],
    this.medicines = const [],
    this.labs = const [],
    this.advice = const [],
    this.ownAdvice = '',
    this.validDays,
    this.followUpOn,
  });

  final String complaint;
  final List<String> diagnoses;
  final List<MedLine> medicines;
  final List<String> labs;

  /// Advice picked off the catalogue, in the order it was picked.
  final List<String> advice;

  /// Whatever the doctor wrote themselves, kept apart from the catalogue so
  /// unticking a snippet never eats a sentence they typed.
  final String ownAdvice;

  /// How long the prescription stands for, in days. Null means the server's
  /// own default rather than a promise this screen invented.
  final int? validDays;

  final DateTime? followUpOn;

  ConsultDraft copyWith({
    String? complaint,
    List<String>? diagnoses,
    List<MedLine>? medicines,
    List<String>? labs,
    List<String>? advice,
    String? ownAdvice,
    int? validDays,
    bool clearValidity = false,
    DateTime? followUpOn,
    bool clearFollowUp = false,
  }) => ConsultDraft(
    complaint: complaint ?? this.complaint,
    diagnoses: diagnoses ?? this.diagnoses,
    medicines: medicines ?? this.medicines,
    labs: labs ?? this.labs,
    advice: advice ?? this.advice,
    ownAdvice: ownAdvice ?? this.ownAdvice,
    validDays: clearValidity ? null : (validDays ?? this.validDays),
    followUpOn: clearFollowUp ? null : (followUpOn ?? this.followUpOn),
  );

  /// Nothing has been written yet — nothing to save, nothing to lose.
  bool get isEmpty =>
      complaint.trim().isEmpty &&
      diagnoses.isEmpty &&
      medicines.isEmpty &&
      labs.isEmpty &&
      advice.isEmpty &&
      ownAdvice.trim().isEmpty &&
      validDays == null &&
      followUpOn == null;

  /// The advice as one block, the catalogue's sentences first and then the
  /// doctor's own — which is the order they read in.
  String get adviceText =>
      [...advice, if (ownAdvice.trim().isNotEmpty) ownAdvice.trim()].join('\n');

  /// When the prescription stops standing, counted from [now].
  DateTime? validUntil(DateTime now) =>
      validDays == null ? null : DateTime(now.year, now.month, now.day + validDays!);

  Map<String, dynamic> toJson() => {
    'complaint': complaint,
    'diagnoses': diagnoses,
    'medicines': [for (final m in medicines) m.toJson()],
    'labs': labs,
    'advice': advice,
    'ownAdvice': ownAdvice,
    'validDays': validDays,
    'followUpOn': followUpOn?.toIso8601String(),
  };

  factory ConsultDraft.fromJson(Map<String, dynamic> j) => ConsultDraft(
    complaint: j['complaint']?.toString() ?? '',
    diagnoses: [for (final d in (j['diagnoses'] as List? ?? const [])) '$d'],
    medicines: [
      for (final m in (j['medicines'] as List? ?? const []))
        if (m is Map<String, dynamic>) MedLine.fromJson(m),
    ],
    labs: [for (final l in (j['labs'] as List? ?? const [])) '$l'],
    advice: [for (final a in (j['advice'] as List? ?? const [])) '$a'],
    ownAdvice: j['ownAdvice']?.toString() ?? '',
    validDays: (j['validDays'] as num?)?.toInt(),
    followUpOn: DateTime.tryParse(j['followUpOn']?.toString() ?? ''),
  );
}

/// The draft on this phone, per patient.
///
/// Keyed by patient so two consultations in one clinic session cannot write
/// over each other, and cleared the moment the prescription is issued — a draft
/// that outlives what it became is the one a doctor sends twice.
class ConsultDrafts {
  const ConsultDrafts(this._prefs);

  final SharedPreferences _prefs;

  static String _key(String patientId) => 'consult_draft_$patientId';

  ConsultDraft? read(String patientId) {
    final raw = _prefs.getString(_key(patientId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return ConsultDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A draft written by an older build of this screen. Losing it is a
      // nuisance; crashing the consult it belongs to is not an option.
      return null;
    }
  }

  Future<void> write(String patientId, ConsultDraft draft) async {
    if (draft.isEmpty) return clear(patientId);
    await _prefs.setString(_key(patientId), jsonEncode(draft.toJson()));
  }

  Future<void> clear(String patientId) => _prefs.remove(_key(patientId));
}

/// Something worth saying out loud before this medicine is prescribed.
///
/// Only what is written on the record: the patient's own allergy list against
/// the name being prescribed. It does not know drug classes — that a
/// sulfonylurea is a sulfa derivative is exactly the kind of inference nothing
/// here is entitled to make — so it matches words, and says what it matched.
/// A doctor reading "this patient is recorded allergic to sulfa" can decide;
/// a doctor reading an invented class warning cannot tell what it knew.
String? cautionFor(String medicineName, List<String> allergies) {
  final name = medicineName.toLowerCase();
  if (name.trim().isEmpty) return null;

  for (final allergy in allergies) {
    final term = allergy.toLowerCase().trim();
    if (term.isEmpty) continue;
    // Both ways round: "Sulfa" against "Sulfamethoxazole", and
    // "Penicillin (amoxicillin)" against "Amoxicillin".
    final words = term.split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 3);
    final hit = name.contains(term) || words.any(name.contains);
    if (hit) {
      return 'This patient is recorded as allergic to $allergy. Check before prescribing.';
    }
  }
  return null;
}
