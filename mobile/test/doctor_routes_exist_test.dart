import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every row on a doctor screen goes somewhere.
///
/// ---- Why this is a source scan and not a widget test ----------------------
///
/// "Letterhead and signature" pointed at `/clinician/practice` for a day.
/// The route existed, the screen opened, the analyzer was happy, and every
/// test passed — the screen simply had no signature control on it. A widget
/// test for that row would have asserted it navigates, which it did.
///
/// What this catches is the cheaper half: a push to a path the router does not
/// declare at all, which is a blank page. It cannot catch a push to a real
/// page that cannot do the job; only reading the destination catches that.

final _routerFile = File('lib/core/router/app_router.dart');

/// The paths the router declares, with `:params` left as they are written.
Set<String> _declaredPaths() {
  final src = _routerFile.readAsStringSync();
  return {
    for (final m in RegExp(r"path:\s*'([^']+)'").allMatches(src)) m.group(1)!,
  };
}

/// Every `context.push('/literal')` under the doctor's screens.
///
/// Interpolated segments become `:id`, because that is what the router writes
/// and the two have to be compared in the same shape. A push whose whole path
/// is a variable is skipped: there is no literal here to check.
List<({String file, int line, String path})> _pushes() {
  final out = <({String file, int line, String path})>[];
  final dirs = [
    Directory('lib/features/doctor_home'),
    Directory('lib/features/clinician/presentation'),
  ];
  final push = RegExp(r"""context\.push\(\s*\n?\s*'([^']*)'""");

  for (final dir in dirs) {
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        // Two lines, because the formatter breaks a long push after the open
        // bracket and the path then sits on the next one.
        final window = i + 1 < lines.length ? '$line\n${lines[i + 1]}' : line;
        final m = push.firstMatch(window);
        if (m == null) continue;
        final raw = m.group(1)!;
        if (!raw.startsWith('/')) continue;
        out.add((
          file: entity.path.replaceAll(r'\', '/'),
          line: i + 1,
          path: _normalise(raw),
        ));
      }
    }
  }
  return out;
}

/// `/clinician/patients/${a.id}?tab=tests` → `/clinician/patients/:id`.
String _normalise(String raw) {
  final withoutQuery = raw.split('?').first;
  return withoutQuery
      .split('/')
      .map((seg) => seg.contains(r'$') ? ':id' : seg)
      .join('/');
}

/// The router's own `/clinician/patients/:id` → `/clinician/patients/:id`.
String _asPattern(String declared) =>
    declared.split('/').map((seg) => seg.startsWith(':') ? ':id' : seg).join('/');

void main() {
  test('the scan finds the screens it is meant to read', () {
    // Every assertion below iterates this. On an empty list they all pass.
    final found = _pushes();
    expect(
      found.length,
      greaterThan(30),
      reason: 'only ${found.length} pushes found — the scan is looking in the '
          'wrong place, and a scan that reads nothing passes everything',
    );
  });

  test('every path a doctor screen pushes is a route the router declares', () {
    final declared = _declaredPaths().map(_asPattern).toSet();
    final missing = <String>[];

    for (final p in _pushes()) {
      if (declared.contains(p.path)) continue;
      missing.add('${p.file}:${p.line}  ${p.path}');
    }

    expect(
      missing,
      isEmpty,
      reason: '\n\nThese open a path the router does not declare, so the tap '
          'lands on a blank page:\n\n  ${missing.join('\n  ')}\n',
    );
  });

  test('the signature is reachable, and from the screen that owns it', () {
    // The specific dead end this file was written after: My profile offered
    // "Digital signature", the unfinished list offered to finish it, and both
    // went to Practice — which has no signature control on it at all.
    final signature = File(
      'lib/features/doctor_home/presentation/doctor_signature_screen.dart',
    );
    expect(signature.existsSync(), isTrue, reason: 'the signature has no screen');
    expect(_declaredPaths(), contains('/clinician/more/signature'));

    final practice = File(
      'lib/features/clinician/presentation/practice_screen.dart',
    ).readAsStringSync();
    expect(
      practice.toLowerCase(),
      isNot(contains('signature')),
      reason: 'if Practice grows a signature control, the comment in '
          'doctor_signature_screen.dart about why this screen exists is stale',
    );

    for (final file in [
      'lib/features/clinician/presentation/clinician_more_screen.dart',
      'lib/features/doctor_home/domain/profile_completeness.dart',
    ]) {
      final src = File(file).readAsStringSync();
      if (!src.contains('ignature')) continue;
      expect(
        src,
        contains('/clinician/more/signature'),
        reason: '$file names the signature and sends the doctor elsewhere',
      );
    }
  });
}
