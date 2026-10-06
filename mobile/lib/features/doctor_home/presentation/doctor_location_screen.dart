import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/error_view.dart';
import '../../appointments/data/clinic_repository.dart';
import '../../appointments/domain/clinic.dart';
import '../../appointments/domain/service.dart';
import '../../appointments/presentation/appointment_providers.dart';
import '../domain/weekly_schedule.dart';
import 'widgets/not_on_file.dart';
import 'widgets/profile_parts.dart';

/// One place this doctor consults, and what patients are told about it
/// (`Profile-Location`).
///
/// ---- Fees are the practice's, not this building's -------------------------
///
/// The artboard puts a price list on the location — "Fees at this location",
/// four services with their own amounts. A `Service` row belongs to the
/// practice (optionally to one doctor), and no booking has ever read a
/// per-location price. So the services are shown here as what they are, the
/// practice's, with the one line that keeps it honest; charging different
/// amounts at Salt Lake and New Town needs a field that does not exist yet.
///
/// ---- What else the board asks for, drawn and inert ------------------------
///
/// A landmark, the location's type, which payments it takes, "collect fee at
/// booking", an ABDM HFR link, and the facilities list. The record keeps none
/// of them, so they are drawn as the design has them and marked "Not on file
/// yet" — shown so the shape of the screen is visible, inert so nobody sets
/// something that is not saved. See widgets/not_on_file.dart.
class DoctorLocationScreen extends ConsumerStatefulWidget {
  const DoctorLocationScreen({super.key, required this.clinicId});

  final String clinicId;

  @override
  ConsumerState<DoctorLocationScreen> createState() =>
      _DoctorLocationScreenState();
}

class _DoctorLocationScreenState extends ConsumerState<DoctorLocationScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  final _mapUrl = TextEditingController();

  bool _loaded = false;
  bool _dirty = false;
  bool _saving = false;
  String? _failed;

  List<TextEditingController> get _fields =>
      [_name, _address, _city, _phone, _mapUrl];

  @override
  void initState() {
    super.initState();
    for (final c in _fields) {
      c.addListener(() {
        if (_loaded && !_dirty) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  void _adopt(Clinic clinic) {
    if (_loaded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loaded) return;
      _name.text = clinic.name;
      _address.text = clinic.addressLine ?? '';
      _city.text = clinic.city ?? '';
      _phone.text = clinic.phone ?? '';
      _mapUrl.text = clinic.mapUrl ?? '';
      setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final clinics = ref.watch(clinicsProvider);
    final clinic = (clinics.valueOrNull ?? const <Clinic>[])
        .where((c) => c.id == widget.clinicId)
        .firstOrNull;
    if (clinic != null) _adopt(clinic);

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Location', style: D.screenTitle.copyWith(color: D.ink)),
            if (clinic != null)
              Text(
                clinic.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: D.statLabel.copyWith(color: D.inkMuted),
              ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('loc-save'),
            onPressed: _dirty && !_saving ? _save : null,
            style: TextButton.styleFrom(
              foregroundColor: D.brand,
              disabledForegroundColor: D.inkFaint,
            ),
            child: _saving
                ? const SizedBox(
                    width: D.icon,
                    height: D.icon,
                    child: CircularProgressIndicator(strokeWidth: 2, color: D.brand),
                  )
                : Text(
                    'Save',
                    style: D.bodyStrong.copyWith(
                      color: _dirty ? D.brand : D.inkFaint,
                    ),
                  ),
          ),
          SizedBox(width: D.s2),
        ],
      ),
      body: SafeArea(
        top: false,
        child: clinics.when(
          loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
          error: (e, _) => ProfileFailed(
            error: e,
            onRetry: () => ref.invalidate(clinicsProvider),
          ),
          data: (_) => clinic == null
              ? const ProfileEmpty(
                  text: 'That location is not one of this practice’s.',
                  icon: Icons.location_off_outlined,
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
                  children: [
                    const ProfileEyebrow(label: 'ADDRESS'),
                    SizedBox(height: D.s2),
                    ProfileGroup(
                      children: [
                        _Field(
                          first: true,
                          label: 'Location name',
                          hint: 'City Care Clinic · Salt Lake',
                          controller: _name,
                          fieldKey: const Key('loc-name'),
                        ),
                        const PendingChoice(
                          label: 'Type',
                          options: [
                            'Clinic',
                            'Hospital',
                            'Diagnostic centre',
                            'Home visit',
                          ],
                        ),
                        _Field(
                          label: 'Address',
                          hint: 'DD-24, Sector 1',
                          controller: _address,
                          fieldKey: const Key('loc-address'),
                          lines: 2,
                        ),
                        _Field(
                          label: 'Town or city',
                          hint: 'Kolkata 700064',
                          controller: _city,
                          fieldKey: const Key('loc-city'),
                        ),
                        const PendingField(label: 'Landmark'),
                        _Field(
                          label: 'Phone for patients',
                          hint: '+91 33 4000 1234',
                          controller: _phone,
                          fieldKey: const Key('loc-phone'),
                          keyboard: TextInputType.phone,
                        ),
                        _Field(
                          // The artboard's "Move pin". There is no map on this
                          // record — a link is what it keeps, and a link is
                          // what patients are given.
                          label: 'Map link',
                          hint: 'https://maps.app.goo.gl/…',
                          controller: _mapUrl,
                          fieldKey: const Key('loc-map'),
                          keyboard: TextInputType.url,
                        ),
                      ],
                    ),
                    if (_mapUrl.text.trim().isNotEmpty) ...[
                      SizedBox(height: D.s2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _openMap(_mapUrl.text.trim()),
                          icon: const Icon(Icons.map_outlined, size: D.iconMd),
                          label: Text(
                            'Check the pin',
                            style: D.dateLine.copyWith(color: D.brand),
                          ),
                          style: TextButton.styleFrom(foregroundColor: D.brand),
                        ),
                      ),
                    ],
                    SizedBox(height: D.s6),

                    const ProfileEyebrow(label: 'FEES'),
                    SizedBox(height: D.s2),
                    const _Fees(),
                    SizedBox(height: D.s6),

                    const ProfileEyebrow(label: 'PAYMENTS'),
                    SizedBox(height: D.s2),
                    ProfileGroup(
                      children: const [
                        PendingChoice(
                          first: true,
                          label: 'What this location takes',
                          options: ['UPI', 'Cash', 'Card', 'Net banking'],
                        ),
                        PendingSwitch(
                          title: 'Collect fee at booking',
                          sub: 'Patients pay online when they book a slot',
                        ),
                      ],
                    ),
                    SizedBox(height: D.s2),
                    Padding(
                      padding: EdgeInsets.only(left: D.s1),
                      child: Text(
                        // The nearest thing that does work, named, so the row
                        // above does not read as the only way money moves.
                        'A service with a fee on it is already paid online when '
                        'a patient books it. The switch above would make that '
                        'the rule for this location.',
                        style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                      ),
                    ),
                    SizedBox(height: D.s6),

                    const ProfileEyebrow(label: 'ABDM'),
                    SizedBox(height: D.s2),
                    ProfileGroup(
                      children: const [
                        PendingRow(
                          first: true,
                          title: 'HFR ID',
                          subtitle: 'Health Facility Registry',
                        ),
                      ],
                    ),
                    SizedBox(height: D.s2),
                    Padding(
                      padding: EdgeInsets.only(left: D.s1),
                      child: Text(
                        'Linking this location\u2019s HFR ID would make records '
                        'created here recognised across ABDM.',
                        style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                      ),
                    ),
                    SizedBox(height: D.s6),

                    const ProfileEyebrow(label: 'FACILITIES'),
                    SizedBox(height: D.s2),
                    ProfileGroup(
                      children: const [
                        PendingChoice(
                          first: true,
                          label: 'What patients will find here',
                          options: [
                            'Wheelchair access',
                            'Parking',
                            'Lab sample collection',
                            'Pharmacy',
                            'Lift',
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: D.s6),

                    // Last, where the board puts it, and under its own name.
                    const ProfileEyebrow(label: 'SCHEDULE'),
                    SizedBox(height: D.s2),
                    _Schedule(clinicId: clinic.id),
                    SizedBox(height: D.s6),

                    if (_failed != null) ...[
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
                      SizedBox(height: D.s5),
                    ],

                    const PendingNote(
                      what: 'the kind of place this is, its landmark, which '
                          'payments it takes, collecting the fee at booking, '
                          'the ABDM link and the facilities list',
                    ),
                    SizedBox(height: D.s5),

                    TextButton(
                      onPressed: _saving ? null : () => _stopPractising(clinic),
                      style: TextButton.styleFrom(
                        foregroundColor: D.danger,
                        minimumSize: Size(
                          0,
                          MediaQuery.textScalerOf(context).scale(D.tap),
                        ),
                      ),
                      child: Text(
                        'Stop practising here',
                        style: D.bodyStrong.copyWith(color: D.danger),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _openMap(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that link.')),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _failed = null;
    });
    try {
      await ref.read(clinicRepositoryProvider).update(widget.clinicId, {
        'name': _name.text.trim(),
        // Empty clears it. A blank address on a location patients are sent to
        // is worth being able to set deliberately.
        'addressLine': _address.text.trim(),
        'city': _city.text.trim(),
        'phone': _phone.text.trim(),
        'mapUrl': _mapUrl.text.trim(),
      });
      ref.invalidate(clinicsProvider);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }

  Future<void> _stopPractising(Clinic clinic) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: D.card,
        title: Text('Close ${clinic.name}?', style: D.subhead.copyWith(color: D.ink)),
        content: Text(
          'It stops being offered for booking and its published hours go with '
          'it. Appointments already booked there are not cancelled — the desk '
          'still has to ring those patients.',
          style: D.body.copyWith(color: D.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep it', style: D.bodyStrong.copyWith(color: D.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Close it', style: D.bodyStrong.copyWith(color: D.danger)),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() {
      _saving = true;
      _failed = null;
    });
    try {
      await ref.read(clinicRepositoryProvider).deactivate(widget.clinicId);
      ref.invalidate(clinicsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }
}

/// This doctor's week here, in one line, and the way to change it.
class _Schedule extends ConsumerWidget {
  const _Schedule({required this.clinicId});

  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hours = ref.watch(locationHoursProvider(clinicId)).valueOrNull;
    final mine = hours?.doctors.firstOrNull;
    final week = mine?.weeklyHours ?? const <WeeklyHour>[];

    return ProfileGroup(
      children: [
        ProfileLink(
          first: true,
          title: 'Schedule',
          subtitle: hours == null
              ? 'Reading the diary…'
              : summaryLine(week, mine?.slotMinutes ?? 15),
          onTap: () => context.push('/clinician/more/schedule?clinicId=$clinicId'),
        ),
      ],
    );
  }
}

/// What the practice charges, shown here because this is where the artboard
/// asks for it — and labelled as the practice's, because that is whose it is.
class _Fees extends ConsumerWidget {
  const _Fees();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(bookableServicesProvider).valueOrNull
        ?? const <ClinicService>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileGroup(
          children: [
            if (services.isEmpty)
              ProfileLink(
                first: true,
                title: 'No fees set',
                subtitle: 'Nothing is collected through the app',
                onTap: () => context.push('/clinician/more/services'),
              )
            else ...[
              for (final (i, s) in services.indexed)
                ProfileRow(
                  first: i == 0,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: D.body.copyWith(color: D.ink)),
                            Text(
                              [
                                s.modeLabel,
                                if (s.durationMinutes != null)
                                  '${s.durationMinutes} min',
                              ].join(' · '),
                              style: D.statLabel.copyWith(color: D.inkFaint),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: D.s2),
                      Text(
                        s.price,
                        style: D.subtitle.copyWith(
                          color: D.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ProfileLink(
                title: 'Set fees',
                onTap: () => context.push('/clinician/more/services'),
              ),
            ],
          ],
        ),
        SizedBox(height: D.s2),
        Padding(
          padding: EdgeInsets.only(left: D.s1),
          child: Text(
            // The artboard calls this "Fees at this location". It is not: one
            // price list serves every location, and saying otherwise here is
            // how a clinic believes it has set a different rate at New Town.
            'These are the practice’s fees and apply at every location. '
            'Patients see them before booking.',
            style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// A label above a box, inside a card row.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.fieldKey,
    this.first = false,
    this.lines = 1,
    this.keyboard,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Key fieldKey;
  final bool first;
  final int lines;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      first: first,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: D.statLabel.copyWith(color: D.inkMuted)),
          TextField(
            key: fieldKey,
            controller: controller,
            minLines: lines,
            maxLines: lines,
            keyboardType: keyboard,
            textCapitalization: TextCapitalization.words,
            style: D.input.copyWith(color: D.ink),
            decoration: D.bareField(
              hint: hint,
              hintStyle: D.input.copyWith(color: D.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}
