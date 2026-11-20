import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';

import 'catalog_helper.dart';

import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Seed implements NoteSource {
  _Seed([this.skip = const {}]);
  final Set<String> skip;
  @override
  Future<List<Note>> load() async => [
    for (final n in [
      Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
      Note(uid: 'g', summary: 'Ideas', categories: ['kind-folder']),
      Note(uid: 'a', summary: 'Alpha', parentUid: 'f', categories: ['red']),
      Note(uid: 'b', summary: 'Beta', categories: ['blue']),
    ])
      if (!skip.contains(n.uid)) n,
  ];
}

AppState _state(MemoryStorage prefs, [Set<String> skip = const {}]) => AppState(
  SpaceNoteSource(
    Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore()),
    seed: _Seed(skip),
  ),
  prefs: prefs,
);

Future<void> _show(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(1500, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
}

void main() {
  group('folder state', () {
    test('survives a rebuild with the same prefs', () async {
      final prefs = MemoryStorage();
      final a = _state(prefs);
      await a.load();
      expect(a.collapsed, isEmpty);
      a.toggle('f');
      final b = _state(prefs);
      await b.load();
      expect(b.collapsed, {'f'});
      b.toggle('f');
      final c = _state(prefs);
      await c.load();
      expect(c.collapsed, isEmpty);
    });

    test('drops uids that no longer exist', () async {
      final prefs = MemoryStorage();
      final a = _state(prefs);
      await a.load();
      a.toggle('f');
      a.toggle('g');
      final b = _state(prefs, {'g'});
      await b.load();
      expect(b.collapsed, {'f'});
    });

    test('ignores corrupt saved values', () async {
      for (final bad in ['nope', '{"a":1}', '[1,null]']) {
        final prefs = MemoryStorage()
          ..write('davdart.folders.collapsed.v1.default', bad);
        final s = _state(prefs);
        await s.load();
        expect(s.collapsed, isEmpty, reason: bad);
      }
    });

    test('is kept per Space', () async {
      final prefs = MemoryStorage();
      AppState open() {
        final c = catalogWithPlanning(prefs, planningSeed: _Seed());
        return AppState(c.sourceFor(c.current!), prefs: prefs, catalog: c);
      }

      final s = open();
      await s.load();
      s.toggle('f');
      await s.createSpace('Inbox');
      expect(s.collapsed, isEmpty);
      await s.switchSpace('planning');
      expect(s.collapsed, {'f'});
      final r = open();
      await r.load();
      expect(r.collapsed, {'f'});
    });
  });

  group('tags accordion', () {
    testWidgets('is collapsed by default and opens on tap, remembered', (
      t,
    ) async {
      final prefs = MemoryStorage();
      final s = _state(prefs);
      await s.load();
      await _show(t, s);
      expect(find.text('Tags (2)'), findsOneWidget);
      expect(find.text('TAGS'), findsNothing);
      expect(find.byKey(const Key('tag-red')).hitTestable(), findsNothing);
      await t.tap(find.text('Tags (2)'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tag-red')).hitTestable(), findsOneWidget);
      expect(s.tagsOpen, isTrue);

      final s2 = _state(prefs);
      await s2.load();
      await _show(t, s2);
      expect(find.byKey(const Key('tag-red')).hitTestable(), findsOneWidget);
      await t.tap(find.text('Tags (2)'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tag-red')).hitTestable(), findsNothing);
      expect(prefs.read('davdart.tags.open.v1.default'), isNull);
    });

    testWidgets('opens while a tag filter is active', (t) async {
      final s = _state(MemoryStorage());
      await s.load();
      await _show(t, s);
      s.setTag('red');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tag-red')).hitTestable(), findsOneWidget);
      s.setTag(null);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tag-red')).hitTestable(), findsNothing);
    });

    testWidgets('tapping a chip filters', (t) async {
      final prefs = MemoryStorage()
        ..write('davdart.tags.open.v1.default', 'true');
      final s = _state(prefs);
      await s.load();
      await _show(t, s);
      await t.tap(find.byKey(const Key('tag-blue')));
      await t.pumpAndSettle();
      expect(s.tag, 'blue');
    });
  });
}
