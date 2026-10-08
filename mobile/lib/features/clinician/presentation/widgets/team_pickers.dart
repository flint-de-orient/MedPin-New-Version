import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/doctor_tokens.dart';

/// The three controls the People forms are built from: a text field, a menu,
/// and a list of locations to tick.
///
/// They are here rather than in `live_fields.dart` because those are rows
/// inside a card — label left, value right — and these are the board's
/// standalone 56dp fields with their label above them. The two shapes do not
/// substitute for one another, and a field that looks like a row is a field
/// nobody taps.

/// A 56dp bordered field, as the board draws every text input on these forms.
class TeamTextField extends StatelessWidget {
  const TeamTextField({
    super.key,
    required this.controller,
    this.hint,
    this.caps = TextCapitalization.none,
    this.keyboard,
    this.maxLength,
    this.validator,
    this.formatters,
    this.onChanged,
    this.lines = 1,
  });

  final TextEditingController controller;
  final String? hint;
  final TextCapitalization caps;
  final TextInputType? keyboard;
  final int? maxLength;
  final String? Function(String?)? validator;

  /// What the field will and will not accept as it is typed — digits only on
  /// an account number, upper case on an IFSC. A check that only runs on
  /// submit lets somebody fill a box wrongly and find out at the end.
  final List<TextInputFormatter>? formatters;

  /// Told as it is typed, for a button that has to go live on what is in the
  /// box. A validator runs on submit and cannot answer that.
  final ValueChanged<String>? onChanged;

  /// How tall, for the boxes that hold a sentence rather than a field.
  final int lines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textCapitalization: caps,
      keyboardType: keyboard,
      maxLength: maxLength,
      validator: validator,
      inputFormatters: formatters,
      onChanged: onChanged,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 2,
      style: D.input.copyWith(color: D.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: D.input.copyWith(color: D.inkFaint),
        // The counter would push the field 20dp taller than the board's 56 for
        // no information: the limit is a guard against a pasted essay, not a
        // budget anybody is spending.
        counterText: '',
        filled: true,
        fillColor: D.card,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: D.s4,
          vertical: D.cardPad,
        ),
        border: _border(D.lineStrong),
        enabledBorder: _border(D.lineStrong),
        focusedBorder: _border(D.brand),
        errorBorder: _border(D.danger),
        focusedErrorBorder: _border(D.danger),
        errorStyle: D.caption.copyWith(color: D.danger, height: 1.4),
      ),
    );
  }

  static OutlineInputBorder _border(Color colour) => OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(D.rCard)),
        borderSide: BorderSide(color: colour),
      );
}

/// One of a known list, in the board's 56dp field with a chevron.
class TeamSelect extends StatelessWidget {
  const TeamSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.emptyLabel,
    this.enabled = true,
  });

  final String? value;
  final List<({String id, String name})> options;
  final ValueChanged<String?> onChanged;

  /// False draws it as what it is: a field this reader may not change.
  ///
  /// Not a handler that drops the change — a control that moves nothing when
  /// tapped reads as broken, and somebody who has just failed to demote the
  /// practice's head should be told why rather than left tapping.
  final bool enabled;

  /// What "none chosen" reads as. Null leaves it out, for a field that must
  /// hold something.
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.textScalerOf(context).scale(D.inputH),
      ),
      padding: EdgeInsets.symmetric(horizontal: D.s4),
      decoration: BoxDecoration(
        color: enabled ? D.card : D.track,
        borderRadius: BorderRadius.circular(D.rCard),
        border: Border.all(color: enabled ? D.lineStrong : D.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          // Without this the field sizes itself to its widest item and clips
          // away to nothing where the parent is narrower — a chevron over an
          // empty box, which is what the old form showed on a 360dp phone.
          isExpanded: true,
          value: value,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: D.iconLg,
            color: enabled ? D.inkMuted : D.inkFaint,
          ),
          style: D.input.copyWith(color: enabled ? D.ink : D.inkMuted),
          dropdownColor: D.card,
          borderRadius: BorderRadius.circular(D.rCard),
          items: [
            if (emptyLabel != null)
              DropdownMenuItem(
                value: null,
                child: Text(
                  emptyLabel!,
                  style: D.input.copyWith(color: D.inkFaint),
                ),
              ),
            for (final o in options)
              DropdownMenuItem(
                value: o.id,
                child: Text(
                  o.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: D.input.copyWith(color: D.ink),
                ),
              ),
          ],
          // Null is what disables a dropdown. Material then greys the chosen
          // item itself, which is why the style above does not have to.
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

/// Which locations somebody may run, as the board's ticked list.
///
/// ---- Why none ticked means all of them ----------------------------------
///
/// The server reads an empty list as every location, because every membership
/// written before the field existed has one and all of those people run every
/// branch this morning. Reading empty as "nowhere" would lock the platform's
/// staff out of their own diaries; reading it as "everywhere" changes nothing
/// for them.
///
/// So this cannot draw an unticked list as a restriction. It says what an
/// unticked list means, in a line under the tick boxes, and the row that
/// matters — "Every location" — is the first one and ticks itself when the
/// others are clear.
class TeamLocations extends StatelessWidget {
  const TeamLocations({
    super.key,
    required this.locations,
    required this.chosen,
    required this.onChanged,
    this.enabled = true,
  });

  final List<({String id, String name})> locations;
  final List<String> chosen;
  final ValueChanged<List<String>> onChanged;

  /// False shows the list and takes no taps. See [TeamSelect.enabled].
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final all = chosen.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: enabled ? D.card : D.track,
        borderRadius: BorderRadius.circular(D.rCard),
        border: Border.all(color: enabled ? D.lineStrong : D.line),
      ),
      padding: EdgeInsets.symmetric(horizontal: D.s4),
      child: Column(
        children: [
          _Tick(
            label: 'Every location',
            on: all,
            first: true,
            // Already every one; ticking it again would do nothing, and a box
            // that does nothing when tapped reads as broken.
            onTap: all || !enabled ? null : () => onChanged(const []),
          ),
          for (final l in locations)
            _Tick(
              label: l.name,
              on: chosen.contains(l.id),
              first: false,
              onTap: !enabled
                  ? null
                  : () {
                      final next = [...chosen];
                      next.contains(l.id) ? next.remove(l.id) : next.add(l.id);
                      onChanged(next);
                    },
            ),
        ],
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({
    required this.label,
    required this.on,
    required this.first,
    required this.onTap,
  });

  final String label;
  final bool on;
  final bool first;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.textScalerOf(context).scale(D.inputH),
      ),
      padding: EdgeInsets.symmetric(vertical: D.s2),
      child: Row(
        children: [
          Container(
            width: D.iconDisc,
            height: D.iconDisc,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? D.brand : D.card,
              borderRadius: BorderRadius.circular(D.gapTight),
              border: Border.all(color: on ? D.brand : D.lineStrong, width: 1.5),
            ),
            child: on
                ? const Icon(Icons.check_rounded, size: D.icon, color: D.onBrand)
                : null,
          ),
          SizedBox(width: D.s3),
          Expanded(
            child: Text(
              label,
              style: D.input.copyWith(
                color: onTap == null ? D.inkMuted : D.ink,
              ),
            ),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: D.line)),
      ),
      child: Semantics(
        checked: on,
        child: onTap == null ? row : InkWell(onTap: onTap, child: row),
      ),
    );
  }
}
