import 'package:flutter/material.dart';

/// The new doctor design's scale: `D`.
///
/// ---- Why a second token file and not more of `T` ---------------------------
///
/// The app you have today is drawn from `T` (core/theme/tokens.dart) and must
/// keep looking exactly as it does. The new doctor screens are a different
/// design — lighter ground, larger cards, a floating bar — and folding their
/// values into `T` would change screens nobody asked to change.
///
/// So: one file, named for what it is, listed in tool/verify_tokens.dart's
/// exemptions beside `T`'s own. Everything the new screens draw comes from
/// here; a raw value in a widget still fails the build, which is the whole
/// point of the ratchet.
///
/// When the new design replaces the old one, this file becomes the scale and
/// `T` goes — not the other way round.
class D {
  const D._();

  // ============================================================== spacing
  //
  // The same 4px grid the rest of the app is on. A gap that "needs" 13 needs
  // 12 or 16.

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  // ================================================================= type
  //
  // Six sizes. 16 is the floor for anything a patient-facing clinician reads
  // at arm's length between consultations; 12 is for captions only.

  /// 28/1.1 heavy — "Hi, Dr. Sen". One per screen.
  ///
  /// 32 on the mock-up, which is 390dp wide. The clinic's phones are 360dp,
  /// where 32 pushed a real name ("Dr. Amit Kumar Dey") onto three lines and
  /// left the screen looking zoomed in.
  static const TextStyle greeting = TextStyle(
    fontSize: 28,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  /// 24/1.0 heavy — a stat card's number, the biggest thing in it.
  static const TextStyle metric = TextStyle(
    fontSize: 24,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  /// 20/1.25 heavy — a section heading ("Quick actions").
  static const TextStyle section = TextStyle(
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
  );

  /// 16/1.4 — body, and a tile's label.
  static const TextStyle body = TextStyle(fontSize: 16, height: 1.4);

  /// 16/1.3 semibold — a card's own title.
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );

  /// 14/1.35 — secondary prose, and a quick action's label.
  static const TextStyle small = TextStyle(fontSize: 14, height: 1.35);

  /// 13/1.3 bold — a quick action's label, two short lines at most.
  ///
  /// The one size off the scale, and measured rather than chosen. Three cards
  /// across a 360dp phone leave 96dp inside a card, and "Prescriptions" needs
  /// 100 at 14 and 93 at 13. At 16 — the mock-up's size, drawn for a 390dp
  /// screen — it broke in the middle of the word, which is how the clinic
  /// first saw it: "Prescriptio / ns".
  static const TextStyle tile = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );

  /// 12/1.3 — a stat card's label under its number. Same reason as [tile]:
  /// "appointments" does not fit a third of the screen at 14.
  static const TextStyle caption = TextStyle(fontSize: 12, height: 1.3);

  /// 12/1.2 semibold — the bar's labels, a chip, a count.
  static const TextStyle label = TextStyle(
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  // =============================================================== colour
  //
  // One brand blue, one tint of it, three inks, and the clinical semantics.
  // Nothing decorative: a colour on this screen always means something.

  /// The brand, as the rest of the app already has it.
  static const Color brand = Color(0xFF003399);

  /// The disc behind a quick action's icon, and the bar's active pill.
  static const Color brandTint = Color(0xFFE8F0FD);

  /// The page itself — a very light blue-grey the white cards sit on.
  static const Color ground = Color(0xFFF3F6FB);
  static const Color card = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFE6ECF5);

  static const Color ink = Color(0xFF0A1B33);
  static const Color inkMuted = Color(0xFF5A6B84);
  static const Color inkFaint = Color(0xFF8795AB);

  /// Waiting, and done. Both carry a word as well as a colour — red-green
  /// deficiency is common among these patients' doctors too.
  static const Color pending = Color(0xFFB45309);
  static const Color done = Color(0xFF076B3C);

  /// An emergency: its card, its edge, the disc its mark sits on, its words.
  static const Color dangerGround = Color(0xFFFDECEC);
  static const Color dangerLine = Color(0xFFF3C9C9);
  static const Color dangerMark = Color(0xFFC21C1C);
  static const Color danger = Color(0xFFB4211F);

  /// A count nobody has read yet.
  static const Color badge = Color(0xFFD92D20);
  static const Color onBrand = Color(0xFFFFFFFF);

  // ================================================================ shape

  /// A card: the stat cards, the emergency card, a quick action.
  static const double rCard = 20;

  /// Inside a card: the icon disc, a chip.
  static const double rInner = 16;

  /// The floating bar at the foot of the screen.
  static const double rBar = 28;

  /// A count, a "NEW" chip.
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(999));

  /// One soft shadow, one light source, used only where a card lifts off the
  /// ground. The bar gets a slightly deeper one because it floats over content.
  static const List<BoxShadow> lift = [
    BoxShadow(color: Color(0x0D0A1B33), blurRadius: 16, offset: Offset(0, 6)),
  ];
  static const List<BoxShadow> liftBar = [
    BoxShadow(color: Color(0x140A1B33), blurRadius: 24, offset: Offset(0, 8)),
  ];

  // ================================================================= size

  /// Nothing tappable is smaller than this.
  static const double tap = 48;

  /// The disc behind a quick action's icon.
  static const double disc = 40;
}
