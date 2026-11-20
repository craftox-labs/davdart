import 'dart:ui' as ui;

import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/logo.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('logo tokens exist, differ, and show on the frame in both themes', () {
    for (final t in [Tokens.light, Tokens.dark]) {
      expect(t.logoLower, isNot(t.logoUpper));
      expect(t.logoLower, isNot(t.frame));
      expect(t.logoUpper, isNot(t.frame));
      for (final c in [t.logoLower, t.logoUpper]) {
        final a = c.computeLuminance(), b = t.frame.computeLuminance();
        final ratio =
            (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
        expect(ratio, greaterThan(1.8));
      }
    }
  });

  test('painter renders at several sizes without exceptions', () {
    for (final s in [
      const Size(16, 16),
      const Size(36, 36),
      const Size(120, 60),
      const Size(512, 512),
      Size.zero,
    ]) {
      final rec = ui.PictureRecorder();
      LogoPainter(
        lower: const Color(0xFF434343),
        upper: const Color(0xFFE6E6E6),
      ).paint(Canvas(rec), s);
      rec.endRecording().dispose();
    }
  });
}
