import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../../shared/utils/csv.dart';
import '../../../clinician/domain/appointment.dart';
import '../../domain/consultation_report.dart';
import '../doctor_history_screen.dart';

/// The outline button the Reports and History headers both carry.
///
/// One widget for both because they are the same act under two words — the
/// artboard says "Export" over the MIS and "Download" over the diary, and a
/// doctor who learns one should not have to learn the other.
class ExportButton extends StatelessWidget {
  const ExportButton({super.key, required this.label, required this.onPressed});

  final String label;

  /// Null while there is nothing to hand over; the button then reads as off
  /// rather than disappearing, so its place on the screen stays put.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.file_download_outlined, size: D.iconMd),
      label: Text(label, style: D.dateLine),
      style: OutlinedButton.styleFrom(
        foregroundColor: D.ink,
        disabledForegroundColor: D.inkFaint,
        side: const BorderSide(color: D.lineStrong),
        minimumSize: Size(0, MediaQuery.textScalerOf(context).scale(D.tap - D.s2)),
        padding: EdgeInsets.symmetric(horizontal: D.s3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
      ),
    );
  }
}

/// Handing a table to the doctor.
///
/// ---- Where the file goes ---------------------------------------------------
///
/// Into the app's temporary directory and straight to the OS share sheet, which
/// is the same path the clinic export takes and for the same reason: these rows
/// have named patients on them, so the doctor picks the destination every time
/// and nothing lands somewhere another app can read unasked.
///
/// "Export" and "Download" are the same act on a phone — Save to Files is in
/// that sheet, next to sending it on.
Future<void> shareTable(
  BuildContext context, {
  required String filename,
  required String csv,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: filename),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not build the file. $e')));
  }
}

String _day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// The MIS as a table: the figures, then the two splits beneath them.
///
/// One file rather than three, with a blank line between blocks — a spreadsheet
/// opens it and a parser can split on the gaps. It carries the window and the
/// window it was compared with, because a figure without its dates is a number
/// somebody will later mis-remember.
String reportCsv(ConsultationSummary r) {
  final blocks = <String>[
    csvTable(
      ['Window', 'From', 'To'],
      [
        ['This period', _day(r.from), _day(r.to)],
        ['Compared with', _day(r.previousFrom), _day(r.previousTo)],
      ],
    ),
    csvTable(
      ['Figure', 'This period', 'Period before'],
      [
        ['Consultations', r.consultations.value, r.consultations.previous],
        ['New patients', r.newPatients.value, r.newPatients.previous],
        ['Missed appointments', r.missed.value, r.missed.previous],
        ['Prescriptions', r.prescriptions.value, r.prescriptions.previous],
        // Blank rather than nought where nothing was timed: the file is read
        // long after the screen that explained it.
        [
          'Average consultation (minutes)',
          r.average.minutes ?? '',
          'from ${r.average.from} timed',
        ],
      ],
    ),
    // Paise, not the formatted rupees on the screen. A spreadsheet is going to
    // be summed, and "₹24,000" is text.
    csvTable(
      ['Fees through the app', 'Paise', 'Appointments'],
      [
        ['Collected', r.fees.collectedPaise, r.fees.paidCount],
        ['Still owed', r.fees.outstandingPaise, r.fees.outstandingCount],
        ['Refunded', r.fees.refundedPaise, ''],
        // The denominator travels with the money: without it the total reads
        // as the practice's takings, and the desk's cash is not in this app.
        ['Charged in the app', '', r.fees.countedOf],
        ['Consultations in the window', '', r.fees.consultations],
      ],
    ),
    if (r.byLocation.isNotEmpty)
      csvTable(
        ['Location', 'Consultations'],
        [for (final l in r.byLocation) [l.name, l.count]],
      ),
    if (r.byDiagnosis.isNotEmpty)
      csvTable(
        ['Diagnosis', 'Prescriptions'],
        [for (final d in r.byDiagnosis) [d.name, d.count]],
      ),
    csvTable(
      ['Date', 'Consultations'],
      [for (final d in r.perDay) [_day(d.date), d.count]],
    ),
  ];
  return blocks.join('\r\n\r\n');
}

String reportFilename(ConsultationSummary r) =>
    'reports_${_day(r.from)}_to_${_day(r.to)}.csv';

/// The history as a table, in the order it is read on screen.
String historyCsv(List<Appointment> rows) => csvTable(
  ['Date', 'Time', 'Patient', 'Outcome', 'Reason', 'Location', 'Minutes'],
  [
    for (final a in rows)
      [
        a.scheduledFor == null ? '' : _day(a.scheduledFor!),
        a.scheduledFor == null ? '' : DateFormat('HH:mm').format(a.scheduledFor!),
        a.patientName,
        outcomeOf(a).$1,
        a.reason ?? '',
        a.clinicName ?? '',
        a.calledAt != null && a.completedAt != null
            ? a.completedAt!.difference(a.calledAt!).inMinutes
            : '',
      ],
  ],
);

String historyFilename(int days) =>
    'history_last_${days}_days_${_day(DateTime.now())}.csv';
