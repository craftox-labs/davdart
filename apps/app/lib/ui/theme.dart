import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/tokens.dart';

/// Our [Tokens] for the brightness of the surrounding forui theme.
Tokens tokensOf(BuildContext context) =>
    context.theme.colors.brightness == Brightness.dark
    ? Tokens.dark
    : Tokens.light;

FColors _colors(Tokens t, FColors base) {
  final dark = base.brightness == Brightness.dark;
  return base.copyWith(
    background: t.bg,
    foreground: t.fg,
    primary: t.accent,
    primaryForeground: dark ? t.bg : const Color(0xFFFFFFFF),
    secondary: t.line,
    secondaryForeground: t.fg,
    muted: Color.alphaBlend(t.line.withValues(alpha: .5), t.bg),
    mutedForeground: t.muted,
    card: t.surface,
    border: t.line,
  );
}

final _cache = <(Brightness, bool), FThemeData>{};

/// The forui theme for a brightness, coloured from [Tokens] so the look stays
/// close to the web board. [touch] picks the touch-sized variant.
FThemeData buildTheme(Brightness b, {required bool touch}) =>
    _cache.putIfAbsent((b, touch), () {
      final dark = b == Brightness.dark;
      final t = dark ? Tokens.dark : Tokens.light;
      return FThemeData(
        touch: touch,
        debugLabel: 'davdart ${dark ? 'dark' : 'light'}',
        colors: _colors(t, dark ? FColors.neutralDark : FColors.neutralLight),
      );
    });

/// Phones and tablets get touch sizing, desktops the compact one.
bool get isTouchPlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
