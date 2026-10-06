import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../doctor_home/presentation/widgets/profile_parts.dart';
import '../data/clinician_repository.dart';
import '../domain/team_member.dart';
import 'clinician_providers.dart';
import 'team_add_screen.dart' show teamProblem;
import 'widgets/team_parts.dart';
import 'widgets/team_pickers.dart';

/// One person's job here (`People — member` on the canvas).
///
/// ---- What this screen is for, and what it is not ------------------------
///
/// It edits the membership, never the person. Their name, their number and
/// their qualifications are their own and are edited from their own profile —
/// a practice that could rename a colleague could rename them on every
/// prescription they have ever signed.
///
/// ---- The permission list is read, not set -------------------------------
///
/// The board draws the grant as ticks and crosses with no controls, and that
/// is right: the grant comes from the role, and a per-permission switch here
/// would be a second way to set one thing. The list says which role it came
/// from, and says so differently when somebody has customised it — "these are
/// the defaults" and "somebody decided this" are different facts, and only one
/// of them changes when the role does.
class TeamMemberScreen extends ConsumerStatefulWidget {
  const TeamMemberScreen({super.key, required this.membershipId});

  final String membershipId;

  @override
  ConsumerState<TeamMemberScreen> createState() => _TeamMemberScreenState();
}

class _TeamMemberScreenState extends ConsumerState<TeamMemberScreen> {
  /// Null until the row has loaded, then this screen's own copy of it.
  String? _role;
  String? _departmentId;
  List<String>? _locationIds;

  /// Out of this practice when the screen opened: suspended, or left.
  ///
  /// Only `suspended` counted once, so somebody who had left opened with the
  /// switch off — reading as a person with access — and saving any other
  /// change sent `active` along with it, handing their access back without
  /// anybody asking for it. Neither can sign in here, so both open with the
  /// switch on.
  bool? _wasOut;
  bool _suspended = false;

  bool _dirty = false;
  bool _saving = false;
  String? _failed;

  /// Takes the row once, so a refresh behind the screen does not overwrite
  /// what somebody is halfway through changing.
  void _adopt(TeamMember m) {
    if (_role != null) return;
    _role = m.role;
    _departmentId = m.department?.id;
    _locationIds = [...m.locationIds];
    _wasOut = m.status == 'suspended' || m.status == 'left';
    _suspended = _wasOut!;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamProvider);
    final roster = async.valueOrNull;
    final member = roster?.items
        .where((m) => m.id == widget.membershipId)
        .firstOrNull;

    if (member != null) _adopt(member);

    return Scaffold(
      backgroundColor: D.ground,
      appBar: teamBar(
        context,
        title: member?.name ?? 'Loading…',
        subtitle: member == null ? null : _identityLine(member),
        leadingAfterBack: member == null
            ? null
            : TeamDisc(name: member.name, faded: !member.isActive),
      ),
      body: SafeArea(
        top: false,
        child: switch ((async, member)) {
          (AsyncError(:final error), _) => ListView(
              padding: EdgeInsets.all(D.s5),
              children: [
                ProfileFailed(
                  onRetry: () => ref.invalidate(teamProvider),
                  error: error,
                ),
              ],
            ),
          (AsyncLoading(), _) =>
            const Center(child: CircularProgressIndicator(color: D.brand)),
          (_, null) => ProfileEmpty(
              // Somebody else removed them while this was open, or the link
              // is stale. Said rather than drawn as a form over nobody.
              text: 'This person is not on the practice’s list any more.',
              icon: Icons.person_off_outlined,
            ),
          (_, final m?) => _Body(
              member: m,
              roster: roster!,
              role: _role!,
              departmentId: _departmentId,
              locationIds: _locationIds!,
              suspended: _suspended,
              dirty: _dirty,
              saving: _saving,
              failed: _failed,
              onRole: (v) => setState(() {
                _role = v;
                _dirty = true;
              }),
              onDepartment: (v) => setState(() {
                _departmentId = v;
                _dirty = true;
              }),
              onLocations: (v) => setState(() {
                _locationIds = v;
                _dirty = true;
              }),
              onSuspended: (v) => setState(() {
                _suspended = v;
                _dirty = true;
              }),
              onSave: () => _save(m),
            ),
        },
      ),
    );
  }

  Future<void> _save(TeamMember m) async {
    setState(() {
      _saving = true;
      _failed = null;
    });
    try {
      await ref.read(clinicianRepositoryProvider).updateMember(
            m.id,
            role: _role == m.role ? null : _role,
            departmentId: _departmentId,
            locationIds: _locationIds,
            // Only when the switch was moved, so `active` goes only when it
            // was turned off. Re-sending the state it opened in is not
            // harmless: `active` is the server's cue to clear a left mark and
            // check the staff limit, and somebody shown as "Account off" may
            // have left as well — a department change must not bring them
            // back.
            status: _suspended == _wasOut
                ? null
                : (_suspended ? 'suspended' : 'active'),
            // The row as this screen opened it. If a colleague has changed
            // this person since, the server says so and nothing is saved.
            version: m.version,
          );
      ref.invalidate(teamProvider);
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = teamProblem(
          e,
          'Could not save. Check the connection and try again.',
        );
      });
    }
  }
}

/// Their number and when this job started, in the header under their name.
///
/// The date is the membership's, not the account's: somebody who has used
/// MedPin for two years and joined this practice in March joined *here* in
/// March, and the other number would be a quiet lie about how long they have
/// worked for you.
String _identityLine(TeamMember m) {
  final started = m.startedOn;
  return [
    if (m.phone.isNotEmpty) m.phone,
    if (started != null) 'Joined ${DateFormat('MMM yyyy').format(started)}',
  ].join(' · ');
}

class _Body extends StatelessWidget {
  const _Body({
    required this.member,
    required this.roster,
    required this.role,
    required this.departmentId,
    required this.locationIds,
    required this.suspended,
    required this.dirty,
    required this.saving,
    required this.failed,
    required this.onRole,
    required this.onDepartment,
    required this.onLocations,
    required this.onSuspended,
    required this.onSave,
  });

  final TeamMember member;
  final TeamRoster roster;
  final String role;
  final String? departmentId;
  final List<String> locationIds;
  final bool suspended;
  final bool dirty;
  final bool saving;
  final String? failed;
  final ValueChanged<String> onRole;
  final ValueChanged<String?> onDepartment;
  final ValueChanged<List<String>> onLocations;
  final ValueChanged<bool> onSuspended;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final m = member;

    // The head cannot be demoted or suspended from the app. A practice with
    // nobody who can administer it is one only we can recover, and the lever
    // that would do it is this screen.
    final locked = m.isOwner;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(D.s5, D.s2, D.s5, D.s6),
            children: [
              if (locked)
                TeamNote(
                  icon: Icons.verified_user_outlined,
                  title: 'This is the practice’s head',
                  body: 'Their role and their access cannot be changed from '
                      'the app. A practice with nobody who can administer it '
                      'is one only MedPin can recover.',
                ),
              if (locked) SizedBox(height: D.s5),

              FieldLabel(
                label: 'Role',
                child: TeamSelect(
                  value: role,
                  options: [
                    for (final r in teamRoles) (id: r, name: roleLabel(r)),
                    // A role this build has not heard of still appears, as
                    // itself: a list that silently dropped it would show
                    // "Front desk" over somebody who is not on the desk.
                    if (!teamRoles.contains(role))
                      (id: role, name: roleLabel(role)),
                  ],
                  onChanged: locked ? (_) {} : (v) => onRole(v ?? role),
                ),
              ),

              if (role != m.role && m.usingPreset) ...[
                SizedBox(height: D.s2),
                _Aside(
                  // Said before it happens rather than discovered afterwards.
                  text: 'Their permissions will change to the defaults for '
                      '${roleInSentence(role)}.',
                ),
              ],
              if (role != m.role && !m.usingPreset) ...[
                SizedBox(height: D.s2),
                _Aside(
                  // The opposite case, and the one that surprises: somebody
                  // with a customised grant keeps it, so a promoted dietician
                  // could be a doctor who cannot prescribe.
                  text: 'Their permissions were set by hand and will not '
                      'change with the role. Check the list below after '
                      'saving.',
                  tone: D.pending,
                ),
              ],

              if (roster.departments.isNotEmpty) ...[
                SizedBox(height: D.s5),
                FieldLabel(
                  label: 'Department',
                  child: TeamSelect(
                    value: departmentId,
                    options: roster.departments,
                    emptyLabel: 'Not set',
                    onChanged: locked ? (_) {} : onDepartment,
                  ),
                ),
              ],

              if (roster.locations.length > 1) ...[
                SizedBox(height: D.s5),
                FieldLabel(
                  label: 'Locations',
                  note: locked
                      ? 'The head runs every location, whatever is ticked '
                          'here.'
                      : 'None ticked means every location, including any the '
                          'practice opens later.',
                  child: TeamLocations(
                    locations: roster.locations,
                    chosen: locationIds,
                    onChanged: locked ? (_) {} : onLocations,
                  ),
                ),
              ],

              SizedBox(height: D.s6),
              _Can(member: m, role: role),

              SizedBox(height: D.s4),
              _Suspend(
                member: m,
                value: suspended,
                locked: locked,
                onChanged: onSuspended,
              ),

              if (failed != null) ...[
                SizedBox(height: D.s4),
                TeamFailure(message: failed!),
              ],
            ],
          ),
        ),
        // The board pins Save to the foot of the screen. Outside the list, so
        // a form longer than the phone never leaves it scrolled out of reach.
        Padding(
          padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.s6),
          child: TeamButton(
            label: 'Save',
            busy: saving,
            onPressed: dirty && !saving && !locked ? onSave : null,
          ),
        ),
      ],
    );
  }
}

/// A sentence beside a field, in the field's own column.
class _Aside extends StatelessWidget {
  const _Aside({required this.text, this.tone = D.inkMuted});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: D.s1),
      child: Text(
        text,
        style: D.statLabel.copyWith(color: tone, height: 1.45),
      ),
    );
  }
}

/// What the role lets them do, as ticks and crosses.
class _Can extends StatelessWidget {
  const _Can({required this.member, required this.role});

  final TeamMember member;

  /// The role as the picker currently reads, which may not be the saved one.
  final String role;

  @override
  Widget build(BuildContext context) {
    final changing = role != member.role;

    return Container(
      padding: EdgeInsets.all(D.s5),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What this role can do',
            style: D.screenTitle.copyWith(color: D.ink),
          ),
          SizedBox(height: D.hair / 2),
          Text(
            // Three different facts, and the screen says which: the role's
            // defaults, a grant somebody chose, or a list that is about to be
            // replaced because the picker above has moved.
            changing
                ? 'Still the ${roleLabel(member.role)} grant — saving applies '
                    'the ${roleLabel(role)} one.'
                : member.usingPreset
                    ? 'Set by the ${roleLabel(member.role)} role'
                    : 'Set by hand for this person, not by their role',
            style: D.body.copyWith(color: D.inkMuted),
          ),
          SizedBox(height: D.s4),
          for (final p in permissionLabels)
            _CanRow(label: p.$2, on: member.permissions.contains(p.$1)),
        ],
      ),
    );
  }
}

class _CanRow extends StatelessWidget {
  const _CanRow({required this.label, required this.on});

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: D.gapTight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: D.hair),
            child: Icon(
              // A tick and a cross, not one icon in two colours. Red-green
              // deficiency runs alongside diabetes, and these clinics' staff
              // read this on a 6-inch phone in a corridor.
              on ? Icons.check_rounded : Icons.close_rounded,
              size: D.iconMd,
              color: on ? D.done : D.inkFaint,
            ),
          ),
          SizedBox(width: D.s3),
          Expanded(
            child: Text(
              label,
              style: D.subtitle.copyWith(color: on ? D.ink : D.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Turning somebody's access off, and saying what that does not do.
class _Suspend extends StatelessWidget {
  const _Suspend({
    required this.member,
    required this.value,
    required this.locked,
    required this.onChanged,
  });

  final TeamMember member;
  final bool value;
  final bool locked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final left = member.status == 'left';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.s5, vertical: D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suspend access',
                      style: D.row.copyWith(
                        color: locked ? D.inkMuted : D.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: D.hair / 2),
                    Text(
                      // What it does and what it does not, because
                      // "suspended" alone reads as deletion to somebody
                      // worried about losing records.
                      'They cannot sign in. Everything they have already '
                      'written stays exactly where it is.',
                      style: D.body.copyWith(color: D.inkMuted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: D.s4),
              Switch.adaptive(
                value: value,
                onChanged: locked ? null : onChanged,
                activeTrackColor: D.brand,
              ),
            ],
          ),
          if (left) ...[
            SizedBox(height: D.s2),
            Text(
              // The switch alone would call somebody who left "suspended",
              // and say nothing about what turning it off does.
              value
                  ? 'They left this practice. Turn this off to give them their '
                      'access back.'
                  : 'They left this practice. Saving gives them their access '
                      'back.',
              style: D.statLabel.copyWith(
                color: value ? D.inkMuted : D.pending,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
