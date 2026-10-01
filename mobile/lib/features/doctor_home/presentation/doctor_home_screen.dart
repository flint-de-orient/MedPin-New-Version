import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/data/care_contact.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../clinician/domain/appointment.dart';
import '../../clinician/domain/clinician_models.dart';
import '../../clinician/presentation/clinician_providers.dart';

/// The doctor's day, in the new design.
///
/// ---- What this is ----------------------------------------------------------
///
/// The doctor panel's Home, drawn from `D` (core/theme/doctor_tokens.dart) and
/// reading today's server, so what it shows is this clinic's real day rather
/// than a mock-up's numbers. It sits in the doctor's shell, which draws the bar
/// beneath it (widgets/doctor_nav_bar.dart).
///
/// Home shows this and nothing else, as asked. The clinical cards that used to
/// be here — blood-pressure control, follow-ups, recent labs, chat summaries —
/// are not lost: they are the old Home, kept at `/clinician/clinical-cards` and
/// reached from More, until the new design has screens of its own for them.
///
/// ---- Every number here is one the server actually answers ------------------
///
/// The three counts are today's diary, counted three ways, so they add up on
/// screen: everything booked today, the ones still to be seen, the ones seen.
/// A cancellation and a no-show are in none of them — a clinic's "12 today" is
/// twelve people expected, not twelve rows.
///
/// Two of the six quick actions have no screen in this build yet. They say so
/// when tapped rather than opening the nearest thing and leaving the doctor to
/// work out why it is not what the tile said.
class DoctorHomeScreen extends ConsumerWidget {
  const DoctorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(clinicianNotificationsProvider).valueOrNull;

    return Scaffold(
      backgroundColor: D.ground,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(appointmentsTodayProvider);
            ref.invalidate(openAlertsProvider);
            ref.invalidate(clinicianNotificationsProvider);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s6),
            children: [
              _Header(unread: notifications?.unread ?? 0),
              SizedBox(height: D.s5),
              const _Greeting(),
              SizedBox(height: D.s5),
              const _TodayStats(),
              const _EmergencyCard(),
              SizedBox(height: D.s6),
              Text('Quick actions', style: D.section.copyWith(color: D.ink)),
              SizedBox(height: D.s3),
              const _QuickActions(),
              SizedBox(height: D.s6),
              const _AssistantCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The logo, the bell and the doctor's own photo.
class _Header extends ConsumerWidget {
  const _Header({required this.unread});

  /// Everything waiting: messages, alerts and requests together. The dot says
  /// there is something, not how much — the bar's badge counts the messages.
  final int unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;

    return Row(
      children: [
        const AppLogo(size: D.s8),
        const Spacer(),
        Semantics(
          button: true,
          label: unread > 0 ? '$unread waiting' : 'Nothing waiting',
          child: InkWell(
            onTap: () => context.push('/clinician/alerts'),
            customBorder: const CircleBorder(),
            child: Container(
              width: D.tap,
              height: D.tap,
              decoration: const BoxDecoration(
                color: D.card,
                shape: BoxShape.circle,
                boxShadow: D.lift,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.notifications_none_rounded, color: D.ink),
                  if (unread > 0)
                    Positioned(
                      top: D.s3,
                      right: D.s3,
                      child: Container(
                        width: D.s2,
                        height: D.s2,
                        decoration: const BoxDecoration(color: D.badge, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: D.s3),
        InkWell(
          onTap: () => context.push('/clinician/more'),
          customBorder: const CircleBorder(),
          child: UserAvatar(
            name: user?.name ?? '',
            avatarUrl: user?.avatarUrl,
            accent: D.brand,
            size: D.tap,
          ),
        ),
      ],
    );
  }
}

/// Who is reading, and where and when they are.
class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final practice = ref.watch(careContactProvider).valueOrNull?.practiceName;
    final today = DateFormat('EEE, d MMM yyyy').format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hi, ${doctorNameOf(user?.name, user?.role)}',
          style: D.greeting.copyWith(color: D.ink),
          maxLines: 2,
        ),
        SizedBox(height: D.s1),
        Text('Good to see you again', style: D.body.copyWith(color: D.inkMuted)),
        SizedBox(height: D.s2),
        Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: D.s4, color: D.brand),
            SizedBox(width: D.s2),
            // The practice is left out until it has loaded, rather than
            // standing in with a placeholder nobody can tell from a name.
            Expanded(
              child: Text(
                practice == null ? today : '$today · $practice',
                style: D.bodyStrong.copyWith(color: D.brand),
                maxLines: 2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Dr." in front of a doctor's name, unless they have written it themselves.
@visibleForTesting
String doctorNameOf(String? name, String? role) {
  final bare = (name ?? '').trim();
  if (bare.isEmpty) return 'Doctor';
  if (role != 'doctor' || RegExp(r'^dr(\.|\s)', caseSensitive: false).hasMatch(bare)) return bare;
  return 'Dr. $bare';
}

/// Today's diary as three numbers.
class _TodayStats extends ConsumerWidget {
  const _TodayStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(appointmentsTodayProvider);

    return today.when(
      loading: () => const _StatsRow(counts: null),
      error: (_, _) => _StatsFailed(onRetry: () => ref.invalidate(appointmentsTodayProvider)),
      data: (list) => _StatsRow(counts: TodayCounts.of(list)),
    );
  }
}

/// Today's appointments, counted the three ways the screen shows.
@immutable
class TodayCounts {
  const TodayCounts({required this.total, required this.pending, required this.completed});

  /// Everybody expected today. A cancellation and a no-show are nobody
  /// expected, and a request with no time yet is not booked at all.
  final int total;

  /// Still to be seen: confirmed, arrived, or in the room now.
  final int pending;
  final int completed;

  static const _booked = {'confirmed', 'checked_in', 'in_consultation', 'completed'};
  static const _waiting = {'confirmed', 'checked_in', 'in_consultation'};

  factory TodayCounts.of(List<Appointment> appointments) {
    final booked = appointments.where((a) => !a.isRequest && _booked.contains(a.status));
    return TodayCounts(
      total: booked.length,
      pending: booked.where((a) => _waiting.contains(a.status)).length,
      completed: booked.where((a) => a.status == 'completed').length,
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.counts});

  /// Null while the day is still loading: the cards hold their shape and show
  /// "—", because a zero that means "not known yet" reads as an empty clinic.
  final TodayCounts? counts;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              value: counts?.total,
              label: 'Total\nappointments',
              tone: D.ink,
            ),
          ),
          SizedBox(width: D.s3),
          Expanded(
            child: _StatCard(
              value: counts?.pending,
              label: 'Pending\nconsultations',
              tone: D.pending,
            ),
          ),
          SizedBox(width: D.s3),
          Expanded(
            child: _StatCard(
              value: counts?.completed,
              label: 'Completed\nconsultations',
              tone: D.done,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, required this.tone});

  final int? value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.s3, vertical: D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rCard),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value?.toString() ?? '—',
            style: D.metric.copyWith(color: tone),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: D.s2),
          Text(
            label,
            style: D.small.copyWith(color: D.inkMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StatsFailed extends StatelessWidget {
  const _StatsFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rCard),
        border: Border.all(color: D.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Today's list did not load.",
              style: D.body.copyWith(color: D.inkMuted),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

/// Open alerts, worst first. The screen draws the newest emergency or urgent one.
final openAlertsProvider = Provider.autoDispose<AsyncValue<List<ClinicalAlert>>>((ref) {
  return ref
      .watch(alertsProvider((status: 'open', severity: null)))
      .whenData((page) => page.items);
});

/// The one open emergency, when there is one.
///
/// Nothing is drawn when there is not: an empty red card is noise on the
/// screen a doctor reads first thing in the morning. A failure is silent here
/// too — the bell and the alerts screen are the record, and a broken red box
/// where an emergency goes is worse than none.
class _EmergencyCard extends ConsumerWidget {
  const _EmergencyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(openAlertsProvider).valueOrNull ?? const <ClinicalAlert>[];
    final urgent = [
      for (final a in alerts)
        if (a.severity == 'emergency' || a.severity == 'urgent') a,
    ]..sort((a, b) {
      if (a.severity != b.severity) return a.severity == 'emergency' ? -1 : 1;
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    if (urgent.isEmpty) return const SizedBox.shrink();

    final alert = urgent.first;
    final patient = alert.patientName;
    final heading = alert.severity == 'emergency' ? 'Emergency' : 'Urgent';

    return Padding(
      padding: EdgeInsets.only(top: D.s4),
      child: Material(
        color: D.dangerGround,
        borderRadius: BorderRadius.circular(D.rCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(D.rCard),
          onTap: () => context.push(
            alert.patientId == null
                ? '/clinician/alerts'
                : '/clinician/patients/${alert.patientId}/thread',
          ),
          child: Container(
            padding: EdgeInsets.all(D.s4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.rCard),
              border: Border.all(color: D.dangerLine),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: D.disc,
                  height: D.disc,
                  decoration: BoxDecoration(
                    color: D.dangerMark,
                    borderRadius: BorderRadius.circular(D.rInner),
                  ),
                  child: const Icon(Icons.priority_high_rounded, color: D.onBrand),
                ),
                SizedBox(width: D.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient == null ? heading : '$heading · $patient',
                        style: D.bodyStrong.copyWith(color: D.danger),
                      ),
                      SizedBox(height: D.s1),
                      Text(
                        alert.detail?.trim().isNotEmpty == true ? alert.detail!.trim() : alert.title,
                        style: D.small.copyWith(color: D.danger),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: D.s2),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: D.s4, color: D.danger),
                          SizedBox(width: D.s1),
                          Flexible(
                            child: Text(
                              '${agoOf(alert.createdAt)} · Review now',
                              style: D.label.copyWith(color: D.danger),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: D.danger),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How long ago, in the words a person uses. "Just now" under a minute.
@visibleForTesting
String agoOf(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Just now';
  final minutes = (now ?? DateTime.now()).difference(at).inMinutes;
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return '$minutes min ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours hour${hours == 1 ? '' : 's'} ago';
  final days = hours ~/ 24;
  return '$days day${days == 1 ? '' : 's'} ago';
}

/// What a doctor does between patients, in one tap.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    const actions = <_Action>[
      _Action('Patient queue', Icons.groups_2_outlined, '/clinician/appointments'),
      _Action('New patient', Icons.person_add_alt_outlined, '/clinician/patients/new'),
      _Action('Prescriptions', Icons.description_outlined, '/clinician/patients'),
      _Action('Test results', Icons.science_outlined, null),
      _Action('Start consultation', Icons.mic_none_rounded, '/clinician/appointments'),
      _Action('Follow-ups', Icons.event_available_outlined, null),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Three across on a phone, two when the text is scaled far up and
        // three would clip the longest label ("Start consultation").
        final scale = MediaQuery.textScalerOf(context).scale(D.small.fontSize!) / D.small.fontSize!;
        final columns = scale > 1.3 ? 2 : 3;
        final gap = D.s3;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(width: width, child: _ActionTile(action: action)),
          ],
        );
      },
    );
  }
}

@immutable
class _Action {
  const _Action(this.label, this.icon, this.route);

  final String label;
  final IconData icon;

  /// Null where the new build has no screen for it yet. The tile says so
  /// rather than opening something else.
  final String? route;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final _Action action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: D.card,
      borderRadius: BorderRadius.circular(D.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(D.rCard),
        onTap: () {
          final route = action.route;
          if (route != null) {
            context.push(route);
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${action.label} is not built yet.')),
          );
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.s4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(D.rCard),
            border: Border.all(color: D.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: D.disc,
                height: D.disc,
                decoration: BoxDecoration(
                  color: D.brandTint,
                  borderRadius: BorderRadius.circular(D.rInner),
                ),
                child: Icon(action.icon, color: D.brand),
              ),
              SizedBox(height: D.s3),
              Text(
                action.label,
                style: D.bodyStrong.copyWith(color: D.ink),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The assistant, as a doorway rather than a claim.
///
/// It says what it does and nothing about what it has found: a banner that
/// promises "insights" above an empty database is a promise the screen cannot
/// keep.
class _AssistantCard extends StatelessWidget {
  const _AssistantCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: D.brand,
      borderRadius: BorderRadius.circular(D.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(D.rCard),
        onTap: () => context.push('/clinician/chat-review'),
        child: Padding(
          padding: EdgeInsets.all(D.s5),
          child: Row(
            children: [
              Container(
                width: D.disc,
                height: D.disc,
                decoration: BoxDecoration(
                  color: D.onBrand.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(D.rInner),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: D.onBrand),
              ),
              SizedBox(width: D.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'AI Assistant',
                            style: D.section.copyWith(color: D.onBrand),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: D.s2),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.s1),
                          decoration: BoxDecoration(
                            color: D.onBrand.withValues(alpha: 0.2),
                            borderRadius: D.rPill,
                          ),
                          child: Text('NEW', style: D.label.copyWith(color: D.onBrand)),
                        ),
                      ],
                    ),
                    SizedBox(height: D.s1),
                    Text(
                      'Read what the assistant told your patients, and answer it yourself.',
                      style: D.small.copyWith(color: D.onBrand),
                    ),
                  ],
                ),
              ),
              SizedBox(width: D.s2),
              const Icon(Icons.chevron_right_rounded, color: D.onBrand),
            ],
          ),
        ),
      ),
    );
  }
}

