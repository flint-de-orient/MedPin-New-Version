import 'package:flutter_test/flutter_test.dart';

import 'package:medpin/features/clinician/domain/appointment.dart';
import 'package:medpin/features/doctor_home/domain/consultation_report.dart';
import 'package:medpin/features/doctor_home/presentation/widgets/report_export.dart';
import 'package:medpin/shared/utils/csv.dart';

/// The tables the Reports and History tabs hand out.
///
/// The way a CSV goes wrong is silent: a free-text reason with a comma in it
/// ends the row early and shifts every column after it, in a file somebody
/// opens a week later and reads as the truth. So the escaping is tested, and
/// so is the one thing the figures must not do — print a nought where nothing
/// was recorded.

void main() {
  group('escaping', () {
    test('a plain value is left alone', () {
      expect(csvField('Follow-up'), 'Follow-up');
      expect(csvField(12), '12');
      expect(csvField(null), '');
    });

    test('a comma, a quote or a newline is quoted', () {
      expect(csvField('Fever, cough'), '"Fever, cough"');
      expect(csvField('He said "no"'), '"He said ""no"""');
      expect(csvField('line\nbreak'), '"line\nbreak"');
    });

    test('a row keeps its columns when a cell has a comma in it', () {
      expect(
        csvRow(['Priya Sharma', 'Fever, cough', 9]),
        'Priya Sharma,"Fever, cough",9',
        reason: 'three columns, not four',
      );
    });

    test('a table is CRLF, as the standard asks', () {
      expect(
        csvTable(['A', 'B'], [
          [1, 2],
        ]),
        'A,B\r\n1,2',
      );
    });
  });

  group('the history table', () {
    Appointment appointment(Map<String, dynamic> extra) => Appointment.fromJson({
      'id': 'a1',
      'patientId': 'p1',
      'patientName': 'Priya Sharma',
      'status': 'completed',
      'mode': 'in_person',
      'scheduledFor': DateTime(2026, 9, 30, 9, 14).toUtc().toIso8601String(),
      ...extra,
    });

    test('says the outcome in the word the screen uses', () {
      final csv = historyCsv([
        appointment({'status': 'no_show'}),
      ]);
      expect(csv, contains('Missed'));
      expect(
        csv,
        isNot(contains('no_show')),
        reason: 'the file is read by the same doctor as the screen',
      );
    });

    test('an untimed visit leaves the minutes blank, not nought', () {
      final csv = historyCsv([appointment(const {})]);
      expect(csv.trim().split('\r\n').last, endsWith(','));
    });

    test('a timed visit carries the minutes it took', () {
      final csv = historyCsv([
        appointment({
          'calledAt': DateTime(2026, 9, 30, 9, 14).toUtc().toIso8601String(),
          'completedAt': DateTime(2026, 9, 30, 9, 28).toUtc().toIso8601String(),
        }),
      ]);
      expect(csv.trim().split('\r\n').last, endsWith(',14'));
    });
  });

  group('the report table', () {
    ConsultationSummary summary({int? averageMinutes}) =>
        ConsultationSummary.fromJson({
          'from': '2026-09-01',
          'to': '2026-09-30',
          'previous': {'from': '2026-08-02', 'to': '2026-08-31'},
          'kpis': {
            'consultations': {'value': 286, 'previous': 255},
            'newPatients': {'value': 64, 'previous': 55},
            'missed': {'value': 21, 'previous': 18},
            'prescriptions': {'value': 271, 'previous': 240},
            'averageMinutes': {'value': averageMinutes, 'from': 250},
          },
          'perDay': [
            {'date': '2026-09-01', 'count': 10},
          ],
          'byLocation': [
            {'name': 'City Care, Salt Lake', 'count': 168},
          ],
          'byDiagnosis': const [],
        });

    test('carries the window it covers and the one it was compared with', () {
      final csv = reportCsv(summary());
      expect(csv, contains('This period,2026-09-01,2026-09-30'));
      expect(csv, contains('Compared with,2026-08-02,2026-08-31'));
    });

    test('an untimed month leaves the average blank rather than nought', () {
      expect(
        reportCsv(summary()),
        contains('Average consultation (minutes),,from 250 timed'),
      );
    });

    test('a timed month carries the figure', () {
      expect(reportCsv(summary(averageMinutes: 11)), contains(',11,from 250 timed'));
    });

    test('a location with a comma in its name stays one column', () {
      expect(reportCsv(summary()), contains('"City Care, Salt Lake",168'));
    });

    test('the filename says which window it is', () {
      expect(reportFilename(summary()), 'reports_2026-09-01_to_2026-09-30.csv');
    });
  });
}
