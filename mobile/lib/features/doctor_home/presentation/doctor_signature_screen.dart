import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/doctor_tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/data/upload_repository.dart';
import '../../../shared/widgets/authed_image.dart';
import '../../auth/presentation/auth_controller.dart';
import 'widgets/profile_parts.dart';

/// The signature that prints on every prescription.
///
/// ---- Why it has a screen of its own ----------------------------------------
///
/// It was a dialog inside the Profile tab, which made it unreachable from
/// anywhere else — and My profile's "Letterhead and signature" row pointed at
/// the Practice screen, which has no signature control at all. One upload, one
/// route, and both screens link to it.
///
/// ---- Why the preview is the size of the card ------------------------------
///
/// "Set" tells a doctor a file exists. It does not tell them whether it is the
/// right signature, the right way up, or legible — and the first place they
/// would otherwise find out is a prescription already sent. It is drawn on
/// white whatever the theme, because the ink is cut out on transparency and
/// prints onto paper; near-black on a dark card would look like nothing.
class DoctorSignatureScreen extends ConsumerStatefulWidget {
  const DoctorSignatureScreen({super.key});

  @override
  ConsumerState<DoctorSignatureScreen> createState() =>
      _DoctorSignatureScreenState();
}

class _DoctorSignatureScreenState extends ConsumerState<DoctorSignatureScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final signature = user?.signatureUrl;

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
        title: Text('Digital signature', style: D.screenTitle.copyWith(color: D.ink)),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s8),
          children: [
            Padding(
              padding: EdgeInsets.only(left: D.s1, bottom: D.s4),
              child: Text(
                signature == null
                    ? 'Every prescription you write goes out unsigned until '
                          'this is uploaded.'
                    : 'Printed at the foot of every prescription you write.',
                style: D.statLabel.copyWith(
                  color: signature == null ? D.pending : D.inkMuted,
                  height: 1.45,
                ),
              ),
            ),
            if (signature != null) ...[
              const ProfileEyebrow(label: 'As it prints'),
              SizedBox(height: D.s2),
              Container(
                padding: EdgeInsets.symmetric(horizontal: D.s5, vertical: D.s4),
                decoration: BoxDecoration(
                  // White, always. See the note at the top of this file.
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(D.rSection),
                  border: Border.all(color: D.line),
                  boxShadow: D.lift,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: D.tileMin,
                      child: AuthedImage(
                        path: signature,
                        width: double.infinity,
                        height: D.tileMin,
                        radius: 0,
                        fit: BoxFit.contain,
                        background: Colors.white,
                      ),
                    ),
                    const Divider(height: 1, thickness: 1, color: D.line),
                    SizedBox(height: D.s2),
                    Text(
                      user?.name ?? '',
                      style: D.subtitle.copyWith(
                        // On the white plate, not the theme's ink.
                        color: D.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: D.s2),
              Padding(
                padding: EdgeInsets.only(left: D.s1),
                child: Text(
                  'The paper background is removed automatically, so this '
                  'prints as ink on the prescription.',
                  style: D.caption.copyWith(color: D.inkFaint, height: 1.4),
                ),
              ),
              SizedBox(height: D.s5),
            ],
            FilledButton.icon(
              key: const Key('sig-upload'),
              onPressed: _busy ? null : _upload,
              icon: _busy
                  ? const SizedBox(
                      width: D.icon,
                      height: D.icon,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: D.onBrand,
                      ),
                    )
                  : const Icon(Icons.draw_outlined, size: D.iconMd),
              label: Text(
                signature == null ? 'Upload a signature' : 'Replace it',
                style: D.bodyStrong.copyWith(color: D.onBrand),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: D.brand,
                disabledBackgroundColor: D.track,
                foregroundColor: D.onBrand,
                minimumSize: Size(
                  0,
                  MediaQuery.textScalerOf(context).scale(D.inputH),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(D.rCard),
                ),
              ),
            ),
            SizedBox(height: D.s4),
            Container(
              padding: EdgeInsets.all(D.s4),
              decoration: BoxDecoration(
                color: D.brandTint,
                borderRadius: BorderRadius.circular(D.rCard),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: D.iconLg,
                    color: D.brand,
                  ),
                  SizedBox(width: D.s3),
                  Expanded(
                    child: Text(
                      'Sign on plain white paper and photograph it straight on. '
                      'The clearer the ink, the better it prints.',
                      style: D.statLabel.copyWith(color: D.brand, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _upload() async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await pickImageSource(context);
    if (source == null) return;

    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 600,
      imageQuality: 90,
    );
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final asset = await ref
          .read(uploadRepositoryProvider)
          .uploadImage(
            path: file.path,
            filename: file.name,
            kind: UploadKind.signature,
          );
      final user = await ref
          .read(authRepositoryProvider)
          .updateMe(signatureAssetId: asset.id);
      ref.read(authControllerProvider.notifier).replaceUser(user);
      messenger.showSnackBar(const SnackBar(content: Text('Signature saved')));
    } on ApiException {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not upload the signature')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Camera or gallery, on the new design's sheet.
///
/// Shared, because the avatar and the signature both ask it and a sheet that
/// looks different depending on which one opened it reads as two apps.
Future<ImageSource?> pickImageSource(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<ImageSource>(
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
            for (final (i, option) in [
              (Icons.photo_camera_outlined, l10n.chatAttachCamera, ImageSource.camera),
              (Icons.photo_library_outlined, l10n.chatAttachGallery, ImageSource.gallery),
            ].indexed)
              ProfileRow(
                first: i == 0,
                onTap: () => Navigator.pop(ctx, option.$3),
                child: Row(
                  children: [
                    Icon(option.$1, size: D.iconLg, color: D.brand),
                    SizedBox(width: D.s3),
                    Expanded(
                      child: Text(option.$2, style: D.body.copyWith(color: D.ink)),
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
