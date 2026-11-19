import 'dart:async';

import 'package:davdart/davdart.dart';

import '../../../test/support/fake_caldav.dart';

import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/persistent_store.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/list_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

class FakeSource implements NoteSource {
  FakeSource(this.notes);
  final List<Note> notes;
  @override
  Future<List<Note>> load() async => notes;
}

class SlowSource implements NoteSource {
  SlowSource(this.result);
  final Future<List<Note>> result;
  @override
  Future<List<Note>> load() => result;
}

final sample = [
  Note(
    uid: 'a',
    summary: 'Build decisions',
    description:
        'item_id: davdart-decisions\nstatus: todo\nowner: tm\n\n'
        '## Confirmed\n- first slice is the core\n- **public** repo',
    categories: ['davdart', 'planning', 'status-todo'],
    created: DateTime.utc(2026, 11, 19),
  ),
  Note(
    uid: 'b',
    summary: 'Core slice',
    parentUid: 'a',
    description: 'item_id: davdart-slice-1\nstatus: backlog\n\nBody text',
    categories: ['davdart', 'status-backlog'],
    created: DateTime.utc(2026, 11, 20),
  ),
  Note(uid: 'c', summary: 'Loose note', description: 'just text'),
];

Future<void> pump(WidgetTester t, {Size size = const Size(1400, 900)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(DavdartApp(source: FakeSource(sample)));
  await t.pumpAndSettle();
}

void main() {
  group('AppState', () {
    test('groups the board by status and filters by query and tag', () async {
      final s = AppState(FakeSource(sample));
      await s.load();
      expect(s.columns.map((c) => c.$1), ['backlog', 'todo', 'notes']);
      s.setQuery('body text');
      expect(s.filtered.map((n) => n.uid), ['b']);
      s.setQuery('');
      s.setTag('planning');
      expect(s.filtered.map((n) => n.uid), ['a']);
      s.setTag('planning');
      expect(s.tag, isNull);
    });

    test('edits go through a local Space', () async {
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      final s = AppState(SpaceNoteSource(space, seed: FakeSource(sample)));
      await s.load();
      expect(s.editable, isTrue);
      expect(s.notes, hasLength(3));
      await s.setStatus('b', 'doing');
      final b = (await space.notes()).firstWhere((n) => n.uid == 'b');
      expect(PlanItem.fromNote(b).status, 'doing');
      expect(b.categories, contains('status-doing'));
      expect(b.categories, isNot(contains('status-backlog')));
      await s.setStatus('c', 'todo');
      expect(PlanItem.fromNote(s.tree.find('c')!.note).status, 'todo');
      await s.addNote('  New idea ', parentUid: 'a', status: 'backlog');
      expect(s.notes, hasLength(4));
      expect(s.selected!.summary, 'New idea');
      expect(s.selected!.parentUid, 'a');
      expect(PlanItem.fromNote(s.selected!).status, 'backlog');
      await s.addNote('   ');
      expect(s.notes, hasLength(4));
      // reload keeps the edits and does not re-seed
      await s.load();
      expect(s.notes, hasLength(4));
    });

    test(
      'edits survive a restart through storage, damaged data is ignored',
      () async {
        final storage = MemoryStorage();
        Space open() => Space(
          SpaceConfig(id: 's', name: 'S'),
          PersistentNoteStore(storage),
        );
        final a = AppState(SpaceNoteSource(open(), seed: FakeSource(sample)));
        await a.load();
        await a.setStatus('b', 'done');
        await a.addNote('Kept');
        final b = AppState(SpaceNoteSource(open(), seed: FakeSource(sample)));
        await b.load();
        expect(b.notes, hasLength(4));
        expect(PlanItem.fromNote(b.tree.find('b')!.note).status, 'done');
        storage.write('davdart.space.v1', '{not json');
        final c = AppState(SpaceNoteSource(open(), seed: FakeSource(sample)));
        await c.load();
        expect(c.notes, hasLength(3));
      },
    );

    test(
      'saved views persist, apply and delete; bad data is ignored',
      () async {
        final prefs = MemoryStorage();
        final a = AppState(FakeSource(sample), prefs: prefs);
        a.setView(ViewMode.list);
        a.setTag('planning');
        a.setQuery(' body ');
        expect(a.hasFilter, isTrue);
        a.saveView('Planning bodies');
        a.saveView('   ');
        expect(a.savedViews, hasLength(1));
        final b = AppState(FakeSource(sample), prefs: prefs);
        expect(b.savedViews.single.name, 'Planning bodies');
        await b.load();
        b.setView(ViewMode.board);
        b.setTag(null);
        b.setQuery('');
        b.applyView(b.savedViews.single);
        expect(b.searchController.text, 'body');
        expect((b.view, b.tag, b.query), (ViewMode.list, 'planning', 'body'));
        b.deleteView('Planning bodies');
        expect(AppState(FakeSource(sample), prefs: prefs).savedViews, isEmpty);
        prefs.write('davdart.views.v1', '{oops');
        expect(AppState(FakeSource(sample), prefs: prefs).savedViews, isEmpty);
      },
    );

    test(
      'spaces: separate notes, restart keeps the list and current space',
      () async {
        final storage = MemoryStorage();
        AppState open() {
          final c = SpaceCatalog(storage, planningSeed: FakeSource(sample));
          return AppState(c.sourceFor(c.current), prefs: storage, catalog: c);
        }

        final s = open();
        await s.load();
        expect(s.currentSpaceName, 'Planning');
        expect(s.notes, hasLength(3));
        await s.createSpace('  Inbox ');
        expect(s.currentSpaceName, 'Inbox');
        expect(s.notes, isEmpty);
        await s.addNote('Only here');
        expect(s.notes, hasLength(1));
        await s.switchSpace('planning');
        expect(s.notes, hasLength(3));
        await s.switchSpace(s.spaces.last.id);
        final r = open();
        expect(r.currentSpaceName, 'Inbox');
        await r.load();
        expect(r.notes.map((n) => n.summary), ['Only here']);
        await r.createSpace('   ');
        expect(r.spaces, hasLength(2));
      },
    );

    test('rename a space; delete removes its data, never Planning', () async {
      final storage = MemoryStorage();
      final c = SpaceCatalog(storage, planningSeed: FakeSource(sample));
      final s = AppState(c.sourceFor(c.current), prefs: storage, catalog: c);
      await s.load();
      await s.createSpace('Inbox');
      await s.addNote('doomed');
      s.setQuery('x');
      s.saveView('v');
      final id = s.currentSpaceId!;
      expect(s.renameSpace('  '), isFalse);
      expect(s.renameSpace('Planning'), isFalse);
      expect(s.renameSpace('Scratch'), isTrue);
      expect(s.currentSpaceName, 'Scratch');
      expect(storage.keys, contains('davdart.views.v1.$id'));
      expect(storage.read('davdart.views.v1'), isNull);
      final doomed = c.sourceFor(id);
      expect(SpaceCatalog(storage).spaces.last.name, 'Scratch');
      expect(storage.keys.any((k) => k.startsWith('sp.$id.')), isTrue);
      await s.deleteSpace();
      expect(s.currentSpaceId, 'planning');
      expect(s.notes, hasLength(3));
      expect(s.spaces.map((e) => e.id), ['planning']);
      expect(storage.keys.where((k) => k.contains(id)), isEmpty);
      await doomed.save(
        Note(uid: 'late', summary: 'late', description: ''),
      ); // a save still running after delete must not leave data behind
      expect(storage.keys.where((k) => k.contains(id)), isEmpty);
      await s.deleteSpace(); // Planning: ignored
      expect(s.spaces, hasLength(1));
      expect(s.renameSpace('Work'), isTrue);
      expect(s.currentSpaceName, 'Work');
    });

    test(
      'a slow load from a space left behind does not overwrite the new one',
      () async {
        final storage = MemoryStorage();
        final gate = Completer<List<Note>>();
        final c = SpaceCatalog(storage, planningSeed: SlowSource(gate.future));
        final s = AppState(c.sourceFor(c.current), prefs: storage, catalog: c);
        final first = s.load(); // planning seed is still loading
        await s.createSpace('Inbox');
        await s.addNote('mine');
        gate.complete(sample);
        await first;
        expect(s.currentSpaceName, 'Inbox');
        expect(s.notes.map((n) => n.summary), ['mine']);
      },
    );

    test(
      'duplicate space names get a number; saved views are per space',
      () async {
        final storage = MemoryStorage();
        final c = SpaceCatalog(storage, planningSeed: FakeSource(sample));
        final s = AppState(c.sourceFor(c.current), prefs: storage, catalog: c);
        await s.load();
        s.setQuery('x');
        s.saveView('mine');
        await s.createSpace('Planning');
        await s.createSpace('Planning');
        expect(s.spaces.map((e) => e.name), [
          'Planning',
          'Planning 2',
          'Planning 3',
        ]);
        expect(s.savedViews, isEmpty);
        await s.switchSpace('planning');
        expect(s.savedViews.map((v) => v.name), ['mine']);
        storage.write('davdart.spaces.v1', '{broken');
        final c2 = SpaceCatalog(storage);
        expect(c2.spaces.map((e) => e.id), ['planning']);
        expect(storage.read('davdart.spaces.v1.unreadable'), '{broken');
      },
    );

    test('keeps the error when loading fails', () async {
      final s = AppState(_Failing());
      await s.load();
      expect(s.error, contains('boom'));
      expect(s.loading, isFalse);
    });
  });

  group('wide layout', () {
    testWidgets('shows sidebar, board columns and opens the detail pane', (
      t,
    ) async {
      await pump(t);
      expect(find.text('BACKLOG'), findsOneWidget);
      expect(find.text('TODO'), findsOneWidget);
      expect(find.text('davdart-slice-1'), findsWidgets);
      await t.tap(find.text('davdart-decisions').first);
      await t.pumpAndSettle();
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.textContaining('first slice is the core'), findsOneWidget);
      // The board stays visible beside the detail on a wide screen.
      expect(find.text('BACKLOG'), findsOneWidget);
    });

    testWidgets('switches to the list and shows the tree', (t) async {
      await pump(t);
      await t.tap(find.text('List').first);
      await t.pumpAndSettle();
      expect(find.text('Core slice'), findsWidgets);
      expect(find.text('Loose note'), findsWidgets);
    });

    testWidgets('new note dialog adds a note and selects it', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      await t.pumpWidget(
        DavdartApp(source: SpaceNoteSource(space, seed: FakeSource(sample))),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('New note'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('new-note-title')), 'Fresh idea');
      await t.tap(find.byKey(const Key('new-note-add')));
      await t.pumpAndSettle();
      final saved = (await space.notes()).where(
        (n) => n.summary == 'Fresh idea',
      );
      expect(saved, hasLength(1));
      expect(PlanItem.fromNote(saved.single).status, 'backlog');
      expect(find.text('Fresh idea'), findsWidgets);
    });

    test('updateNote keeps the header; deleteNote moves children up', () async {
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      final s = AppState(SpaceNoteSource(space, seed: FakeSource(sample)));
      await s.load();
      await s.updateNote('b', title: ' Core slice 2 ', text: 'New text');
      final b = s.tree.find('b')!.note;
      expect(b.summary, 'Core slice 2');
      expect(
        b.description,
        'item_id: davdart-slice-1\nstatus: backlog\n\nNew text',
      );
      await s.updateNote('b', tags: ['x', 'status-done', '']);
      expect(s.tree.find('b')!.note.categories, ['status-backlog', 'x']);
      await s.updateNote('b', title: '   ');
      expect(s.tree.find('b')!.note.summary, 'Core slice 2');
      s.select('a');
      await s.deleteNote('a');
      expect(s.notes.map((n) => n.uid).toSet(), {'b', 'c'});
      expect(s.tree.find('b')!.note.parentUid, isNull);
      expect(s.selectedUid, isNull);
      expect(s.error, isNull);
    });

    test('deleting every note does not bring the seed back', () async {
      final storage = MemoryStorage();
      AppState open() => AppState(
        SpaceNoteSource(
          Space(SpaceConfig(id: 's', name: 'S'), PersistentNoteStore(storage)),
          seed: FakeSource(sample),
          flags: storage,
        ),
      );
      final s = open();
      await s.load();
      for (final n in [...s.notes]) {
        await s.deleteNote(n.uid);
      }
      expect(s.notes, isEmpty);
      final again = open();
      await again.load();
      expect(again.notes, isEmpty);
    });

    test(
      'connect, sync, edit syncs, restart keeps the login, disconnect',
      () async {
        final server = FakeCalDav();
        final storage = MemoryStorage();
        SpaceNoteSource open() => SpaceNoteSource(
          Space(SpaceConfig(id: 's', name: 'S'), PersistentNoteStore(storage)),
          seed: FakeSource(sample),
          flags: storage,
          davBase: Uri.parse('https://fake.test/dav/'),
          httpClient: server.client,
        );
        final s = AppState(open());
        await s.load();
        expect(s.connected, isFalse);
        await s.connect('c/', 'tm', 'pw');
        expect(s.connected, isTrue);
        expect(s.syncMessage, startsWith('Synced'));
        expect(server.ics, hasLength(3));
        await s.setStatus('b', 'doing');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          server.ics.values.any((v) => v.contains('status-doing')),
          isTrue,
        );
        // another device adds a note; sync pulls it
        server.external(
          'z.ics',
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\n'
              'BEGIN:VJOURNAL\r\nUID:z\r\nDTSTAMP:20261119T000000Z\r\n'
              'SUMMARY:From elsewhere\r\nEND:VJOURNAL\r\nEND:VCALENDAR\r\n',
        );
        await s.sync();
        expect(s.notes.map((n) => n.uid), contains('z'));
        // restart: login survives, no re-seed, nothing re-marked dirty
        final r = AppState(open());
        await r.load();
        expect(r.connected, isTrue);
        expect(r.notes, hasLength(4));
        await r.disconnect();
        expect(r.connected, isFalse);
        expect(r.notes, hasLength(4));
      },
    );

    test(
      'reconnecting does not resurrect notes deleted on the server',
      () async {
        final server = FakeCalDav();
        final storage = MemoryStorage();
        final s = AppState(
          SpaceNoteSource(
            Space(
              SpaceConfig(id: 's', name: 'S'),
              PersistentNoteStore(storage),
            ),
            seed: FakeSource(sample),
            flags: storage,
            davBase: Uri.parse('https://fake.test/dav/'),
            httpClient: server.client,
          ),
        );
        await s.load();
        await s.connect('c/', 'tm', 'pw');
        expect(server.ics, hasLength(3));
        await s.disconnect();
        // offline: server loses a note, we edit another
        server.externalDelete(
          server.ics.entries.firstWhere((e) => e.value.contains('UID:c')).key,
        );
        await s.setStatus('b', 'done');
        await s.connect('c/', 'tm', 'pw');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(s.notes.map((n) => n.uid).toSet(), {'a', 'b'});
        expect(server.ics, hasLength(2));
        expect(server.ics.values.any((v) => v.contains('status-done')), isTrue);
      },
    );

    test('connect with replaceLocal takes the server copy only', () async {
      final server = FakeCalDav();
      server.external(
        'z.ics',
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\n'
            'BEGIN:VJOURNAL\r\nUID:z\r\nDTSTAMP:20261119T000000Z\r\n'
            'SUMMARY:Server note\r\nEND:VJOURNAL\r\nEND:VCALENDAR\r\n',
      );
      final storage = MemoryStorage();
      final s = AppState(
        SpaceNoteSource(
          Space(SpaceConfig(id: 's', name: 'S'), PersistentNoteStore(storage)),
          seed: FakeSource(sample),
          flags: storage,
          davBase: Uri.parse('https://fake.test/dav/'),
          httpClient: server.client,
        ),
      );
      await s.load();
      expect(s.notes, hasLength(3));
      await s.connect('c/', 'tm', 'pw', replaceLocal: true);
      expect(s.notes.map((n) => n.uid), ['z']);
      expect(server.ics, hasLength(1));
    });

    test('a refused login changes nothing', () async {
      final storage = MemoryStorage();
      final src = SpaceNoteSource(
        Space(SpaceConfig(id: 's', name: 'S'), PersistentNoteStore(storage)),
        seed: FakeSource(sample),
        flags: storage,
        davBase: Uri.parse('https://fake.test/dav/'),
        httpClient: MockClient((r) async => http.Response('no', 401)),
      );
      final s = AppState(src);
      await s.load();
      await s.connect('c/', 'tm', 'bad');
      expect(s.connected, isFalse);
      expect(s.syncMessage, startsWith('Could not connect'));
      expect(s.notes, hasLength(3));
    });

    test('discover offers collections by name as connectable paths', () async {
      final storage = MemoryStorage();
      final src = SpaceNoteSource(
        Space(SpaceConfig(id: 's', name: 'S'), PersistentNoteStore(storage)),
        flags: storage,
        davBase: Uri.parse('https://fake.test/dav/'),
        httpClient: MockClient((r) async {
          expect(r.url.path, '/dav/tm/');
          return http.Response(
            '<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
            '<response><href>/dav/tm/</href><propstat><prop>'
            '<resourcetype><collection/></resourcetype></prop></propstat></response>'
            '<response><href>/dav/tm/abc-123/</href><propstat><prop>'
            '<displayname>planning</displayname>'
            '<resourcetype><collection/><C:calendar/></resourcetype>'
            '</prop></propstat></response></multistatus>',
            207,
          );
        }),
      );
      final s = AppState(src);
      final found = await s.discoverCollections(' tm ', 'pw');
      expect(found.map((c) => (c.name, c.path)), [('planning', 'tm/abc-123/')]);
    });

    testWidgets('detail lists earlier versions kept by a merge', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      await space.store.addRevision(
        Revision(
          uid: 'c',
          at: DateTime.utc(2026, 11, 19, 10),
          reason: 'overlapping edit',
          summary: 'Loose note',
          body: 'old words',
        ),
      );
      await t.pumpWidget(
        DavdartApp(source: SpaceNoteSource(space, seed: FakeSource(sample))),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Loose note').first);
      await t.pumpAndSettle();
      expect(find.text('Earlier versions (1)'), findsOneWidget);
      await t.tap(find.text('Earlier versions (1)'));
      await t.pumpAndSettle();
      expect(find.text('old words'), findsOneWidget);
      await t.tap(find.text('Build decisions').first);
      await t.pumpAndSettle();
      expect(find.textContaining('Earlier versions'), findsNothing);
    });

    testWidgets('edit dialog changes the title', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      await t.pumpWidget(
        DavdartApp(source: SpaceNoteSource(space, seed: FakeSource(sample))),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Loose note').first);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('edit-note')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('edit-title')), 'Renamed');
      await t.tap(find.byKey(const Key('edit-save')));
      await t.pumpAndSettle();
      expect((await space.notes()).map((n) => n.summary), contains('Renamed'));
      await t.tap(find.byKey(const Key('delete-note')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('delete-confirm')));
      await t.pumpAndSettle();
      expect(
        (await space.notes()).map((n) => n.summary),
        isNot(contains('Renamed')),
      );
    });

    testWidgets('space menu creates and switches spaces', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = SpaceCatalog(storage, planningSeed: FakeSource(sample));
      final state = AppState(
        c.sourceFor(c.current),
        prefs: storage,
        catalog: c,
      );
      await t.pumpWidget(DavdartApp(state: state));
      await t.pumpAndSettle();
      expect(find.text('Planning'), findsWidgets);
      await t.tap(find.byKey(const Key('space-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('New space…'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('space-name')), 'Inbox');
      await t.tap(find.byKey(const Key('space-create')));
      await t.pumpAndSettle();
      expect(find.text('Inbox'), findsWidgets);
      expect(find.text('No notes'), findsWidgets);
    });

    testWidgets('space menu renames and deletes', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = SpaceCatalog(storage, planningSeed: FakeSource(sample));
      final state = AppState(
        c.sourceFor(c.current),
        prefs: storage,
        catalog: c,
      );
      await t.pumpWidget(DavdartApp(state: state));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('space-menu')));
      await t.pumpAndSettle();
      expect(find.text('Delete this space…'), findsNothing);
      await t.tap(find.text('New space…'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('space-name')), 'Inbox');
      await t.tap(find.byKey(const Key('space-create')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('space-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('Rename this space…'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('space-rename-name')), 'Later');
      await t.tap(find.byKey(const Key('space-rename')));
      await t.pumpAndSettle();
      expect(state.currentSpaceName, 'Later');
      await t.tap(find.byKey(const Key('space-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete this space…'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('space-delete')));
      await t.pumpAndSettle();
      expect(state.currentSpaceName, 'Planning');
      expect(state.spaces, hasLength(1));
    });

    test('search across spaces finds notes and opens the hit', () async {
      final storage = MemoryStorage();
      final c = SpaceCatalog(storage, planningSeed: FakeSource(sample));
      final s = AppState(c.sourceFor(c.current), prefs: storage, catalog: c);
      await s.load();
      await s.createSpace('Inbox');
      await s.addNote('Loose idea about decisions');
      final hits = await s.searchAllSpaces('DECISIONS');
      expect(hits.map((h) => h.space.name).toSet(), {'Planning', 'Inbox'});
      expect(await s.searchAllSpaces('  '), isEmpty);
      final planning = hits.firstWhere((h) => h.space.id == 'planning');
      await s.openHit(planning);
      expect(s.currentSpaceName, 'Planning');
      expect(s.selectedUid, planning.note.uid);
    });

    testWidgets('search narrows the list', (t) async {
      await pump(t);
      await t.tap(find.text('List').first);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'loose');
      await t.pumpAndSettle();
      expect(find.text('Loose note'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(NoteListView),
          matching: find.text('Build decisions'),
        ),
        findsNothing,
      );
    });
  });

  group('narrow layout', () {
    testWidgets('uses a drawer and a single pane', (t) async {
      await pump(t, size: const Size(420, 800));
      expect(find.byTooltip('Menu'), findsOneWidget);
      await t.tap(find.byTooltip('Menu'));
      await t.pumpAndSettle();
      expect(find.text('NOTES'), findsOneWidget);
      await t.tap(find.text('Core slice').last);
      await t.pumpAndSettle();
      expect(find.text('Body text'), findsOneWidget);
      expect(find.text('BACKLOG'), findsNothing);
      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      expect(find.text('BACKLOG'), findsOneWidget);
    });
  });

  testWidgets('a 320px phone does not overflow', (t) async {
    await pump(t, size: const Size(320, 640));
    expect(t.takeException(), isNull);
    await t.tap(find.byTooltip('Show list'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  test('a bad feed entry is skipped, not fatal', () {
    final notes = parseNotesJson(
      '[{"uid":null},{"uid":"ok","title":"T",'
      '"created":"garbage"},{"uid":"ok"},5]',
    );
    expect(notes.map((n) => n.uid), ['ok']);
    expect(notes.single.created, isNull);
  });

  test('a filter tag that no longer exists is cleared on reload', () async {
    final src = FakeSource(sample);
    final s = AppState(src);
    await s.load();
    s.setTag('planning');
    src.notes.removeWhere((n) => n.uid == 'a');
    await s.load();
    expect(s.tag, isNull);
  });

  test('parses the JSON feed', () {
    final notes = parseNotesJson(
      '[{"uid":"x","title":"T","body":"b",'
      '"tags":["a"],"status":null,"parent":"p",'
      '"created":"2026-11-19T01:00:00.000Z","modified":null}]',
    );
    expect(notes.single.parentUid, 'p');
    expect(notes.single.categories, ['a']);
    expect(notes.single.created, DateTime.utc(2026, 11, 19, 1));
  });
}

class _Failing implements NoteSource {
  @override
  Future<List<Note>> load() async => throw Exception('boom');
}
