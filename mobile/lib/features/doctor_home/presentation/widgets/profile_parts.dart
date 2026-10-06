import 'package:flutter/material.dart';

import '../../../../core/theme/doctor_tokens.dart';
import '../../../../shared/widgets/error_view.dart';

/// The pieces the four record tabs are built from: the card, the section
/// heading, the chip, the row, the little chart.
///
/// They live together because the tabs have to look like one screen. The
/// artboards draw the same white card at radius 24 on every tab, the same
/// hairline between rows, and the same uppercase eyebrow over a list — a tab
/// that invents its own is a tab that looks like a different app.

enum ChipKind { plain, warn, allergy, brand }

class ProfileChip extends StatelessWidget {
  const ProfileChip({super.key, required this.label, this.kind = ChipKind.plain});

  final String label;
  final ChipKind kind;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      ChipKind.warn => (D.pendingGround, D.pending, null),
      ChipKind.allergy => (D.card, D.pending, D.pendingLine),
      ChipKind.brand => (D.brandTint, D.brand, null),
      ChipKind.plain => (D.track, D.inkMuted, null),
    };

    return Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.textScalerOf(context).scale(D.s6 + D.s1 / 2),
      ),
      padding: EdgeInsets.symmetric(horizontal: D.gapIcon, vertical: D.s1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: D.rPill,
        border: border == null ? null : Border.all(color: border),
      ),
      child: Align(
        widthFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kind == ChipKind.allergy) ...[
              const Icon(Icons.warning_amber_rounded, size: D.iconSm, color: D.pending),
              SizedBox(width: D.s1),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: D.caption.copyWith(
                  color: fg,
                  fontWeight: kind == ChipKind.plain ? FontWeight.w600 : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The white card every section on these tabs sits in.
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    this.lifted = false,
    required this.child,
  });

  final String? title;
  final String? subtitle;

  /// A link in the heading's right-hand corner.
  final Widget? action;

  /// The artboard lifts one card per tab with the deeper brand shadow — the
  /// thing it wants read first.
  final bool lifted;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s5),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: lifted ? D.liftBrand : D.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: D.screenTitle.copyWith(color: D.ink)),
                      if (subtitle != null) ...[
                        SizedBox(height: D.s1 / 2),
                        Text(subtitle!, style: D.body.copyWith(color: D.inkMuted)),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...[SizedBox(width: D.s3), action!],
              ],
            ),
            SizedBox(height: D.s4),
          ],
          child,
        ],
      ),
    );
  }
}

/// An uppercase eyebrow over a list.
class ProfileEyebrow extends StatelessWidget {
  const ProfileEyebrow({super.key, required this.label, this.colour = D.inkFaint});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) =>
      Text(label.toUpperCase(), style: D.eyebrow.copyWith(color: colour));
}

/// A row in a list inside a card, with the artboard's hairline above it.
class ProfileRow extends StatelessWidget {
  const ProfileRow({super.key, required this.child, this.first = false, this.onTap});

  final Widget child;
  final bool first;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      // The artboard's 56, with the padding that keeps a two-line row off its
      // own hairline. A single line sits at 56; a subtitle grows past it.
      constraints: BoxConstraints(
        minHeight: MediaQuery.textScalerOf(context).scale(D.rowH),
      ),
      padding: EdgeInsets.symmetric(vertical: D.s2),
      alignment: Alignment.centerLeft,
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: D.line)),
      ),
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

/// One card of rows, as every group on the profile screens is drawn.
///
/// Shared by the Profile tab and My profile, because the two sit one tap
/// apart and a card that is 24dp on one and 16dp on the other reads as two
/// different apps.
class ProfileGroup extends StatelessWidget {
  const ProfileGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.s5),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rSection),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(children: children),
    );
  }
}

/// A row that goes somewhere, with what it currently says on the right.
///
/// The label always describes the row and never the saved value: a row whose
/// title turned into its own contents stopped describing itself the moment it
/// was filled in. The state goes in [value] or [badge], which is where every
/// other row on these screens puts it.
class ProfileLink extends StatelessWidget {
  const ProfileLink({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.badge,
    this.badgeGround,
    this.badgeInk,
    this.first = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;

  /// The current setting, in quiet type on the right.
  final String? value;

  /// A pill instead, where the state is something to act on.
  final String? badge;
  final Color? badgeGround;
  final Color? badgeInk;

  final bool first;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      first: first,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: D.row.copyWith(color: D.ink)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: D.statLabel.copyWith(color: D.inkFaint),
                  ),
              ],
            ),
          ),
          if (badge != null) ...[
            SizedBox(width: D.s2),
            Container(
              padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.s1 / 2),
              decoration: BoxDecoration(
                color: badgeGround ?? D.track,
                borderRadius: D.rPill,
              ),
              child: Text(
                badge!,
                style: D.caption.copyWith(
                  color: badgeInk ?? D.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (value != null) ...[
            SizedBox(width: D.s2),
            Text(value!, style: D.statLabel.copyWith(color: D.inkMuted)),
          ],
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

/// Nothing to show, said rather than left blank.
class ProfileEmpty extends StatelessWidget {
  const ProfileEmpty({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Its own side padding, not whatever the parent happens to give it. In a
      // padded list it looked right; dropped straight into a screen body — as
      // History does when the diary is empty — the sentence ran to both edges
      // of the phone.
      padding: EdgeInsets.symmetric(horizontal: D.s5, vertical: D.s6),
      child: Column(
        children: [
          if (icon != null) ...[
            Icon(icon, size: D.s8, color: D.inkFaint),
            SizedBox(height: D.s3),
          ],
          Text(text, textAlign: TextAlign.center, style: D.body.copyWith(color: D.inkMuted)),
        ],
      ),
    );
  }
}

/// The record did not load — said once, with a way to ask again.
class ProfileFailed extends StatelessWidget {
  const ProfileFailed({super.key, required this.onRetry, this.error});

  final VoidCallback onRetry;

  /// What went wrong, where it is known. "The record did not load" sends
  /// somebody to ask why, and the answer — a route that is not on this server,
  /// a session that has expired — is sitting in the exception being discarded.
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(D.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The record did not load.',
              textAlign: TextAlign.center,
              style: D.body.copyWith(color: D.inkMuted),
            ),
            if (error != null) ...[
              SizedBox(height: D.s2),
              Text(
                ErrorView.messageFor(context, error!),
                textAlign: TextAlign.center,
                style: D.statLabel.copyWith(color: D.inkFaint),
              ),
            ],
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

/// A measurement tile: the label, the figure, and what it means in a word.
class VitalTile extends StatelessWidget {
  const VitalTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.band,
    this.bandColour = D.inkMuted,
  });

  final String label;
  final String value;
  final String? unit;
  final String? band;
  final Color bandColour;

  /// Nothing has been measured. The tile stays — a doctor needs to see that
  /// the blood pressure is missing, not that there is no row for it — but it
  /// reads as an absence rather than a figure.
  bool get missing => value.trim().isEmpty || value == '—';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.cardPad, vertical: D.s3),
      decoration: BoxDecoration(color: D.ground, borderRadius: BorderRadius.circular(D.s3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: D.statLabel.copyWith(color: D.inkMuted)),
          SizedBox(height: D.s1),
          Text.rich(
            TextSpan(
              text: missing ? '—' : value,
              style: D.tileFigure.copyWith(color: missing ? D.inkFaint : D.ink),
              children: [
                if (!missing && unit != null && unit!.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: D.statLabel.copyWith(color: D.inkFaint, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
          if (missing) ...[
            SizedBox(height: D.s1),
            Text(
              'Not recorded',
              style: D.caption.copyWith(color: D.inkFaint, fontWeight: FontWeight.w600),
            ),
          ] else if (band != null) ...[
            SizedBox(height: D.s1),
            Text(
              band!,
              style: D.caption.copyWith(color: bandColour, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two letters for the disc: a name's own, titles skipped.
///
/// Shared, because the AI composer and the diary both draw the same disc and
/// a second copy is a second place "Dr. Arjun Sen" comes out as "DS".
String initialsOf(String name) {
  final bare = name.trim().replaceFirst(
    RegExp(r'^(dr|prof|mr|mrs|ms|smt|shri|sri)\.?\s+', caseSensitive: false),
    '',
  );
  final parts = bare.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}
