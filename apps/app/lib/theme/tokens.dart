import 'dart:ui' show Color;

/// Design tokens shared with the web board (apps/web/lib/web_app.dart). One
/// place for colour, spacing and radius, so the look is set once.
class Tokens {
  const Tokens({
    required this.bg,
    required this.surface,
    required this.line,
    required this.fg,
    required this.muted,
    required this.accent,
  });

  final Color bg;
  final Color surface;
  final Color line;
  final Color fg;
  final Color muted;
  final Color accent;

  static const light = Tokens(
    bg: Color(0xFFFAFAF8),
    surface: Color(0xFFFFFFFF),
    line: Color(0xFFE4E2DC),
    fg: Color(0xFF1B1B1A),
    muted: Color(0xFF6B6A66),
    accent: Color(0xFF2F5FD0),
  );

  static const dark = Tokens(
    bg: Color(0xFF161615),
    surface: Color(0xFF202020),
    line: Color(0xFF33322F),
    fg: Color(0xFFECEBE7),
    muted: Color(0xFF9A9890),
    accent: Color(0xFF8FB0FF),
  );

  static const double radius = 8;
  static const double gap = 12;
  static const double sidebarWidth = 280;
  static const double detailWidth = 440;

  /// Width at which the sidebar stays on screen instead of a drawer.
  static const double wideBreakpoint = 880;

  /// Width at which the detail opens beside the list instead of replacing it.
  static const double splitBreakpoint = 1280;
}
