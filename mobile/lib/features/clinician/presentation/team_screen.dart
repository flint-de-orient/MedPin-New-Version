import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../doctor_home/presentation/widgets/profile_parts.dart';
import '../domain/billing.dart';
import '../domain/team_member.dart';
import 'clinician_providers.dart';
import 'widgets/team_parts.dart';

/// Everyone who works here (`People` on the canvas).
///
/// ---- Why this replaces three screens ------------------------------------
///
/// Front desk, Clinic care and half of Practice answered one question between
/// them — who works at this practice and what may they do — and none of them
/// could show a department or a location, because a membership carried
/// neither. Each knew about one role, because the role was in the URL.
///
/// A practice could not add a doctor at all. There was no screen and no route:
/// hiring one meant asking the platform operator.
///
/// ---- One card, grouped by role ------------------------------------------
///
/// Nobody opens this asking "who is the eleventh person". They open it asking
/// "who is on the desk" or "which doctors are in", so the list is grouped and
/// the groups are ordered by how often that question is asked.
///
/// The board draws every group inside one white card with an uppercase
/// heading each, rather than a card per group. That is the difference between
/// a list of people and eleven boxes: depth is information here, and a border
/// around each role would say the roles are separate things to act on when
/// the thing to act on is a person.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(teamProvider);
    final roster = async.valueOrNull;
    final canAdd = roster != null && roster.canManage;

    return Scaffold(
      backgroundColor: D.ground,
      appBar: teamBar(
        context,
        title: 'People',
        actions: [
          if (canAdd)
            IconButton(
              tooltip: 'Add someone',
              icon: const Icon(Icons.person_add_alt_1_rounded, size: D.iconDisc),
              color: D.brand,
              onPressed: () => _add(context, ref, roster),
            ),
          SizedBox(width: D.s1),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(teamProvider.future),
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
            error: (err, _) => ListView(
              padding: EdgeInsets.all(D.s5),
              children: [
                ProfileFailed(
                  onRetry: () => ref.invalidate(teamProvider),
                  error: err,
                ),
              ],
            ),
            data: (r) => _Roster(roster: r, onAdd: () => _add(context, ref, r)),
          ),
        ),
      ),
    );
  }
}

/// Opening the add form, or saying why it will not open.
///
/// The cap is said before the form rather than after it is filled in: a
/// refusal at the end of nine fields is nine fields of wasted work.
void _add(BuildContext context, WidgetRef ref, TeamRoster? roster) {
  if (roster != null && roster.atCap) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'This practice is at its limit of ${roster.staffCap} people. '
          'Remove somebody, or ask about a larger plan.',
        ),
      ),
    );
    return;
  }
  context.push('/clinician/team/add');
}

class _Roster extends StatelessWidget {
  const _Roster({required this.roster, required this.onAdd});

  final TeamRoster roster;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    // Every role the server named, then anybody whose role this build has not
    // heard of — under their own heading rather than counted in the number
    // above the list and never drawn. A laboratory technician added this
    // morning was once exactly that: a number with no row.
    final known = teamRoles.toSet();
    final unknown = <String>{
      for (final m in roster.items)
        if (!known.contains(m.role)) m.role,
    }.toList()..sort();

    // The first three always show, with a sentence when nobody holds them.
    // "No dietician" is a fact worth seeing; an empty laboratory is not.
    const always = {'doctor', 'staff', 'dietician'};
    final shown = [
      for (final role in teamRoles)
        if (always.contains(role) || roster.items.any((m) => m.role == role)) role,
      ...unknown,
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(D.s5, D.s2, D.s5, D.s8),
      children: [
        if (roster.staffCap != null) ...[
          _Seats(roster: roster),
          SizedBox(height: D.s4),
        ],

        ProfileGroup(
          children: [
            for (final role in shown)
              _Group(
                role: role,
                roster: roster,
                first: role == shown.first,
              ),
          ],
        ),
        SizedBox(height: D.s4),

        if (roster.canManage)
          TeamButton(
            label: 'Add someone',
            icon: Icons.add_rounded,
            onPressed: onAdd,
          )
        else
          Padding(
            padding: EdgeInsets.only(left: D.s1),
            child: Text(
              // Said once, at the bottom, rather than as a disabled control
              // on every row. A greyed button per person is eleven reminders
              // that you cannot do something.
              'Only somebody who manages staff can add or change people here.',
              style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
            ),
          ),
      ],
    );
  }
}

/// How many of the plan's seats are taken.
///
/// Shown only where there is a cap, which is every practice until somebody
/// types a number. The figure is there as well as the tone — somebody who
/// cannot separate blue from amber still reads "7 of 8".
class _Seats extends StatelessWidget {
  const _Seats({required this.roster});

  final TeamRoster roster;

  @override
  Widget build(BuildContext context) {
    final cap = roster.staffCap!;
    final full = roster.atCap;
    // The plan's display name, through the same map the billing screen uses.
    // The server sends the key — `trial`, `essential` — and printing that
    // would put "on the essential plan" in front of a doctor, in a sentence
    // the Plan and billing screen spells with a capital.
    final plan = roster.plan == null ? null : PlanOption.labelFor(roster.plan);

    return Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.textScalerOf(context).scale(D.disc),
      ),
      padding: EdgeInsets.symmetric(horizontal: D.cardPad, vertical: D.s3),
      decoration: BoxDecoration(
        color: full ? D.pendingGround : D.brandTint,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              // The plan's name only where the practice is on one. The
              // founding clinic is on none, and "on the null plan" is worse
              // than counting without naming a tier.
              plan == null
                  ? '${roster.staffUsed} of $cap people'
                  : '${roster.staffUsed} of $cap people on the $plan plan',
              style: D.bodyStrong.copyWith(
                color: full ? D.pending : D.brand,
              ),
            ),
          ),
          if (full) ...[
            SizedBox(width: D.s3),
            Text(
              'At the limit',
              style: D.bodyStrong.copyWith(color: D.pending),
            ),
          ],
        ],
      ),
    );
  }
}

/// One role's heading and its people.
class _Group extends StatelessWidget {
  const _Group({required this.role, required this.roster, required this.first});

  final String role;
  final TeamRoster roster;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final people = roster.items.where((m) => m.role == role).toList();

    return Container(
      // The hairline belongs to the row below a heading, not to the heading —
      // which is why the first group has none and each later one gets its own.
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: D.line)),
      ),
      padding: EdgeInsets.only(top: first ? D.s4 : D.s5, bottom: D.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rolePlural(role).toUpperCase(),
            style: D.eyebrow.copyWith(color: D.inkFaint),
          ),
          if (people.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: D.s3),
              child: Text(
                // Empty is informative here, not noise: "no dietician" is a
                // fact a doctor should be able to see without counting rows.
                'Nobody yet.',
                style: D.statLabel.copyWith(color: D.inkMuted),
              ),
            )
          else
            for (final m in people)
              _Person(
                member: m,
                where: roster.whereLabel(m),
                department: m.department?.name,
                first: m == people.first,
                onTap: roster.canManage
                    ? () => context.push('/clinician/team/${m.id}')
                    : null,
              ),
        ],
      ),
    );
  }
}

/// One person: the disc, their name, what they are and where.
class _Person extends StatelessWidget {
  const _Person({
    required this.member,
    required this.where,
    required this.department,
    required this.first,
    this.onTap,
  });

  final TeamMember member;
  final String where;
  final String? department;
  final bool first;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final gone = !member.isActive;
    final pill = statusPill(member);

    // "Endocrinology · Salt Lake", or whichever half exists. A solo clinic has
    // no departments, so the dot cannot be hard-coded between them.
    final meta = [if (department != null) department!, where].join(' · ');

    return ProfileRow(
      first: first,
      onTap: onTap,
      child: Row(
        children: [
          TeamDisc(name: member.name, faded: gone),
          SizedBox(width: D.s3),
          // Expanded, and no Spacer beside it — the two both take flex and
          // split the row, leaving the name ellipsised with blank space next
          // to it.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: D.row.copyWith(
                          color: gone ? D.inkMuted : D.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (pill != null) ...[
                      SizedBox(width: D.s2),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: D.gapIcon,
                          vertical: D.hair,
                        ),
                        decoration: BoxDecoration(
                          color: pill.ground,
                          borderRadius: D.rPill,
                        ),
                        child: Text(
                          pill.label,
                          style: D.caption.copyWith(
                            color: pill.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: D.body.copyWith(color: D.inkMuted),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            SizedBox(width: D.s1),
            const Icon(
              Icons.chevron_right_rounded,
              size: D.iconMd,
              color: D.inkFaint,
            ),
          ],
        ],
      ),
    );
  }
}
