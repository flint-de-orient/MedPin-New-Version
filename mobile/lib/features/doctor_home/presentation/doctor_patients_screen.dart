import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../clinician/domain/clinician_models.dart';
import '../../clinician/presentation/clinician_providers.dart';

/// The doctor's Patients tab, from the canvas's Doctor-Patients and
/// Doctor-Patients-Search artboards.
///
/// ---- One screen, not two ----------------------------------------------------
///
/// The search artboard is this screen with the field in hand: the same rows,
/// a count of what matched, and a way to add somebody who is not on the roll.
/// Searching here therefore narrows this list rather than pushing a second
/// screen, which is also what the server does — `search` is a parameter of the
/// same list.
///
/// ---- The chips are the server's own orders, not invented buckets ------------
///
/// The artboard's chips are counted buckets — "Today · 12", "Follow-up due · 9",
/// "Abnormal results · 14" — and the server counts none of them. Rather than
/// show a number nobody can stand behind, the chips are the four orderings and
/// the one filter the list genuinely has: everybody, unread first, recent
/// visits first, by name, and high risk. Each re-asks the server; none of them
/// is a filter applied to whatever happened to be loaded.
class DoctorPatientsScreen extends ConsumerStatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  ConsumerState<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

/// What the chips ask for. `riskBand` narrows the roll; the rest order it.
enum _View {
  all('All', 'risk', null),
  unread('Unread first', 'inbox', null),
  recent('Recent visits', 'recent', null),
  name('By name', 'name', null),
  high('High risk', 'risk', 'high');

  const _View(this.label, this.sort, this.riskBand);

  final String label;
  final String sort;
  final String? riskBand;
}

class _DoctorPatientsScreenState extends ConsumerState<DoctorPatientsScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  _View _view = _View.all;
  int _pages = 1;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _search.text.trim().isNotEmpty;
    final query = (
      riskBand: _view.riskBand,
      search: searching ? _search.text.trim() : null,
      sort: _view.sort,
      pages: _pages,
    );
    final patients = ref.watch(patientsProvider(query));

    return Scaffold(
      backgroundColor: D.ground,
      body: SafeArea(
        bottom: false,
        // One scroll view, header included. The header is not a fixed block
        // above the list: at a large text size its title, search field and
        // wrapped chips are taller than the phone, and a fixed header that
        // tall leaves the roll no room at all — it overflowed by 117px.
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(patientsProvider(query)),
          child: ListView(
            padding: EdgeInsets.only(bottom: D.s6),
            children: [
              _Header(
                total: patients.valueOrNull?.total,
                search: _search,
                searchFocus: _searchFocus,
                view: _view,
                onView: (v) => setState(() {
                  _view = v;
                  _pages = 1;
                }),
                onSearchChanged: () => setState(() => _pages = 1),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, 0),
                child: patients.when(
                  loading: () => Padding(
                    padding: EdgeInsets.symmetric(vertical: D.s8),
                    child: const Center(child: CircularProgressIndicator(color: D.brand)),
                  ),
                  error: (_, _) => _Failed(onRetry: () => ref.invalidate(patientsProvider(query))),
                  data: (page) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(D.s1, 0, D.s1, D.s3),
                        child: Text(
                          searching
                              ? matchesLine(page.total, _search.text.trim())
                              : _view.label == 'All'
                                  ? 'EVERYBODY'
                                  : _view.label.toUpperCase(),
                          style: D.chip.copyWith(color: D.inkFaint),
                        ),
                      ),
                      for (final patient in page.items)
                        Padding(
                          padding: EdgeInsets.only(bottom: D.gapIcon),
                          child: _PatientCard(patient: patient),
                        ),
                      if (page.items.isEmpty) _NothingFound(searching: searching),
                      if (searching) const _AddInstead(),
                      if (page.hasMore)
                        Padding(
                          padding: EdgeInsets.only(top: D.s2),
                          child: TextButton(
                            onPressed: () => setState(() => _pages += 1),
                            child: Text(
                              'Show more patients',
                              style: D.subtitle.copyWith(color: D.brand, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "2 matches for “98765”" — the artboard's own line, and it counts the
/// server's total rather than the rows that happen to be on screen.
@visibleForTesting
String matchesLine(int total, String search) =>
    '$total MATCH${total == 1 ? '' : 'ES'} FOR “$search”';

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.search,
    required this.searchFocus,
    required this.view,
    required this.onView,
    required this.onSearchChanged,
  });

  /// Null until the roll has loaded: the line says nothing rather than zero.
  final int? total;
  final TextEditingController search;
  final FocusNode searchFocus;
  final _View view;
  final ValueChanged<_View> onView;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final searching = search.text.isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(D.s5, D.s4, D.s5, D.cardPad),
      decoration: const BoxDecoration(
        color: D.card,
        border: Border(bottom: BorderSide(color: D.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Patients', style: D.greeting.copyWith(color: D.ink)),
                    SizedBox(height: D.s1 / 2),
                    Text(
                      total == null ? ' ' : '$total patient${total == 1 ? '' : 's'}',
                      style: D.body.copyWith(color: D.inkMuted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: D.s3),
              FilledButton.icon(
                onPressed: () => context.push('/clinician/patients/new'),
                icon: const Icon(Icons.add_rounded, size: D.iconMd),
                label: Text('Add patient', style: D.dateLine),
                style: FilledButton.styleFrom(
                  backgroundColor: D.brandTint,
                  foregroundColor: D.brand,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(horizontal: D.s3),
                  minimumSize: D.hug,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
                ),
              ),
            ],
          ),
          SizedBox(height: D.cardPad),
          Container(
            // Scaled, not fixed: a constant height around text clips it the
            // moment the reader turns their text size up — and this clinic's
            // doctors are not the only ones who hold the phone.
            height: MediaQuery.textScalerOf(context).scale(D.discLg),
            padding: EdgeInsets.symmetric(horizontal: D.s4),
            decoration: BoxDecoration(
              color: D.card,
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
                    focusNode: searchFocus,
                    onChanged: (_) => onSearchChanged(),
                    textInputAction: TextInputAction.search,
                    style: D.subtitle.copyWith(color: D.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search by name or mobile number',
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
          // Wrapped, not scrolled sideways: five known chips, and a filter a
          // doctor cannot see is a filter they do not use.
          Wrap(
            spacing: D.s2,
            runSpacing: D.s2,
            children: [
              for (final v in _View.values)
                _Chip(label: v.label, selected: v == view, onTap: () => onView(v)),
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

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.patient});

  final PatientListItem patient;

  @override
  Widget build(BuildContext context) {
    final flag = flagFor(patient);

    return Container(
      padding: EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rCardLg),
        border: Border.all(color: D.line),
        boxShadow: D.lift,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(
                name: patient.name,
                avatarUrl: patient.avatarUrl,
                accent: D.brand,
                size: D.tap,
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
                        if (patient.lastMessage != null) ...[
                          SizedBox(width: D.s2),
                          Text(
                            lastSeenLabel(patient.lastMessage!.at),
                            style: D.caption.copyWith(color: D.inkFaint),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: D.s1 - 1),
                    Text(patient.phone, style: D.statLabel.copyWith(color: D.inkMuted)),
                    if (flag != null) ...[
                      SizedBox(height: D.s1),
                      Row(
                        children: [
                          Container(
                            width: D.gapTight,
                            height: D.gapTight,
                            decoration: BoxDecoration(color: flag.colour, shape: BoxShape.circle),
                          ),
                          SizedBox(width: D.gapTight),
                          Flexible(
                            child: Text(
                              flag.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: D.statLabel.copyWith(color: flag.colour, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: D.cardPad),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/clinician/patients/${patient.id}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: D.ink,
                    side: const BorderSide(color: D.line),
                    minimumSize: const Size.fromHeight(D.tap),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
                  ),
                  child: Text('View', style: D.subtitle.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
              SizedBox(width: D.s2),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.push('/clinician/patients/${patient.id}/consult'),
                  style: FilledButton.styleFrom(
                    backgroundColor: D.brandTint,
                    foregroundColor: D.brand,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(D.tap),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
                  ),
                  child: Text('Consult', style: D.subtitle.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one line under a patient's number: the most urgent true thing the roll
/// knows about them, or nothing.
///
/// The artboard's examples — "Urgent chat · not reviewed", "In queue · waiting
/// 22 min", "Creatinine up since last visit" — come from a queue and a result
/// trend the list does not carry. These are what it does carry, in the order a
/// doctor would want them.
@visibleForTesting
({String text, Color colour})? flagFor(PatientListItem p) {
  if (p.openAlertCount > 0) {
    return (
      text: p.openAlertCount == 1 ? '1 open alert' : '${p.openAlertCount} open alerts',
      colour: D.danger,
    );
  }
  if (p.unreadCount > 0) {
    return (
      text: p.unreadCount == 1 ? '1 unread message' : '${p.unreadCount} unread messages',
      colour: D.brand,
    );
  }
  if (p.riskBand == 'critical' || p.riskBand == 'high') {
    return (text: '${p.riskBand == 'critical' ? 'Critical' : 'High'} risk', colour: D.pending);
  }
  final reading = p.lastReadingValue;
  if (reading != null && p.lastReadingAt != null) {
    return (
      text: 'Last reading $reading · ${DateFormat('d MMM').format(p.lastReadingAt!)}',
      colour: D.inkMuted,
    );
  }
  return null;
}

/// When they last wrote: today's time, then the day, then the date.
@visibleForTesting
String lastSeenLabel(DateTime at, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(clock.year, clock.month, clock.day);
  final days = (today.difference(day).inHours / 24).round();
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat.E().format(at);
  return DateFormat('d MMM').format(at);
}

/// The artboard's dashed card: the patient may simply not be on the roll yet.
class _AddInstead extends StatelessWidget {
  const _AddInstead();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: D.s2),
      padding: EdgeInsets.all(D.cardPadLg),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rCardLg),
        border: Border.all(color: D.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Not the patient you’re looking for?',
            style: D.subtitle.copyWith(color: D.ink, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: D.s1),
          Text(
            'Add them, and you can start a consultation straight away.',
            style: D.body.copyWith(color: D.inkMuted),
          ),
          SizedBox(height: D.s3),
          FilledButton.icon(
            onPressed: () => context.push('/clinician/patients/new'),
            icon: const Icon(Icons.add_rounded, size: D.iconMd),
            label: Text('Add new patient', style: D.subtitle.copyWith(fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: D.brandTint,
              foregroundColor: D.brand,
              elevation: 0,
              minimumSize: const Size.fromHeight(D.tap),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.s3)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NothingFound extends StatelessWidget {
  const _NothingFound({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: D.s8),
      child: Column(
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.people_alt_outlined,
            size: D.s8,
            color: D.inkFaint,
          ),
          SizedBox(height: D.s3),
          Text(
            searching ? 'Nobody matches that.' : 'No patients on your roll yet.',
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
              'The patient list did not load.',
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
