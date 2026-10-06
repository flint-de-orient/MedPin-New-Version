import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/doctor_tokens.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../clinician/data/practice_repository.dart';
import 'widgets/profile_parts.dart';

/// What MedPin holds about this account, and what it has agreed to
/// (`Doctor-MyProfile` → Privacy and data).
///
/// ---- Why this screen has no switches -----------------------------------
///
/// Nothing on it is a setting. A clinician cannot withdraw the data-processing
/// consent and keep using the app, because the app's whole function is
/// processing patient data on the practice's behalf — a switch that offered
/// that would either be a lie or would delete somebody's livelihood in one
/// tap. So this reads, and says who to ask for the two things it cannot do.
///
/// ---- Why there is no contact address here ------------------------------
///
/// There is no support address in this build. Writing one would be inventing
/// it, and an address that bounces is worse than being told to ask the
/// practice — which is true, reachable, and the route the law expects for a
/// staff account anyway. When a support contact is configured this screen is
/// where it goes.
class DoctorPrivacyScreen extends ConsumerWidget {
  const DoctorPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final consent = user?.consent;
    final practice = ref.watch(practiceOverviewProvider).valueOrNull;

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
          'Privacy and data',
          style: D.screenTitle.copyWith(color: D.ink),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
          children: [
            const ProfileEyebrow(label: 'WHAT YOU AGREED TO'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                _Agreed(
                  first: true,
                  title: 'Terms of use',
                  at: consent?.terms,
                ),
                _Agreed(
                  title: 'Processing patient data',
                  sub: 'On behalf of the practice you work for',
                  at: consent?.dataProcessing,
                ),
                _Agreed(
                  title: 'The assistant is not a diagnosis',
                  sub: 'Its answers are drafts for a clinician to check',
                  at: consent?.aiDisclaimer,
                ),
              ],
            ),
            if (consent?.isEmpty ?? true) ...[
              SizedBox(height: D.s2),
              Padding(
                padding: EdgeInsets.only(left: D.s1),
                child: Text(
                  // Not the same as a refusal, and said so: an account made
                  // before the record existed has nothing stored, and reading
                  // that as "you declined" would be the wrong fact about
                  // somebody who has used the app for a year.
                  'Nothing is recorded against this account. Accounts made '
                  'before MedPin kept these dates have none; it does not mean '
                  'anything was refused.',
                  style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                ),
              ),
            ],
            SizedBox(height: D.s6),

            const ProfileEyebrow(label: 'WHAT IS HELD ABOUT YOU'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                // Read off the account rather than listed from memory, so a
                // line here cannot claim a field the account does not have.
                _Held(
                  first: true,
                  label: 'Name',
                  value: user?.name,
                ),
                _Held(label: 'Mobile number', value: user?.phone),
                _Held(label: 'Email', value: user?.email),
                _Held(
                  label: 'Professional details',
                  value: _professionalCount(ref),
                ),
                _Held(
                  label: 'Where you work',
                  value: practice?.name,
                ),
              ],
            ),
            SizedBox(height: D.s2),
            Padding(
              padding: EdgeInsets.only(left: D.s1),
              child: Text(
                // The distinction that matters most on this screen, and the
                // one somebody asking for an erasure has to be told: their
                // own account and their patients' records are different
                // things with different owners.
                'Patient records are the practice’s, not yours and not '
                'MedPin’s. What you write into a consultation stays on the '
                'patient’s record if you leave.',
                style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
              ),
            ),
            SizedBox(height: D.s6),

            const ProfileEyebrow(label: 'A COPY, OR AN ERASURE'),
            SizedBox(height: D.s2),
            ProfileGroup(
              children: [
                ProfileRow(
                  first: true,
                  child: Text(
                    // What to actually do, rather than a button that opens a
                    // mail app with nothing to send it to.
                    'Ask the head of ${practice?.name ?? 'your practice'}. '
                    'They raise it with MedPin and can have your account '
                    'switched off, which stops you signing in without '
                    'touching anything you have written.',
                    style: D.statLabel.copyWith(color: D.inkMuted, height: 1.45),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// How much of the professional record is filled in — a count, not a list.
///
/// A screen that printed the registration number and the council back at
/// somebody would be a second place those live, and the Professional screen
/// is where they are read and changed.
String? _professionalCount(WidgetRef ref) {
  final u = ref.read(authControllerProvider).user;
  if (u == null) return null;
  final filled = [
    (u.registrationNo ?? '').isNotEmpty,
    (u.qualifications ?? '').isNotEmpty,
    u.degrees.isNotEmpty,
    u.specialisations.isNotEmpty,
    (u.bio ?? '').isNotEmpty,
  ].where((e) => e).length;
  if (filled == 0) return 'None filled in';
  return '$filled of 5 filled in';
}

/// One agreement and the day it was given.
class _Agreed extends StatelessWidget {
  const _Agreed({
    required this.title,
    required this.at,
    this.sub,
    this.first = false,
  });

  final String title;
  final String? sub;
  final DateTime? at;
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
                if (sub != null)
                  Text(sub!, style: D.statLabel.copyWith(color: D.inkFaint)),
              ],
            ),
          ),
          SizedBox(width: D.s2),
          if (at == null)
            Text(
              'Not recorded',
              style: D.statLabel.copyWith(color: D.inkFaint),
            )
          else
            Row(
              children: [
                const Icon(Icons.check_rounded, size: D.iconMd, color: D.done),
                SizedBox(width: D.s1),
                Text(
                  DateFormat('d MMM yyyy').format(at!),
                  style: D.statLabel.copyWith(color: D.inkMuted),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One thing the account holds, and what it currently is.
class _Held extends StatelessWidget {
  const _Held({required this.label, required this.value, this.first = false});

  final String label;
  final String? value;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final set = (value ?? '').isNotEmpty;
    return ProfileRow(
      first: first,
      child: Row(
        children: [
          Expanded(child: Text(label, style: D.row.copyWith(color: D.ink))),
          SizedBox(width: D.s2),
          Flexible(
            child: Text(
              set ? value! : 'Not set',
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: D.statLabel.copyWith(
                color: set ? D.inkMuted : D.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
