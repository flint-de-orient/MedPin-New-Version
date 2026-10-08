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
import 'widgets/live_fields.dart';
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
/// ---- The rest of the board, now that the columns exist --------------------
///
/// Type, landmark, the payments this desk takes, whether a priced service has
/// to be paid for at booking, the ABDM HFR id and the facilities list all save
/// now. The HFR id is stored as typed and never shown as verified: nothing
/// here asks the registry.
class DoctorLocationScreen extends ConsumerStatefulWidget {
  const DoctorLocationScreen({super.key, required this.clinicId});

  /// The location being edited, or [newLocation] to create one.
  ///
  /// ---- Why creating lives on the editing screen ---------------------------
  ///
  /// The doctor panel could not create a location at all. The only button in
  /// the app was on `clinics_screen.dart`, three hops behind a one-time push
  /// notification — while two of this panel's own screens told the doctor
  /// nothing could be booked until a location existed.
  ///
  /// A second screen would be these same fourteen fields written twice, and
  /// the pair would drift the first time one gained a field. The server takes
  /// the same body either way; only the verb changes.
  final String clinicId;

  /// The id that means "there is no location yet".
  static const newLocation = 'new';

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
  final _landmark = TextEditingController();
  final _hfr = TextEditingController();

  String _kind = 'clinic';
  List<String> _facilities = const [];
  List<String> _payments = const [];
  bool _collectAtBooking = false;

  bool _loaded = false;
  bool _dirty = false;
  bool _saving = false;
  String? _failed;

  List<TextEditingController> get _fields =>
      [_name, _address, _city, _phone, _mapUrl, _landmark, _hfr];

  /// A change made by a chip or a switch, which has no controller to listen
  /// to. Wrapped so every one of them marks the screen dirty the same way.
  void _change(VoidCallback apply) => setState(() {
    apply();
    _dirty = true;
  });

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
      _landmark.text = clinic.landmark ?? '';
      _hfr.text = clinic.hfrId ?? '';
      setState(() {
        _kind = clinic.kind;
        _facilities = [...clinic.facilities];
        _payments = [...clinic.paymentMethods];
        _collectAtBooking = clinic.collectFeeAtBooking;
        _loaded = true;
      });
    });
  }

  /// True when this screen is making a location rather than changing one.
  bool get _creating => widget.clinicId == DoctorLocationScreen.newLocation;

  @override
  Widget build(BuildContext context) {
    final clinics = ref.watch(clinicsProvider);
    final clinic = _creating
        ? null
        : (clinics.valueOrNull ?? const <Clinic>[])
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
            Text(
              _creating ? 'New location' : 'Location',
              style: D.screenTitle.copyWith(color: D.ink),
            ),
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
          data: (_) => clinic == null && !_creating
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
                        ChoiceField(
                          label: 'Type',
                          options: const {
                            'clinic': 'Clinic',
                            'hospital': 'Hospital',
                            'diagnostic_centre': 'Diagnostic centre',
                            'home_visit': 'Home visit',
                          },
                          value: _kind,
                          // Never cleared: every location is some kind of
                          // place, and 'clinic' is the one it falls back to.
                          onChanged: (v) => _change(() => _kind = v ?? 'clinic'),
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
                        TextFieldRow(
                          label: 'Landmark',
                          hint: 'Opposite Tank 9, near City Centre',
                          controller: _landmark,
                          fieldKey: const Key('loc-landmark'),
                          caps: TextCapitalization.sentences,
                        ),
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
                      children: [
                        _Payments(
                          values: _payments,
                          onChanged: (v) => _change(() => _payments = v),
                        ),
                        SwitchField(
                          title: 'Collect fee at booking',
                          sub: 'Patients pay online when they book a slot',
                          value: _collectAtBooking,
                          onChanged: (v) => _change(() => _collectAtBooking = v),
                        ),
                      ],
                    ),
                    SizedBox(height: D.s2),
                    Padding(
                      padding: EdgeInsets.only(left: D.s1),
                      child: Text(
                        // The nearest thing that does work, named, so the row
                        // above does not read as the only way money moves.
                        'A service with a fee on it can be paid online when a '
                        'patient books it. With this on, it has to be.',
                        style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                      ),
                    ),
                    SizedBox(height: D.s6),

                    const ProfileEyebrow(label: 'ABDM'),
                    SizedBox(height: D.s2),
                    ProfileGroup(
                      children: [
                        TextFieldRow(
                          first: true,
                          label: 'HFR ID',
                          hint: 'Health Facility Registry',
                          controller: _hfr,
                          fieldKey: const Key('loc-hfr'),
                        ),
                      ],
                    ),
                    SizedBox(height: D.s2),
                    Padding(
                      padding: EdgeInsets.only(left: D.s1),
                      child: Text(
                        'Saved as typed. Nothing here checks it against the '
                        'registry, so it is a record of the id and not a '
                        'verification.',
                        style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                      ),
                    ),
                    SizedBox(height: D.s6),

                    const ProfileEyebrow(label: 'FACILITIES'),
                    SizedBox(height: D.s2),
                    ProfileGroup(
                      children: [
                        TagField(
                          first: true,
                          label: 'What patients will find here',
                          values: _facilities,
                          suggestions: const [
                            'Wheelchair access',
                            'Parking',
                            'Lab sample collection',
                            'Pharmacy',
                            'Lift',
                          ],
                          onChanged: (v) => _change(() => _facilities = v),
                        ),
                      ],
                    ),
                    SizedBox(height: D.s6),

                    // Last, where the board puts it, and under its own name.
                    //
                    // Not while creating: hours are published against a
                    // location that exists, and there is nothing to publish
                    // them against until this one is saved.
                    if (clinic != null) ...[
                      const ProfileEyebrow(label: 'SCHEDULE'),
                      SizedBox(height: D.s2),
                      _Schedule(clinicId: clinic.id),
                      SizedBox(height: D.s6),
                    ],

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


                    // Nothing to close that does not exist yet.
                    if (clinic != null)
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
      final body = {
        'name': _name.text.trim(),
        // Empty clears it. A blank address on a location patients are sent to
        // is worth being able to set deliberately.
        'addressLine': _address.text.trim(),
        'city': _city.text.trim(),
        'phone': _phone.text.trim(),
        'mapUrl': _mapUrl.text.trim(),
        'kind': _kind,
        // Null, not an empty string: an empty landmark is one nobody set.
        'landmark': _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
        'hfrId': _hfr.text.trim().isEmpty ? null : _hfr.text.trim(),
        'facilities': _facilities,
        'paymentMethods': _payments,
        'collectFeeAtBooking': _collectAtBooking,
      };

      final repo = ref.read(clinicRepositoryProvider);
      if (_creating) {
        await repo.create(body);
      } else {
        await repo.update(widget.clinicId, body);
      }
      ref.invalidate(clinicsProvider);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      // Created: back to the list, which is where the new row is. Staying
      // would leave the screen looking like an editor for something it can
      // no longer find, because its id is still "new".
      if (_creating) {
        context.pop();
        return;
      }
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

/// What the desk takes, in the words a patient would use.
///
/// Stored as codes so a report can group them; shown as words, because
/// "net_banking" is not something anybody says.
class _Payments extends StatelessWidget {
  const _Payments({required this.values, required this.onChanged});

  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  static const _labels = {
    'upi': 'UPI',
    'cash': 'Cash',
    'card': 'Card',
    'net_banking': 'Net banking',
  };

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      first: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What this location takes',
            style: D.statLabel.copyWith(color: D.inkMuted),
          ),
          SizedBox(height: D.s2),
          Wrap(
            spacing: D.s2,
            runSpacing: D.s2,
            children: [
              for (final entry in _labels.entries)
                _PaymentChip(
                  label: entry.value,
                  on: values.contains(entry.key),
                  onTap: () => onChanged(
                    values.contains(entry.key)
                        ? [for (final v in values) if (v != entry.key) v]
                        : [...values, entry.key],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  const _PaymentChip({
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? D.brandTint : D.card,
        borderRadius: D.rPill,
        child: InkWell(
          onTap: onTap,
          borderRadius: D.rPill,
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(D.tap - D.s2),
            ),
            padding: EdgeInsets.symmetric(horizontal: D.s3),
            decoration: BoxDecoration(
              borderRadius: D.rPill,
              border: Border.all(
                color: on ? D.brand : D.lineStrong,
                width: on ? 1.5 : 1,
              ),
            ),
            child: Align(
              widthFactor: 1,
              child: Text(
                label,
                style: D.dateLine.copyWith(color: on ? D.brand : D.inkMuted),
              ),
            ),
          ),
        ),
      ),
    );
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
