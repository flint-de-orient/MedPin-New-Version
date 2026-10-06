import 'package:flutter/material.dart';

import '../../../../core/theme/doctor_tokens.dart';
import 'profile_parts.dart';

/// Everything the design asks for that the record cannot hold yet.
///
/// ---- Why these are drawn at all -------------------------------------------
///
/// The profile boards ask for a great deal the server has no field for: a
/// profession type, a medical council, an ABDM link, qualifications with their
/// institutions, a location's facilities, which payments it takes, how many
/// patients share a slot. Leaving them off kept the screens honest and left
/// nobody able to see what the profile is going to be. Drawing them live would
/// be worse — a control that saves nothing is a setting a doctor believes they
/// have set.
///
/// So they are drawn, and they are visibly inert: muted, untappable, and
/// carrying the same three words wherever they appear. The schema arrives
/// field by field, and each one that lands turns its row live.
///
/// ---- The one rule ----------------------------------------------------------
///
/// Nothing in here ever shows a value. Not a placeholder, not a greyed example,
/// not a plausible default. "Not on file yet" is the only thing an unbacked
/// control is allowed to say, because the first person to read a greyed
/// "MBBS, Calcutta Medical College" as the doctor's own is the one who prints
/// it on a prescription.

/// The mark itself.
class NotOnFile extends StatelessWidget {
  const NotOnFile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: D.s2, vertical: D.s1 / 2),
      decoration: const BoxDecoration(color: D.track, borderRadius: D.rPill),
      child: Text(
        'Not on file yet',
        style: D.caption.copyWith(color: D.inkFaint, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A row of the design that has nothing behind it.
///
/// Reads as a row, never as an empty field: no chevron, because there is
/// nowhere to go, and the title is muted so it does not sit at the same weight
/// as the rows that work.
class PendingRow extends StatelessWidget {
  const PendingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.first = false,
  });

  final String title;
  final String? subtitle;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      first: first,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: D.row.copyWith(color: D.inkMuted)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: D.statLabel.copyWith(color: D.inkFaint),
                  ),
              ],
            ),
          ),
          SizedBox(width: D.s2),
          const NotOnFile(),
        ],
      ),
    );
  }
}

/// A field of the design with no column to save into.
///
/// Drawn as the box it will be, with nothing in it and nothing to type: a
/// disabled field a doctor can tap and fill would lose what they wrote.
class PendingField extends StatelessWidget {
  const PendingField({
    super.key,
    required this.label,
    this.first = false,
    this.lines = 1,
  });

  final String label;
  final bool first;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      first: first,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: D.statLabel.copyWith(color: D.inkMuted)),
              ),
              const NotOnFile(),
            ],
          ),
          SizedBox(height: D.gapTight),
          Container(
            height: MediaQuery.textScalerOf(context).scale(
              lines == 1 ? D.inputH : D.inputH * 1.6,
            ),
            decoration: BoxDecoration(
              color: D.track,
              borderRadius: BorderRadius.circular(D.rCard),
            ),
          ),
        ],
      ),
    );
  }
}

/// A set of chips the design offers and the record cannot keep.
///
/// The options are shown, because what the field will hold is the useful part;
/// none is marked chosen, because nothing has been.
class PendingChoice extends StatelessWidget {
  const PendingChoice({
    super.key,
    required this.label,
    required this.options,
    this.note,
    this.first = false,
  });

  final String label;
  final List<String> options;
  final String? note;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      first: first,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: D.statLabel.copyWith(color: D.inkMuted)),
              ),
              const NotOnFile(),
            ],
          ),
          if (note != null) ...[
            SizedBox(height: D.s1 / 2),
            Text(note!, style: D.caption.copyWith(color: D.inkFaint, height: 1.4)),
          ],
          SizedBox(height: D.s2),
          Wrap(
            spacing: D.s2,
            runSpacing: D.s2,
            children: [
              for (final option in options)
                Container(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.textScalerOf(context).scale(D.tap - D.s2),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: D.s3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: D.rPill,
                    border: Border.all(color: D.line),
                  ),
                  child: Text(
                    option,
                    style: D.dateLine.copyWith(color: D.inkFaint),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A figure the design lets the doctor step up and down, with nothing to step.
///
/// The em-dash is the point: a zero or a plausible default here would be read
/// as the setting, and "4 walk-in places" that nothing honours is worse than
/// no figure at all.
class PendingStepper extends StatelessWidget {
  const PendingStepper({
    super.key,
    required this.title,
    required this.sub,
    this.first = false,
  });

  final String title;
  final String sub;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      first: first,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: D.row.copyWith(color: D.inkMuted)),
                Text(sub, style: D.statLabel.copyWith(color: D.inkFaint)),
              ],
            ),
          ),
          SizedBox(width: D.s2),
          const NotOnFile(),
          SizedBox(width: D.s2),
          Text(
            '—',
            style: D.subtitle.copyWith(color: D.inkFaint, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// A switch the design offers that nothing reads.
///
/// Drawn off and untouchable rather than left out: off is what the system
/// actually does today, so the picture is true even though the control is not.
class PendingSwitch extends StatelessWidget {
  const PendingSwitch({
    super.key,
    required this.title,
    required this.sub,
    this.first = false,
  });

  final String title;
  final String sub;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      first: first,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: D.row.copyWith(color: D.inkMuted)),
                Text(sub, style: D.statLabel.copyWith(color: D.inkFaint)),
              ],
            ),
          ),
          SizedBox(width: D.s2),
          const NotOnFile(),
          SizedBox(width: D.s2),
          const Switch(value: false, onChanged: null),
        ],
      ),
    );
  }
}

/// The note at the foot of a screen that carries any of the above.
class PendingNote extends StatelessWidget {
  const PendingNote({super.key, required this.what});

  /// The things on this screen, named, so the note is about what is on the
  /// page rather than a general apology.
  final String what;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.brandTint,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: D.iconLg, color: D.brand),
          SizedBox(width: D.s3),
          Expanded(
            child: Text(
              'Marked "Not on file yet": $what. The app has nowhere to keep '
              'these yet, so they are shown as they will be and cannot be '
              'filled in. Nothing here is a saved value.',
              style: D.statLabel.copyWith(color: D.brand, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
