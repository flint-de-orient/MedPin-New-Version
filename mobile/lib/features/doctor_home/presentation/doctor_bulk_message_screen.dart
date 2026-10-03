import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../clinician/domain/clinician_models.dart';
import '../../clinician/presentation/clinician_providers.dart';
import '../domain/bulk_message.dart';

/// Writing to several patients at once.
///
/// The artboard offers this in the new-chat sheet with one example beside it —
/// "everyone with a follow-up due this week" — and that example is the whole
/// design: this is not a mailing list, it is a way of saying one thing to a
/// group a doctor can already name. So the people come from the roll and from
/// the follow-up window, both of which the server already answers, and nothing
/// here invents a segment.
///
/// Each patient gets the message in their own thread and cannot see that
/// anybody else got it. See [BulkMessageController] for why this is a loop over
/// the ordinary send rather than a new endpoint.
class DoctorBulkMessageScreen extends ConsumerStatefulWidget {
  const DoctorBulkMessageScreen({super.key});

  @override
  ConsumerState<DoctorBulkMessageScreen> createState() => _DoctorBulkMessageScreenState();
}

class _DoctorBulkMessageScreenState extends ConsumerState<DoctorBulkMessageScreen> {
  final _search = TextEditingController();
  final _message = TextEditingController();

  /// Chosen, in the order they were chosen, so the send order is the order the
  /// doctor sees — "the first four went" has to mean something.
  final _chosen = <BulkRecipient>[];

  @override
  void dispose() {
    _search.dispose();
    _message.dispose();
    super.dispose();
  }

  bool _isChosen(String id) => _chosen.any((r) => r.id == id);

  void _toggle(BulkRecipient who) {
    setState(() {
      if (_isChosen(who.id)) {
        _chosen.removeWhere((r) => r.id == who.id);
      } else if (_chosen.length < kBulkLimit) {
        _chosen.add(who);
      }
    });
  }

  /// Everybody the server says is due or overdue inside the window.
  Future<void> _addFollowUps(int days) async {
    final due = await ref.read(followUpsProvider(days).future);
    if (!mounted) return;
    final people = [
      for (final p in [...due.overdue, ...due.due])
        if ((p.name ?? '').trim().isNotEmpty) BulkRecipient(id: p.id, name: p.name!.trim()),
    ];
    setState(() {
      for (final person in people) {
        if (!_isChosen(person.id) && _chosen.length < kBulkLimit) _chosen.add(person);
      }
    });
    if (!mounted) return;
    if (people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nobody is due a follow-up in that window.')),
      );
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _chosen.isEmpty) return;

    final people = List<BulkRecipient>.from(_chosen);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send to ${people.length} patient${people.length == 1 ? '' : 's'}?'),
        content: Text(
          'Each one gets this in their own chat, from your clinic. They will not '
          'see who else it went to.\n\n“$text”',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await ref.read(bulkMessageProvider.notifier).send(people, text);
    if (!mounted) return;

    final send = ref.read(bulkMessageProvider);
    // The conversations list has to show what was just said.
    ref.invalidate(patientsProvider);
    await _report(people, send);
  }

  /// What actually happened, by name, with a way to send to the ones it missed.
  Future<void> _report(List<BulkRecipient> people, BulkSend send) async {
    final missed = [
      for (final p in people)
        if (send.outcomes[p.id] == BulkOutcome.failed) p,
    ];

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: false,
      backgroundColor: D.card,
      barrierColor: D.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: D.s8 + D.s1,
                  height: D.s1,
                  decoration: const BoxDecoration(color: D.lineStrong, borderRadius: D.rPill),
                ),
              ),
              SizedBox(height: D.s5),
              Text(
                sendSummary(send, people.length),
                style: D.screenTitle.copyWith(color: missed.isEmpty ? D.ink : D.danger),
              ),
              SizedBox(height: D.s2),
              Text(
                missed.isEmpty
                    ? 'Each message is in that patient’s own chat now.'
                    : 'These did not go. Nothing was sent to them.',
                style: D.body.copyWith(color: D.inkMuted),
              ),
              if (missed.isNotEmpty) ...[
                SizedBox(height: D.s3),
                for (final p in missed)
                  Padding(
                    padding: EdgeInsets.only(bottom: D.gapTight),
                    child: Row(
                      children: [
                        const Icon(Icons.close_rounded, size: D.icon, color: D.danger),
                        SizedBox(width: D.s2),
                        Expanded(
                          child: Text(p.name, style: D.body.copyWith(color: D.ink)),
                        ),
                      ],
                    ),
                  ),
              ],
              SizedBox(height: D.s5),
              if (missed.isNotEmpty)
                FilledButton(
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    setState(() {
                      _chosen
                        ..clear()
                        ..addAll(missed);
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: D.brand,
                    foregroundColor: D.onBrand,
                    minimumSize: Size.fromHeight(
                      MediaQuery.textScalerOf(context).scale(D.inputH),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(D.rCard),
                    ),
                  ),
                  child: Text('Try these ${missed.length} again', style: D.dateLine),
                )
              else
                FilledButton(
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    context.pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: D.brand,
                    foregroundColor: D.onBrand,
                    minimumSize: Size.fromHeight(
                      MediaQuery.textScalerOf(context).scale(D.inputH),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(D.rCard),
                    ),
                  ),
                  child: Text('Done', style: D.dateLine),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted) ref.read(bulkMessageProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final search = _search.text.trim();
    final query = (
      riskBand: null,
      search: search.isEmpty ? null : search,
      sort: 'recent',
      pages: 1,
    );
    final patients = ref.watch(patientsProvider(query));
    final send = ref.watch(bulkMessageProvider);

    return Scaffold(
      backgroundColor: D.ground,
      appBar: AppBar(
        backgroundColor: D.ground,
        surfaceTintColor: D.ground,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: MediaQuery.textScalerOf(context).scale(D.bar),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded, size: D.iconDisc),
          color: D.ink,
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Text('Message several patients', style: D.screenTitle.copyWith(color: D.ink)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, D.s4),
                children: [
                  _SearchBox(
                    controller: _search,
                    onChanged: () => setState(() {}),
                  ),
                  SizedBox(height: D.s3),
                  // The artboard's own example, and the only group this server
                  // can name without being asked who is in it.
                  Row(
                    children: [
                      Expanded(
                        child: _Quick(
                          label: 'Follow-ups due this week',
                          onTap: () => _addFollowUps(7),
                        ),
                      ),
                      SizedBox(width: D.s2),
                      Expanded(
                        child: _Quick(
                          label: 'Due in 30 days',
                          onTap: () => _addFollowUps(30),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: D.s4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _chosen.isEmpty
                              ? 'NOBODY CHOSEN YET'
                              : '${_chosen.length} CHOSEN · UP TO $kBulkLimit',
                          style: D.chip.copyWith(color: D.inkFaint),
                        ),
                      ),
                      if (_chosen.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(_chosen.clear),
                          style: TextButton.styleFrom(minimumSize: D.hug),
                          child: Text(
                            'Clear',
                            style: D.dateLine.copyWith(color: D.brand),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: D.s2),
                  patients.when(
                    loading: () => Padding(
                      padding: EdgeInsets.symmetric(vertical: D.s8),
                      child: const Center(child: CircularProgressIndicator(color: D.brand)),
                    ),
                    error: (_, _) => Padding(
                      padding: EdgeInsets.symmetric(vertical: D.s6),
                      child: Text(
                        'The roll did not load.',
                        textAlign: TextAlign.center,
                        style: D.body.copyWith(color: D.inkMuted),
                      ),
                    ),
                    data: (page) {
                      // Whoever was chosen stays on the list even when a search
                      // would hide them, so nobody is silently dropped from a
                      // send they are already in.
                      final shown = <PatientListItem>[...page.items];
                      final ids = {for (final p in shown) p.id};
                      return Container(
                        decoration: BoxDecoration(
                          color: D.card,
                          borderRadius: BorderRadius.circular(D.rSection),
                          border: Border.all(color: D.line),
                          boxShadow: D.lift,
                        ),
                        child: Column(
                          children: [
                            for (final who in _chosen)
                              if (!ids.contains(who.id))
                                _Row(
                                  id: who.id,
                                  name: who.name,
                                  detail: 'Chosen',
                                  chosen: true,
                                  onTap: () => _toggle(who),
                                ),
                            for (final p in shown)
                              _Row(
                                id: p.id,
                                name: p.name,
                                detail: p.phone,
                                avatarUrl: p.avatarUrl,
                                chosen: _isChosen(p.id),
                                full: !_isChosen(p.id) && _chosen.length >= kBulkLimit,
                                onTap: () =>
                                    _toggle(BulkRecipient(id: p.id, name: p.name)),
                              ),
                            if (shown.isEmpty && _chosen.isEmpty)
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: D.s6),
                                child: Text(
                                  'Nobody matches that.',
                                  style: D.body.copyWith(color: D.inkMuted),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            _Composer(
              controller: _message,
              people: _chosen.length,
              send: send,
              onChanged: () => setState(() {}),
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// The design's search field: one box, one hairline, the icon inside it.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final searching = controller.text.isNotEmpty;
    return Container(
      height: MediaQuery.textScalerOf(context).scale(D.discLg),
      padding: EdgeInsets.symmetric(horizontal: D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rCard),
        border: Border.all(color: searching ? D.brand : D.lineStrong, width: searching ? 1.5 : 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: D.iconLg, color: D.inkFaint),
          SizedBox(width: D.gapIcon),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              style: D.subtitle.copyWith(color: D.ink),
              decoration: D.bareField(
                hint: 'Patient name or mobile',
                hintStyle: D.subtitle.copyWith(color: D.inkFaint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A group the server can name: adds everybody in it to the choice.
class _Quick extends StatelessWidget {
  const _Quick({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: D.brandTint,
      borderRadius: BorderRadius.circular(D.rCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(D.rCard),
        child: Container(
          constraints: BoxConstraints(
            minHeight: MediaQuery.textScalerOf(context).scale(D.tap),
          ),
          padding: EdgeInsets.symmetric(horizontal: D.s3, vertical: D.s2),
          child: Row(
            children: [
              const Icon(Icons.add_rounded, size: D.iconMd, color: D.brand),
              SizedBox(width: D.gapTight),
              Expanded(
                child: Text(label, style: D.statLabel.copyWith(color: D.brand)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One patient, and whether they are in the send.
class _Row extends StatelessWidget {
  const _Row({
    required this.id,
    required this.name,
    required this.detail,
    required this.chosen,
    required this.onTap,
    this.avatarUrl,
    this.full = false,
  });

  final String id;
  final String name;
  final String detail;
  final String? avatarUrl;
  final bool chosen;

  /// The limit is reached and this one is not in it — so it cannot be tapped,
  /// and says why rather than doing nothing.
  final bool full;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: chosen,
      button: true,
      child: InkWell(
        onTap: full ? null : onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s3),
          child: Row(
            children: [
              UserAvatar(name: name, avatarUrl: avatarUrl, accent: D.brand, size: D.disc - D.s2),
              SizedBox(width: D.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: D.subtitle.copyWith(
                        color: full ? D.inkFaint : D.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      full ? '$kBulkLimit is the most in one go' : detail,
                      style: D.statLabel.copyWith(color: D.inkFaint),
                    ),
                  ],
                ),
              ),
              SizedBox(width: D.s2),
              Icon(
                chosen ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: D.iconMark,
                color: chosen ? D.brand : D.lineStrong,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What to say, and the button that says it.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.people,
    required this.send,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final int people;
  final BulkSend send;
  final VoidCallback onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ready = people > 0 && controller.text.trim().isNotEmpty && !send.running;

    return Container(
      padding: EdgeInsets.fromLTRB(D.s4, D.s3, D.s4, D.s3),
      decoration: const BoxDecoration(
        color: D.card,
        border: Border(top: BorderSide(color: D.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.rCard),
              border: Border.all(color: D.lineStrong),
            ),
            child: TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              maxLength: 400,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => onChanged(),
              style: D.subtitle.copyWith(color: D.ink),
              decoration: D.bareField(
                hint: 'e.g. Your follow-up is due this week — please book a time.',
                hintStyle: D.subtitle.copyWith(color: D.inkFaint),
              ).copyWith(counterText: ''),
            ),
          ),
          SizedBox(height: D.s3),
          if (send.running)
            Padding(
              padding: EdgeInsets.only(bottom: D.s3),
              child: Row(
                children: [
                  const SizedBox(
                    width: D.icon,
                    height: D.icon,
                    child: CircularProgressIndicator(strokeWidth: 2, color: D.brand),
                  ),
                  SizedBox(width: D.s3),
                  Expanded(
                    child: Text(
                      'Sending · ${send.sent + send.failed} of $people',
                      style: D.statLabel.copyWith(color: D.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
          FilledButton(
            onPressed: ready ? onSend : null,
            style: FilledButton.styleFrom(
              backgroundColor: D.brand,
              foregroundColor: D.onBrand,
              disabledBackgroundColor: D.line,
              disabledForegroundColor: D.inkFaint,
              elevation: 0,
              minimumSize: Size.fromHeight(MediaQuery.textScalerOf(context).scale(D.inputH)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rCard)),
            ),
            child: Text(
              people == 0
                  ? 'Choose who it goes to'
                  : 'Send to $people patient${people == 1 ? '' : 's'}',
              style: D.input.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(height: D.gapTight),
          Text(
            'Each patient gets this in their own chat. Nobody sees who else it went to.',
            textAlign: TextAlign.center,
            style: D.caption.copyWith(color: D.inkFaint),
          ),
        ],
      ),
    );
  }
}
