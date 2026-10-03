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

/// The doctor's day, drawn from the design canvas's Doctor-Dashboard artboard.
///
/// ---- Measured from the artboard ---------------------------------------------
///
/// Every size, colour and radius here is the artboard's: 28 for the greeting,
/// 30 for a number, 13 for its label, cards at 16 and the two wide ones at 20,
/// discs at 48, the bar 64 tall at 28. The artboard is 390dp wide and the
/// clinic's phones are 360, so where those 30dp would split a word the screen
/// takes it out of padding rather than out of the type.
///
/// ---- Everything on it is this clinic's own day ------------------------------
///
/// The three numbers are today's diary counted three ways, the red card is the
/// open emergency, the bell's dot and the bar's count are what is waiting. No
/// number here is decoration: if the server has not answered yet the cards hold
/// their shape and show "—", because a zero that means "not known" reads as an
/// empty clinic.
///
/// Home shows this and nothing else, as asked. The clinical cards that used to
/// be here are the old Home, kept at `/clinician/clinical-cards` and reached
/// from More, until the new design has screens of its own for them.
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
            padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.s5),
            children: [
              _Header(unread: notifications?.unread ?? 0),
              SizedBox(height: D.s5),
              const _Greeting(),
              SizedBox(height: D.s5),
              const _TodayStats(),
              const _EmergencyCard(),
              SizedBox(height: D.s5),
              Text('Quick actions', style: D.section.copyWith(color: D.ink)),
              SizedBox(height: D.s3),
              const _QuickActions(),
              SizedBox(height: D.s5),
              const _AssistantCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wordmark, the bell and the doctor's own photo.
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
        const AppWordmark(height: D.logo),
        const Spacer(),
        Semantics(
          button: true,
          label: unread > 0 ? 'Notifications, $unread waiting' : 'Notifications',
          child: InkWell(
            onTap: () => context.push('/clinician/alerts'),
            customBorder: const CircleBorder(),
            child: Container(
              width: D.tap,
              height: D.tap,
              decoration: BoxDecoration(
                color: D.card,
                shape: BoxShape.circle,
                border: Border.all(color: D.line),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.notifications_none_rounded, size: D.iconLg, color: D.ink),
                  if (unread > 0)
                    Positioned(
                      top: D.gapTight,
                      right: D.gapIcon,
                      child: Container(
                        width: D.s2,
                        height: D.s2,
                        decoration: BoxDecoration(
                          color: D.danger,
                          shape: BoxShape.circle,
                          border: Border.all(color: D.card, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: D.s2),
        Semantics(
          button: true,
          label: 'Profile',
          child: InkWell(
            onTap: () => context.push('/clinician/more'),
            customBorder: const CircleBorder(),
            child: UserAvatar(
              name: user?.name ?? '',
              avatarUrl: user?.avatarUrl,
              accent: D.brand,
              size: D.tap,
            ),
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
        Text('Good to see you again', style: D.subtitle.copyWith(color: D.inkMuted)),
        SizedBox(height: D.s1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: D.s1 / 2),
              child: const Icon(Icons.calendar_today_rounded, size: D.icon, color: D.brand),
            ),
            SizedBox(width: D.s2),
            // The practice is left out until it has loaded, rather than
            // standing in with a placeholder nobody can tell from a name.
            Expanded(
              child: Text(
                practice == null ? today : '$today · $practice',
                style: D.dateLine.copyWith(color: D.brand),
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
              label: 'Total appointments',
              tone: D.ink,
              route: '/clinician/appointments',
            ),
          ),
          SizedBox(width: D.s2),
          Expanded(
            child: _StatCard(
              value: counts?.pending,
              label: 'Pending consultations',
              tone: D.pending,
              route: '/clinician/appointments',
            ),
          ),
          SizedBox(width: D.s2),
          Expanded(
            child: _StatCard(
              value: counts?.completed,
              label: 'Completed consultations',
              tone: D.done,
              route: '/clinician/appointments',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.tone,
    required this.route,
  });

  final int? value;
  final String label;
  final Color tone;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: D.card,
      borderRadius: BorderRadius.circular(D.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(D.rCard),
        onTap: () => context.push(route),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.cardPad),
          decoration: BoxDecoration(
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
              SizedBox(height: D.gapTight),
              Text(
                label,
                style: D.statLabel.copyWith(color: D.inkMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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
      padding: EdgeInsets.all(D.cardPad),
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
          TextButton(onPressed: onRetry, child: Text('Try again', style: D.bodyStrong)),
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
    final said = alert.detail?.trim();

    return Padding(
      padding: EdgeInsets.only(top: D.s5),
      child: Material(
        color: D.dangerGround,
        borderRadius: BorderRadius.circular(D.rCardLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(D.rCardLg),
          onTap: () => context.push(
            alert.patientId == null
                ? '/clinician/alerts'
                : '/clinician/patients/${alert.patientId}/thread',
          ),
          child: Container(
            padding: EdgeInsets.all(D.cardPadLg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.rCardLg),
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
                    borderRadius: BorderRadius.circular(D.rMark),
                  ),
                  child: const Icon(Icons.priority_high_rounded, size: D.iconMark, color: D.onBrand),
                ),
                SizedBox(width: D.cardPad),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              patient == null ? heading : '$heading · $patient',
                              style: D.cardTitle.copyWith(color: D.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: D.s2),
                          const Icon(Icons.chevron_right_rounded, size: D.iconMd, color: D.danger),
                        ],
                      ),
                      SizedBox(height: D.gapTight),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '$heading message: ', style: D.body.copyWith(color: D.inkMuted)),
                            TextSpan(
                              text: said == null || said.isEmpty ? alert.title : '“$said”',
                              style: D.body.copyWith(color: D.ink),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: D.gapTight),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, size: D.iconSm, color: D.danger),
                          SizedBox(width: D.s1),
                          Flexible(
                            child: Text(
                              agoOf(alert.createdAt),
                              style: D.bodyStrong.copyWith(color: D.danger),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: D.gapIcon),
                          Text('·', style: D.bodyStrong.copyWith(color: D.dangerFaint)),
                          SizedBox(width: D.gapIcon),
                          Text(
                            'Review now',
                            style: D.bodyStrong.copyWith(
                              color: D.danger,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                              decorationColor: D.danger,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
      _Action('Follow-ups', Icons.event_available_outlined, '/clinician/follow-ups'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Three across, as the artboard draws them — two when the reader has
        // turned the text size up far enough that three would clip a label.
        final scale = MediaQuery.textScalerOf(context).scale(D.tile.fontSize!) / D.tile.fontSize!;
        final columns = scale > 1.3 ? 2 : 3;
        final width = (constraints.maxWidth - D.s2 * (columns - 1)) / columns;

        return Wrap(
          spacing: D.s2,
          runSpacing: D.s2,
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
          // The artboard fixes the tile at 112; a minimum rather than a height,
          // so a label that needs a third line is not cut off.
          constraints: const BoxConstraints(minHeight: D.tileMin),
          padding: EdgeInsets.symmetric(horizontal: D.s1, vertical: D.cardPad),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(D.rCard),
            border: Border.all(color: D.line),
            boxShadow: D.lift,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: D.disc,
                height: D.disc,
                decoration: BoxDecoration(
                  color: D.brandTint,
                  borderRadius: BorderRadius.circular(D.rMark),
                ),
                child: Icon(action.icon, size: D.iconDisc, color: D.brand),
              ),
              SizedBox(height: D.gapIcon),
              Text(
                action.label,
                style: D.tile.copyWith(color: D.ink),
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
class _AssistantCard extends StatelessWidget {
  const _AssistantCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: D.brand,
      borderRadius: BorderRadius.circular(D.rCardLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(D.rCardLg),
        onTap: () => context.push('/clinician/ai'),
        child: Container(
          padding: EdgeInsets.all(D.cardPadLg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(D.rCardLg),
            boxShadow: D.liftBrand,
          ),
          child: Row(
            children: [
              Container(
                width: D.discLg,
                height: D.discLg,
                decoration: BoxDecoration(
                  color: D.onBrandTile,
                  borderRadius: BorderRadius.circular(D.rMarkLg),
                  border: Border.all(color: D.onBrandTileLine),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: D.iconMark, color: D.onBrand),
              ),
              SizedBox(width: D.cardPad),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'AI Assistant',
                            style: D.cardTitle.copyWith(color: D.onBrand),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: D.s2),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: D.s1 + 3, vertical: D.s1 / 2),
                          decoration: BoxDecoration(
                            color: D.onBrandChip,
                            borderRadius: BorderRadius.circular(D.rChip),
                            border: Border.all(color: D.onBrandChipLine),
                          ),
                          child: Text('NEW', style: D.chip.copyWith(color: D.onBrand)),
                        ),
                      ],
                    ),
                    SizedBox(height: D.s1),
                    Text(
                      'Read what it told your patients, and answer it yourself.',
                      style: D.body.copyWith(color: D.onBrandProse),
                    ),
                  ],
                ),
              ),
              SizedBox(width: D.s2),
              const Icon(Icons.chevron_right_rounded, size: D.iconLg, color: D.onBrandProse),
            ],
          ),
        ),
      ),
    );
  }
}
