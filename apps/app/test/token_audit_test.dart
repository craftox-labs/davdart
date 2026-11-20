import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

class _Source implements NoteSource {
  @override
  Future<List<Note>> load() async => [Note(uid: 'a', summary: 'One')];
}

/// Source files of lib/ui that must hold no literal look values: those live in
/// lib/theme/tokens.dart, and lib/ui/theme.dart feeds them to forui.
Iterable<File> _uiFiles() => Directory('lib/ui')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('/theme.dart'));

/// Arguments of every `name(...)` call in [src] (balanced parentheses).
Iterable<String> _args(String src, RegExp opener) sync* {
  for (final m in opener.allMatches(src)) {
    var depth = 1;
    var i = m.end;
    while (i < src.length && depth > 0) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') depth--;
      i++;
    }
    yield src.substring(m.end, i - 1);
  }
}

void main() {
  group('token audit of lib/ui', () {
    final literal = {
      'Color literal': RegExp(r'\bColor\(\s*0x|\bColors\.'),
      'fontSize literal': RegExp(r'fontSize:\s*\d'),
      'fontWeight literal': RegExp(r'fontWeight:\s*FontWeight\.'),
      'letterSpacing literal': RegExp(r'letterSpacing:\s*-?\.?\d'),
      'radius literal': RegExp(r'Radius\.circular\(\s*\d'),
      'size literal': RegExp(
        r'\b(?:width|height|size|spacing|runSpacing):\s*[1-9]',
      ),
    };

    test('no colour, font or size literals', () {
      final found = <String>[];
      for (final f in _uiFiles()) {
        final src = f.readAsStringSync();
        literal.forEach((what, re) {
          for (final m in re.allMatches(src)) {
            final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
            found.add('${f.path}:$line $what');
          }
        });
      }
      expect(found, isEmpty, reason: 'use tokensOf(context): $found');
    });

    test('no numeric padding or margin literals (0 is allowed)', () {
      final found = <String>[];
      final number = RegExp(r'(?<![\w.])[1-9]\d*(?:\.\d+)?');
      for (final f in _uiFiles()) {
        final src = f.readAsStringSync();
        for (final a in _args(src, RegExp(r'EdgeInsets\.\w+\('))) {
          if (number.hasMatch(a)) found.add('${f.path}: EdgeInsets($a)');
        }
        for (final a in _args(src, RegExp(r'\bSizedBox\('))) {
          if (RegExp(r'(width|height):\s*[1-9]').hasMatch(a)) {
            found.add('${f.path}: SizedBox($a)');
          }
        }
      }
      expect(found, isEmpty, reason: 'use tokensOf(context).space: $found');
    });
  });

  group('tokens drive the UI', () {
    testWidgets('changing tokens changes the themed widgets', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      const red = Color(0xFFAA0000);
      const green = Color(0xFF00AA00);
      final custom = Tokens.light.copyWith(
        frame: red,
        accent: green,
        sizes: const SizeTokens(rail: 90, railItem: 50),
        type: const TypeTokens(title: 31),
        radii: const RadiusTokens(panel: 30),
      );
      await t.pumpWidget(DavdartApp(source: _Source(), tokens: custom));
      await t.pumpAndSettle();

      // Colour: the frame, and forui's primary fed from the accent token.
      expect(
        t
            .widgetList<ColoredBox>(
              find.ancestor(
                of: find.byKey(const Key('icon-rail')),
                matching: find.byType(ColoredBox),
              ),
            )
            .any((b) => b.color == red),
        isTrue,
      );
      expect(
        FTheme.of(t.element(find.byKey(const Key('icon-rail')))).colors.primary,
        green,
      );
      // Size, type and radius.
      expect(t.getSize(find.byKey(const Key('icon-rail'))).width, 90);
      expect(t.getSize(find.byKey(const Key('logo-slot'))).width, 50);
      expect(t.widget<Text>(find.text('Board').first).style?.fontSize, 31);
      final panel = t.widget<Container>(find.byKey(const Key('shell-panel')));
      expect(
        (panel.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(30),
      );
    });
  });
}
