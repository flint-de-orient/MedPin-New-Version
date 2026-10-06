import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/error_view.dart';
import '../../clinician/data/practice_repository.dart';
import '../../clinician/domain/practice.dart';
import 'widgets/live_fields.dart';
import 'widgets/profile_parts.dart';

/// How patients book, are reminded, and reach the clinic.
///
/// ---- One editor, two places it is shown -----------------------------------
///
/// The board puts booking rules on the settings hub and again on the schedule
/// screen. They are the practice's either way — a patient who may cancel two
/// hours before at Salt Lake and not at New Town is a patient who rings the
/// desk to ask which — so there is one editor, here, and the schedule screen
/// shows the same three read-only with a way to this one. Two editors for one
/// setting is how they end up disagreeing.
class DoctorCareRulesScreen extends ConsumerStatefulWidget {
  const DoctorCareRulesScreen({super.key});

  @override
  ConsumerState<DoctorCareRulesScreen> createState() =>
      _DoctorCareRulesScreenState();
}

class _DoctorCareRulesScreenState extends ConsumerState<DoctorCareRulesScreen> {
  PracticeRules? _rules;
  bool _dirty = false;
  bool _busy = false;
  String? _failed;

  void _edit(PracticeRules next) => setState(() {
    _rules = next;
    _dirty = true;
  });

  @override
  Widget build(BuildContext context) {
    final practice = ref.watch(practiceOverviewProvider);
    final loaded = practice.valueOrNull;
    if (loaded != null && _rules == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _rules == null) setState(() => _rules = loaded.rules);
      });
    }
    final rules = _rules;

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
            Text('Patients and care', style: D.screenTitle.copyWith(color: D.ink)),
            Text(
              'The same at every location',
              style: D.statLabel.copyWith(color: D.inkMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('care-save'),
            onPressed: _dirty && !_busy && rules != null ? () => _save(rules) : null,
            style: TextButton.styleFrom(
              foregroundColor: D.brand,
              disabledForegroundColor: D.inkFaint,
            ),
            child: _busy
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
        child: practice.when(
          loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
          error: (e, _) => ProfileFailed(
            error: e,
            onRetry: () => ref.invalidate(practiceOverviewProvider),
          ),
          data: (_) => rules == null
              ? const Center(child: CircularProgressIndicator(color: D.brand))
              : ListView(
                  padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
                  children: [
                    // ---- Booking rules --------------------------------
                    const ProfileEyebrow(label: 'BOOKING RULES'),
                    SizedBox(height: D.s2),
                    ProfileGroup(
                      children: [
                        SwitchField(
                          first: true,
                          title: 'Online booking',
                          sub: 'Patients book from the MedPin app',
                          value: rules.onlineBooking,
                          onChanged: (v) => _edit(rules.copyWith(onlineBooking: v)),
                        ),
                        StepperField(
                          title: 'Open booking',
                          sub: 'How far ahead patients can book',
                          value: rules.bookingWindowDays,
                          min: 1,
                          max: 365,
                          noneLabel: 'Any time',
                          unit: ' days',
                          onChanged: (v) =>
                              _edit(rules.copyWith(bookingWindowDays: () => v)),
                        ),
                        StepperField(
                          title: 'Cancel or reschedule',
                          sub: 'Allowed until this long before',
                          value: rules.cancelCutoffHours,
                          min: 1,
                          max: 168,
                          noneLabel: 'Any time',
                          unit: ' h',
                          onChanged: (v) =>
                              _edit(rules.copyWith(cancelCutoffHours: () => v)),
                        ),
                      ],
                    ),
                    SizedBox(height: D.s2),
                    Padding(
                      padding: EdgeInsets.only(left: D.s1),
                      child: Text(
                        'Closing online booking leaves your published hours as '
                        'they are — the desk can still book into them.',
                        style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                      ),
                    ),
                    SizedBox(height: D.s6),

                    // ---- Follow-up reminders --------------------------
                    const ProfileEyebrow(label: 'FOLLOW-UP REMINDERS'),
                    SizedBox(height: D.s2),
                    ProfileGroup(
                      children: [
                        StepperField(
                          first: true,
                          title: 'Remind them',
                          sub: 'Before the day you asked them back',
                          value: rules.reminderDaysBefore,
                          min: 0,
                          max: 30,
                          unit: ' days',
                          onChanged: (v) =>
                              _edit(rules.copyWith(reminderDaysBefore: v ?? 0)),
                        ),
                        _Channels(
                          values: rules.reminderChannels,
                          onChanged: (v) =>
                              _edit(rules.copyWith(reminderChannels: v)),
                        ),
                      ],
                    ),
                    SizedBox(height: D.s6),

                    // ---- Chat and urgent messages ---------------------
                    const ProfileEyebrow(label: 'CHAT AND URGENT MESSAGES'),
                    SizedBox(height: D.s2),
                    ProfileGroup(
                      children: [
                        SwitchField(
                          first: true,
                          title: 'Any time',
                          sub: 'Patients can message whenever they need to',
                          value: rules.messagingAlways,
                          onChanged: (v) => _edit(
                            rules.copyWith(
                              messagingAlways: v,
                              // Opening it again clears hours that would
                              // otherwise sit there meaning nothing.
                              messagingFrom: v ? () => null : null,
                              messagingTo: v ? () => null : null,
                            ),
                          ),
                        ),
                        if (!rules.messagingAlways) ...[
                          _Hour(
                            title: 'From',
                            value: rules.messagingFrom,
                            onChanged: (v) =>
                                _edit(rules.copyWith(messagingFrom: () => v)),
                          ),
                          _Hour(
                            title: 'To',
                            value: rules.messagingTo,
                            onChanged: (v) =>
                                _edit(rules.copyWith(messagingTo: () => v)),
                          ),
                        ],
                        SwitchField(
                          title: 'Urgent messages any time',
                          sub: 'They come through outside the hours above',
                          value: rules.urgentAlways,
                          onChanged: (v) => _edit(rules.copyWith(urgentAlways: v)),
                        ),
                      ],
                    ),
                    SizedBox(height: D.s2),
                    Padding(
                      padding: EdgeInsets.only(left: D.s1),
                      child: Text(
                        // What the hours do and do not do. A patient is never
                        // stopped from writing: what changes is whether
                        // anybody is woken about it.
                        'A message sent outside these hours still arrives and '
                        'is still delivered. What changes is whether anybody '
                        'is alerted about it at two in the morning.',
                        style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                      ),
                    ),
                    SizedBox(height: D.s6),

                    if (_failed != null)
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
                ),
        ),
      ),
    );
  }

  Future<void> _save(PracticeRules rules) async {
    final practice = ref.read(practiceOverviewProvider).valueOrNull;
    if (practice == null) return;

    // Caught here as well as on the server, because the server's refusal
    // arrives as a sentence and this one arrives beside the control.
    if (!rules.messagingAlways &&
        (rules.messagingFrom == null || rules.messagingTo == null)) {
      setState(() => _failed = 'Set both hours, or leave messaging open all day.');
      return;
    }
    if (!rules.messagingAlways && rules.messagingFrom == rules.messagingTo) {
      setState(() => _failed = 'The hours have to be a real window.');
      return;
    }

    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      await ref.read(practiceRepositoryProvider).update(practice.id, rules.toJson());
      ref.invalidate(practiceOverviewProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }
}

/// Where a reminder goes.
///
/// The app cannot be turned off: it is the one channel that always exists, and
/// a reminder with nowhere to go is a patient who was never reminded.
class _Channels extends StatelessWidget {
  const _Channels({required this.values, required this.onChanged});

  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  static const _labels = {'app': 'In the app', 'whatsapp': 'WhatsApp', 'sms': 'SMS'};

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sent by', style: D.statLabel.copyWith(color: D.inkMuted)),
          SizedBox(height: D.s2),
          Wrap(
            spacing: D.s2,
            runSpacing: D.s2,
            children: [
              for (final entry in _labels.entries)
                _ChannelChip(
                  label: entry.value,
                  on: values.contains(entry.key),
                  // The app stays on. Everything else toggles.
                  locked: entry.key == 'app',
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

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.label,
    required this.on,
    required this.locked,
    required this.onTap,
  });

  final String label;
  final bool on;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: on,
      button: !locked,
      child: Material(
        color: on ? D.brandTint : D.card,
        borderRadius: D.rPill,
        child: InkWell(
          onTap: locked ? null : onTap,
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: D.dateLine.copyWith(color: on ? D.brand : D.inkMuted),
                ),
                if (locked) ...[
                  SizedBox(width: D.gapTight),
                  const Icon(Icons.lock_outline_rounded, size: D.icon, color: D.brand),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One end of the messaging window.
class _Hour extends StatelessWidget {
  const _Hour({required this.title, required this.value, required this.onChanged});

  final String title;

  /// 'HH:mm', or null while it has not been set.
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ProfileLink(
      title: title,
      value: value == null ? 'Not set' : _spoken(value!),
      onTap: () async {
        final at = await showTimePicker(
          context: context,
          initialTime: value == null
              ? const TimeOfDay(hour: 9, minute: 0)
              : _parse(value!),
          helpText: title.toUpperCase(),
        );
        if (at == null) return;
        onChanged(
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}',
        );
      },
    );
  }

  static TimeOfDay _parse(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 0,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  static String _spoken(String hhmm) {
    final at = _parse(hhmm);
    return DateFormat('h:mm a').format(DateTime(2000, 1, 1, at.hour, at.minute));
  }
}
