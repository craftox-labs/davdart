import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/tokens.dart';

/// Our [Tokens] for the brightness of the surrounding forui theme.
Tokens tokensOf(BuildContext context) =>
    context.theme.colors.brightness == Brightness.dark
    ? Tokens.dark
    : Tokens.light;

FColors _colors(Tokens t, FColors base) => base.copyWith(
  background: t.panel,
  foreground: t.fg,
  primary: t.accent,
  primaryForeground: t.onAccent,
  secondary: t.selected,
  secondaryForeground: t.fg,
  muted: t.hover,
  mutedForeground: t.muted,
  // forui fills text fields and popovers with `card`.
  card: t.field,
  border: t.divider,
);

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
