import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/doctor_tokens.dart';
import 'profile_parts.dart';

/// The controls the profile screens are built from, now that the fields exist.
///
/// These replace the inert set in not_on_file.dart one at a time, as each
/// column lands. The shapes are deliberately the same — a row that was muted
/// yesterday and works today should be in the same place, the same size, with
/// the same words.

/// One choice from a short, known list.
///
/// A chip each rather than a dropdown: with six options that always fit, a
/// menu hides what the field can hold behind a tap, and the thing a doctor
/// wants to know first is what the choices are.
class ChoiceField extends StatelessWidget {
  const ChoiceField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.note,
    this.first = false,
  });

  final String label;

  /// Stored value to shown label.
  final Map<String, String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? note;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return ProfileRow(
      first: first,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: D.statLabel.copyWith(color: D.inkMuted)),
          if (note != null) ...[
            SizedBox(height: D.s1 / 2),
            Text(note!, style: D.caption.copyWith(color: D.inkFaint, height: 1.4)),
          ],
          SizedBox(height: D.s2),
          Wrap(
            spacing: D.s2,
            runSpacing: D.s2,
            children: [
              for (final entry in options.entries)
                _Chip(
                  label: entry.value,
                  on: entry.key == value,
                  // Tapping the chosen one clears it. A field with no "none"
                  // is a field somebody can set by accident and never unset.
                  onTap: () => onChanged(entry.key == value ? null : entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Several from a list, plus whatever the clinic calls its own.
///
/// The suggestions are a starting point, never the whole set: a specialty this
/// platform has not heard of is a doctor who cannot describe themselves.
class TagField extends StatefulWidget {
  const TagField({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    this.suggestions = const [],
    this.note,
    this.addLabel = 'Add',
    this.first = false,
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;
  final String? note;
  final String addLabel;
  final bool first;

  @override
  State<TagField> createState() => _TagFieldState();
}

class _TagFieldState extends State<TagField> {
  @override
  Widget build(BuildContext context) {
    // Suggestions that are not already on, so the list shrinks as it is used
    // rather than showing a chosen chip twice.
    final rest = [
      for (final s in widget.suggestions)
        if (!widget.values.contains(s)) s,
    ];

    return ProfileRow(
      first: widget.first,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.label, style: D.statLabel.copyWith(color: D.inkMuted)),
          if (widget.note != null) ...[
            SizedBox(height: D.s1 / 2),
            Text(
              widget.note!,
              style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
            ),
          ],
          SizedBox(height: D.s2),
          Wrap(
            spacing: D.s2,
            runSpacing: D.s2,
            children: [
              for (final value in widget.values)
                _Chip(
                  label: value,
                  on: true,
                  trailing: Icons.close_rounded,
                  onTap: () => widget.onChanged(
                    [for (final v in widget.values) if (v != value) v],
                  ),
                ),
              for (final s in rest)
                _Chip(
                  label: s,
                  on: false,
                  onTap: () => widget.onChanged([...widget.values, s]),
                ),
              _Chip(
                label: '+ ${widget.addLabel}',
                on: false,
                dashed: true,
                onTap: _typeOne,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _typeOne() async {
    final controller = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: D.card,
        title: Text(widget.label, style: D.subhead.copyWith(color: D.ink)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          style: D.input.copyWith(color: D.ink),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: D.bodyStrong.copyWith(color: D.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(widget.addLabel, style: D.bodyStrong.copyWith(color: D.brand)),
          ),
        ],
      ),
    );
    controller.dispose();
    final value = typed?.trim() ?? '';
    // Silently ignoring a duplicate is right here: the doctor's intent was to
    // have it on the list, and it is.
    if (value.isEmpty || widget.values.contains(value)) return;
    widget.onChanged([...widget.values, value]);
  }
}

/// A figure with a minus and a plus, as the design draws every slot setting.
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.title,
    required this.sub,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    this.step = 1,
    this.unit = '',
    this.noneLabel,
    this.first = false,
  });

  final String title;
  final String sub;
  final int? value;
  final ValueChanged<int?> onChanged;
  final int min;
  final int max;
  final int step;
  final String unit;

  /// What null reads as — "Any time", "None". Where this is given, stepping
  /// below [min] clears the field rather than stopping at it.
  final String? noneLabel;

  final bool first;

  @override
  Widget build(BuildContext context) {
    final at = value;
    final canLess = noneLabel != null ? at != null : (at ?? min) > min;
    final canMore = at == null ? true : at + step <= max;

    return ProfileRow(
      first: first,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: D.row.copyWith(color: D.ink)),
                Text(sub, style: D.statLabel.copyWith(color: D.inkFaint)),
              ],
            ),
          ),
          SizedBox(width: D.s2),
          _Round(
            icon: Icons.remove_rounded,
            label: 'Less $title',
            onTap: !canLess
                ? null
                : () {
                    if (at == null) return;
                    final next = at - step;
                    onChanged(next < min ? null : next);
                  },
          ),
          SizedBox(
            width: D.s8 + D.s5,
            child: Text(
              at == null ? (noneLabel ?? '—') : '$at$unit',
              textAlign: TextAlign.center,
              style: D.subtitle.copyWith(
                color: at == null ? D.inkMuted : D.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _Round(
            icon: Icons.add_rounded,
            label: 'More $title',
            onTap: !canMore ? null : () => onChanged(at == null ? min : at + step),
          ),
        ],
      ),
    );
  }
}

/// A switch with its reason under it.
class SwitchField extends StatelessWidget {
  const SwitchField({
    super.key,
    required this.title,
    required this.sub,
    required this.value,
    required this.onChanged,
    this.first = false,
  });

  final String title;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
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
                Text(title, style: D.row.copyWith(color: D.ink)),
                Text(sub, style: D.statLabel.copyWith(color: D.inkFaint)),
              ],
            ),
          ),
          SizedBox(width: D.s2),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: D.onBrand,
            activeTrackColor: D.brand,
          ),
        ],
      ),
    );
  }
}

/// A label above a box, as every field in this design is drawn.
class TextFieldRow extends StatelessWidget {
  const TextFieldRow({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.fieldKey,
    this.first = false,
    this.lines = 1,
    this.keyboard,
    this.caps = TextCapitalization.none,
    this.digitsOnly = false,
    this.counter,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Key fieldKey;
  final bool first;
  final int lines;
  final TextInputType? keyboard;
  final TextCapitalization caps;
  final bool digitsOnly;

  /// A length to show, for a field with a limit worth knowing about.
  final int? counter;

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
              if (counter != null)
                ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (context, value, _) => Text(
                    '${value.text.characters.length}/$counter',
                    style: D.caption.copyWith(
                      color: value.text.characters.length > counter!
                          ? D.danger
                          : D.inkFaint,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: D.gapTight),
          Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(D.inputH),
            ),
            padding: EdgeInsets.symmetric(horizontal: D.s4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.rCard),
              border: Border.all(color: D.lineStrong),
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              key: fieldKey,
              controller: controller,
              minLines: lines,
              maxLines: lines,
              keyboardType: keyboard,
              textCapitalization: caps,
              inputFormatters: digitsOnly
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              style: D.input.copyWith(color: D.ink),
              decoration: D.bareField(
                hint: hint,
                hintStyle: D.input.copyWith(color: D.inkFaint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.on,
    required this.onTap,
    this.trailing,
    this.dashed = false,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;
  final IconData? trailing;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? D.brandTint : D.card,
        borderRadius: D.rPill,
        child: InkWell(
          onTap: onTap,
          borderRadius: D.rPill,
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(D.tap - D.s2),
            ),
            padding: EdgeInsets.symmetric(horizontal: D.s3),
            decoration: BoxDecoration(
              borderRadius: D.rPill,
              border: Border.all(
                color: on ? D.brand : (dashed ? D.line : D.lineStrong),
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
                if (trailing != null) ...[
                  SizedBox(width: D.gapTight),
                  Icon(trailing, size: D.icon, color: on ? D.brand : D.inkFaint),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: onTap == null ? D.track : D.brandTint,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: D.tap,
            height: D.tap,
            child: Icon(
              icon,
              size: D.iconMd,
              color: onTap == null ? D.inkFaint : D.brand,
            ),
          ),
        ),
      ),
    );
  }
}
