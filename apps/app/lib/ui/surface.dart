import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'theme.dart';

/// The one fill of a selected or hovered row (list row, tree row, nav row,
/// palette row): [Tokens.selected] or [Tokens.hover] on a rounded surface,
/// with the row's padding inside it. Callers own the tap handling and the key
/// (an [FTappable] around the surface), so the interaction stays where the
/// gesture is defined.
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.selected = false,
    this.hovered = false,
    this.radius,
    this.padding,
    this.square = false,
    this.color,
    this.constraints,
  });

  final Widget child;
  final bool selected;
  final bool hovered;

  /// Corner radius; defaults to [RadiusTokens.small] (chips and tree rows).
  final double? radius;

  /// Insets inside the fill; none when null.
  final EdgeInsets? padding;

  /// A square fill (a full-width list row); the default rounds the corners.
  final bool square;

  /// Fill override for the few surfaces that are not the row tones (the rail
  /// item's [Tokens.activeItem]).
  final Color? color;

  /// Least size of the surface (a touch-sized row).
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final fill = color ?? (selected ? t.selected : (hovered ? t.hover : null));
    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: square
            ? null
            : BorderRadius.circular(radius ?? t.radii.small),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (constraints != null) {
      box = ConstrainedBox(constraints: constraints!, child: box);
    }
    return box;
  }
}
