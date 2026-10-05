import 'package:flutter/material.dart';

/// The new doctor design's scale: `D`.
///
/// ---- Taken from the artboards, not guessed ---------------------------------
///
/// Every value here is read off the design canvas ("Medpin App",
/// Doctor-Dashboard and its siblings): the artboards are 390 x 980, set in
/// Figtree, on the colours this app already uses — #003399 and the same inks,
/// lines and clinical reds and greens. So the design is not a repaint; it is
/// the same palette in a lighter, rounder frame.
///
/// ---- Why a second token file and not more of `T` ---------------------------
///
/// The patient, dietician and desk screens are drawn from `T`
/// (core/theme/tokens.dart) and must keep looking exactly as they do. Folding
/// these values into `T` would change screens nobody asked to change. One file,
/// named for what it is, listed in tool/verify_tokens.dart's exemptions beside
/// `T`'s own — a raw value in a widget still fails the build.
///
/// ---- 390 drawn, 360 held ---------------------------------------------------
///
/// The artboards are 390dp wide; the clinic's phones are 360. Sizes here are
/// the artboard's. Where 30dp of missing width would split a word, the screen
/// takes it out of padding, never out of the type.
class D {
  const D._();

  /// Figtree, as the design is set. Bundled, not fetched: a clinic's phone is
  /// often on a weak connection and a font that arrives late is a screen that
  /// reflows under the doctor's thumb.
  static const String family = 'Figtree';

  // ============================================================== spacing

  /// The gap between one day's bar and the next, and the height a day with
  /// nobody in it is still drawn at — a closed Sunday is a flat mark, not a
  /// hole in the chart.
  static const double hair = 2;

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  /// The artboard's own in-between steps: a card's inside, the gap under an
  /// icon, the space between a mark and what it marks.
  static const double gapTight = 6;
  static const double gapIcon = 10;
  static const double cardPad = 14;
  static const double cardPadLg = 18;

  // ================================================================= type

  static TextStyle _f(double size, double h, int weight, {double spacing = 0}) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: h,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight.toDouble())],
    letterSpacing: spacing,
  );

  /// 28/1.15 heavy — "Hi, Dr. Sen". One per screen.
  static final TextStyle greeting = _f(28, 1.15, 800, spacing: -0.56);

  /// 15/1.3 — the line under it.
  static final TextStyle subtitle = _f(15, 1.3, 400);

  /// 14/1.3 semibold — the date and clinic, in brand blue.
  static final TextStyle dateLine = _f(14, 1.3, 600);

  /// 30/1 heavy — a stat card's number, tabular so three cards line up.
  static final TextStyle metric = _f(30, 1, 800, spacing: -0.6).copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// 22/1.15 heavy — a measurement on a tile, tabular so a column of them
  /// lines up. Smaller than [metric]: eight of these fit a screen, four of
  /// those do.
  static final TextStyle tileFigure = _f(22, 1.15, 800, spacing: -0.22).copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// 13/1.3 — a stat card's label under its number.
  static final TextStyle statLabel = _f(13, 1.3, 400);

  /// 18/1.25 bold — a section heading ("Quick actions").
  static final TextStyle section = _f(18, 1.25, 700);

  /// 20/1.25 bold — a screen's own title in the bar, as the artboards set it.
  static final TextStyle screenTitle = _f(20, 1.25, 700);

  /// 24/1.2 heavy — the assistant's opening question.
  static final TextStyle opening = _f(24, 1.2, 800, spacing: -0.48);

  /// 26/1 heavy — the health score in an answer, tabular like every figure.
  static final TextStyle score = _f(26, 1, 800).copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// 16/1.25 bold — a heading inside a card, under the card's own title.
  static final TextStyle subhead = _f(16, 1.25, 700);

  /// 17/1.3 bold — a card's own title ("Emergency · Priya Sharma").
  static final TextStyle cardTitle = _f(17, 1.3, 700);

  /// 14/1.5 — a card's prose.
  static final TextStyle body = _f(14, 1.5, 400);

  /// 16/1.3 — what somebody has typed into a field. The artboard's forms are
  /// set a size up from its prose: this is the one place a reader checks a
  /// digit at arm's length, across a counter.
  static final TextStyle input = _f(16, 1.3, 400);

  /// 14/1.5 semibold — the red line under an emergency, a card's own action.
  static final TextStyle bodyStrong = _f(14, 1.5, 600);

  /// 14/1.25 semibold — a quick action's label, two short lines at most.
  static final TextStyle tile = _f(14, 1.25, 600);

  /// 12/1.3 — small print.
  static final TextStyle caption = _f(12, 1.3, 400);

  /// 11/1.2 — the bar's labels, and a chip.
  static final TextStyle navLabel = _f(11, 1.2, 600);
  static final TextStyle navLabelOn = _f(11, 1.2, 700);
  static final TextStyle chip = _f(11, 1.2, 800, spacing: 0.66);

  /// 11/1.2 bold — a count nobody has read.
  static final TextStyle badgeText = _f(11, 1.2, 700);

  // ================================================================ fields

  /// A text field with no chrome of its own.
  ///
  /// Every field in this design is a box the widget draws: one hairline, one
  /// radius, the icon and the unit inside it. The app's own
  /// `InputDecorationTheme` is the old design's and fights that — it fills the
  /// field white, adds its own padding, and draws its own rounded border
  /// *inside* the one already drawn.
  ///
  /// `border: InputBorder.none` alone does not stop it: the theme keeps a
  /// separate border for the enabled, focused, error and focused-error states,
  /// and each wins in its own state. The new-chat sheet autofocuses its search,
  /// so the focused border reached the phone as a second rounded box sitting
  /// inside the first.
  static InputDecoration bareField({String? hint, TextStyle? hintStyle}) =>
      InputDecoration(
        isDense: true,
        filled: false,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        hintText: hint,
        hintStyle: hintStyle,
      );

  // =============================================================== colour

  static const Color brand = Color(0xFF003399);
  static const Color brandTint = Color(0xFFEBF1FB);

  /// A bar on a chart: the brand at half strength, so the one bar that is
  /// marked in full brand reads as the answer to "which day".
  static const Color brandBar = Color(0xFF7F99CC);

  static const Color ground = Color(0xFFF7F9FC);

  /// The sunken track a segmented choice sits in, and a colleague's initials.
  static const Color track = Color(0xFFF1F4F9);
  static const Color card = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFE5E9F0);

  /// The heavier hairline: a sheet's grab handle, a field's resting border.
  static const Color lineStrong = Color(0xFFD5DBE5);

  static const Color ink = Color(0xFF111827);
  static const Color inkMuted = Color(0xFF545E72);
  static const Color inkFaint = Color(0xFF69738A);

  /// Waiting, and done. Each carries a word as well as a colour.
  static const Color pending = Color(0xFFB45309);

  /// The ground and the edge that go with it: a risk chip, an allergy, a
  /// reading that is out of range.
  static const Color pendingGround = Color(0xFFFEF6E7);
  static const Color pendingLine = Color(0xFFF0D3A8);

  /// Done, on a chip of its own: a result inside its reference range.
  static const Color doneGround = Color(0xFFE7F5EE);
  static const Color done = Color(0xFF076B3C);

  /// An emergency: its card, its edge, the disc its mark sits on, its words,
  /// and the faint separator between the time and "Review now".
  static const Color dangerGround = Color(0xFFFDECEC);
  static const Color dangerLine = Color(0xFFF3C4C4);
  static const Color dangerMark = Color(0xFFB91C1C);
  static const Color danger = Color(0xFFB91C1C);
  static const Color dangerFaint = Color(0xFFD5A0A0);

  static const Color onBrand = Color(0xFFFFFFFF);

  /// The page behind a sheet, dimmed — the artboard's 40% ink.
  static const Color scrim = Color(0x66111827);

  /// On the brand card: the assistant's tile, its edge, its prose.
  static const Color onBrandTile = Color(0x1FFFFFFF);
  static const Color onBrandTileLine = Color(0x38FFFFFF);
  static const Color onBrandChip = Color(0x29FFFFFF);
  static const Color onBrandChipLine = Color(0x47FFFFFF);
  static const Color onBrandProse = Color(0xD1FFFFFF);

  // ================================================================ shape

  /// A card: stats, quick actions. 20 for the two wide ones, 28 for the bar.
  static const double rSection = 24;
  static const double rCard = 16;
  static const double rCardLg = 20;
  static const double rMark = 14;
  static const double rMarkLg = 16;
  static const double rBar = 28;
  static const double rBarItem = 22;
  static const double rChip = 6;

  /// The top of a chart bar, barely rounded.
  static const double rTick = 3;
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(999));

  /// One light source. The cards barely lift; the brand card and the bar carry
  /// the design's deeper blue shadow.
  static const List<BoxShadow> lift = [
    BoxShadow(color: Color(0x0D003399), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A003399), blurRadius: 3, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> liftBrand = [
    BoxShadow(color: Color(0x38003399), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const List<BoxShadow> liftBar = [
    BoxShadow(color: Color(0x1A003399), blurRadius: 24, offset: Offset(0, 8)),
  ];

  // ================================================================= size

  /// Nothing tappable is smaller than this.
  static const double tap = 44;

  /// A button that is as wide as its label, and no wider.
  ///
  /// The app's global button theme asks every button for `Size.fromHeight(52)`
  /// — which is an *infinite* minimum width, because that is what
  /// `Size.fromHeight` means. A button carrying it into a Row starves whatever
  /// sits beside it: the Patients header's title came out one letter per line,
  /// with "Add patient" pushed off the screen entirely. Any button here that
  /// is not meant to span the screen passes this as its `minimumSize`.
  static const Size hug = Size(0, tap);

  /// The logo's height, and the discs: the header's buttons, a quick action's
  /// icon, the emergency's mark, the assistant's tile.
  static const double logo = 36;
  static const double disc = 48;
  static const double discLg = 52;

  /// A field is exactly this tall, and so is the button that submits it.
  static const double inputH = 56;

  /// A quick action is at least this tall, and the bar is exactly this.
  static const double tileMin = 112;
  static const double bar = 64;

  /// A count: never narrower than this, however few digits.
  static const double badgeMin = 18;

  static const double iconSm = 14;
  static const double icon = 16;
  static const double iconMd = 18;
  static const double iconLg = 20;
  static const double iconDisc = 22;
  static const double iconMark = 24;
}
