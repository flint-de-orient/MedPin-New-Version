import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../appointments/domain/clinic.dart';
import '../../appointments/presentation/appointment_providers.dart';
import 'widgets/profile_parts.dart';

/// The places this practice consults from.
///
/// The artboard goes straight from "Locations · 3 locations" to one location,
/// which only works for a practice with one. This is the step between: the
/// list, each row saying where it is and when the doctor sits there, so the
/// right one is opened rather than the first one.
///
/// Closed locations are kept at the foot rather than hidden. A location that
/// was closed by mistake is otherwise unreachable, and reopening it is a
/// field on the record rather than a new location with the same name.
class DoctorLocationsScreen extends ConsumerWidget {
  const DoctorLocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinics = ref.watch(clinicsProvider);

    return Scaffold(
      backgroundColor: D.ground,
      appBar: AppBar(
        backgroundColor: D.card,
        surfaceTintColor: D.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: D.line)),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(D.bar),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded, size: D.iconDisc),
          color: D.ink,
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Text('Locations', style: D.screenTitle.copyWith(color: D.ink)),
      ),
      body: SafeArea(
        top: false,
        child: clinics.when(
          loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
          error: (e, _) => ProfileFailed(
            error: e,
            onRetry: () => ref.invalidate(clinicsProvider),
          ),
          data: (all) {
            final open = [for (final c in all) if (c.isActive) c];
            final closed = [for (final c in all) if (!c.isActive) c];

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(clinicsProvider),
              child: ListView(
                padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
                children: [
                  if (open.isEmpty)
                    const ProfileEmpty(
                      text: 'No open location yet. With none, there are no '
                          'hours to publish and nobody can book a time.',
                      icon: Icons.location_off_outlined,
                    )
                  else
                    ProfileGroup(
                      children: [
                        for (final (i, c) in open.indexed)
                          ProfileLink(
                            first: i == 0,
                            title: c.name,
                            subtitle: _where(c),
                            onTap: () =>
                                context.push('/clinician/more/locations/${c.id}'),
                          ),
                      ],
                    ),
                  if (closed.isNotEmpty) ...[
                    SizedBox(height: D.s6),
                    const ProfileEyebrow(label: 'CLOSED'),
                    SizedBox(height: D.s2),
                    ProfileGroup(
                      children: [
                        for (final (i, c) in closed.indexed)
                          ProfileLink(
                            first: i == 0,
                            title: c.name,
                            subtitle: 'Not offered for booking',
                            onTap: () =>
                                context.push('/clinician/more/locations/${c.id}'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Where it is, in the words the record actually holds.
  static String _where(Clinic c) {
    final parts = [
      if ((c.addressLine ?? '').trim().isNotEmpty) c.addressLine!.trim(),
      if ((c.city ?? '').trim().isNotEmpty) c.city!.trim(),
    ];
    return parts.isEmpty ? 'No address on it yet' : parts.join(', ');
  }
}
