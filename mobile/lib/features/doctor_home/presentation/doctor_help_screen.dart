import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../core/update/build_info.dart';
import '../../../shared/widgets/error_view.dart';
import '../../clinician/data/clinician_repository.dart';
import '../../clinician/domain/support_request.dart';
import '../../clinician/presentation/widgets/team_parts.dart';
import '../../clinician/presentation/widgets/team_pickers.dart';
import 'widgets/profile_parts.dart';

/// This account's own support requests, newest first.
///
/// Its own provider rather than a field on the screen, so sending one and
/// then replying to it both refresh the same list.
final supportRequestsProvider =
    FutureProvider.autoDispose<List<SupportRequest>>((ref) {
  return ref.watch(clinicianRepositoryProvider).supportRequests();
});

/// Help and support (`Doctor-MyProfile` → Help and support).
///
/// ---- Why this is not an email address ------------------------------------
///
/// The row had nothing behind it, and the obvious fix — print support@ in the
/// copy — is worse than it looks. An address in an app is an address somebody
/// has to monitor forever, and the first time nobody does, a doctor who cannot
/// print a prescription writes into silence. A request that lands in a queue
/// with a state on it is a message somebody can be held to.
///
/// ---- Three things, in the order they help --------------------------------
///
/// The answers this app can give itself come first, because most of what gets
/// asked is a screen somebody has not found. Then what has already been asked,
/// so a doctor does not raise the same thing twice. Asking is last.
class DoctorHelpScreen extends ConsumerWidget {
  const DoctorHelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(supportRequestsProvider);
    final rows = async.valueOrNull ?? const <SupportRequest>[];

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
          'Help and support',
          style: D.screenTitle.copyWith(color: D.ink),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(supportRequestsProvider.future),
          child: ListView(
            padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
            children: [
              const ProfileEyebrow(label: 'ANSWERS'),
              SizedBox(height: D.s2),
              ProfileGroup(
                children: [
                  for (final (i, a) in _answers.indexed)
                    _Answer(answer: a, first: i == 0),
                ],
              ),
              SizedBox(height: D.s6),

              Row(
                children: [
                  const Expanded(child: ProfileEyebrow(label: 'WHAT YOU HAVE ASKED')),
                  if (async.isLoading)
                    const SizedBox(
                      width: D.icon,
                      height: D.icon,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: D.brand,
                      ),
                    ),
                ],
              ),
              SizedBox(height: D.s2),
              if (async case AsyncError(:final error))
                ProfileFailed(
                  error: error,
                  onRetry: () => ref.invalidate(supportRequestsProvider),
                )
              else if (rows.isEmpty && !async.isLoading)
                ProfileGroup(
                  children: [
                    ProfileRow(
                      first: true,
                      child: Text(
                        'Nothing yet.',
                        style: D.statLabel.copyWith(color: D.inkMuted),
                      ),
                    ),
                  ],
                )
              else
                ProfileGroup(
                  children: [
                    for (final (i, r) in rows.indexed)
                      _RequestRow(request: r, first: i == 0),
                  ],
                ),
              SizedBox(height: D.s6),

              TeamButton(
                label: 'Ask MedPin for help',
                icon: Icons.support_agent_outlined,
                onPressed: () => _ask(context, ref),
              ),
              SizedBox(height: D.s5),

              const ProfileEyebrow(label: 'WHAT WE WILL SEE'),
              SizedBox(height: D.s2),
              const _Facts(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    final asked = await showModalBottomSheet<({String topic, String message})>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: D.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
      ),
      builder: (_) => const _AskSheet(),
    );
    if (asked == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final made = await ref
          .read(clinicianRepositoryProvider)
          .askForHelp(topic: asked.topic, message: asked.message);
      ref.invalidate(supportRequestsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            // The reference, because the next thing that happens is often a
            // phone call, and this is what somebody reads out on it.
            'Sent. Your reference is ${made.reference}.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(ErrorView.messageFor(context, e))),
      );
    }
  }
}

// ----------------------------------------------------------------- answers

/// One thing this app can answer about itself.
typedef _Help = ({String question, String answer, String? goTo, String? go});

/// The questions that are a screen somebody has not found.
///
/// Every one of these is checkable against the app as it stands. Nothing here
/// describes a feature that does not exist, and nothing promises a timescale —
/// the commonest way a help page becomes a liability is by answering a
/// question the product has since stopped answering the same way.
const _answers = <_Help>[
  (
    question: 'A prescription printed without my registration number',
    answer: 'The number on a prescription is the practice’s, from the '
        'letterhead — not the one on your own profile. Set it under '
        'Prescription letterhead and signature.',
    goTo: 'Open the letterhead',
    go: '/clinician/more/signature',
  ),
  (
    question: 'A patient cannot book with me',
    answer: 'Booking needs three things: online booking open for the '
        'practice, hours published for you at that location, and the location '
        'open that day. The Schedules screen shows which of the three is '
        'missing.',
    goTo: 'Open schedules and slots',
    go: '/clinician/more/schedule',
  ),
  (
    question: 'A colleague cannot sign in',
    answer: 'Check they are on the People list and not suspended. Staff sign '
        'in with a code texted to their own number — nobody sets a '
        'colleague’s password, so there is none to reset.',
    goTo: 'Open People',
    go: '/clinician/team',
  ),
  (
    question: 'When do online fees reach my bank?',
    answer: 'Fees paid inside the app are collected by MedPin and sent to the '
        'account on your Payouts screen. Money taken at the desk never passes '
        'through us.',
    goTo: 'Open payouts',
    go: '/clinician/more/payouts',
  ),
  (
    question: 'I want a copy of my data, or my account removed',
    answer: 'Both go through the head of your practice, who raises it with '
        'us. Privacy and data says what is held about you.',
    goTo: 'Open privacy and data',
    go: '/clinician/more/privacy',
  ),
];

class _Answer extends StatefulWidget {
  const _Answer({required this.answer, required this.first});

  final _Help answer;
  final bool first;

  @override
  State<_Answer> createState() => _AnswerState();
}

class _AnswerState extends State<_Answer> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.answer;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: widget.first ? null : const Border(top: BorderSide(color: D.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              constraints: BoxConstraints(
                minHeight: MediaQuery.textScalerOf(context).scale(D.rowH),
              ),
              padding: EdgeInsets.symmetric(vertical: D.s2),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      a.question,
                      style: D.row.copyWith(color: D.ink),
                    ),
                  ),
                  SizedBox(width: D.s2),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: D.iconLg,
                    color: D.inkFaint,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            Padding(
              padding: EdgeInsets.only(bottom: D.s2),
              child: Text(
                a.answer,
                style: D.statLabel.copyWith(color: D.inkMuted, height: 1.5),
              ),
            ),
            if (a.go != null)
              Padding(
                padding: EdgeInsets.only(bottom: D.s2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.push(a.go!),
                    style: TextButton.styleFrom(
                      foregroundColor: D.brand,
                      padding: EdgeInsets.zero,
                      minimumSize: Size(
                        0,
                        MediaQuery.textScalerOf(context).scale(D.tap),
                      ),
                    ),
                    child: Text(
                      a.goTo!,
                      style: D.subtitle.copyWith(
                        color: D.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- the list

class _RequestRow extends ConsumerWidget {
  const _RequestRow({required this.request, required this.first});

  final SupportRequest request;
  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final (state, needsYou) = supportStateLabel(r);

    return ProfileLink(
      first: first,
      title: supportTopicLabel(r.topic),
      subtitle: [
        r.reference,
        if (r.createdAt != null) DateFormat('d MMM').format(r.createdAt!),
      ].join(' · '),
      badge: state,
      badgeGround: needsYou ? D.brandTint : D.track,
      badgeInk: needsYou ? D.brand : D.inkMuted,
      onTap: () => _open(context, ref, r),
    );
  }

  void _open(BuildContext context, WidgetRef ref, SupportRequest r) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: D.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
      ),
      builder: (_) => _ThreadSheet(request: r),
    );
  }
}

/// What was said, and the way to add to it.
class _ThreadSheet extends ConsumerStatefulWidget {
  const _ThreadSheet({required this.request});

  final SupportRequest request;

  @override
  ConsumerState<_ThreadSheet> createState() => _ThreadSheetState();
}

class _ThreadSheetState extends ConsumerState<_ThreadSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _failed;

  /// The thread as it now stands — replaced by whatever a write answers with,
  /// so the sheet does not have to be closed and reopened to see a reply land.
  late SupportRequest _r = widget.request;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final closed = _r.state == 'closed';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(D.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                supportTopicLabel(_r.topic),
                style: D.section.copyWith(color: D.ink),
              ),
              SizedBox(height: D.s1),
              Text(
                [
                  _r.reference,
                  if (_r.appVersion != null) 'from ${_r.appVersion}',
                  supportStateLabel(_r).$1,
                ].join(' · '),
                style: D.caption.copyWith(color: D.inkFaint),
              ),
              SizedBox(height: D.s5),

              _Said(text: _r.message, fromMedPin: false, at: _r.createdAt),
              for (final reply in _r.replies)
                _Said(
                  text: reply.text,
                  fromMedPin: reply.fromMedPin,
                  at: reply.at,
                ),

              if (_failed != null) ...[
                SizedBox(height: D.s4),
                TeamFailure(message: _failed!),
              ],

              SizedBox(height: D.s5),
              if (closed)
                Text(
                  // Said rather than leaving a dead box: a closed thread that
                  // still offers a reply field is a reply somebody writes and
                  // then loses.
                  'This request is closed. Raise a new one and mention '
                  '${_r.reference} if it comes back.',
                  style: D.statLabel.copyWith(color: D.inkMuted, height: 1.45),
                )
              else ...[
                TeamTextField(
                  controller: _text,
                  hint: 'Add to this request',
                  caps: TextCapitalization.sentences,
                  maxLength: 4000,
                  lines: 3,
                ),
                SizedBox(height: D.s3),
                TeamButton(
                  label: 'Send',
                  busy: _busy,
                  onPressed: _busy ? null : _send,
                ),
                TextButton(
                  onPressed: _busy ? null : _close,
                  style: TextButton.styleFrom(
                    foregroundColor: D.inkMuted,
                    minimumSize: Size.fromHeight(
                      MediaQuery.textScalerOf(context).scale(D.tap),
                    ),
                  ),
                  child: Text('Sorted — close it', style: D.subtitle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final next = await ref
          .read(clinicianRepositoryProvider)
          .replyToSupport(_r.id, text);
      ref.invalidate(supportRequestsProvider);
      if (!mounted) return;
      _text.clear();
      setState(() {
        _busy = false;
        _r = next;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }

  Future<void> _close() async {
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      await ref.read(clinicianRepositoryProvider).closeSupport(_r.id);
      ref.invalidate(supportRequestsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = ErrorView.messageFor(context, e);
      });
    }
  }
}

/// One message in the thread.
class _Said extends StatelessWidget {
  const _Said({required this.text, required this.fromMedPin, this.at});

  final String text;
  final bool fromMedPin;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: D.s3),
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: fromMedPin ? D.brandTint : D.track,
        borderRadius: BorderRadius.circular(D.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // Who said it, in a word. The alignment alone would carry it for
            // most people and not for somebody reading at three times the
            // text size, where everything is full width.
            fromMedPin ? 'MedPin' : 'You',
            style: D.caption.copyWith(
              color: fromMedPin ? D.brand : D.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: D.s1),
          Text(text, style: D.statLabel.copyWith(color: D.ink, height: 1.5)),
          if (at != null) ...[
            SizedBox(height: D.s1),
            Text(
              DateFormat('d MMM, h:mm a').format(at!),
              style: D.caption.copyWith(color: D.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- asking

class _AskSheet extends StatefulWidget {
  const _AskSheet();

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _message = TextEditingController();
  String _topic = 'bug';

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enough = _message.text.trim().length >= 10;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(D.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ask MedPin for help',
                style: D.section.copyWith(color: D.ink),
              ),
              SizedBox(height: D.s5),

              FieldLabel(
                label: 'What is it about?',
                child: Wrap(
                  spacing: D.s2,
                  runSpacing: D.s2,
                  children: [
                    for (final entry in supportTopics.entries)
                      TeamChip(
                        label: entry.value,
                        on: _topic == entry.key,
                        onTap: () => setState(() => _topic = entry.key),
                      ),
                  ],
                ),
              ),
              SizedBox(height: D.s5),

              FieldLabel(
                label: 'What happened?',
                note: 'Please do not put a patient’s name or number in '
                    'here. Say "a patient" — we can find the rest from '
                    'your practice if we need it.',
                child: TeamTextField(
                  controller: _message,
                  hint: 'Tapping Print on a prescription does nothing.',
                  caps: TextCapitalization.sentences,
                  maxLength: 4000,
                  lines: 4,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(height: D.s5),

              TeamButton(
                label: 'Send',
                onPressed: enough
                    ? () => Navigator.of(context).pop((
                        topic: _topic,
                        message: _message.text.trim(),
                      ))
                    : null,
              ),
              if (!enough)
                Padding(
                  padding: EdgeInsets.only(top: D.s2, left: D.s1),
                  child: Text(
                    'A sentence or two, so somebody can act on it.',
                    style: D.caption.copyWith(color: D.inkFaint),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- what we see

/// What goes with a request, listed rather than assumed.
///
/// A doctor about to write to a company should be able to see what that
/// company will be able to read. All three are already on the row the server
/// writes; this is only saying so.
class _Facts extends StatelessWidget {
  const _Facts();

  @override
  Widget build(BuildContext context) {
    final build = BuildInfo.current;

    return ProfileGroup(
      children: [
        ProfileLink(
          first: true,
          title: 'This app',
          value: '${build.version} (${build.build})',
        ),
        const ProfileLink(
          title: 'Your name and number',
          value: 'Sent',
        ),
        const ProfileLink(
          title: 'Which practice you work at',
          value: 'Sent',
        ),
        const ProfileLink(
          title: 'Anything about a patient',
          // The one that matters: nothing clinical is attached, and the form
          // asks the doctor not to type any.
          value: 'Not sent',
        ),
      ],
    );
  }
}
