import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/tokens.dart';
import 'theme.dart';

/// Which surface a [CardBox] sits on: a card (board card, detail block) uses
/// the card tokens, a tile inside a card uses the panel tokens.
enum CardVariant { card, tile }

/// The one card surface: [Tokens.card] (or [Tokens.panel] for
/// [CardVariant.tile]) with its border and [RadiusTokens.card], an accent
/// border when [selected], and the content padding inside it. Optionally
/// tappable ([onTap]); [tapKey] keys the tap target so widget tests can press
/// it.
class CardBox extends StatelessWidget {
  const CardBox({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.selected = false,
    this.onTap,
    this.tapKey,
    this.variant = CardVariant.card,
    this.constraints,
    this.selectedBorderWidth,
  });

  final Widget child;

  /// Defaults to [SpaceTokens.lg] on every side.
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final double? width;
  final bool selected;
  final VoidCallback? onTap;
  final Key? tapKey;
  final CardVariant variant;
  final BoxConstraints? constraints;

  /// Border width while [selected]; defaults to [BorderTokens.hairline].
  final double? selectedBorderWidth;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final tile = variant == CardVariant.tile;
    Widget box = Container(
      width: width,
      constraints: constraints,
      margin: margin,
      padding: padding ?? EdgeInsets.all(t.space.lg),
      decoration: BoxDecoration(
        color: tile ? t.panel : t.card,
        borderRadius: BorderRadius.circular(t.radii.card),
        border: Border.all(
          color: selected ? t.accent : (tile ? t.panelBorder : t.cardBorder),
          width: selected
              ? (selectedBorderWidth ?? t.borders.hairline)
              : t.borders.hairline,
        ),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return FTappable(key: tapKey, onPress: onTap, child: box);
  }
}
