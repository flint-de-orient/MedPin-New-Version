import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/error_view.dart';
import '../../clinician/data/practice_repository.dart';
import '../../clinician/domain/practice.dart';
import '../../clinician/presentation/widgets/team_parts.dart';
import '../../clinician/presentation/widgets/team_pickers.dart';
import 'widgets/profile_parts.dart';

/// Where this practice's money is sent (`Doctor-MyProfile` → Payouts and bank
/// account).
///
/// ---- Why a clinic has to tell us this at all -----------------------------
///
/// There is one Razorpay account and it is MedPin's. A fee a patient pays
/// inside the app therefore lands with us, not with the clinic, and we owe it
/// to them — this is the account it is owed into. Cash taken at the desk never
/// touches any of this, which the screen says, because a doctor who thinks
/// desk cash is routed through MedPin is a doctor who will not trust either
/// number.
///
/// ---- Why the account number is blank every time --------------------------
///
/// The server stores it `select: false` and sends back four digits. Nothing
/// can pre-fill the box, by design: an account number sitting in a text field
/// is an account number somebody can alter one digit of, and a wrong digit is
/// a transfer that leaves and does not arrive. Changing the account means
/// typing it out.
class DoctorPayoutsScreen extends ConsumerStatefulWidget {
  const DoctorPayoutsScreen({super.key});

  @override
  ConsumerState<DoctorPayoutsScreen> createState() =>
      _DoctorPayoutsScreenState();
}

class _DoctorPayoutsScreenState extends ConsumerState<DoctorPayoutsScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _ifsc = TextEditingController();
  final _bank = TextEditingController();
  final _upi = TextEditingController();

  /// Null until the practice has loaded, then its own copy.
  PayoutAccount? _saved;

  /// True once somebody starts replacing the account, so the number box is
  /// only shown when it is going to be used.
  bool _editing = false;

  bool _busy = false;
  String? _failed;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _ifsc.dispose();
    _bank.dispose();
    _upi.dispose();
    super.dispose();
  }

  /// Takes the saved account once, so a refresh behind the screen cannot
  /// overwrite what somebody is halfway through typing.
  void _adopt(PayoutAccount p) {
    if (_saved != null) return;
    _saved = p;
    _name.text = p.accountName ?? '';
    _ifsc.text = p.ifsc ?? '';
    _bank.text = p.bankName ?? '';
    _upi.text = p.upiId ?? '';
    // Nothing on file is nothing to replace, so the form opens ready to type.
    _editing = !p.onFile;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(practiceOverviewProvider);
    final practice = async.valueOrNull;
    if (practice != null) _adopt(practice.payout);
    final saved = _saved;

    return Scaffold(
      backgroundColor: D.ground,
      appBar: AppBar(
        backgroundColor: D.card,
        surfaceTintColor: D.card,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: D.line)),
        toolbarHeight: MediaQuery.textScalerOf(context).scale(D.bar),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded, size: D.iconDisc),
          color: D.ink,
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Text(
          'Payouts and bank account',
          style: D.screenTitle.copyWith(color: D.ink),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: switch ((async, practice)) {
          (AsyncError(:final error), _) => ListView(
              padding: EdgeInsets.all(D.s4),
              children: [
                ProfileFailed(
                  error: error,
                  onRetry: () => ref.invalidate(practiceOverviewProvider),
                ),
              ],
            ),
          (AsyncLoading(), _) =>
            const Center(child: CircularProgressIndicator(color: D.brand)),
          (_, null) => ProfileEmpty(
              text: 'This account is not attached to a practice yet.',
              icon: Icons.account_balance_outlined,
            ),
          (_, final p?) => _body(p, saved!),
        },
      ),
    );
  }

  Widget _body(PracticeOverview practice, PayoutAccount saved) {
    return Form(
      key: _form,
      child: ListView(
        padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
        children: [
          TeamNote(
            icon: Icons.account_balance_outlined,
            title: 'What is settled here',
            body: 'Fees patients pay inside the app are collected by MedPin '
                'and sent to this account. Money taken at the desk — cash, '
                'your own card machine, your own UPI — never passes through '
                'us and is not affected by anything on this screen.',
          ),
          SizedBox(height: D.s5),

          const ProfileEyebrow(label: 'ON FILE'),
          SizedBox(height: D.s2),
          ProfileGroup(
            children: [
              ProfileLink(
                first: true,
                title: 'Account',
                value: saved.line,
              ),
              if ((saved.upiId ?? '').isNotEmpty && saved.accountLast4 != null)
                ProfileLink(title: 'UPI id', value: saved.upiId),
              ProfileLink(
                title: 'Confirmed by MedPin',
                // What it is, not a tick: a confirmation is a transfer that
                // actually arrived, and only an operator can say so.
                value: saved.verifiedAt == null
                    ? 'Not yet'
                    : DateFormat('d MMM yyyy').format(saved.verifiedAt!),
              ),
              if (saved.updatedAt != null)
                ProfileLink(
                  title: 'Last changed',
                  value: DateFormat('d MMM yyyy').format(saved.updatedAt!),
                ),
            ],
          ),
          if (saved.onFile && saved.verifiedAt == null) ...[
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                // Said plainly, because "not yet" beside an account somebody
                // typed last month reads as something being wrong.
                'We confirm an account the first time a transfer reaches it. '
                'Until then this says "not yet", which is normal.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
          ],
          SizedBox(height: D.s6),

          const ProfileEyebrow(label: 'BANK ACCOUNT'),
          SizedBox(height: D.s2),
          FieldLabel(
            label: 'Account holder’s name',
            note: 'Exactly as the bank has it. A transfer to a name that does '
                'not match is returned.',
            child: TeamTextField(
              controller: _name,
              hint: 'City Care Clinic',
              caps: TextCapitalization.words,
              maxLength: 160,
            ),
          ),
          SizedBox(height: D.s4),

          if (_editing)
            FieldLabel(
              label: 'Account number',
              note: 'Typed once and not shown again — only the last four '
                  'digits are kept where they can be read back.',
              child: TeamTextField(
                controller: _number,
                hint: '6 to 18 digits',
                keyboard: TextInputType.number,
                maxLength: 18,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final n = (v ?? '').trim();
                  if (n.isEmpty) return null;
                  if (n.length < 6) return 'An account number is at least 6 digits.';
                  return null;
                },
              ),
            )
          else
            ProfileGroup(
              children: [
                ProfileLink(
                  first: true,
                  title: 'Account number',
                  value: saved.accountLast4 == null
                      ? 'Not set'
                      : '••••••${saved.accountLast4}',
                  onTap: () => setState(() => _editing = true),
                ),
              ],
            ),
          if (!_editing) ...[
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                'Tap it to replace the account. You will type the whole number.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
          ],
          SizedBox(height: D.s4),

          FieldLabel(
            label: 'IFSC',
            child: TeamTextField(
              controller: _ifsc,
              hint: 'SBIN0001234',
              maxLength: 11,
              caps: TextCapitalization.characters,
              formatters: [UpperCaseFormatter()],
              validator: (v) {
                final code = (v ?? '').trim().toUpperCase();
                if (code.isEmpty) return null;
                // The Reserve Bank's own shape. Checked here because the
                // alternative is finding out days later, as a returned
                // payment.
                if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(code)) {
                  return 'An IFSC is four letters, a zero, then six more.';
                }
                return null;
              },
            ),
          ),
          SizedBox(height: D.s4),

          FieldLabel(
            label: 'Bank and branch',
            note: 'Optional. Only so you can recognise the account on this '
                'screen.',
            child: TeamTextField(
              controller: _bank,
              hint: 'State Bank of India, Salt Lake',
              caps: TextCapitalization.words,
              maxLength: 120,
            ),
          ),
          SizedBox(height: D.s6),

          const ProfileEyebrow(label: 'OR UPI'),
          SizedBox(height: D.s2),
          FieldLabel(
            label: 'UPI id',
            note: 'Instead of a bank account, or as well as one. Either is '
                'enough for us to pay you.',
            child: TeamTextField(
              controller: _upi,
              hint: 'citycare@okaxis',
              maxLength: 120,
              validator: (v) {
                final id = (v ?? '').trim();
                if (id.isEmpty) return null;
                if (!RegExp(r'^[\w.\-]{2,64}@[A-Za-z]{2,32}$').hasMatch(id)) {
                  return 'A UPI id looks like name@bank.';
                }
                return null;
              },
            ),
          ),

          if (_failed != null) ...[
            SizedBox(height: D.s4),
            TeamFailure(message: _failed!),
          ],

          SizedBox(height: D.s6),
          TeamButton(
            label: 'Save account',
            busy: _busy,
            onPressed: _busy ? null : () => _save(practice),
          ),
          SizedBox(height: D.s4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: D.s1),
            child: Text(
              // The one thing a clinic should know before they change this.
              'Changing the account number means MedPin has to confirm the new '
              'one before the next payout, so a change made mid-month can '
              'delay that month’s transfer.',
              style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(PracticeOverview practice) async {
    if (!(_form.currentState?.validate() ?? false)) return;

    final number = _number.text.trim();
    final upi = _upi.text.trim();
    final ifsc = _ifsc.text.trim().toUpperCase();
    final saved = _saved!;

    // Replacing nothing: the number box was never opened, so whatever is on
    // file stays. The server needs it sent back, and the app does not have it
    // — so a save that touches only the name or the IFSC has to be refused
    // rather than quietly clearing the account.
    if (!_editing && saved.accountLast4 != null && number.isEmpty) {
      setState(() {
        _failed = 'To change anything about the bank account, tap the account '
            'number and type it again. We do not keep a copy the app can read.';
      });
      return;
    }

    if (number.isEmpty && upi.isEmpty) {
      setState(() {
        _failed = 'Give either a bank account with its IFSC, or a UPI id. '
            'Without one of those there is nowhere to send the money.';
      });
      return;
    }
    if (number.isNotEmpty && ifsc.isEmpty) {
      setState(() => _failed = 'A bank account needs its IFSC.');
      return;
    }

    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final after = await ref.read(practiceRepositoryProvider).update(practice.id, {
        'payout': {
          'accountName': _name.text.trim().isEmpty ? null : _name.text.trim(),
          'accountNumber': number.isEmpty ? null : number,
          'ifsc': ifsc.isEmpty ? null : ifsc,
          'bankName': _bank.text.trim().isEmpty ? null : _bank.text.trim(),
          'upiId': upi.isEmpty ? null : upi,
        },
      });
      if (!mounted) return;

      /*
       * Did it actually land?
       *
       * The route validates with a zod object, and zod *strips* keys it does
       * not know rather than refusing them. A server that predates this
       * field therefore drops `payout` in the middle, saves nothing, and
       * answers 200 — and the screen used to say "Saved".
       *
       * For a tagline that is a wasted tap. Here it is a clinic believing
       * MedPin knows where to send their money, and finding out at the end of
       * a month. So the answer is checked against what was sent, and nothing
       * is cleared when it does not match: the number stays in the box so it
       * can be sent again once the server has it.
       */
      if (!_landed(after, number: number, upi: upi)) {
        setState(() {
          _busy = false;
          _failed = 'This server has not been updated to store a payout '
              'account yet, so nothing was saved. Nothing has changed — try '
              'again once MedPin has deployed it.';
        });
        return;
      }

      ref.invalidate(practiceOverviewProvider);
      // Cleared rather than kept: the number is saved, and a box still
      // holding it is a box somebody can read it out of.
      _number.clear();
      setState(() {
        _busy = false;
        _editing = false;
        _saved = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved. We will confirm it on the next transfer.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }

  /// Whether the account the server answered with is the one that was sent.
  ///
  /// Checked on the account number where there is one, because that is the
  /// field that decides where money goes and the only one whose arrival
  /// cannot be inferred from anything else. The last four digits are all that
  /// comes back, which is enough: a server that stored the number returns
  /// them, and one that dropped the field returns null.
  ///
  /// UPI alone is checked on the id itself, since there is no number to read
  /// four digits off.
  ///
  /// A null practice — a deployment with no practice row at all — counts as
  /// not landed. Saying "saved" against a server that answered with nothing
  /// is the failure this whole check exists for.
  bool _landed(PracticeOverview? after, {required String number, required String upi}) {
    if (after == null) return false;
    if (number.isNotEmpty) {
      return after.payout.accountLast4 == number.substring(number.length - 4);
    }
    return after.payout.upiId == upi;
  }
}

/// Keeps an IFSC in the case the bank prints it in.
///
/// `textCapitalization` is a hint to the keyboard and nothing more: a pasted
/// code, or one typed on a keyboard that ignores the hint, stays lower case
/// and then fails a check the doctor cannot see the reason for.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}
