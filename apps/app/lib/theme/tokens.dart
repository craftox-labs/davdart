import 'dart:ui' show Color, FontWeight;

import 'package:flutter/animation.dart' show Curve, Curves;
import 'package:flutter/painting.dart' show TextStyle;

// HOW TO RETHEME
// One source: this file. Nothing in lib/ui holds a colour, font size, weight,
// spacing, radius or size of its own. Widgets read them from [Tokens] through
// one accessor, `tokensOf(context)` (lib/ui/theme.dart), and the forui theme
// is built only from these tokens (`buildTheme` in lib/ui/theme.dart). A test
// (test/token_audit_test.dart) fails if a literal slips back into lib/ui.
//
// COLOUR: edit the values of [Tokens.light] and [Tokens.dark]. The look is
//   two-tone: `frame` fills the window, the rail and the margin; `panel` is
//   the inset, rounded content area; `activeItem` fills the selected rail
//   item (it defaults to the `panel` value so the item reads as a tab opening
//   into the panel; give it another value for a plain highlight, which is
//   also what shows while the side panel is collapsed); `card` and `field`
//   sit on the panel. `tooltipBackground` and `tooltipText` colour every
//   tooltip (inverted against the theme: dark bubble on light, light on dark). `barrier`, `destructive`
//   and `error` (with their `on...` colours) feed forui's dialogs and errors.
//   forui's own `card` colour also fills its text fields and popovers, so it
//   is fed from [field]; our cards use [card] directly.
// TYPE: [TypeTokens]: font family, optional line height, the size scale
//   (micro to display) and the weights. Text styles are its getters; forui
//   gets the family through `buildTheme`.
// SPACING: [SpaceTokens], one scale (xxs to huge) for every padding, gap and
//   margin.
// RADIUS: [RadiusTokens] (small, control, card, panel, tab); forui's own radii
//   and border width are fed from them. `tab` rounds the active rail tab and
//   its concave joins into the panel.
// SIZES: [SizeTokens] (rail, inset, sidebar with its min and max drag width,
//   resize handle, detail, top bar, dialogs, board column, status dot,
//   spinner, indents), [IconTokens] (icon sizes) and
//   [BorderTokens] (border widths).
// Layout breakpoints are the static constants at the end of [Tokens].

/// Type scale, weights and family.
class TypeTokens {
  const TypeTokens({
    this.fontFamily = 'packages/forui/Inter',
    this.fontFamilyFallback = const [],
    this.lineHeight,
    this.micro = 11,
    this.caption = 12,
    this.body = 13,
    this.title = 16,
    this.heading = 17,
    this.display = 22,
    this.paneTitle = 13,
    this.regular = FontWeight.w400,
    this.medium = FontWeight.w500,
    this.semibold = FontWeight.w600,
    this.bold = FontWeight.w700,
    this.paneTitleWeight = FontWeight.w600,
    this.labelSpacing = .8,
    this.monoFamily = 'monospace',
  });

  /// Family fed to forui's typeface. Text widgets inherit it from the theme.
  final String fontFamily;
  final List<String> fontFamilyFallback;

  /// Line height multiplier applied to our text styles; null keeps forui's.
  final double? lineHeight;

  final double micro, caption, body, title, heading, display;
  final FontWeight regular, medium, semibold, bold;

  /// Size and weight of every pane header title: the side panel section
  /// name, the item title in the main and peek panes, and the Home
  /// breadcrumb. The colour is [Tokens.paneTitleColor].
  final double paneTitle;
  final FontWeight paneTitleWeight;

  /// Letter spacing of small uppercase section labels.
  final double labelSpacing;

  /// Family of code and field names.
  final String monoFamily;

  TextStyle _s(double size, [FontWeight? weight]) =>
      TextStyle(fontSize: size, fontWeight: weight, height: lineHeight);

  TextStyle get microStyle => _s(micro);
  TextStyle get captionStyle => _s(caption);
  TextStyle get bodyStyle => _s(body);
  TextStyle get titleStyle => _s(title, semibold);
  TextStyle get headingStyle => _s(heading, bold);
  TextStyle get displayStyle => _s(display, bold);

  /// The one title style of all pane header rows (colour comes from the
  /// caller via [Tokens.paneTitleColor]).
  TextStyle get paneTitleStyle => _s(paneTitle, paneTitleWeight);

  /// Small uppercase section label.
  TextStyle get labelStyle => TextStyle(
    fontSize: micro,
    fontWeight: semibold,
    letterSpacing: labelSpacing,
    height: lineHeight,
  );

  /// Code and field names at caption size.
  TextStyle get monoStyle =>
      TextStyle(fontFamily: monoFamily, fontSize: caption, height: lineHeight);

  /// Caption-size and body-size text with emphasis.
  TextStyle get captionStrong => _s(caption, semibold);
  TextStyle get bodyStrong => _s(body, semibold);

  /// Weight only (keeps the surrounding size), for bold inline runs.
  TextStyle get boldStyle => TextStyle(fontWeight: bold);
  TextStyle get semiboldStyle => TextStyle(fontWeight: semibold);

  /// Sizes of markdown headings 1 to 4 in a note.
  List<double> get markdownHeadings => [
    display - 2,
    heading,
    body + 2,
    body + 1,
  ];
}

/// One spacing scale for padding, gaps and margins.
class SpaceTokens {
  const SpaceTokens({
    this.xxs = 2,
    this.xs = 4,
    this.sm = 6,
    this.md = 8,
    this.lg = 12,
    this.xl = 16,
    this.xxl = 20,
    this.xxxl = 24,
    this.huge = 40,
  });
  final double xxs, xs, sm, md, lg, xl, xxl, xxxl, huge;
}

/// Corner radii.
class RadiusTokens {
  const RadiusTokens({
    this.small = 6,
    this.control = 8,
    this.card = 8,
    this.panel = 12,
    this.tab = 4,
  });

  /// Chips, tree rows.
  final double small;

  /// Buttons, fields, the rail highlight.
  final double control;

  /// Cards and detail blocks.
  final double card;

  /// The inset content panel.
  final double panel;

  /// The active rail tab and the concave corners joining it to the panel.
  final double tab;
}

/// Motion: how the side panes slide open and shut.
class MotionTokens {
  const MotionTokens({
    this.slide = const Duration(milliseconds: 200),
    this.curve = Curves.easeOutCubic,
    this.dragGhost = 0.4,
  });

  /// Time for a pane to slide between closed and open.
  final Duration slide;
  final Curve curve;

  /// Opacity of a tab left behind while it is dragged.
  final double dragGhost;
}

/// Border widths.
class BorderTokens {
  const BorderTokens({this.hairline = 1, this.focus = 2});
  final double hairline;

  /// Outline of a drop target while a drag is over it.
  final double focus;
}

/// Icon sizes.
class IconTokens {
  const IconTokens({
    this.sm = 14,
    this.md = 16,
    this.lg = 18,
    this.rail = 20,
    this.tree = 15,
  });
  final double sm, md, lg, rail, tree;
}

/// Fixed dimensions of the shell and its parts.
class SizeTokens {
  const SizeTokens({
    this.rail = 52,
    this.railItem = 36,
    this.logoLarge = 56,
    this.frameInset = 6,
    this.sidebar = 280,
    this.sidebarMin = 200,
    this.sidebarMax = 520,
    this.resizeHit = 8,
    this.resizeLine = 2,
    this.detail = 440,
    this.detailMin = 320,
    this.detailMax = 720,
    this.listMin = 280,
    this.paneHeader = 44,
    this.sectionHeader = 32,
    this.detailTab = 280,
    this.boardColumn = 264,
    this.contentMax = 1800,
    this.statusDot = 8,
    this.spinner = 14,
    this.statusField = 160,
    this.metaLabel = 104,
    this.eventTime = 56,
    this.chevronBox = 20,
    this.listChevronBox = 24,
    this.listMarker = 22,
    this.treeIndent = 14,
    this.listIndent = 20,
    this.dialogSm = 360,
    this.dialog = 420,
    this.dialogMd = 380,
    this.dialogLg = 480,
    this.dialogXl = 560,
    this.narrowBar = 440,
    this.pageMax = 860,
    this.editorLines = 10,
    this.editorLinesFull = 26,
    this.tabStrip = 34,
    this.tabMin = 88,
    this.tabMax = 180,
    this.tabClose = 16,
  });

  /// Edge of the logo on the first-run screen (and other large uses).
  final double logoLarge;
  final double rail, railItem, frameInset, sidebar, detail;

  /// Height of the one header row every pane starts with (side panel,
  /// main pane, peek pane), so titles and actions line up across them.
  final double paneHeader;

  /// Height of every side-panel section's title row, so titles never move
  /// when switching sections (trailing actions must fit inside it).
  final double sectionHeader;

  /// Width of the detail header tab where the note replaces the list.
  final double detailTab;

  /// Smallest and largest width the side panel can be dragged to; [sidebar]
  /// is its default (and the width a double-click on the handle restores).
  final double sidebarMin, sidebarMax;

  /// Grab width of the drag handle on the side panel edge, and the width of
  /// the line it shows on hover.
  final double resizeHit, resizeLine;

  /// Limits of the detail pane's drag handle ([detail] is the default and
  /// the double-click reset), and the least width the list keeps beside it.
  final double detailMin, detailMax, listMin;

  /// [boardColumn] is the least width of a board column; [contentMax] caps
  /// the Home grid (board and Today strip), left-aligned beyond it.
  final double boardColumn,
      contentMax,
      statusDot,
      spinner,
      statusField,
      metaLabel,
      eventTime;
  final double chevronBox, listChevronBox, listMarker;
  final double treeIndent, listIndent;
  final double dialogSm, dialog, dialogMd, dialogLg, dialogXl;

  /// Width below which the top bar swaps its view toggle for one icon.
  final double narrowBar;

  /// Widest the full-page note grows (the text stays readable), and the
  /// body editor's least height in lines in the peek pane and the full page.
  final double pageMax;
  final int editorLines, editorLinesFull;

  /// Document tab strip: its height, the narrowest and widest a tab gets
  /// (tabs shrink towards [tabMin], then the strip scrolls) and the square
  /// of a tab's close button.
  final double tabStrip, tabMin, tabMax, tabClose;
}

/// Design tokens shared with the web board (apps/web/lib/web_app.dart). One
/// place for colour, type, spacing, radius and size, so the look is set once.
class Tokens {
  const Tokens({
    required this.frame,
    required this.panel,
    required this.panelBorder,
    required this.divider,
    required this.activeItem,
    required this.onActiveItem,
    required this.logoLower,
    required this.logoUpper,
    required this.rail,
    required this.card,
    required this.cardBorder,
    required this.field,
    required this.selected,
    required this.hover,
    required this.fg,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.statusDone,
    required this.statusTodo,
    required this.statusBlocked,
    required this.barrier,
    required this.destructive,
    required this.onDestructive,
    required this.error,
    required this.onError,
    required this.tooltipBackground,
    required this.tooltipText,
    this.type = const TypeTokens(),
    this.space = const SpaceTokens(),
    this.radii = const RadiusTokens(),
    this.borders = const BorderTokens(),
    this.icons = const IconTokens(),
    this.sizes = const SizeTokens(),
    this.motion = const MotionTokens(),
  });

  /// Window background: behind the rail and around the panel.
  final Color frame;

  /// The inset content panel.
  final Color panel;

  /// 1px border of the content panel.
  final Color panelBorder;

  /// Thin separators inside the panel (top bar, list rows, detail edge).
  final Color divider;

  /// Fill of the active rail item: the tab that opens into the panel (same
  /// value as [panel] by default), or a plain rounded highlight while the side
  /// panel is collapsed.
  final Color activeItem;

  /// Icon colour on [activeItem].
  final Color onActiveItem;

  /// The two shapes of the davdart logo (lower and upper). Both must stay
  /// visible on [frame], where the rail logo sits.
  final Color logoLower, logoUpper;

  /// Idle rail icon colour.
  final Color rail;

  /// Board cards, detail blocks and the folder bar, on the panel.
  final Color card;

  /// Border of cards.
  final Color cardBorder;

  /// Text field fill.
  final Color field;

  /// Selected row (tree, list) on the panel; also forui's selected tone.
  final Color selected;

  /// Hover tone for rows and buttons.
  final Color hover;

  /// Main text.
  final Color fg;

  /// Secondary text and idle icons inside the panel.
  final Color muted;

  /// Accent: links, focus, the "doing" status, primary buttons.
  final Color accent;

  /// Text on [accent].
  final Color onAccent;

  /// Status dot colours (doing uses [accent], other statuses use [muted]).
  final Color statusDone;
  final Color statusTodo;
  final Color statusBlocked;

  /// Scrim behind dialogs and sheets.
  final Color barrier;

  /// Destructive actions, and the text on them.
  final Color destructive;
  final Color onDestructive;

  /// Error text and borders, and the text on an error fill.
  final Color error;
  final Color onError;

  /// Tooltip bubble and its text (inverted against the theme).
  final Color tooltipBackground;
  final Color tooltipText;

  /// Colour of pane header titles (the same as the main text).
  Color get paneTitleColor => fg;

  final TypeTokens type;
  final SpaceTokens space;
  final RadiusTokens radii;
  final BorderTokens borders;
  final IconTokens icons;
  final SizeTokens sizes;
  final MotionTokens motion;

  /// A copy with some colours or groups replaced (used by tests and previews).
  Tokens copyWith({
    Color? frame,
    Color? panel,
    Color? accent,
    Color? fg,
    TypeTokens? type,
    SpaceTokens? space,
    RadiusTokens? radii,
    BorderTokens? borders,
    IconTokens? icons,
    SizeTokens? sizes,
  }) => Tokens(
    frame: frame ?? this.frame,
    panel: panel ?? this.panel,
    panelBorder: panelBorder,
    divider: divider,
    activeItem: activeItem,
    onActiveItem: onActiveItem,
    logoLower: logoLower,
    logoUpper: logoUpper,
    rail: rail,
    card: card,
    cardBorder: cardBorder,
    field: field,
    selected: selected,
    hover: hover,
    fg: fg ?? this.fg,
    muted: muted,
    accent: accent ?? this.accent,
    onAccent: onAccent,
    statusDone: statusDone,
    statusTodo: statusTodo,
    statusBlocked: statusBlocked,
    barrier: barrier,
    destructive: destructive,
    onDestructive: onDestructive,
    error: error,
    onError: onError,
    tooltipBackground: tooltipBackground,
    tooltipText: tooltipText,
    type: type ?? this.type,
    space: space ?? this.space,
    radii: radii ?? this.radii,
    borders: borders ?? this.borders,
    icons: icons ?? this.icons,
    sizes: sizes ?? this.sizes,
    motion: motion,
  );

  // Neutral placeholders; real colours come later.
  static const light = Tokens(
    frame: Color(0xFFE9E9E9),
    panel: Color(0xFFFFFFFF),
    panelBorder: Color(0xFFD9D9D9),
    divider: Color(0xFFE8E8E8),
    activeItem: Color(0xFFFFFFFF),
    onActiveItem: Color(0xFF111111),
    logoLower: Color(0xFF434343),
    logoUpper: Color(0xFF9A9A9A),
    rail: Color(0xFF666666),
    card: Color(0xFFF6F6F6),
    cardBorder: Color(0xFFE2E2E2),
    field: Color(0xFFF3F3F3),
    selected: Color(0xFFEDEDED),
    hover: Color(0xFFF1F1F1),
    fg: Color(0xFF1B1B1B),
    muted: Color(0xFF6E6E6E),
    accent: Color(0xFF2F5FD0),
    onAccent: Color(0xFFFFFFFF),
    statusDone: Color(0xFF3FA37A),
    statusTodo: Color(0xFFD8A23A),
    statusBlocked: Color(0xFFD9694F),
    barrier: Color(0x33000000),
    destructive: Color(0xFFE7000B),
    onDestructive: Color(0xFFFAFAFA),
    error: Color(0xFFE7000B),
    onError: Color(0xFFFAFAFA),
    tooltipBackground: Color(0xFF1B1B1B),
    tooltipText: Color(0xFFF2F2F2),
  );

  static const dark = Tokens(
    frame: Color(0xFF111111),
    panel: Color(0xFF1A1A1A),
    panelBorder: Color(0xFF2C2C2C),
    divider: Color(0xFF2A2A2A),
    activeItem: Color(0xFF1A1A1A),
    onActiveItem: Color(0xFFF2F2F2),
    logoLower: Color(0xFF6E6E6E),
    logoUpper: Color(0xFFE6E6E6),
    rail: Color(0xFF8C8C8C),
    card: Color(0xFF222222),
    cardBorder: Color(0xFF2F2F2F),
    field: Color(0xFF222222),
    selected: Color(0xFF282828),
    hover: Color(0xFF232323),
    fg: Color(0xFFE6E6E6),
    muted: Color(0xFF8E8E8E),
    accent: Color(0xFF8FB0FF),
    onAccent: Color(0xFF111111),
    statusDone: Color(0xFF3FA37A),
    statusTodo: Color(0xFFD8A23A),
    statusBlocked: Color(0xFFD9694F),
    barrier: Color(0x7A000000),
    destructive: Color(0xFFFF6467),
    onDestructive: Color(0xFFFAFAFA),
    error: Color(0xFFFF6467),
    onError: Color(0xFFFAFAFA),
    tooltipBackground: Color(0xFF2B2B2B),
    tooltipText: Color(0xFFECECEC),
  );

  /// Width at which the sidebar stays on screen instead of a drawer.
  static const double wideBreakpoint = 880;

  /// Width at which the detail opens beside the list instead of replacing it.
  static const double splitBreakpoint = 1280;

  /// Width below which the Home Today panels stack in one column.
  static const double stackBreakpoint = 600;
}
