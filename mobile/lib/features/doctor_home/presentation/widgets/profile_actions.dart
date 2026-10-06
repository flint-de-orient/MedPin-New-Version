import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/doctor_tokens.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/providers/locale_provider.dart';
import '../../../../shared/widgets/language_picker.dart';
import '../../../auth/presentation/auth_controller.dart';
import 'profile_parts.dart';

/// The two things both profile screens do.
///
/// The boards put App language and Log out on the Profile tab *and* on the
/// settings hub. Two copies of a sheet drift — this app has already had the
/// language picker three times, in three shapes — so the act lives here once
/// and both screens call it.

/// What a language is called, in its own script.
///
/// A Bengali speaker has to find "বাংলা" while the app is still in English,
/// which is exactly the moment they need this row.
String languageName(String? code) =>
    LanguagePicker.options
        .where((o) => o.code == (code ?? 'en'))
        .map((o) => o.native)
        .firstOrNull ??
    'English';

/// The three the app speaks, on the sheet every other choice here uses.
Future<void> pickAppLanguage(BuildContext context, WidgetRef ref) async {
  final current = ref.read(localeControllerProvider)?.languageCode;
  final picked = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    showDragHandle: false,
    backgroundColor: D.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(D.rSection)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(D.s5, D.s3, D.s5, D.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: D.s8 + D.s3,
                height: D.s1,
                decoration: const BoxDecoration(
                  color: D.lineStrong,
                  borderRadius: D.rPill,
                ),
              ),
            ),
            SizedBox(height: D.s4),
            for (final (i, option) in LanguagePicker.options.indexed)
              ProfileRow(
                first: i == 0,
                onTap: () => Navigator.pop(ctx, option.code),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.native,
                        style: D.row.copyWith(color: D.ink),
                      ),
                    ),
                    if (option.code == current)
                      const Icon(Icons.check_rounded, size: D.iconLg, color: D.brand),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null) return;

  await ref.read(localeControllerProvider.notifier).setLanguage(picked);
  ref.read(authControllerProvider.notifier).updateLocalUserLanguage(picked);
  try {
    await ref.read(authRepositoryProvider).updateMe(language: picked);
  } on ApiException {
    // Local preference still applies.
  }
}

/// Ends the session, once the doctor has said so.
Future<void> confirmLogout(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: D.card,
      title: Text('Log out?', style: D.subhead.copyWith(color: D.ink)),
      content: Text(
        'You will need to log in again to open the clinic dashboard.',
        style: D.body.copyWith(color: D.inkMuted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Stay', style: D.bodyStrong.copyWith(color: D.inkMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            l10n.profileLogout,
            style: D.bodyStrong.copyWith(color: D.danger),
          ),
        ),
      ],
    ),
  );
  if (ok == true) await ref.read(authControllerProvider.notifier).logout();
}
