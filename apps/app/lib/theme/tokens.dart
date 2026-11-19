import 'dart:ui' show Color;

// HOW TO RETHEME
// Every colour in lib/ui comes from [Tokens] through one accessor,
// `tokensOf(context)` (lib/ui/theme.dart), and the forui theme is built only
// from these tokens (`buildTheme` in lib/ui/theme.dart). To change the look,
// edit the values of [Tokens.light] and [Tokens.dark] below; nothing else
// holds a colour. The look is two-tone: `frame` fills the window, the rail and
// the margin; `panel` is the inset, rounded content area; `activeItem` is the
// third tone (selected rail icon); `card` and `field` sit on the panel.
// Sizes (rail width, inset, radii) are the constants at the end of [Tokens].
// Note: forui's own `card` colour also fills its text fields and popovers, so
// it is fed from [field]; our cards use [card] directly.

/// Design tokens shared with the web board (apps/web/lib/web_app.dart). One
/// place for colour, spacing and radius, so the look is set once.
class Tokens {
  const Tokens({
    required this.frame,
    required this.panel,
    required this.panelBorder,
    required this.divider,
    required this.activeItem,
    required this.onActiveItem,
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
  });

  /// Window background: behind the rail and around the panel.
  final Color frame;

  /// The inset content panel.
  final Color panel;

  /// 1px border of the content panel.
  final Color panelBorder;

  /// Thin separators inside the panel (top bar, list rows, detail edge).
  final Color divider;

  /// Highlight of the active rail icon (a rounded square).
  final Color activeItem;

  /// Icon colour on [activeItem].
  final Color onActiveItem;

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

  // Neutral placeholders; real colours come later.
  static const light = Tokens(
    frame: Color(0xFFE9E9E9),
    panel: Color(0xFFFFFFFF),
    panelBorder: Color(0xFFD9D9D9),
    divider: Color(0xFFE8E8E8),
    activeItem: Color(0xFFD6D6D6),
    onActiveItem: Color(0xFF111111),
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
  );

  static const dark = Tokens(
    frame: Color(0xFF111111),
    panel: Color(0xFF1A1A1A),
    panelBorder: Color(0xFF2C2C2C),
    divider: Color(0xFF2A2A2A),
    activeItem: Color(0xFF303030),
    onActiveItem: Color(0xFFF2F2F2),
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
  );

  static const double radius = 8;
  static const double gap = 12;
  static const double sidebarWidth = 280;
  static const double detailWidth = 440;

  /// Width at which the sidebar stays on screen instead of a drawer.
  static const double wideBreakpoint = 880;

  /// Width at which the detail opens beside the list instead of replacing it.
  static const double splitBreakpoint = 1280;

  // Shell frame.
  /// Width of the icon rail on the left edge.
  static const double railWidth = 52;

  /// Side of an icon rail button (the active highlight).
  static const double railItem = 36;

  /// Corner radius of the active rail highlight.
  static const double railItemRadius = 8;

  /// Margin between the window edge and the inset content panel.
  static const double frameInset = 6;

  /// Corner radius of the inset content panel.
  static const double panelRadius = 12;
}
