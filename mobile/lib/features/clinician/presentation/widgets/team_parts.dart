import 'package:flutter/material.dart';

import '../../../../core/capabilities/capabilities.dart';
import '../../../../core/router/area.dart';
import '../../../../core/theme/doctor_tokens.dart';
import '../../../doctor_home/presentation/widgets/profile_parts.dart';
import '../../domain/team_member.dart';

/// The pieces the three People screens share.
///
/// They live together because the list, the add form and one person's screen
/// are one thing seen three ways: a role named on the list must be the same
/// word on the form, and a permission a role grants must read identically
/// wherever it is shown. Two copies of either is two answers.

// ------------------------------------------------------------------- roles

/// Every role a practice can hire into, in the order the board lists them.
///
/// The server's seven, written out. A role this build has not heard of still
/// gets a row on the list — under its own heading, made readable — so a role
/// the server gains next month arrives as a person rather than as nobody.
const teamRoles = <String>[
  'doctor',
  'staff',
  'dietician',
  'doctor_assistant',
  'lab_manager',
  'lab_technician',
  'practice_manager',
];

/// The heading over a group of them: "Doctors", "Front desk".
const _plurals = <String, String>{
  'doctor': 'Doctors',
  'staff': 'Front desk',
  'dietician': 'Dieticians',
  'doctor_assistant': 'Doctor’s assistants',
  'lab_manager': 'Laboratory managers',
  'lab_technician': 'Laboratory technicians',
  'practice_manager': 'Practice managers',
};

/// What this screen calls a role, in every place it names one.
///
/// The profile's names from [roleLabels], except the desk: "Clinic staff"
/// there, "Front desk" here, where it sits beside six other kinds of staff. A
/// role neither knows is its own name made readable, never a blank.
String roleLabel(String role) {
  if (role == 'staff') return 'Front desk';
  final known = roleLabels[role];
  if (known != null) return known;
  final words = role.replaceAll('_', ' ').trim();
  if (words.isEmpty) return 'No role';
  return words[0].toUpperCase() + words.substring(1);
}

/// The heading for a group of them.
String rolePlural(String role) => _plurals[role] ?? roleLabel(role);

/// The role mid-sentence: "a laboratory technician", "the front desk".
String roleInSentence(String role) {
  if (role == 'staff') return 'the front desk';
  final label = roleLabel(role).toLowerCase();
  return '${'aeiou'.contains(label[0]) ? 'an' : 'a'} $label';
}

// ------------------------------------------------------------- permissions

/// Every grant a membership can hold, in the order the member screen lists
/// them: what they may do to a patient first, then to the practice.
///
/// Mirrors `PERMISSIONS` in backend models/Membership.js through [Perm], so a
/// name that drifts is a compile error rather than a line that is quietly
/// always a cross.
const permissionLabels = <(String, String)>[
  (Perm.viewPatient, 'View patients'),
  (Perm.editRecord, 'Edit records'),
  (Perm.prescribe, 'Prescribe'),
  (Perm.chatRead, 'Read patient chats'),
  (Perm.chatReply, 'Reply to patient chats'),
  (Perm.shareRecords, 'Share records with another clinic'),
  (Perm.manageStaff, 'Add and change people'),
  (Perm.manageDepartment, 'Run departments and billing'),
  (Perm.viewAudit, 'Read the audit log'),
];

// ---------------------------------------------------------------- the disc

/// Somebody's initials, as the board draws them beside their name.
///
/// Faded for anybody who cannot sign in, and the row says the word as well —
/// a disc two greys apart from another disc is not a status to a reader with
/// diabetic retinopathy, which most of these clinics' doctors treat daily.
class TeamDisc extends StatelessWidget {
  const TeamDisc({super.key, required this.name, this.faded = false, this.size});

  final String name;
  final bool faded;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final side = size ?? D.discSm;
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: faded ? D.track : D.brandTint,
        borderRadius: D.rPill,
      ),
      child: Text(
        initialsOf(name),
        style: D.bodyStrong.copyWith(
          color: faded ? D.inkFaint : D.brand,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- the pill

/// The one pill a row can carry: Owner, or why they cannot sign in.
///
/// Only one, because the board draws one and because a row with three pills
/// after a long Bengali name wraps into a paragraph. Status wins over Owner:
/// a suspended head is a fact about today, "Owner" is a fact about the
/// practice.
({String label, Color ground, Color ink})? statusPill(TeamMember m) {
  return switch (m.status) {
    'suspended' => (label: 'Suspended', ground: D.pendingGround, ink: D.pending),
    'left' => (label: 'Left', ground: D.track, ink: D.inkMuted),
    'disabled' => (label: 'Account off', ground: D.track, ink: D.inkMuted),
    'invited' => (label: 'Invited', ground: D.brandTint, ink: D.brand),
    _ when m.isOwner => (label: 'Owner', ground: D.brandTint, ink: D.brand),
    _ => null,
  };
}

// ------------------------------------------------------------------ a field

/// A label over a control, as the add form draws every one of its fields.
///
/// Its own vertical space rather than whatever the column happens to give it:
/// the form stacks nine of these and a gap that came from a sibling is a gap
/// that changes when the sibling does.
class FieldLabel extends StatelessWidget {
  const FieldLabel({super.key, required this.label, this.note, required this.child});

  final String label;

  /// Said under the control, where it explains what the control does. Not a
  /// placeholder inside it — a hint that vanishes the moment somebody types
  /// is a hint nobody can check their answer against.
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: D.s2),
          child: Text(label, style: D.bodyStrong.copyWith(color: D.ink)),
        ),
        child,
        if (note != null)
          Padding(
            padding: EdgeInsets.only(top: D.gapTight, left: D.s1),
            child: Text(
              note!,
              style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
            ),
          ),
      ],
    );
  }
}

/// The board's pill-shaped choice, used for the role on the add form.
///
/// Chips rather than a menu: seven roles are what a practice can hire, and a
/// list of seven hidden behind a tap is how the laboratory roles came to exist
/// on the server and be unreachable from the app.
class TeamChip extends StatelessWidget {
  const TeamChip({
    super.key,
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
      child: InkWell(
        onTap: onTap,
        borderRadius: D.rPill,
        child: Container(
          // The board draws these 40 tall. They are [D.tap] here, because 40
          // is under the floor every tappable thing in this app stands on and
          // these readers are largely elderly — the one place on these three
          // screens where the artboard is not followed to the pixel.
          //
          // Raised with the text as well, so a wrapped label is not cut.
          constraints: BoxConstraints(
            minHeight: MediaQuery.textScalerOf(context).scale(D.tap),
          ),
          padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? D.brand : D.card,
            borderRadius: D.rPill,
            border: Border.all(color: on ? D.brand : D.lineStrong),
          ),
          child: Text(
            label,
            // Wraps rather than fading out: "Laboratory technician" at a
            // raised text scale is wider than a 360dp phone.
            softWrap: true,
            maxLines: 3,
            textAlign: TextAlign.center,
            style: D.bodyStrong.copyWith(color: on ? D.onBrand : D.inkMuted),
          ),
        ),
      ),
    );
  }
}

/// The 56dp primary button the board puts at the foot of each of these
/// screens.
class TeamButton extends StatelessWidget {
  const TeamButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final off = onPressed == null || busy;
    return Semantics(
      button: true,
      enabled: !off,
      child: Material(
        color: off ? D.track : D.brand,
        borderRadius: BorderRadius.circular(D.rCard),
        // No lift on a disabled button: a shadow says "press me".
        elevation: 0,
        child: InkWell(
          onTap: off ? null : onPressed,
          borderRadius: BorderRadius.circular(D.rCard),
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(D.inputH),
            ),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s2),
            child: busy
                ? const SizedBox(
                    width: D.iconLg,
                    height: D.iconLg,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: D.inkMuted,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: D.iconLg,
                          color: off ? D.inkFaint : D.onBrand,
                        ),
                        SizedBox(width: D.s2),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          style: D.subhead.copyWith(
                            color: off ? D.inkFaint : D.onBrand,
                            fontWeight: FontWeight.w600,
                          ),
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

/// What went wrong, said where the thing that failed is.
class TeamFailure extends StatelessWidget {
  const TeamFailure({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.dangerGround,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Text(
        message,
        style: D.statLabel.copyWith(color: D.danger, height: 1.45),
      ),
    );
  }
}

/// The blue panel the board uses to say something the reader should know
/// before they act.
class TeamNote extends StatelessWidget {
  const TeamNote({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.shield_outlined,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.cardPad, vertical: D.s3),
      decoration: BoxDecoration(
        color: D.brandTint,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: D.hair / 2),
            child: Icon(icon, size: D.iconLg, color: D.brand),
          ),
          SizedBox(width: D.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  // 15/600: the board's own, and the one place on these
                  // screens where a sentence is both small and load-bearing.
                  style: D.subtitle.copyWith(
                    color: D.brand,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: D.hair / 2),
                Text(
                  body,
                  style: D.body.copyWith(color: D.ink, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A screen header in the board's shape: back arrow, title, one action.
AppBar teamBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  Widget? leadingAfterBack,
  List<Widget> actions = const [],
}) {
  return AppBar(
    backgroundColor: D.ground,
    surfaceTintColor: D.ground,
    elevation: 0,
    scrolledUnderElevation: 0,
    toolbarHeight: MediaQuery.textScalerOf(context).scale(D.bar),
    leadingWidth: leadingAfterBack == null ? null : D.disc + D.discSm + D.s2,
    leading: leadingAfterBack == null
        ? null
        : Row(
            children: [
              const _Back(),
              leadingAfterBack,
              SizedBox(width: D.s2),
            ],
          ),
    titleSpacing: 0,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: D.screenTitle.copyWith(color: D.ink),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: D.body.copyWith(color: D.inkMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    ),
    actions: actions,
  );
}

class _Back extends StatelessWidget {
  const _Back();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      icon: const Icon(Icons.arrow_back_rounded, size: D.iconDisc),
      color: D.ink,
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}
