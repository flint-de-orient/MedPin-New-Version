/// The doctor's consultation MIS, as the server counts it.
///
/// ---- Two of the design's figures are not here ------------------------------
///
/// `Doctor-Reports` shows fees collected and referrals. Neither is recorded
/// anywhere in this system — there is no money against a patient, and nothing
/// writes down a referral — so the server does not send them and this does not
/// invent them. The screen says they are not recorded rather than showing a
/// zero, because a zero is a claim about the practice's month.
///
/// Average consultation time is here but may be null: it needs both ends of a
/// consultation, and the end was only recorded from the release that added it.
library;

class ReportCount {
  const ReportCount({required this.value, required this.previous});

  final int value;
  final int previous;

  int get change => value - previous;

  /// The change as a percentage of the previous window, or null when there is
  /// nothing to compare against — a first month has no "+12%".
  int? get percent => previous == 0 ? null : ((change / previous) * 100).round();

  factory ReportCount.fromJson(Map<String, dynamic> j) => ReportCount(
    value: (j['value'] as num?)?.toInt() ?? 0,
    previous: (j['previous'] as num?)?.toInt() ?? 0,
  );
}

/// How long a consultation takes, and how many it was worked out from.
class AverageConsult {
  const AverageConsult({required this.minutes, required this.from});

  /// Null while nothing has been timed.
  final int? minutes;

  /// The consultations that had both a start and an end.
  final int from;

  factory AverageConsult.fromJson(Map<String, dynamic> j) => AverageConsult(
    minutes: (j['value'] as num?)?.toInt(),
    from: (j['from'] as num?)?.toInt() ?? 0,
  );
}

class DayCount {
  const DayCount({required this.date, required this.count});

  final DateTime date;
  final int count;
}

class NamedCount {
  const NamedCount({required this.name, required this.count, this.id});

  final String name;
  final int count;
  final String? id;
}

class ConsultationSummary {
  const ConsultationSummary({
    required this.from,
    required this.to,
    required this.previousFrom,
    required this.previousTo,
    required this.consultations,
    required this.newPatients,
    required this.missed,
    required this.prescriptions,
    required this.average,
    required this.perDay,
    required this.byLocation,
    required this.byDiagnosis,
  });

  final DateTime from;
  final DateTime to;
  final DateTime previousFrom;
  final DateTime previousTo;

  final ReportCount consultations;
  final ReportCount newPatients;
  final ReportCount missed;
  final ReportCount prescriptions;
  final AverageConsult average;

  final List<DayCount> perDay;
  final List<NamedCount> byLocation;
  final List<NamedCount> byDiagnosis;

  /// How many consultations ended with a prescription, as a percentage — the
  /// design's "95% of consultations". Null when nobody was seen, because a
  /// share of nothing is not 0%.
  int? get prescribedShare => consultations.value == 0
      ? null
      : ((prescriptions.value / consultations.value) * 100).round();

  /// Nobody was seen, nothing was written. Worth saying as itself.
  bool get isEmpty =>
      consultations.value == 0 && prescriptions.value == 0 && missed.value == 0;

  factory ConsultationSummary.fromJson(Map<String, dynamic> j) {
    final kpis = j['kpis'] as Map<String, dynamic>? ?? const {};
    final previous = j['previous'] as Map<String, dynamic>? ?? const {};
    DateTime day(Object? v) => DateTime.tryParse('$v') ?? DateTime.now();

    return ConsultationSummary(
      from: day(j['from']),
      to: day(j['to']),
      previousFrom: day(previous['from']),
      previousTo: day(previous['to']),
      consultations: ReportCount.fromJson(
        kpis['consultations'] as Map<String, dynamic>? ?? const {},
      ),
      newPatients: ReportCount.fromJson(
        kpis['newPatients'] as Map<String, dynamic>? ?? const {},
      ),
      missed: ReportCount.fromJson(kpis['missed'] as Map<String, dynamic>? ?? const {}),
      prescriptions: ReportCount.fromJson(
        kpis['prescriptions'] as Map<String, dynamic>? ?? const {},
      ),
      average: AverageConsult.fromJson(
        kpis['averageMinutes'] as Map<String, dynamic>? ?? const {},
      ),
      perDay: [
        for (final d in (j['perDay'] as List? ?? const []))
          if (d is Map<String, dynamic>)
            DayCount(
              date: day(d['date']),
              count: (d['count'] as num?)?.toInt() ?? 0,
            ),
      ],
      byLocation: [
        for (final r in (j['byLocation'] as List? ?? const []))
          if (r is Map<String, dynamic>)
            NamedCount(
              id: r['clinicId']?.toString(),
              name: r['name']?.toString() ?? '',
              count: (r['count'] as num?)?.toInt() ?? 0,
            ),
      ],
      byDiagnosis: [
        for (final r in (j['byDiagnosis'] as List? ?? const []))
          if (r is Map<String, dynamic>)
            NamedCount(
              name: r['name']?.toString() ?? '',
              count: (r['count'] as num?)?.toInt() ?? 0,
            ),
      ],
    );
  }
}

/// One line of the consultation register.
class ConsultationRow {
  const ConsultationRow({
    required this.patientId,
    required this.patientName,
    required this.at,
    this.reason,
    this.clinicName,
    this.minutes,
  });

  final String? patientId;
  final String patientName;
  final DateTime at;
  final String? reason;
  final String? clinicName;
  final int? minutes;

  factory ConsultationRow.fromJson(Map<String, dynamic> j) => ConsultationRow(
    patientId: j['patientId']?.toString(),
    patientName: j['patientName']?.toString() ?? 'Patient',
    at: DateTime.tryParse(j['at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    reason: j['reason']?.toString(),
    clinicName: j['clinicName']?.toString(),
    minutes: (j['minutes'] as num?)?.toInt(),
  );
}

/// One line of the prescription register.
class PrescriptionRow {
  const PrescriptionRow({
    required this.patientId,
    required this.patientName,
    required this.at,
    required this.diagnosis,
    required this.medicines,
    required this.tests,
    this.followUpOn,
    required this.recordState,
  });

  final String? patientId;
  final String patientName;
  final DateTime at;
  final List<String> diagnosis;
  final int medicines;
  final int tests;
  final DateTime? followUpOn;

  /// `current`, or why it no longer stands.
  final String recordState;

  bool get stands => recordState == 'current';

  factory PrescriptionRow.fromJson(Map<String, dynamic> j) => PrescriptionRow(
    patientId: j['patientId']?.toString(),
    patientName: j['patientName']?.toString() ?? 'Patient',
    at: DateTime.tryParse(j['at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    diagnosis: [for (final d in (j['diagnosis'] as List? ?? const [])) '$d'],
    medicines: (j['medicines'] as num?)?.toInt() ?? 0,
    tests: (j['tests'] as num?)?.toInt() ?? 0,
    followUpOn: DateTime.tryParse(j['followUpOn']?.toString() ?? '')?.toLocal(),
    recordState: j['recordState']?.toString() ?? 'current',
  );
}

/// Who was asked back, and whether they came.
class FollowUpCompliance {
  const FollowUpCompliance({required this.items, required this.kept, required this.due});

  final List<FollowUpRow> items;

  /// Of those whose date has passed.
  final int kept;
  final int due;

  /// Null when nobody's follow-up has come due yet: a percentage of nothing
  /// would read as nobody coming back.
  int? get percent => due == 0 ? null : ((kept / due) * 100).round();

  factory FollowUpCompliance.fromJson(Map<String, dynamic> j) => FollowUpCompliance(
    items: [
      for (final r in (j['items'] as List? ?? const []))
        if (r is Map<String, dynamic>) FollowUpRow.fromJson(r),
    ],
    kept: (j['kept'] as num?)?.toInt() ?? 0,
    due: (j['due'] as num?)?.toInt() ?? 0,
  );
}

class FollowUpRow {
  const FollowUpRow({
    required this.patientId,
    required this.patientName,
    required this.dueOn,
    required this.came,
    required this.pending,
  });

  final String? patientId;
  final String patientName;
  final DateTime dueOn;
  final bool came;

  /// Their date is still ahead of them, so not coming back is not a miss.
  final bool pending;

  factory FollowUpRow.fromJson(Map<String, dynamic> j) => FollowUpRow(
    patientId: j['patientId']?.toString(),
    patientName: j['patientName']?.toString() ?? 'Patient',
    dueOn: DateTime.tryParse(j['dueOn']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    came: j['came'] == true,
    pending: j['pending'] == true,
  );
}
