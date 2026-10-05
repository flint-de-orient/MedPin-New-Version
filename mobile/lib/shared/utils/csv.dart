/// Writing a table a spreadsheet will open.
///
/// Lifted out of `clinic_export.dart`, which had the only correct copy of it,
/// because the Reports and History tabs hand out tables too. A second escaper
/// is a second chance to write the one that forgets quotes — and the failure is
/// silent: a free-text note with a comma in it ends the row early and shifts
/// every column after it, in a file somebody opens a week later.
library;

/// One RFC 4180 field.
///
/// Quote when the value contains a comma, a quote or a newline, and double any
/// quote inside.
String csvField(Object? value) {
  final s = value?.toString() ?? '';
  if (!s.contains(RegExp(r'[",\n\r]'))) return s;
  return '"${s.replaceAll('"', '""')}"';
}

String csvRow(List<Object?> cells) => cells.map(csvField).join(',');

/// A whole table: the header, then the rows, CRLF as the standard asks.
String csvTable(List<Object?> headers, List<List<Object?>> rows) =>
    [csvRow(headers), for (final r in rows) csvRow(r)].join('\r\n');
