import 'package:flutter/material.dart';

import '../../../../core/theme/doctor_tokens.dart';

/// Turning a request down, and the one thing the doctor should know first.
///
/// ---- Why this asks at all -------------------------------------------------
///
/// The server tells the patient. It writes a line into the thread they asked
/// in and sends a push, and neither can be unsent — so a mis-tap on a row
/// between two other rows is a patient told they cannot be seen. A sheet is
/// one tap of friction against an action with no undo.
///
/// ---- Why the reason says who reads it ------------------------------------
///
/// It goes to the patient, in their own thread, exactly as typed. Somebody
/// writing "diary full, try him next week" believing it is a private note has
/// written that to the patient. So the field says whose words these become,
/// above the box rather than under it.
///
/// Returns the reason — possibly empty, which is a decline with no reason
/// given — or null if the doctor backed out.
Future<String?> declineRequest(BuildContext context, String who) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: D.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
    ),
    builder: (_) => _DeclineSheet(who: who),
  );
}

class _DeclineSheet extends StatefulWidget {
  const _DeclineSheet({required this.who});

  final String who;

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  final _reason = TextEditingController();

  /// The reasons a request is actually turned down here, so the commonest
  /// answer is a tap. Each is written as the patient will read it.
  static const _canned = [
    'The day you asked for is full.',
    'I am not consulting that day.',
    'Please ask the desk to book you in.',
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The keyboard, or the box sits under it.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(D.s5, D.s5, D.s5, D.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Decline this request?',
                style: D.section.copyWith(color: D.ink),
              ),
              SizedBox(height: D.s1),
              Text(
                '${widget.who} will be told, and asked to request another day. '
                'They will not be given a time.',
                style: D.statLabel.copyWith(color: D.inkMuted, height: 1.45),
              ),
              SizedBox(height: D.s5),

              Text(
                'What they will be told (optional)',
                style: D.bodyStrong.copyWith(color: D.ink),
              ),
              SizedBox(height: D.s2),
              Wrap(
                spacing: D.s2,
                runSpacing: D.s2,
                children: [
                  for (final line in _canned)
                    _Canned(
                      label: line,
                      onTap: () => setState(() => _reason.text = line),
                      on: _reason.text == line,
                    ),
                ],
              ),
              SizedBox(height: D.s3),
              TextField(
                controller: _reason,
                maxLines: 3,
                minLines: 2,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                style: D.input.copyWith(color: D.ink),
                decoration: InputDecoration(
                  hintText: 'Or write your own',
                  hintStyle: D.input.copyWith(color: D.inkFaint),
                  counterText: '',
                  filled: true,
                  fillColor: D.card,
                  contentPadding: EdgeInsets.all(D.s4),
                  border: _border(D.lineStrong),
                  enabledBorder: _border(D.lineStrong),
                  focusedBorder: _border(D.brand),
                ),
              ),
              SizedBox(height: D.s2),
              Text(
                // Said once, plainly, because the alternative is a doctor
                // discovering it after the fact.
                'This goes to the patient in their own chat, word for word.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
              SizedBox(height: D.s5),

              FilledButton(
                onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: D.danger,
                  foregroundColor: D.onBrand,
                  elevation: 0,
                  minimumSize: Size.fromHeight(
                    MediaQuery.textScalerOf(context).scale(D.inputH),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(D.rCard),
                  ),
                ),
                child: Text(
                  'Decline the request',
                  style: D.subhead.copyWith(color: D.onBrand),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: D.inkMuted,
                  minimumSize: Size.fromHeight(
                    MediaQuery.textScalerOf(context).scale(D.tap),
                  ),
                ),
                child: Text('Keep it waiting', style: D.subtitle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static OutlineInputBorder _border(Color colour) => OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(D.rCard)),
        borderSide: BorderSide(color: colour),
      );
}

/// A reason somebody can tap instead of typing.
class _Canned extends StatelessWidget {
  const _Canned({required this.label, required this.on, required this.onTap});

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
          constraints: BoxConstraints(
            minHeight: MediaQuery.textScalerOf(context).scale(D.tap),
            // Never wider than the sheet: these are sentences, and a sentence
            // in a pill has to be allowed to wrap inside it.
            maxWidth: 320,
          ),
          padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s2),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: on ? D.brandTint : D.card,
            borderRadius: D.rPill,
            border: Border.all(color: on ? D.brand : D.lineStrong),
          ),
          child: Text(
            label,
            softWrap: true,
            style: D.subtitle.copyWith(
              color: on ? D.brand : D.inkMuted,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
