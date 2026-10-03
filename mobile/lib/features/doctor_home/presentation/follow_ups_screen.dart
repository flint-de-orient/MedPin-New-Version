import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../clinician/domain/caseload_panels.dart';
import '../../clinician/presentation/clinician_providers.dart';

/// Patients the doctor asked to come back, from the canvas's Doctor-FollowUps
/// artboard.
///
/// ---- Drawn as designed, minus what nothing can answer -----------------------
///
/// The artboard shows each patient's age, condition and phone number, the words
/// of the advice they were given, whether they have booked, whether a reminder
/// went out, and buttons to call, remind and book. The server's follow-up list
/// answers four things: who, when they were due, which prescription said so,
/// and which doctor wrote it. Everything else would be invented.
///
/// So the two sections the design leads with are here and real — Overdue, and
/// the window ahead — and the things that need a record nobody keeps yet are
/// not drawn at all rather than drawn empty. A row opens the patient, where
/// their number, their conditions and their prescription already live.
///
/// The one addition: the window is a choice. The server takes it as a number
/// of days, the design's "This week" and "Later this month" are two points on
/// it, and a doctor looking at next month's list is doing the same work.
class FollowUpsScreen extends ConsumerStatefulWidget {
  const FollowUpsScreen({super.key});

  @override
  ConsumerState<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends ConsumerState<FollowUpsScreen> {
  static const _windows = [7, 14, 30];
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final followUps = ref.watch(followUpsProvider(_days));

    return Scaffold(
      backgroundColor: D.ground,
      appBar: AppBar(
        backgroundColor: D.card,
        surfaceTintColor: D.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: D.line)),
        // The bar holds two lines of text, so its height follows them.
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
            Text('Follow-ups', style: D.screenTitle.copyWith(color: D.ink)),
            Text('Patients you asked to come back', style: D.statLabel.copyWith(color: D.inkMuted)),
          ],
        ),
      ),
      body: Column(
        children: [
          _Window(
            days: _days,
            windows: _windows,
            onChanged: (d) => setState(() => _days = d),
          ),
          Expanded(
            child: followUps.when(
              loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
              error: (_, _) => _Failed(onRetry: () => ref.invalidate(followUpsProvider(_days))),
              data: (data) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(followUpsProvider(_days)),
                child: _List(data: data, days: _days),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s3),
        decoration: const BoxDecoration(
          color: D.card,
          border: Border(top: BorderSide(color: D.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            // Scaled, not fixed: a constant height around text clips it the
            // moment the reader turns their text size up.
            height: MediaQuery.textScalerOf(context).scale(D.discLg + D.s1),
            child: FilledButton.icon(
              // The diary is where a visit is actually given a time; this
              // screen knows who is due, not when the room is free.
              onPressed: () => context.push('/clinician/appointments'),
              icon: const Icon(Icons.add_rounded, size: D.iconLg),
              label: Text('Schedule a follow-up', style: D.body.copyWith(fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: D.brand,
                foregroundColor: D.onBrand,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rCard)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How far ahead to look. The design's "This week" and "Later this month" as
/// one control, because the server answers both with the same question.
class _Window extends StatelessWidget {
  const _Window({required this.days, required this.windows, required this.onChanged});

  final int days;
  final List<int> windows;
  final ValueChanged<int> onChanged;

  static String _label(int d) => switch (d) {
    7 => 'This week',
    14 => 'Two weeks',
    _ => 'This month',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: D.card,
      padding: EdgeInsets.fromLTRB(D.s5, 0, D.s5, D.cardPad),
      child: Container(
        padding: EdgeInsets.all(D.s1),
        decoration: BoxDecoration(
          color: D.ground,
          borderRadius: BorderRadius.circular(D.rCard),
        ),
        child: Row(
          children: [
            for (final d in windows)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: d == days,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(D.s3),
                    onTap: () => onChanged(d),
                    child: Container(
                      height: MediaQuery.textScalerOf(context).scale(D.disc - D.s2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: d == days ? D.card : null,
                        borderRadius: BorderRadius.circular(D.s3),
                        boxShadow: d == days ? D.lift : null,
                      ),
                      child: Text(
                        _label(d),
                        style: D.body.copyWith(
                          color: d == days ? D.ink : D.inkMuted,
                          fontWeight: d == days ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.data, required this.days});

  final FollowUps data;
  final int days;

  @override
  Widget build(BuildContext context) {
    final nothing = data.overdue.isEmpty && data.due.isEmpty;

    return ListView(
      padding: EdgeInsets.fromLTRB(D.s4, D.s3, D.s4, D.s6),
      children: [
        if (nothing)
          Padding(
            padding: EdgeInsets.only(top: D.s8),
            child: Column(
              children: [
                const Icon(Icons.event_available_outlined, size: D.s8, color: D.inkFaint),
                SizedBox(height: D.s3),
                Text(
                  'Nobody is due back in this window.',
                  textAlign: TextAlign.center,
                  style: D.body.copyWith(color: D.inkMuted),
                ),
              ],
            ),
          ),
        if (data.overdue.isNotEmpty) ...[
          _SectionHead(
            title: 'Overdue',
            subtitle: '${data.overdueTotal} patient${data.overdueTotal == 1 ? '' : 's'}',
          ),
          _Card(
            people: data.overdue,
            shown: data.overdueTotal,
            overdue: true,
          ),
        ],
        if (data.due.isNotEmpty) ...[
          SizedBox(height: D.s4),
          _SectionHead(
            title: _Window._label(days),
            subtitle: '${data.dueTotal} patient${data.dueTotal == 1 ? '' : 's'}',
          ),
          _Card(people: data.due, shown: data.dueTotal, overdue: false),
        ],
      ],
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(D.s1, D.s2, D.s1, D.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: D.cardTitle.copyWith(color: D.ink)),
          SizedBox(height: D.s1 / 2),
          Text(subtitle, style: D.statLabel.copyWith(color: D.inkFaint)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.people, required this.shown, required this.overdue});

  final List<PanelPatient> people;

  /// What the server counted, which can be more than it named.
  final int shown;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.s6),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      padding: EdgeInsets.symmetric(horizontal: D.s4),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < people.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: D.line),
              _Row(person: people[i], overdue: overdue),
            ],
            // Said rather than hidden: the server names the first few and
            // counts the rest, and a list that quietly stops at five is a list
            // a doctor trusts for the wrong number.
            if (shown > people.length)
              Padding(
                padding: EdgeInsets.symmetric(vertical: D.s3),
                child: Text(
                  '${shown - people.length} more not shown',
                  style: D.statLabel.copyWith(color: D.inkFaint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.person, required this.overdue});

  final PanelPatient person;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final when = person.at;

    return InkWell(
      onTap: () => context.push('/clinician/patients/${person.id}'),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: D.cardPad),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name ?? 'A patient',
                    style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: D.s1),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.s1 / 2),
                        decoration: BoxDecoration(
                          color: overdue ? D.dangerGround : D.brandTint,
                          borderRadius: D.rPill,
                        ),
                        child: Text(
                          dueLabel(when, overdue: overdue),
                          style: D.caption.copyWith(
                            color: overdue ? D.danger : D.brand,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (person.detail != null) ...[
                        SizedBox(width: D.s2),
                        Flexible(
                          child: Text(
                            'Advised by ${person.detail}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: D.caption.copyWith(color: D.inkFaint),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: D.s2),
            const Icon(Icons.chevron_right_rounded, size: D.iconMd, color: D.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// "23 days overdue", "Due today", "Due Mon, 5 Oct" — the artboard's wording,
/// from the only date the server sends.
@visibleForTesting
String dueLabel(DateTime? at, {required bool overdue, DateTime? now}) {
  if (at == null) return overdue ? 'Overdue' : 'Due';
  final clock = now ?? DateTime.now();
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(clock.year, clock.month, clock.day);
  final days = (day.difference(today).inHours / 24).round();

  if (days == 0) return 'Due today';
  if (days < 0) {
    final late = -days;
    return '$late day${late == 1 ? '' : 's'} overdue';
  }
  if (days == 1) return 'Due tomorrow';
  return 'Due ${DateFormat('EEE, d MMM').format(at)}';
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(D.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The follow-up list did not load.',
              style: D.body.copyWith(color: D.inkMuted),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: D.s3),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: D.brandTint,
                foregroundColor: D.brand,
                minimumSize: D.hug,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
              ),
              child: Text('Try again', style: D.dateLine),
            ),
          ],
        ),
      ),
    );
  }
}
