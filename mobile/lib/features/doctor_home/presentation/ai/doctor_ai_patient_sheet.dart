import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../clinician/presentation/clinician_providers.dart';
import '../../domain/doctor_ai.dart';

/// Chooses the patient a conversation is about, from this practice's own roll.
///
/// The design writes "type @ for a patient" into the field. A sheet rather
/// than an in-field menu, because the answer has to be an actual patient — a
/// typed name that matches nobody would otherwise look like a question the
/// assistant simply failed to answer.
///
/// Returns true when a patient was chosen.
Future<bool> pickPatientForAi(BuildContext context, WidgetRef ref) async {
  final chosen = await showModalBottomSheet<({String id, String name})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: D.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.s6)),
    ),
    builder: (_) => const _PatientSheet(),
  );
  if (chosen == null) return false;
  ref.read(doctorAiProvider.notifier).about(id: chosen.id, name: chosen.name);
  return true;
}

class _PatientSheet extends ConsumerStatefulWidget {
  const _PatientSheet();

  @override
  ConsumerState<_PatientSheet> createState() => _PatientSheetState();
}

class _PatientSheetState extends ConsumerState<_PatientSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final query = (
      riskBand: null,
      search: _search.trim().isEmpty ? null : _search.trim(),
      sort: 'name',
      pages: 1,
    );
    final patients = ref.watch(patientsProvider(query));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            SizedBox(height: D.s3),
            Container(
              width: D.s8 + D.s1,
              height: D.s1,
              decoration: const BoxDecoration(color: D.line, borderRadius: D.rPill),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(D.s5, D.s5, D.s5, D.s3),
              child: Row(
                children: [
                  Expanded(child: Text('Which patient?', style: D.section.copyWith(color: D.ink))),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, color: D.inkMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: D.s5),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _search = v),
                style: D.subtitle.copyWith(color: D.ink),
                decoration: InputDecoration(
                  hintText: 'Search by name or number',
                  hintStyle: D.subtitle.copyWith(color: D.inkFaint),
                  prefixIcon: const Icon(Icons.search_rounded, color: D.inkFaint),
                  filled: true,
                  fillColor: D.ground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(D.rCard),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: patients.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Padding(
                    padding: EdgeInsets.all(D.s5),
                    child: Text(
                      'The patient list did not load.',
                      style: D.body.copyWith(color: D.inkMuted),
                    ),
                  ),
                ),
                data: (page) {
                  if (page.items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(D.s5),
                        child: Text(
                          _search.isEmpty ? 'No patients yet.' : 'Nobody by that name.',
                          style: D.body.copyWith(color: D.inkMuted),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s6),
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: D.line),
                    itemBuilder: (context, i) {
                      final patient = page.items[i];
                      return ListTile(
                        contentPadding: EdgeInsets.symmetric(vertical: D.s1),
                        title: Text(patient.name, style: D.subtitle.copyWith(color: D.ink)),
                        subtitle: Text(
                          patient.phone,
                          style: D.statLabel.copyWith(color: D.inkFaint),
                        ),
                        onTap: () => Navigator.of(context).pop((id: patient.id, name: patient.name)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
