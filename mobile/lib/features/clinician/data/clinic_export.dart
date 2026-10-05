import 'dart:convert';

import '../domain/clinician_models.dart';
import '../../../shared/utils/csv.dart';

/// Turns the clinic's records into a file the doctor can keep.
///
/// Pure string-building, deliberately: no I/O, no widgets, no providers. The
/// screen fetches, this formats, and something else writes the bytes — which
/// is what makes the escaping below testable rather than something you find
/// out about when a patient with a comma in their address corrupts a column.
///
/// A word on what this is. The file contains named patients with phone numbers
/// and clinical readings, so it is a copy of the clinic's record leaving the
/// clinic's control. Every path here goes through the OS share sheet, meaning
/// the doctor chooses the destination explicitly each time and nothing is ever
/// written somewhere an app could quietly read it.
enum ExportFormat {
  csv('CSV', 'csv', 'text/csv'),
  json('JSON', 'json', 'application/json');

  const ExportFormat(this.label, this.extension, this.mime);

  final String label;
  final String extension;
  final String mime;
}

enum ExportDataset {
  patients('Patients', 'Name, contact, risk band, HbA1c, last reading'),
  alerts('Clinical alerts', 'Open alerts with severity and what raised them'),
  summary('Clinic summary', 'The headline counts and monitoring figures');

  const ExportDataset(this.label, this.detail);

  final String label;
  final String detail;
}

/// The escaping moved to shared/utils/csv.dart when the Reports and History
/// tabs started handing out tables of their own. One copy of it, because the
/// way it goes wrong is silent: a note with a comma in it ends the row early
/// and shifts every column after it.
String _csvRow(List<Object?> cells) => csvRow(cells);

String _iso(DateTime? d) => d?.toIso8601String() ?? '';

class ClinicExport {
  const ClinicExport({
    required this.format,
    required this.datasets,
    this.patients = const [],
    this.alerts = const [],
    this.overview,
    this.analytics,
    required this.generatedAt,
    this.clinicianName = '',
  });

  final ExportFormat format;
  final Set<ExportDataset> datasets;
  final List<PatientListItem> patients;
  final List<ClinicalAlert> alerts;
  final ClinicOverview? overview;
  final ClinicAnalytics? analytics;
  final DateTime generatedAt;
  final String clinicianName;

  String get filename {
    final d = generatedAt;
    final stamp =
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'
        '-${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';
    return 'medpin-export-$stamp.${format.extension}';
  }

  String build() => switch (format) {
    ExportFormat.csv => _buildCsv(),
    ExportFormat.json => _buildJson(),
  };

  // ------------------------------------------------------------------ csv

  /// CSV has no notion of several tables in one file, so when more than one
  /// dataset is selected each gets a titled block separated by a blank line.
  /// A spreadsheet opens it; a parser can split on the blank lines.
  String _buildCsv() {
    final blocks = <String>[];

    if (datasets.contains(ExportDataset.summary) && overview != null) {
      final o = overview!;
      final rows = <List<Object?>>[
        ['Metric', 'Value'],
        ['Total patients', o.patientCount],
        ['New patients today', o.newPatientsToday],
        ['Flagged chats', o.pendingReviews],
        ['Unread messages', o.unreadMessages],
        ['Unread nutrition messages', o.unreadNutrition],
        ['Open alerts', o.totalOpenAlerts],
        ['Emergency alerts', o.emergencyAlerts],
        ['Urgent alerts', o.urgentAlerts],
        ['Risk — critical', o.riskCritical],
        ['Risk — high', o.riskHigh],
        ['Risk — moderate', o.riskModerate],
        ['Risk — low', o.riskLow],
        if (analytics != null) ...[
          ['Check-ins overdue', analytics!.overdueCheckIns],
          ['Never checked in', analytics!.neverCheckedIn],
          ['Trending worse', analytics!.trendingWorse],
          ['Active patients', analytics!.activePatients],
        ],
      ];
      blocks.add('# Clinic summary\n${rows.map(_csvRow).join('\n')}');
    }

    if (datasets.contains(ExportDataset.patients)) {
      final rows = <List<Object?>>[
        [
          'Patient ID',
          'Name',
          'Phone',
          'Risk band',
          'Risk score',
          'HbA1c (%)',
          'HbA1c taken',
          'Last reading (mg/dL)',
          'Last reading at',
          'Trend',
          'Open alerts',
          'Check-in overdue',
          'Check-in interval (days)',
        ],
        for (final p in patients)
          [
            p.id,
            p.name,
            p.phone,
            p.riskBand,
            p.riskScore,
            p.hba1c ?? '',
            _iso(p.hba1cAt),
            p.lastReadingValue ?? '',
            _iso(p.lastReadingAt),
            p.trend,
            p.openAlertCount,
            p.checkInOverdue ? 'yes' : 'no',
            p.checkInIntervalDays ?? '',
          ],
      ];
      blocks.add(
        '# Patients (${patients.length})\n${rows.map(_csvRow).join('\n')}',
      );
    }

    if (datasets.contains(ExportDataset.alerts)) {
      final rows = <List<Object?>>[
        [
          'Alert ID',
          'Patient',
          'Type',
          'Severity',
          'Status',
          'Raised at',
          'Title',
          'Detail',
          'Matched rules',
        ],
        for (final a in alerts)
          [
            a.id,
            a.patientName ?? '',
            a.type,
            a.severity,
            a.status,
            _iso(a.createdAt),
            a.title,
            a.detail ?? '',
            a.matchedRules.join(' | '),
          ],
      ];
      blocks.add(
        '# Clinical alerts (${alerts.length})\n${rows.map(_csvRow).join('\n')}',
      );
    }

    final header =
        '# MedPin export\n'
        '# Generated,${csvField(_iso(generatedAt))}\n'
        '# Clinician,${csvField(clinicianName)}\n'
        '# Contains identifiable patient data — handle as clinical records\n';

    return '$header\n${blocks.join('\n\n')}\n';
  }

  // ----------------------------------------------------------------- json

  String _buildJson() {
    final out = <String, dynamic>{
      'export': {
        'app': 'MedPin',
        'generatedAt': _iso(generatedAt),
        'clinician': clinicianName,
        'datasets': datasets.map((d) => d.name).toList(),
        'notice':
            'Contains identifiable patient data — handle as clinical records.',
      },
    };

    if (datasets.contains(ExportDataset.summary) && overview != null) {
      final o = overview!;
      out['summary'] = {
        'patients': o.patientCount,
        'newPatientsToday': o.newPatientsToday,
        'flaggedChats': o.pendingReviews,
        'unreadMessages': o.unreadMessages,
        'unreadNutrition': o.unreadNutrition,
        'alerts': {
          'open': o.totalOpenAlerts,
          'emergency': o.emergencyAlerts,
          'urgent': o.urgentAlerts,
          'warning': o.warningAlerts,
        },
        'risk': {
          'critical': o.riskCritical,
          'high': o.riskHigh,
          'moderate': o.riskModerate,
          'low': o.riskLow,
        },
        if (analytics != null)
          'monitoring': {
            'overdueCheckIns': analytics!.overdueCheckIns,
            'neverCheckedIn': analytics!.neverCheckedIn,
            'trendingWorse': analytics!.trendingWorse,
            'activePatients': analytics!.activePatients,
          },
      };
    }

    if (datasets.contains(ExportDataset.patients)) {
      out['patients'] = [
        for (final p in patients)
          {
            'id': p.id,
            'name': p.name,
            'phone': p.phone,
            'risk': {'band': p.riskBand, 'score': p.riskScore},
            'hba1c': {'value': p.hba1c, 'takenAt': _iso(p.hba1cAt)},
            'lastReading': {
              'value': p.lastReadingValue,
              'at': _iso(p.lastReadingAt),
            },
            'trend': p.trend,
            'trendDelta': p.trendDelta,
            'openAlerts': p.openAlertCount,
            'checkIn': {
              'overdue': p.checkInOverdue,
              'intervalDays': p.checkInIntervalDays,
            },
          },
      ];
    }

    if (datasets.contains(ExportDataset.alerts)) {
      out['alerts'] = [
        for (final a in alerts)
          {
            'id': a.id,
            'patient': a.patientName,
            'type': a.type,
            'severity': a.severity,
            'status': a.status,
            'createdAt': _iso(a.createdAt),
            'title': a.title,
            'detail': a.detail,
            // The rules that fired. This is the audit trail for why the
            // clinic was alerted, and it is the part a reviewer asks for.
            'matchedRules': a.matchedRules,
          },
      ];
    }

    // Indented: the file is meant to be opened and read, not only parsed.
    return const JsonEncoder.withIndent('  ').convert(out);
  }
}
