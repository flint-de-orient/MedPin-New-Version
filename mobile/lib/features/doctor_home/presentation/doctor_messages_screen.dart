import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../clinician/domain/clinician_models.dart';
import '../../clinician/presentation/clinician_providers.dart';

/// The doctor's Messages tab, from the canvas's Doctor-Messages and
/// Doctor-Messages-New artboards.
///
/// ---- Patients, because colleagues have nowhere to go ------------------------
///
/// The artboard mixes two kinds of conversation: patients, and colleagues —
/// another doctor, the dietician, the front desk. The table that carried
/// colleague messages was retired from this server, so the Colleagues tab says
/// so rather than showing an empty list that looks like nobody has written.
///
/// The patient half is real, and it is the same inbox the roll is sorted by:
/// every row's name, preview, time and unread count come from the server's own
/// `inbox` ordering, so this screen and the Patients tab cannot disagree.
class DoctorMessagesScreen extends ConsumerStatefulWidget {
  const DoctorMessagesScreen({super.key});

  @override
  ConsumerState<DoctorMessagesScreen> createState() => _DoctorMessagesScreenState();
}

enum _Tab { all('All'), unread('Unread'), patients('Patients'), colleagues('Colleagues');

  const _Tab(this.label);

  final String label;
}

class _DoctorMessagesScreenState extends ConsumerState<DoctorMessagesScreen> {
  final _search = TextEditingController();
  _Tab _tab = _Tab.all;
  int _pages = 1;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _search.text.trim().isNotEmpty;
    final query = (
      riskBand: null,
      search: searching ? _search.text.trim() : null,
      sort: 'inbox',
      pages: _pages,
    );
    final patients = ref.watch(patientsProvider(query));
    final waiting = ref.watch(clinicianNotificationsProvider).valueOrNull?.messages;

    return Scaffold(
      backgroundColor: D.ground,
      floatingActionButton: _tab == _Tab.colleagues
          ? null
          : FloatingActionButton.extended(
              onPressed: () => newChat(context, ref),
              backgroundColor: D.brand,
              foregroundColor: D.onBrand,
              icon: const Icon(Icons.edit_outlined, size: D.iconLg),
              label: Text('New chat', style: D.body.copyWith(fontWeight: FontWeight.w600)),
            ),
      body: SafeArea(
        bottom: false,
        // One scroll view, header included — see the Patients tab for why: a
        // fixed header holding a title, a search field and wrapped tabs is
        // taller than the phone once the reader turns their text size up, and
        // then the conversations have nowhere to go.
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(patientsProvider(query)),
          child: ListView(
            padding: EdgeInsets.only(bottom: D.s8 + D.s8),
            children: [
              _Header(
                waiting: waiting,
                urgent: urgentCount(patients.valueOrNull?.items ?? const []),
                search: _search,
                tab: _tab,
                onTab: (t) => setState(() {
                  _tab = t;
                  _pages = 1;
                }),
                onSearchChanged: () => setState(() => _pages = 1),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, 0),
                child: switch (_tab) {
                  _Tab.colleagues => const _ColleaguesNotBuilt(),
                  _ => patients.when(
                    loading: () => Padding(
                      padding: EdgeInsets.symmetric(vertical: D.s8),
                      child: const Center(child: CircularProgressIndicator(color: D.brand)),
                    ),
                    error: (_, _) => _Failed(onRetry: () => ref.invalidate(patientsProvider(query))),
                    data: (page) {
                      final rows = [
                        for (final p in page.items)
                          if (p.lastMessage != null && (_tab != _Tab.unread || p.unreadCount > 0)) p,
                      ];
                      final urgent = [for (final p in rows) if (isUrgent(p)) p];
                      final rest = [for (final p in rows) if (!isUrgent(p)) p];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final p in urgent)
                            Padding(
                              padding: EdgeInsets.only(bottom: D.s4),
                              child: _UrgentCard(patient: p),
                            ),
                          if (rest.isNotEmpty) _Conversations(patients: rest),
                          if (rows.isEmpty) _Empty(tab: _tab, searching: searching),
                          if (page.hasMore)
                            TextButton(
                              onPressed: () => setState(() => _pages += 1),
                              child: Text(
                                'Show more',
                                style: D.subtitle.copyWith(color: D.brand, fontWeight: FontWeight.w600),
                              ),
                            ),
                          SizedBox(height: D.s4),
                          Text(
                            'Patient chats are saved to their records. Urgent messages also alert your front desk.',
                            textAlign: TextAlign.center,
                            style: D.caption.copyWith(color: D.inkFaint, height: 1.5),
                          ),
                        ],
                      );
                    },
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A conversation whose last word from the patient was triaged urgent, which
/// is the one the artboard lifts out of the list in red.
@visibleForTesting
bool isUrgent(PatientListItem p) {
  final urgency = p.lastMessage?.urgency;
  return urgency == 'urgent' || urgency == 'emergency';
}

@visibleForTesting
int urgentCount(List<PatientListItem> patients) => patients.where(isUrgent).length;

class _Header extends StatelessWidget {
  const _Header({
    required this.waiting,
    required this.urgent,
    required this.search,
    required this.tab,
    required this.onTab,
    required this.onSearchChanged,
  });

  /// Unread patient messages, as the server counts them across the practice —
  /// not a tally of the rows that happen to be loaded.
  final int? waiting;
  final int urgent;
  final TextEditingController search;
  final _Tab tab;
  final ValueChanged<_Tab> onTab;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final searching = search.text.isNotEmpty;
    final line = [
      if (waiting != null) '$waiting unread',
      if (urgent > 0) '$urgent urgent',
    ].join(' · ');

    return Container(
      padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.cardPad),
      decoration: const BoxDecoration(
        color: D.card,
        border: Border(bottom: BorderSide(color: D.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Messages', style: D.greeting.copyWith(color: D.ink)),
          SizedBox(height: D.s1 / 2),
          Text(line.isEmpty ? ' ' : line, style: D.body.copyWith(color: D.inkMuted)),
          SizedBox(height: D.cardPad),
          Container(
            // Scaled, not fixed: a constant height around text clips it the
            // moment the reader turns their text size up.
            height: MediaQuery.textScalerOf(context).scale(D.disc),
            padding: EdgeInsets.symmetric(horizontal: D.s4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(D.rCard),
              border: Border.all(color: searching ? D.brand : D.line, width: searching ? 1.5 : 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, size: D.iconLg, color: D.inkFaint),
                SizedBox(width: D.gapIcon),
                Expanded(
                  child: TextField(
                    controller: search,
                    onChanged: (_) => onSearchChanged(),
                    style: D.subtitle.copyWith(color: D.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search people',
                      hintStyle: D.subtitle.copyWith(color: D.inkFaint),
                    ),
                  ),
                ),
                if (searching)
                  IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: D.iconMd),
                    color: D.inkMuted,
                    onPressed: () {
                      search.clear();
                      onSearchChanged();
                    },
                  ),
              ],
            ),
          ),
          SizedBox(height: D.cardPad),
          // Wrapped, not scrolled sideways: four known tabs, and one a doctor
          // cannot see is one they do not use.
          Wrap(
            spacing: D.s2,
            runSpacing: D.s2,
            children: [
              for (final t in _Tab.values)
                _Chip(label: t.label, selected: t == tab, onTap: () => onTab(t)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? D.brand : D.card,
        borderRadius: D.rPill,
        child: InkWell(
          onTap: onTap,
          borderRadius: D.rPill,
          child: Container(
            // No `alignment` here, and the height is a minimum, not a box.
            // An aligned Container with no width fills whatever bounds it is
            // handed, and a Wrap hands it the whole screen — that is how a row
            // of chips becomes a stack of full-width bars.
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(D.tap),
            ),
            padding: EdgeInsets.symmetric(horizontal: D.cardPad),
            decoration: BoxDecoration(
              borderRadius: D.rPill,
              border: Border.all(color: selected ? D.brand : D.line),
            ),
            // widthFactor keeps the chip the width of its own label; the
            // height is free to fill the 44 above, which centres the text.
            child: Align(
              widthFactor: 1,
              child: Text(
                label,
                style: D.dateLine.copyWith(color: selected ? D.onBrand : D.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The red card the artboard puts above the list: the conversation where
/// somebody said something that triage called urgent.
class _UrgentCard extends StatelessWidget {
  const _UrgentCard({required this.patient});

  final PatientListItem patient;

  @override
  Widget build(BuildContext context) {
    final message = patient.lastMessage!;

    return Material(
      color: D.dangerGround,
      borderRadius: BorderRadius.circular(D.rCardLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(D.rCardLg),
        onTap: () => context.push('/clinician/patients/${patient.id}/thread'),
        child: Container(
          padding: EdgeInsets.all(D.s4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(D.rCardLg),
            border: Border.all(color: D.dangerLine),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(
                name: patient.name,
                avatarUrl: patient.avatarUrl,
                accent: D.danger,
                size: D.disc,
              ),
              SizedBox(width: D.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            patient.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: D.body.copyWith(color: D.ink, fontWeight: FontWeight.w700),
                          ),
                        ),
                        SizedBox(width: D.s2),
                        Text(
                          atLabel(message.at),
                          style: D.caption.copyWith(color: D.danger, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    SizedBox(height: D.s1),
                    Text(
                      '${message.urgency == 'emergency' ? 'EMERGENCY' : 'URGENT'} · PATIENT',
                      style: D.chip.copyWith(color: D.danger),
                    ),
                    SizedBox(height: D.s1),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            previewOf(message),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: D.body.copyWith(color: D.ink, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (patient.unreadCount > 0) ...[
                          SizedBox(width: D.s2),
                          _Badge(count: patient.unreadCount, colour: D.danger),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Conversations extends StatelessWidget {
  const _Conversations({required this.patients});

  final List<PatientListItem> patients;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.s6),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < patients.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, indent: D.s4 + D.disc + D.s3, color: D.line),
              _Row(patient: patients[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.patient});

  final PatientListItem patient;

  @override
  Widget build(BuildContext context) {
    final message = patient.lastMessage!;
    final unread = patient.unreadCount > 0;

    return InkWell(
      onTap: () => context.push('/clinician/patients/${patient.id}/thread'),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: D.s4, vertical: D.cardPad),
        child: Row(
          children: [
            UserAvatar(
              name: patient.name,
              avatarUrl: patient.avatarUrl,
              accent: D.brand,
              size: D.disc,
            ),
            SizedBox(width: D.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          patient.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: D.body.copyWith(
                            color: D.ink,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(width: D.s2),
                      Text(
                        atLabel(message.at),
                        style: D.caption.copyWith(
                          color: unread ? D.brand : D.inkFaint,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: D.s1 - 1),
                  Text('Patient', style: D.caption.copyWith(color: D.inkFaint)),
                  SizedBox(height: D.s1 - 1),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          previewOf(message),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: D.body.copyWith(
                            color: unread ? D.ink : D.inkMuted,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        SizedBox(width: D.s2),
                        _Badge(count: patient.unreadCount, colour: D.brand),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The last thing said, with "You:" in front of it when the clinic said it —
/// the patient's own words need no prefix, and a file or a voice note is named
/// for what it is.
@visibleForTesting
String previewOf(MessagePreview message) {
  final fromClinic = message.role != 'user';
  final body = message.preview.trim().isNotEmpty
      ? message.preview.trim()
      : switch (message.mediaType) {
          'image' => 'Photo',
          'audio' => 'Voice message',
          'application' => 'Document',
          _ => 'Attachment',
        };
  return fromClinic ? 'You: $body' : body;
}

/// Today's time, then the day, then the date.
@visibleForTesting
String atLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final clock = now ?? DateTime.now();
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(clock.year, clock.month, clock.day);
  final days = (today.difference(day).inHours / 24).round();
  if (days <= 0) return DateFormat.jm().format(at);
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat.E().format(at);
  return DateFormat('d MMM').format(at);
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.colour});

  final int count;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count unread',
      child: ExcludeSemantics(
        child: Container(
          height: MediaQuery.textScalerOf(context).scale(D.s6 - 2),
          constraints: BoxConstraints(
            minWidth: MediaQuery.textScalerOf(context).scale(D.s6 - 2),
          ),
          padding: EdgeInsets.symmetric(horizontal: D.gapTight),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colour, borderRadius: D.rPill),
          child: Text(
            count > 99 ? '99+' : '$count',
            style: D.caption.copyWith(color: D.onBrand, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// Who to write to: the artboard's sheet, with the half this server has.
Future<void> newChat(BuildContext context, WidgetRef ref) async {
  final chosen = await showModalBottomSheet<PatientListItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: D.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.s6)),
    ),
    builder: (_) => const _NewChatSheet(),
  );
  if (chosen != null && context.mounted) {
    context.push('/clinician/patients/${chosen.id}/thread');
  }
}

class _NewChatSheet extends ConsumerStatefulWidget {
  const _NewChatSheet();

  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final query = (
      riskBand: null,
      search: _search.trim().isEmpty ? null : _search.trim(),
      sort: 'recent',
      pages: 1,
    );
    final patients = ref.watch(patientsProvider(query));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            SizedBox(height: D.s3),
            Container(
              width: D.s8 + D.s1,
              height: D.s1,
              decoration: const BoxDecoration(color: D.line, borderRadius: D.rPill),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s3, D.s3),
              child: Row(
                children: [
                  Expanded(child: Text('New chat', style: D.screenTitle.copyWith(color: D.ink))),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, color: D.inkMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: D.s5),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _search = v),
                style: D.subtitle.copyWith(color: D.ink),
                decoration: InputDecoration(
                  hintText: 'Patient name or mobile',
                  hintStyle: D.subtitle.copyWith(color: D.inkFaint),
                  prefixIcon: const Icon(Icons.search_rounded, color: D.inkFaint),
                  filled: true,
                  fillColor: D.ground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(D.rCard),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            SizedBox(height: D.s4),
            Expanded(
              child: patients.when(
                loading: () => const Center(child: CircularProgressIndicator(color: D.brand)),
                error: (_, _) => Center(
                  child: Text('The list did not load.', style: D.body.copyWith(color: D.inkMuted)),
                ),
                data: (page) => ListView(
                  padding: EdgeInsets.fromLTRB(D.s5, 0, D.s5, D.s6),
                  children: [
                    Text(
                      _search.isEmpty ? 'PATIENTS SEEN RECENTLY' : 'MATCHES',
                      style: D.chip.copyWith(color: D.inkFaint),
                    ),
                    SizedBox(height: D.s2),
                    for (final p in page.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: UserAvatar(
                          name: p.name,
                          avatarUrl: p.avatarUrl,
                          accent: D.brand,
                          size: D.disc - D.s2,
                        ),
                        title: Text(
                          p.name,
                          style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(p.phone, style: D.statLabel.copyWith(color: D.inkMuted)),
                        onTap: () => Navigator.of(context).pop(p),
                      ),
                    if (page.items.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: D.s6),
                        child: Text(
                          'Nobody matches that.',
                          textAlign: TextAlign.center,
                          style: D.body.copyWith(color: D.inkMuted),
                        ),
                      ),
                    SizedBox(height: D.s5),
                    Text('COLLEAGUES & STAFF', style: D.chip.copyWith(color: D.inkFaint)),
                    SizedBox(height: D.s2),
                    Text(
                      'Messaging colleagues is not built yet.',
                      style: D.body.copyWith(color: D.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Said once, plainly, instead of an empty list that reads as silence.
class _ColleaguesNotBuilt extends StatelessWidget {
  const _ColleaguesNotBuilt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(D.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_2_outlined, size: D.s8, color: D.inkFaint),
            SizedBox(height: D.s3),
            Text(
              'Messaging colleagues is not built yet.',
              textAlign: TextAlign.center,
              style: D.cardTitle.copyWith(color: D.ink),
            ),
            SizedBox(height: D.s2),
            Text(
              'Your conversations with patients are here; the dietician’s thread is under Nutrition.',
              textAlign: TextAlign.center,
              style: D.body.copyWith(color: D.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tab, required this.searching});

  final _Tab tab;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: D.s8),
      child: Column(
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.forum_outlined,
            size: D.s8,
            color: D.inkFaint,
          ),
          SizedBox(height: D.s3),
          Text(
            searching
                ? 'Nobody matches that.'
                : tab == _Tab.unread
                    ? 'Nothing unread.'
                    : 'No conversations yet.',
            style: D.body.copyWith(color: D.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(D.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The conversations did not load.',
              textAlign: TextAlign.center,
              style: D.body.copyWith(color: D.inkMuted),
            ),
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
