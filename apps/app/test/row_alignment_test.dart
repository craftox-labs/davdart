import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha', description: 'Alpha body'),
  ];
}

Future<AppState> _pump(WidgetTester t, double width, LayoutSide side) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s = AppState(
    SpaceNoteSource(space, seed: _Seed()),
    prefs: MemoryStorage(),
  );
  s.setLayoutSide(side);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

Finder _k(String k) => find.byKey(Key(k));

void _same(WidgetTester t, Finder a, Finder b, {bool box = true}) {
  expect(a, findsOneWidget);
  expect(b, findsOneWidget);
  final ra = t.getRect(a), rb = t.getRect(b);
  if (box) {
    expect((ra.top - rb.top).abs(), lessThanOrEqualTo(1));
    expect((ra.height - rb.height).abs(), lessThanOrEqualTo(1));
  }
  expect((ra.center.dy - rb.center.dy).abs(), lessThanOrEqualTo(1));
}

void main() {
  for (final side in LayoutSide.values) {
    for (final width in [880.0, 1280.0]) {
      final tag = '$width ${side.name}';
      testWidgets('side header lines up with top bar, $tag', (t) async {
        await _pump(t, width, side);
        _same(t, _k('side-header'), _k('top-bar'));
        _same(
          t,
          find.descendant(of: _k('side-header'), matching: find.text('Files')),
          find
              .descendant(of: _k('top-bar'), matching: find.text('Board'))
              .first,
          box: false,
        );
        final icons = find.descendant(
          of: _k('side-header'),
          matching: find.byType(Icon),
        );
        final bar = find.descendant(
          of: _k('top-bar'),
          matching: find.byType(Icon),
        );
        expect(icons, findsWidgets);
        expect(bar, findsWidgets);
        expect(
          (t.getRect(icons.first).center.dy - t.getRect(bar.first).center.dy)
              .abs(),
          lessThanOrEqualTo(1),
        );
      });

      testWidgets('peek toolbar lines up with side header, $tag', (t) async {
        final s = await _pump(t, width, side);
        s.select('a');
        await t.pumpAndSettle();
        _same(t, _k('peek-toolbar'), _k('side-header'));
        if (width >= 1280) _same(t, _k('peek-toolbar'), _k('top-bar'));
      });
    }
  }
}
