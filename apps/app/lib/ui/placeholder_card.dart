import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// A visible, marked place for something not built yet: muted, a dashed
/// outline, a small 'Placeholder' label, the [title] of the thing it will be
/// and one line saying what it will do. No logic, no data.
///
/// [name] is the key suffix: the card is `placeholder-<name>`.
class PlaceholderCard extends StatelessWidget {
  const PlaceholderCard({
    super.key,
    required this.name,
    required this.title,
    required this.willBe,
  });
  final String name, title, willBe;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final muted = t.type.captionStyle.copyWith(color: t.muted);
    return DashedOutline(
      key: Key('placeholder-$name'),
      radius: t.radii.card,
      child: Padding(
        padding: EdgeInsets.all(t.space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: t.space.xs,
          children: [
            Row(
              children: [
                Text(
                  'Placeholder',
                  key: Key('placeholder-$name-label'),
                  style: t.type.labelStyle.copyWith(color: t.muted),
                ),
                SizedBox(width: t.space.sm),
                Expanded(child: Text(title, style: t.type.bodyStyle)),
              ],
            ),
            Text(willBe, style: muted),
          ],
        ),
      ),
    );
  }
}

/// A rounded rectangle drawn with a dashed stroke around [child] (Flutter has
/// no dashed border of its own). The placeholder card and its chips share it.
class DashedOutline extends StatelessWidget {
  const DashedOutline({
    super.key,
    required this.child,
    required this.radius,
    this.color,
  });
  final Widget child;
  final double radius;

  /// Defaults to the theme's card border.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return CustomPaint(
      painter: _DashedBorder(
        color: color ?? t.cardBorder,
        radius: radius,
        stroke: t.borders.hairline,
      ),
      child: child,
    );
  }
}

/// The dashed stroke behind [DashedOutline].
class _DashedBorder extends CustomPainter {
  const _DashedBorder({
    required this.color,
    required this.radius,
    required this.stroke,
  });
  final Color color;
  final double radius, stroke;

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = stroke / 2;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - stroke, size.height - stroke),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final metric in (Path()..addRRect(r)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + _dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius || old.stroke != stroke;
}
