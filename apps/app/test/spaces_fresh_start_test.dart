import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'catalog_helper.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha', description: 'Alpha body'),
  ];
}

AppState _app(SpaceCatalog c, MemoryStorage m) => AppState(
  c.current == null ? const EmptyNoteSource() : c.sourceFor(c.current!),
  prefs: m,
  catalog: c,
);

void main() {
  group('catalog', () {
    test('a new install has no Space and no current one', () {
      final c = SpaceCatalog(MemoryStorage(), planningSeed: _Seed());
      expect(c.spaces, isEmpty);
      expect(c.current, isNull);
      expect(c.currentInfo, isNull);
    });

    test('an install with legacy data keeps Planning listed', () {
      final m = MemoryStorage()..write('davdart.space.v1', '{"notes":{}}');
      final c = SpaceCatalog(m);
      expect(c.spaces.map((s) => s.id), [SpaceCatalog.planningId]);
      expect(c.current, SpaceCatalog.planningId);
    });

    test('a stored list without Planning does not bring it back', () {
      final m = MemoryStorage()
        ..write('davdart.space.v1', '{"notes":{}}')
        ..write('davdart.spaces.v1', '[{"id":"sp-1","name":"One"}]');
      final c = SpaceCatalog(m);
      expect(c.spaces.map((s) => s.id), ['sp-1']);
      expect(c.current, 'sp-1');
    });

    test('an empty stored list stays empty', () {
      final m = MemoryStorage()
        ..write('davdart.space.v1', '{"notes":{}}')
        ..write('davdart.spaces.v1', '[]');
      expect(SpaceCatalog(m).spaces, isEmpty);
    });

    test('removing a Space removes only its own keys', () {
      final m = MemoryStorage();
      final c = catalogWithPlanning(m);
      final a = c.add('A');
      final b = c.add('B');
      for (final k in [
        'davdart.space.v1',
        'davdart.seeded.v1',
        'davdart.server.v1',
        'davdart.lastserver.v1',
        'davdart.section.v1',
        'sp.${a.id}.davdart.space.v1',
        'sp.${a.id}.davdart.seeded.v1',
        'sp.${b.id}.davdart.space.v1',
      ]) {
        m.write(k, 'x');
      }
      c.remove(a.id);
      expect(m.keys.where((k) => k.startsWith('sp.${a.id}.')), isEmpty);
      expect(m.read('sp.${b.id}.davdart.space.v1'), 'x');
      expect(m.read('davdart.space.v1'), 'x'); // Planning untouched
      expect(m.read('davdart.section.v1'), 'x');
      c.remove(SpaceCatalog.planningId);
      for (final k in SpaceCatalog.legacyKeys) {
        expect(m.read(k), isNull, reason: k);
      }
      expect(m.read('davdart.section.v1'), 'x'); // not a Space key
      expect(m.read('sp.${b.id}.davdart.space.v1'), 'x');
      expect(m.read('davdart.spaces.v1'), isNot(contains('planning')));
    });

    test('a Space id that is a prefix of another keeps the other keys', () {
      final m = MemoryStorage();
      final c = SpaceCatalog(m);
      final a = c.add('A');
      // Same dotted prefix: id "<a>.x" has keys under "sp.<a>.x.".
      final longId = '${a.id}.x';
      m.write(
        'davdart.spaces.v1',
        '[{"id":"${a.id}","name":"A"},{"id":"$longId","name":"L"}]',
      );
      final c2 = SpaceCatalog(m);
      m.write('sp.$longId.davdart.space.v1', 'keep');
      m.write('sp.${a.id}.davdart.space.v1', 'gone');
      c2.remove(a.id);
      expect(m.read('sp.$longId.davdart.space.v1'), 'keep');
      expect(m.read('sp.${a.id}.davdart.space.v1'), isNull);
    });

    test('removing the open Space opens the next, else the previous', () {
      final c = catalogWithPlanning(MemoryStorage());
      final a = c.add('A');
      final b = c.add('B');
      c.select(SpaceCatalog.planningId);
      c.remove(SpaceCatalog.planningId);
      expect(c.current, a.id);
      c.select(b.id);
      c.remove(b.id);
      expect(c.current, a.id); // no next: the previous
      c.remove(a.id);
      expect(c.current, isNull);
      expect(c.spaces, isEmpty);
    });
  });

  group('state', () {
    test('delete the legacy Space: the neighbour opens', () async {
      final m = MemoryStorage();
      final c = catalogWithPlanning(m, planningSeed: _Seed());
      final s = _app(c, m);
      await s.load();
      await s.createSpace('Other');
      await s.switchSpace(SpaceCatalog.planningId);
      expect(s.notes, hasLength(1));
      await s.deleteSpace();
      expect(s.spaces.map((e) => e.name), ['Other']);
      expect(s.currentSpaceName, 'Other');
      expect(s.noSpace, isFalse);
      expect(m.read('davdart.space.v1'), isNull);
    });

    test('delete the last Space: empty state, then create one', () async {
      final m = MemoryStorage();
      final c = SpaceCatalog(m);
      final s = _app(c, m);
      await s.load();
      expect(s.noSpace, isTrue);
      await s.createSpace('First');
      expect(s.noSpace, isFalse);
      expect(s.currentSpaceName, 'First');
      await s.addNote('x');
      await s.deleteSpace();
      expect(s.noSpace, isTrue);
      expect(s.notes, isEmpty);
      expect(s.currentSpaceName, isNull);
      expect(s.editable, isFalse);
      expect(m.keys.where((k) => k.startsWith('sp.')), isEmpty);
      await s.deleteSpace(); // nothing to delete: no error
      await s.createSpace('Again');
      expect(s.currentSpaceName, 'Again');
    });

    test('signing in with no Spaces loads the account Spaces', () async {
      final client = MockClient((r) async {
        if (r.method == 'PROPFIND') {
          return http.Response(
            '<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
            '<response><href>/dav/tm/</href><propstat><prop>'
            '<resourcetype><collection/></resourcetype></prop></propstat></response>'
            '<response><href>/dav/c/</href><propstat><prop>'
            '<displayname>Work</displayname>'
            '<resourcetype><collection/><C:calendar/></resourcetype>'
            '</prop></propstat></response></multistatus>',
            207,
          );
        }
        return http.Response('', 404);
      });
      final m = MemoryStorage();
      final c = SpaceCatalog(
        m,
        davBase: Uri.parse('https://fake.test/dav/'),
        httpClient: client,
      );
      final s = _app(c, m);
      await s.load();
      expect(s.noSpace, isTrue);
      await s.signIn('tm', 'pw');
      expect(s.noSpace, isFalse);
      expect(s.currentSpaceName, 'Work');
      expect(s.source, isNot(isA<EmptyNoteSource>()));
    });

    test('unsynced count warns about edits not saved', () async {
      final m = MemoryStorage();
      final c = SpaceCatalog(m);
      final s = _app(c, m);
      await s.createSpace('One');
      await s.addNote('n');
      expect(await s.unsyncedInCurrent(), 0);
    });
  });

  group('first-run screen', () {
    for (final size in const [
      Size(320, 700),
      Size(880, 900),
      Size(1280, 900),
    ]) {
      testWidgets('shows at $size without exceptions', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final m = MemoryStorage();
        final s = _app(SpaceCatalog(m), m);
        await t.pumpWidget(DavdartApp(state: s));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Create your first Space'), findsOneWidget);
        expect(find.byKey(const Key('first-run-new')), findsOneWidget);
        expect(find.byKey(const Key('first-run-sign-in')), findsOneWidget);
        // Every sidebar section builds with no Space.
        if (size.width >= 880) {
          for (final id in const [
            'rail-views',
            'rail-search',
            'rail-account',
            'rail-settings',
            'rail-notes',
          ]) {
            final f = find.byKey(Key(id));
            if (f.evaluate().isEmpty) continue;
            await t.tap(f);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: id);
          }
          await t.tap(find.byKey(const Key('rail-spaces')));
          await t.pumpAndSettle();
          expect(find.text('New Space…'), findsOneWidget);
          expect(find.text('Delete this space…'), findsNothing);
          expect(t.takeException(), isNull);
        }
        // Create the first Space from the screen.
        await t.tap(find.byKey(const Key('first-run-new')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('space-name')), 'Mine');
        await t.tap(find.byKey(const Key('space-create')));
        await t.pumpAndSettle();
        expect(s.currentSpaceName, 'Mine');
        expect(find.text('Create your first Space'), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('deleting the open Space shows the screen', (t) async {
      t.view.physicalSize = const Size(1280, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final m = MemoryStorage();
      final c = catalogWithPlanning(m, planningSeed: _Seed());
      final s = _app(c, m);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rail-spaces')));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete this space…'));
      await t.pumpAndSettle();
      expect(find.textContaining('never deleted'), findsOneWidget);
      await t.tap(find.byKey(const Key('space-delete')));
      await t.pumpAndSettle();
      expect(find.text('Create your first Space'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
