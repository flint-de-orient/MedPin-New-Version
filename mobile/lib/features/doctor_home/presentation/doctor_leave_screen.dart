import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/error_view.dart';
import '../../appointments/data/clinic_repository.dart';
import '../../appointments/domain/clinic.dart';
import '../../appointments/presentation/appointment_providers.dart';
import '../domain/weekly_schedule.dart';
import 'widgets/profile_parts.dart';

/// Days this location is shut (`Doctor-MyProfile` → Leave and holidays).
///
/// ---- This one was already there ------------------------------------------
///
/// I listed leave among the things the app does not record. It does:
/// `Clinic.overrides` is a list of dated closures, the slot endpoint already
/// honours them, and the old clinic editor has been adding them for months. It
/// was my mistake, and this is the row the board asks for, against the field
/// that already exists.
///
/// ---- Per location, because the closure is -------------------------------
///
/// A doctor away for Durga Puja is away everywhere, but the record hangs the
/// closure on a location — so closing the practice for a week is marking it at
/// each of them, and the screen says which one it is marking rather than
/// pretending to a practice-wide switch it would have to fake.
class DoctorLeaveScreen extends ConsumerStatefulWidget {
  const DoctorLeaveScreen({super.key, this.clinicId});

  final String? clinicId;

  @override
  ConsumerState<DoctorLeaveScreen> createState() => _DoctorLeaveScreenState();
}

class _DoctorLeaveScreenState extends ConsumerState<DoctorLeaveScreen> {
  String? _clinicId;
  bool _busy = false;
  String? _failed;

  @override
  void initState() {
    super.initState();
    _clinicId = widget.clinicId;
  }

  @override
  Widget build(BuildContext context) {
    final clinics = ref.watch(clinicsProvider);
    final rooms = [
      for (final c in clinics.valueOrNull ?? const <Clinic>[])
        if (c.isActive) c,
    ];
    final chosen = rooms
        .where((c) => c.id == (_clinicId ?? (rooms.isEmpty ? '' : rooms.first.id)))
        .firstOrNull;

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
        title: Text(
          'Leave and holidays',
          style: D.screenTitle.copyWith(color: D.ink),
        ),
      ),
      body: SafeArea(
        top: false,
        child: clinics.when(
          loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
          error: (e, _) => ProfileFailed(
            error: e,
            onRetry: () => ref.invalidate(clinicsProvider),
          ),
          data: (_) {
            if (chosen == null) {
              return const ProfileEmpty(
                text: 'This practice has no open location, so there is nothing '
                    'to close.',
                icon: Icons.event_busy_outlined,
              );
            }
            final upcoming = upcomingClosures(chosen.overrides);

            return ListView(
              padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
              children: [
                if (rooms.length > 1) ...[
                  SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(D.tap + D.s3),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      itemCount: rooms.length,
                      separatorBuilder: (_, _) => SizedBox(width: D.s2),
                      itemBuilder: (context, i) => _Chip(
                        label: rooms[i].name,
                        on: rooms[i].id == chosen.id,
                        onTap: () => setState(() => _clinicId = rooms[i].id),
                      ),
                    ),
                  ),
                  SizedBox(height: D.s5),
                ],
                Padding(
                  padding: EdgeInsets.only(left: D.s1, bottom: D.s4),
                  child: Text(
                    'Patients cannot book a slot on these days, and anything '
                    'already booked is not cancelled — the desk still has to '
                    'ring those patients.',
                    style: D.statLabel.copyWith(color: D.inkMuted, height: 1.45),
                  ),
                ),
                if (upcoming.isEmpty)
                  const ProfileEmpty(
                    text: 'No days closed. The published hours run as they are.',
                    icon: Icons.event_available_outlined,
                  )
                else
                  ProfileGroup(
                    children: [
                      for (final (i, o) in upcoming.indexed)
                        ProfileRow(
                          first: i == 0,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      closureLine(o.date),
                                      style: D.row.copyWith(color: D.ink),
                                    ),
                                    if ((o.note ?? '').trim().isNotEmpty)
                                      Text(
                                        o.note!.trim(),
                                        style: D.statLabel.copyWith(color: D.inkFaint),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Open this day again',
                                icon: const Icon(Icons.close_rounded, size: D.iconMd),
                                color: D.inkFaint,
                                onPressed: _busy ? null : () => _reopen(chosen, o),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                SizedBox(height: D.s4),
                FilledButton.icon(
                  key: const Key('leave-add'),
                  onPressed: _busy ? null : () => _close(chosen),
                  icon: _busy
                      ? const SizedBox(
                          width: D.icon,
                          height: D.icon,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: D.onBrand,
                          ),
                        )
                      : const Icon(Icons.event_busy_rounded, size: D.iconMd),
                  label: Text(
                    'Close a day',
                    style: D.bodyStrong.copyWith(color: D.onBrand),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: D.brand,
                    disabledBackgroundColor: D.track,
                    foregroundColor: D.onBrand,
                    minimumSize: Size(
                      0,
                      MediaQuery.textScalerOf(context).scale(D.inputH),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(D.rCard),
                    ),
                  ),
                ),
                if (_failed != null) ...[
                  SizedBox(height: D.s4),
                  Container(
                    padding: EdgeInsets.all(D.s4),
                    decoration: BoxDecoration(
                      color: D.dangerGround,
                      borderRadius: BorderRadius.circular(D.rCard),
                    ),
                    child: Text(
                      _failed!,
                      style: D.statLabel.copyWith(color: D.danger, height: 1.45),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _close(Clinic clinic) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      helpText: 'DAYS YOU ARE AWAY',
    );
    if (picked == null) return;
    await _save(clinic, withClosures(clinic.overrides, picked.start, picked.end));
  }

  Future<void> _reopen(Clinic clinic, ClinicOverride closure) async {
    await _save(
      clinic,
      [for (final o in clinic.overrides) if (o.date != closure.date) o],
    );
  }

  Future<void> _save(Clinic clinic, List<ClinicOverride> overrides) async {
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      await ref.read(clinicRepositoryProvider).update(clinic.id, {
        'overrides': [for (final o in overrides) o.toJson()],
      });
      ref.invalidate(clinicsProvider);
      ref.invalidate(locationHoursProvider(clinic.id));
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: on,
      button: true,
      child: Material(
        color: on ? D.brand : D.card,
        borderRadius: D.rPill,
        child: InkWell(
          onTap: onTap,
          borderRadius: D.rPill,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: D.s4),
            decoration: BoxDecoration(
              borderRadius: D.rPill,
              border: Border.all(color: on ? D.brand : D.lineStrong),
            ),
            child: Align(
              widthFactor: 1,
              child: Text(
                label,
                style: D.dateLine.copyWith(color: on ? D.onBrand : D.inkMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
