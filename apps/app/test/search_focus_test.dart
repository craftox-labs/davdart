import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

const _phones = [Size(320, 568), Size(390, 844)];

void main() {
  testWidgets('wide: the rail Search icon focuses the field', (t) async {
    final s = await pumpTasksApp(t);
    expect(s.nav.searchNode.hasFocus, isFalse);
    await t.tap(_k('rail-search'));
    await t.pumpAndSettle();
    expect(s.section, Section.search);
    expect(s.nav.searchNode.hasFocus, isTrue);
  });

  testWidgets('wide: the palette "Go to Search" focuses it too', (t) async {
    final s = await pumpTasksApp(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump(const Duration(milliseconds: 50));
    await t.enterText(_k('palette-field'), 'go to search');
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(_k('palette-row-go.search'));
    await t.pumpAndSettle();
    expect(s.section, Section.search);
    expect(s.nav.searchNode.hasFocus, isTrue);
  });

  testWidgets('a restored Search section is not focused on start', (t) async {
    final prefs = MemoryStorage()..write('davdart.section.v1', 'search');
    final s = await pumpTasksApp(t, prefs: prefs);
    expect(s.section, Section.search);
    expect(s.nav.searchNode.hasFocus, isFalse);
  });

  for (final size in _phones) {
    testWidgets('phone $size: the bar Search button focuses the field', (
      t,
    ) async {
      final s = await pumpTasksApp(t, size: size);
      await t.tap(_k('bar-search'));
      await t.pumpAndSettle();
      expect(s.section, Section.search);
      expect(s.nav.searchNode.hasFocus, isTrue);
    });

    testWidgets('phone $size: the palette "Go to Search" focuses it', (
      t,
    ) async {
      final s = await pumpTasksApp(t, size: size);
      await t.longPress(_k('bar-search'));
      await t.pumpAndSettle();
      expect(_k('palette'), findsOneWidget);
      await t.enterText(_k('palette-field'), 'go to search');
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(_k('palette-row-go.search'));
      await t.pumpAndSettle();
      expect(_k('palette'), findsNothing);
      expect(s.section, Section.search);
      expect(s.nav.searchNode.hasFocus, isTrue);
    });
  }
}
