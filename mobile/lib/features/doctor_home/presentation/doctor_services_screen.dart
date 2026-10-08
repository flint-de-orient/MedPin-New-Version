import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/submission_keys.dart';
import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/error_view.dart';
import '../../appointments/data/appointment_repository.dart';
import '../../appointments/domain/service.dart';
import 'widgets/profile_parts.dart';

/// What the practice charges for a consultation.
///
/// ---- What an empty list means ----------------------------------------------
///
/// That the app does not collect for visits, which is how every clinic here
/// works today: the desk takes cash and nothing in the app has ever recorded
/// it. So the empty state says that, rather than reading as a setup step the
/// doctor has forgotten.
///
/// ---- Why zero is a row and not a blank -------------------------------------
///
/// "Follow-up within a fortnight — Free" is a real arrangement, and a clinic
/// that sets it means it. A blank amount would be the app not knowing; zero is
/// the clinic having decided.
final servicesProvider = FutureProvider.autoDispose<List<ClinicService>>(
  (ref) => ref.watch(appointmentRepositoryProvider).services(includeWithdrawn: true),
);

class DoctorServicesScreen extends ConsumerWidget {
  const DoctorServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);

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
        title: Text('Services and fees', style: D.screenTitle.copyWith(color: D.ink)),
      ),
      body: SafeArea(
        top: false,
        child: services.when(
          loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
          error: (e, _) => ProfileFailed(
            error: e,
            onRetry: () => ref.invalidate(servicesProvider),
          ),
          data: (rows) {
            final live = [for (final s in rows) if (s.isActive) s];
            final withdrawn = [for (final s in rows) if (!s.isActive) s];

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(servicesProvider),
              child: ListView(
                padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: D.s1, bottom: D.s4),
                    child: Text(
                      'A patient booking one of these is asked to pay it in the '
                      'app. With no services, nothing is collected in the app '
                      'and the desk takes payment as it does now.',
                      style: D.statLabel.copyWith(color: D.inkMuted, height: 1.45),
                    ),
                  ),
                  if (live.isEmpty)
                    const ProfileEmpty(
                      text: 'No services priced yet. Nothing is collected through '
                          'the app until one is added.',
                      icon: Icons.receipt_long_outlined,
                    )
                  else
                    _Card(rows: live, onEdit: (s) => _edit(context, ref, s)),
                  SizedBox(height: D.s4),
                  FilledButton.icon(
                    key: const Key('svc-add'),
                    onPressed: () => _edit(context, ref, null),
                    icon: const Icon(Icons.add_rounded, size: D.iconMd),
                    label: Text('Add a service', style: D.bodyStrong.copyWith(color: D.onBrand)),
                    style: FilledButton.styleFrom(
                      backgroundColor: D.brand,
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
                  if (withdrawn.isNotEmpty) ...[
                    SizedBox(height: D.s6),
                    const ProfileEyebrow(label: 'Withdrawn'),
                    SizedBox(height: D.s2),
                    Padding(
                      padding: EdgeInsets.only(left: D.s1, bottom: D.s2),
                      child: Text(
                        'Not offered any more. Kept because appointments were '
                        'booked against them and a receipt has to be readable.',
                        style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                      ),
                    ),
                    _Card(rows: withdrawn, onEdit: (s) => _edit(context, ref, s)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ClinicService? service,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: D.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
      ),
      builder: (_) => _ServiceSheet(service: service),
    );
    if (saved == true) ref.invalidate(servicesProvider);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.rows, required this.onEdit});

  final List<ClinicService> rows;
  final ValueChanged<ClinicService> onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        children: [
          for (final (i, s) in rows.indexed)
            ProfileRow(
              first: i == 0,
              onTap: () => onEdit(s),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          style: D.subtitle.copyWith(
                            color: D.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          [
                            // Only where it is not the ordinary in-clinic
                            // visit. With every service in the clinic, "In
                            // clinic" on every row is a word that
                            // distinguishes nothing — but a row saved as
                            // `both` or `teleconsult` before this still says
                            // so, because that one does differ.
                            if (s.mode != 'in_clinic') s.modeLabel,
                            if (s.durationMinutes != null) '${s.durationMinutes} min',
                          ].join(' · '),
                          style: D.caption.copyWith(color: D.inkFaint),
                        ),
                        if ((s.note ?? '').isNotEmpty)
                          Text(
                            s.note!,
                            style: D.caption.copyWith(color: D.inkFaint),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: D.s2),
                  Text(
                    s.price,
                    style: D.subtitle.copyWith(
                      color: s.isActive ? D.ink : D.inkFaint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: D.s1),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: D.iconLg,
                    color: D.inkFaint,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Adding or changing one.
class _ServiceSheet extends ConsumerStatefulWidget {
  const _ServiceSheet({required this.service});

  final ClinicService? service;

  @override
  ConsumerState<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends ConsumerState<_ServiceSheet> {
  final _submission = SubmissionKeys();
  late final TextEditingController _name;
  late final TextEditingController _rupees;
  late final TextEditingController _note;
  late String _mode;
  late bool _active;
  bool _busy = false;
  String? _failed;

  ClinicService? get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _service?.name ?? '');
    // Rupees in the field, paise on the wire. A doctor types 500, not 50000.
    _rupees = TextEditingController(text: _service == null ? '' : _service!.rupees);
    _note = TextEditingController(text: _service?.note ?? '');
    // In clinic, always — see the note where the picker used to be. An
    // existing row keeps whatever it was saved as until somebody edits it.
    _mode = _service?.mode ?? 'in_clinic';
    _active = _service?.isActive ?? true;
    for (final c in [_name, _rupees, _note]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _rupees, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Null until both a name and a readable amount are there.
  int? get _paise {
    final typed = _rupees.text.trim();
    if (typed.isEmpty) return null;
    final rupees = double.tryParse(typed);
    if (rupees == null || rupees < 0) return null;
    // Rounded, because 499.995 is not a number of paise and the alternative is
    // storing 49999.5 and arguing about it later.
    return (rupees * 100).round();
  }

  bool get _ready => _name.text.trim().length >= 2 && _paise != null;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: D.s8 + D.s3,
                  height: D.s1,
                  decoration: const BoxDecoration(
                    color: D.lineStrong,
                    borderRadius: D.rPill,
                  ),
                ),
              ),
              SizedBox(height: D.s4),
              Text(
                _service == null ? 'Add a service' : 'Change this service',
                style: D.opening.copyWith(color: D.ink),
              ),
              SizedBox(height: D.s5),
              _Labelled(
                label: 'What it is called',
                child: _Box(
                  child: TextField(
                    key: const Key('svc-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    style: D.input.copyWith(color: D.ink),
                    decoration: D.bareField(
                      hint: 'Follow-up',
                      hintStyle: D.input.copyWith(color: D.inkFaint),
                    ),
                  ),
                ),
              ),
              SizedBox(height: D.s4),
              _Labelled(
                label: 'What it costs',
                child: _Box(
                  child: Row(
                    children: [
                      Text('₹', style: D.input.copyWith(color: D.inkMuted)),
                      SizedBox(width: D.gapTight),
                      Expanded(
                        child: TextField(
                          key: const Key('svc-amount'),
                          controller: _rupees,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          ],
                          style: D.input.copyWith(color: D.ink),
                          decoration: D.bareField(
                            hint: '500',
                            hintStyle: D.input.copyWith(color: D.inkFaint),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: D.gapTight),
              Text(
                // Said plainly, because a clinic that sets zero means it and a
                // clinic that leaves it blank means something else entirely.
                'Zero is a price — a free follow-up — and it is not the same as '
                'leaving this service off the list.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
              /*
               * No "which kind of visit".
               *
               * MedPin sees patients in a clinic. A teleconsult has no
               * `Clinic` row, so there is nowhere for video hours to live and
               * no published day to book one into — the Schedules screen says
               * the same thing about its own video chip. Offering a video
               * price was offering a visit the product cannot arrange, and
               * the first patient to buy one would have nothing to attend.
               *
               * The field stays on the model and the server still accepts all
               * three: a practice may already hold a service saved as `both`,
               * and dropping the value would change what that row means. New
               * ones are in-clinic.
               */
              SizedBox(height: D.s4),
              _Labelled(
                label: 'A line for the patient (optional)',
                child: _Box(
                  child: TextField(
                    key: const Key('svc-note'),
                    controller: _note,
                    textCapitalization: TextCapitalization.sentences,
                    style: D.input.copyWith(color: D.ink),
                    decoration: D.bareField(
                      hint: 'Within 14 days of your last visit',
                      hintStyle: D.input.copyWith(color: D.inkFaint),
                    ),
                  ),
                ),
              ),
              if (_service != null) ...[
                SizedBox(height: D.s4),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Offered to patients',
                            style: D.subtitle.copyWith(color: D.ink),
                          ),
                          Text(
                            'Turn this off to stop offering it without losing '
                            'what it was.',
                            style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _active,
                      activeThumbColor: D.onBrand,
                      activeTrackColor: D.brand,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                  ],
                ),
              ],
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
              SizedBox(height: D.s5),
              FilledButton(
                key: const Key('svc-save'),
                onPressed: _ready && !_busy ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: D.brand,
                  disabledBackgroundColor: D.track,
                  foregroundColor: D.onBrand,
                  disabledForegroundColor: D.inkFaint,
                  minimumSize: Size(
                    0,
                    MediaQuery.textScalerOf(context).scale(D.inputH),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(D.rCard),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: D.icon,
                        height: D.icon,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: D.onBrand,
                        ),
                      )
                    : Text(
                        _service == null ? 'Add it' : 'Save',
                        style: D.bodyStrong.copyWith(
                          color: _ready ? D.onBrand : D.inkFaint,
                        ),
                      ),
              ),
              if (_service != null) ...[
                SizedBox(height: D.s3),
                TextButton(
                  onPressed: _busy ? null : _remove,
                  style: TextButton.styleFrom(
                    foregroundColor: D.danger,
                    minimumSize: Size(
                      0,
                      MediaQuery.textScalerOf(context).scale(D.tap),
                    ),
                  ),
                  child: Text(
                    'Remove this service',
                    style: D.bodyStrong.copyWith(color: D.danger),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final paise = _paise;
    if (paise == null) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      await ref.read(appointmentRepositoryProvider).saveService(
        id: _service?.id,
        name: _name.text.trim(),
        mode: _mode,
        amountPaise: paise,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        isActive: _service == null ? null : _active,
        submission: _submission,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }

  Future<void> _remove() async {
    final service = _service;
    if (service == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: D.card,
        title: Text('Remove “${service.name}”?', style: D.subhead.copyWith(color: D.ink)),
        content: Text(
          'If anybody has been booked against it, it is withdrawn instead of '
          'removed, so their receipt still reads.',
          style: D.body.copyWith(color: D.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep it', style: D.bodyStrong.copyWith(color: D.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Remove it', style: D.bodyStrong.copyWith(color: D.danger)),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final result = await ref
          .read(appointmentRepositoryProvider)
          .deleteService(service.id);
      if (!mounted) return;
      final message = result.message;
      Navigator.of(context).pop(true);
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: D.statLabel.copyWith(color: D.inkMuted)),
      SizedBox(height: D.gapTight),
      child,
    ],
  );
}

class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      minHeight: MediaQuery.textScalerOf(context).scale(D.inputH),
    ),
    padding: EdgeInsets.symmetric(horizontal: D.s4),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(D.rCard),
      border: Border.all(color: D.lineStrong),
    ),
    child: child,
  );
}
