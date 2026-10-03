import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../domain/clinician_models.dart';

/// Fetching the document a prescription *is*.
///
/// A composed prescription has a PDF generated from its items; one filed off
/// paper has the photograph, and nothing to generate a PDF from. Only
/// [PrescriptionSummary.documentUrl] knows which, and only this knows how to
/// get it onto the disk: the API client, because the file needs the session's
/// authorisation, and a cache keyed by the url, because a prescription is
/// immutable once issued — whatever is on disk is current.
///
/// It takes the client rather than a ref: `Ref` and `WidgetRef` are different
/// types, and both callers are widgets.
///
/// This lives apart from any screen because two screens now offer it: the
/// prescription list and the record's Prescriptions tab. Two copies of a fetch
/// that handles auth, naming and caching is two places for a scan to be saved
/// under the wrong extension and open in nothing.
Future<String?> prescriptionDocumentPath(ApiClient client, PrescriptionSummary rx) async {
  final url = rx.documentUrl;
  if (url == null || url.isEmpty) return null;

  final dir = await getTemporaryDirectory();
  // Named for what it is, because a phone opens a file by its name: a WebP
  // written as `.pdf` finds no app that will take it.
  final name = '${rx.referenceNo ?? rx.id}.${rx.documentExtension}'.replaceAll(
    RegExp(r'[^\w.\-]'),
    '_',
  );
  final cached = File('${dir.path}/rx_${url.hashCode}_$name');

  if (!await cached.exists() || await cached.length() == 0) {
    final bytes = await client.getBytes('${AppConfig.apiOrigin}$url');
    if (bytes.isEmpty) throw Exception('empty document download');
    await cached.writeAsBytes(bytes, flush: true);
  }
  return cached.path;
}

/// What to tell the share sheet it is handing over.
///
/// A scan shared as `application/pdf` arrives somewhere that cannot open it.
String prescriptionMimeType(PrescriptionSummary rx) =>
    rx.documentExtension == 'pdf' ? 'application/pdf' : 'image/${rx.documentExtension}';
