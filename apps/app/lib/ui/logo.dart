import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Source: assets/logo/davdart.svg at the repo root (viewBox 539.32 x 566.93).
/// Two identical shapes, the upper one mirrored, forming a 'd' arrow.
const _lowerPath =
    'M539.32,283.46C539.32,287.74 95.86,326.60 94.49,330.71L2.06,514.19C-2.02,526.41 0.03,539.84 7.56,550.29C15.10,560.74 27.19,566.93 40.07,566.93L296.42,566.93C308.31,566.93 319.59,561.65 327.20,552.51L530.03,309.12C536.22,301.69 539.32,292.58 539.32,283.46Z';
const _upperPath =
    'M539.32,283.47C539.32,279.18 95.86,240.33 94.49,236.22L2.06,52.74C-2.02,40.52 0.03,27.09 7.56,16.64C15.10,6.19 27.19,0.00 40.07,0.00L296.42,0.00C308.31,0.00 319.59,5.28 327.20,14.42L530.03,257.81C536.22,265.24 539.32,274.35 539.32,283.47Z';
const _markWidth = 539.32;
const _markHeight = 566.93;

/// Height over width of the mark.
const logoAspect = _markHeight / _markWidth;

/// Parses absolute M, L, C and Z path data (the only commands the logo uses).
Path parseMarkPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLCZ]|-?\d+(?:\.\d+)?').allMatches(d).toList();
  var i = 0;
  double n() => double.parse(tokens[i++].group(0)!);
  while (i < tokens.length) {
    switch (tokens[i++].group(0)) {
      case 'M':
        path.moveTo(n(), n());
      case 'L':
        path.lineTo(n(), n());
      case 'C':
        path.cubicTo(n(), n(), n(), n(), n(), n());
      case 'Z':
        path.close();
    }
  }
  return path;
}

final _lower = parseMarkPath(_lowerPath);
final _upper = parseMarkPath(_upperPath);

/// Paints the davdart mark, scaled to fit the canvas keeping its aspect
/// ratio, centred.
class LogoPainter extends CustomPainter {
  const LogoPainter({required this.lower, required this.upper});
  final Color lower, upper;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = size.width / _markWidth < size.height / _markHeight
        ? size.width / _markWidth
        : size.height / _markHeight;
    canvas.save();
    canvas.translate(
      (size.width - _markWidth * scale) / 2,
      (size.height - _markHeight * scale) / 2,
    );
    canvas.scale(scale);
    canvas.drawPath(_lower, Paint()..color = lower);
    canvas.drawPath(_upper, Paint()..color = upper);
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) =>
      old.lower != lower || old.upper != upper;
}

/// The davdart mark in a square of [extent] (logical pixels), with theme
/// colours and [padding] around it. Labelled 'davdart' for accessibility.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, required this.extent, this.padding = 0});
  final double extent, padding;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Semantics(
      label: 'davdart',
      image: true,
      child: SizedBox(
        width: extent,
        height: extent,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: CustomPaint(
            painter: LogoPainter(lower: t.logoLower, upper: t.logoUpper),
          ),
        ),
      ),
    );
  }
}

/// The logo slot at the top of the rail: the mark on the rail background,
/// as wide as the rail icon glyphs ([IconTokens.rail]), centred in a
/// [SizedBox] the size of a rail item so the slot's height is unchanged.
/// Not tappable.
class LogoSlot extends StatelessWidget {
  const LogoSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return KeyedSubtree(
      key: const Key('logo-slot'),
      child: SizedBox(
        width: t.sizes.railItem,
        height: t.sizes.railItem,
        child: Center(
          child: Semantics(
            label: 'davdart',
            image: true,
            child: SizedBox(
              key: const Key('logo-mark'),
              width: t.icons.rail,
              height: t.icons.rail * logoAspect,
              child: CustomPaint(
                painter: LogoPainter(lower: t.logoLower, upper: t.logoUpper),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
