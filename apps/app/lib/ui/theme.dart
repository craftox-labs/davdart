import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/tokens.dart';

/// Replaces the tokens below it (a preview or a test); without one,
/// [tokensOf] picks [Tokens.light] or [Tokens.dark] by brightness.
class TokensScope extends InheritedWidget {
  const TokensScope({super.key, required this.tokens, required super.child});
  final Tokens tokens;

  @override
  bool updateShouldNotify(TokensScope old) => tokens != old.tokens;
}

/// The one accessor: our [Tokens] for the surrounding forui theme.
Tokens tokensOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<TokensScope>()?.tokens ??
    (context.theme.colors.brightness == Brightness.dark
        ? Tokens.dark
        : Tokens.light);

/// True below [Tokens.wideBreakpoint]: the narrow (drawer, phone) layout,
/// where controls get touch-sized hit targets. Desktop is unaffected.
bool narrowLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < Tokens.wideBreakpoint;

/// Wraps a button so it is at least [Tokens.sizes] touchTarget tall (and wide
/// when [square]) on the narrow layout; unchanged on desktop. Tight
/// constraints make the button itself fill the box, so the whole box is its
/// hit area.
Widget touchBox(BuildContext context, Widget child, {bool square = false}) {
  if (!narrowLayout(context)) return child;
  final m = tokensOf(context).sizes.touchTarget;
  return SizedBox(width: square ? m : null, height: m, child: child);
}

FColors _colors(Tokens t, FColors base) => base.copyWith(
  barrier: t.barrier,
  background: t.panel,
  foreground: t.fg,
  primary: t.accent,
  primaryForeground: t.onAccent,
  secondary: t.selected,
  secondaryForeground: t.fg,
  muted: t.hover,
  mutedForeground: t.muted,
  destructive: t.destructive,
  destructiveForeground: t.onDestructive,
  error: t.error,
  errorForeground: t.onError,
  // forui fills text fields and popovers with `card`.
  card: t.field,
  border: t.divider,
);

FBorderRadius _radius(Tokens t) {
  BorderRadius r(double v) => BorderRadius.all(Radius.circular(v));
  return FBorderRadius(
    xs: r(t.radii.small),
    sm: r(t.radii.control),
    md: r(t.radii.card),
    lg: r(t.radii.panel),
  );
}

final _cache = <(Brightness, bool), FThemeData>{};

/// The forui theme for a brightness, built only from [Tokens]: colours,
/// font family, corner radii and border width. [touch] picks the
/// touch-sized variant. Pass [tokens] to override the defaults (not cached).
FThemeData buildTheme(Brightness b, {required bool touch, Tokens? tokens}) {
  FThemeData make() {
    final dark = b == Brightness.dark;
    final t = tokens ?? (dark ? Tokens.dark : Tokens.light);
    final colors = _colors(
      t,
      dark ? FColors.neutralDark : FColors.neutralLight,
    );
    final typeface = FTypeface.inherit(
      colors: colors,
      touch: touch,
      fontFamily: t.type.fontFamily,
      fontFamilyFallback: t.type.fontFamilyFallback,
    );
    final typography = FTypography(display: typeface, body: typeface);
    return FThemeData(
      touch: touch,
      debugLabel: 'davdart ${dark ? 'dark' : 'light'}',
      colors: colors,
      typography: typography,
      style: FStyle.inherit(
        colors: colors,
        typography: typography,
        touch: touch,
      ).copyWith(borderRadius: _radius(t), borderWidth: t.borders.hairline),
    ).copyWith(
      tooltipStyle: FTooltipStyleDelta.delta(
        decoration: DecorationDelta.shapeDelta(color: t.tooltipBackground),
        textStyle: TextStyleDelta.delta(color: t.tooltipText),
      ),
    );
  }

  return tokens != null ? make() : _cache.putIfAbsent((b, touch), make);
}

/// Phones and tablets get touch sizing, desktops the compact one.
bool get isTouchPlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
