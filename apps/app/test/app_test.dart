import 'dart:async';

import 'package:davdart/davdart.dart';

import '../../../test/support/fake_caldav.dart';

import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/persistent_store.dart';
import 'package:davdart_app/data/space_catalog.dart';

import 'catalog_helper.dart';

import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/list_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/semantics.dart';
import 'package:forui/forui.dart';
import 'package:davdart_app/ui/parts.dart';
import 'package:davdart_app/ui/shell_frame.dart';
import 'package:davdart_app/ui/sidebar.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:davdart_app/theme/tokens.dart';

class FakeSource implements NoteSource {
  FakeSource(this.notes);
  final List<Note> notes;
  @override
  Future<List<Note>> load() async => notes;
}

class MemSource implements EditableNoteSource {
  MemSource(Iterable<Note> start) : notes = {for (final n in start) n.uid: n};
  final Map<String, Note> notes;
  @override
  Future<List<Note>> load() async => [
    for (final n in notes.values) n.copyWith(),
  ];
  @override
  Future<Note> save(Note n) async => notes[n.uid] = n.copyWith();
  @override
  Future<void> delete(String uid) async => notes.remove(uid);
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

Finder byAction(String tooltip) => find.byWidgetPredicate(
  (w) => w is IconAction && w.tooltip == tooltip,
  description: 'IconAction "$tooltip"',
);

/// Home is always the board: the list lives in a saved-view tab.
Future<void> listTab(WidgetTester t) async {
  final s = t.widget<DavdartApp>(find.byType(DavdartApp)).state;
  s.setView(ViewMode.list);
  await t.runAsync(() => s.saveView('List'));
  s.applyView(s.savedViews.single);
  await t.pumpAndSettle();
}

Future<void> pump(WidgetTester t, {Size size = const Size(1400, 900)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  await t.pumpWidget(
    DavdartApp(source: SpaceNoteSource(space, seed: FakeSource(sample))),
  );
  await t.pumpAndSettle();
  // These tests are about the old Day | Board main view, not the Home page.
  t.widget<DavdartApp>(find.byType(DavdartApp)).state.setSection(Section.notes);
  await t.pumpAndSettle();
}

String textOfKey(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  setUp(() => AppState.debugDefaultFocus = HomeFocus.board);
  tearDown(() => AppState.debugDefaultFocus = HomeFocus.day);
  group('AppState', () {
    test('groups the board by status and filters by query and tag', () async {
      final s = AppState(FakeSource(sample));
      await s.load();
      expect(s.columns().map((c) => c.$1), ['backlog', 'todo', 'notes']);
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
      expect(s.peek!.summary, 'New idea');
      expect(s.peek!.parentUid, 'a');
      expect(PlanItem.fromNote(s.peek!).status, 'backlog');
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

    test('saved views are notes: hidden, round trip, apply, update', () async {
      final src = MemSource(sample);
      final a = AppState(src);
      await a.load();
      await a.addFolder('Docs');
      final folder = a.notes.firstWhere(AppState.isFolder).uid;
      a.openFolder(null);
      a.setView(ViewMode.list);
      a.setTag('planning');
      a.setQuery(' body ');
      expect(a.hasFilter, isTrue);
      expect(await a.saveView('Planning bodies'), isNull);
      expect(await a.saveView('   '), isNotNull);
      expect(a.savedViews, hasLength(1));
      final stored = src.notes.values.singleWhere(isViewNote);
      expect(stored.summary, 'Planning bodies');
      expect(stored.description, contains('mode: list'));
      // hidden from tree, lists, tags and search
      expect(a.notes.any(isViewNote), isFalse);
      expect(a.tree.find(stored.uid), isNull);
      expect(a.filtered.any(isViewNote), isFalse);
      expect(a.columns().expand((c) => c.$2).any(isViewNote), isFalse);
      expect(a.tags, isNot(contains('kind-view')));
      a.setQuery('');
      a.setTag(null);
      expect(a.filtered.map((n) => n.uid), isNot(contains(stored.uid)));
      // another client sees the same view
      final b = AppState(src);
      await b.load();
      expect(b.savedViews.single.name, 'Planning bodies');
      b.setView(ViewMode.board);
      b.openFolder(folder);
      b.applyView(b.savedViews.single);
      expect(b.searchController.text, 'body');
      expect((b.view, b.tag, b.query), (ViewMode.list, 'planning', 'body'));
      expect(b.scopeUid, isNull); // saved without a folder
      // a name that exists is refused (any case), nothing is added
      b.openFolder(folder);
      b.setQuery('x');
      expect(await b.saveView('Planning bodies'), isNotNull);
      expect(await b.saveView(' planning BODIES '), isNotNull);
      expect(src.notes.values.where(isViewNote), hasLength(1));
      await b.updateView(b.savedViews.single);
      b.setQuery('');
      b.openFolder(null);
      b.applyView(b.savedViews.single);
      expect((b.query, b.scopeUid), ('x', folder));
      // update from the current state
      b.setView(ViewMode.board);
      b.setQuery('y');
      b.openFolder(null);
      await b.updateView(b.savedViews.single);
      expect(
        src.notes.values.singleWhere(isViewNote).description,
        isNot(contains('folder:')),
      );
      expect(b.savedViews.single.query, 'y');
      expect(b.savedViews.single.view, ViewMode.board);
      // a folder that is gone is dropped on apply
      b.openFolder(folder);
      await b.saveView('Docs view');
      await b.deleteNote(folder);
      b.applyView(b.savedViews.firstWhere((v) => v.name == 'Docs view'));
      expect(b.scopeUid, isNull);
    });

    test('rename and delete a saved view', () async {
      final src = MemSource(sample);
      final s = AppState(src);
      await s.load();
      s.setQuery('a');
      await s.saveView('One');
      await s.saveView('Two');
      final one = s.savedViews.firstWhere((v) => v.name == 'One');
      expect(await s.renameView(one, 'Two'), isNotNull);
      expect(await s.renameView(one, ' two '), isNotNull); // any case
      expect(await s.saveView('TWO'), 'A view with that name exists');
      expect(s.savedViews, hasLength(2));
      expect(await s.renameView(one, '  '), isNotNull);
      expect(await s.renameView(one, ' Uno '), isNull);
      expect(s.savedViews.map((v) => v.name), ['Two', 'Uno']);
      expect(src.notes[one.uid]!.summary, 'Uno');
      await s.deleteView('Two');
      expect(s.savedViews.map((v) => v.name), ['Uno']);
      expect(src.notes.values.where(isViewNote), hasLength(1));
      await s.deleteView('Uno');
      expect(src.notes.values.where(isViewNote), isEmpty);
    });

    test('old local views move into notes once, then never again', () async {
      final prefs = MemoryStorage();
      const old =
          '[{"name":"Planning bodies","view":"list","query":"body","tag":"planning"},'
          '{"name":"Plain","view":"board","query":"","tag":null},{"bad":1}]';
      prefs.write('davdart.views.v1', old);
      final src = MemSource(sample);
      final a = AppState(src, prefs: prefs);
      await a.load();
      expect(a.savedViews.map((v) => v.name), ['Plain', 'Planning bodies']);
      final v = a.savedViews.last;
      expect((v.view, v.query), (ViewMode.list, 'body'));
      expect(v.tags, ['planning']);
      expect(prefs.read('davdart.views.v1'), old); // left untouched
      expect(prefs.read('davdart.views.v1.migrated'), '1');
      await a.deleteView('Plain');
      final b = AppState(src, prefs: prefs);
      await b.load();
      await b.load();
      expect(b.savedViews.map((v) => v.name), ['Planning bodies']);
      expect(src.notes.values.where(isViewNote), hasLength(1));
      // a read-only source keeps the old views for later
      final p2 = MemoryStorage()..write('davdart.views.v1', old);
      final r = AppState(FakeSource(sample), prefs: p2);
      await r.load();
      expect(p2.read('davdart.views.v1.migrated'), isNull);
    });

    test(
      'migration skips names that already exist and retries cleanly',
      () async {
        final prefs = MemoryStorage()
          ..write('davdart.views.v1', '[{"name":"A","view":"list"}]');
        final src = MemSource([
          SavedView('A', ViewMode.board, '', const [], uid: 'v-a').toNote(),
        ]);
        final s = AppState(src, prefs: prefs);
        await s.load();
        expect(src.notes.values.where(isViewNote), hasLength(1));
        expect(s.savedViews.single.view, ViewMode.board);
      },
    );

    test(
      'spaces: separate notes, restart keeps the list and current space',
      () async {
        final storage = MemoryStorage();
        AppState open() {
          final c = catalogWithPlanning(
            storage,
            planningSeed: FakeSource(sample),
          );
          return AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
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

    test(
      'rename a space; delete removes its data and opens the neighbour',
      () async {
        final storage = MemoryStorage();
        final c = catalogWithPlanning(
          storage,
          planningSeed: FakeSource(sample),
        );
        final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
        await s.load();
        await s.createSpace('Inbox');
        await s.addNote('doomed');
        s.setQuery('x');
        await s.saveView('v');
        final id = s.currentSpaceId!;
        expect(await s.renameSpace('  '), isNotNull);
        expect(await s.renameSpace('Planning'), isNotNull);
        expect(await s.renameSpace('Scratch'), isNull);
        expect(s.currentSpaceName, 'Scratch');
        expect(s.savedViews.map((v) => v.name), ['v']);
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
        expect(await s.renameSpace('Work'), isNull);
        expect(s.currentSpaceName, 'Work');
      },
    );

    test(
      'a slow load from a space left behind does not overwrite the new one',
      () async {
        final storage = MemoryStorage();
        final gate = Completer<List<Note>>();
        final c = catalogWithPlanning(
          storage,
          planningSeed: SlowSource(gate.future),
        );
        final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
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
        final c = catalogWithPlanning(
          storage,
          planningSeed: FakeSource(sample),
        );
        final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
        await s.load();
        s.setQuery('x');
        await s.saveView('mine');
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
        final c2 = catalogWithPlanning(storage);
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
      // Home is the dashboard now; the notes panel still lists the Space.
      final s = t.widget<DavdartApp>(find.byType(DavdartApp)).state;
      expect(find.byKey(const Key('home-page')), findsOneWidget);
      await t.tap(find.text('Build decisions').first);
      await t.pumpAndSettle();
      expect(find.text('Confirmed'), findsOneWidget);
      expect(s.peekUid, isNotNull);
    });

    testWidgets('switches to the list and shows the tree', (t) async {
      await pump(t);
      await listTab(t);
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
      await t.tap(find.byKey(const Key('new-note')));
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
      expect(s.peekUid, isNull);
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

    test('account: sign in lists collections as spaces, create, remove, sign out', () async {
      final server = FakeCalDav();
      server.external(
        'one.ics',
        serializeNote(Note(uid: 'one', summary: 'From server')),
      );
      final seen = <String>[];
      final client = MockClient((r) async {
        seen.add('${r.method} ${r.url.path}');
        if (r.method == 'PROPFIND' && r.url.path == '/dav/tm/') {
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
        if (r.method == 'MKCALENDAR') return http.Response('', 201);
        if (r.method == 'PROPPATCH') {
          return http.Response(
            '<multistatus xmlns="DAV:"><response><propstat>'
            '<status>HTTP/1.1 200 OK</status></propstat></response></multistatus>',
            207,
          );
        }
        if (r.url.path == '/dav/tm/' && r.method == 'REPORT') {
          return http.Response('', 404);
        }
        return server.respond(r);
      });
      final storage = MemoryStorage();
      final c = catalogWithPlanning(
        storage,
        davBase: Uri.parse('https://fake.test/dav/'),
        httpClient: client,
      );
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await s.load();
      await s.signIn(' tm ', 'pw');
      expect(s.accountUser, 'tm');
      expect(s.spaces.map((e) => e.name), ['Planning', 'Work']);
      final work = s.spaces.last;
      expect(work.onServer, isTrue);
      // Opening it attaches and pulls the server's notes.
      await s.switchSpace(work.id);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(s.connected, isTrue);
      expect(s.notes.map((n) => n.summary), ['From server']);
      // Its login holds no password of its own.
      expect(
        storage.read('sp.${work.id}.davdart.server.v1'),
        isNot(contains('pw')),
      );
      // New space on the server.
      await s.createSpace('Fresh', onServer: true);
      expect(seen.any((e) => e.startsWith('MKCALENDAR /dav/tm/')), isTrue);
      expect(s.currentSpaceName, 'Fresh');
      expect(s.currentOnServer, isTrue);
      // Removing an account space is local only; refresh brings it back.
      server.log.clear();
      await s.switchSpace(work.id);
      await s.deleteSpace();
      expect(s.spaces.map((e) => e.name), ['Planning', 'Fresh']);
      expect(server.log.where((e) => e.startsWith('DELETE')), isEmpty);
      await s.refreshSpaces();
      expect(s.spaces.map((e) => e.name), contains('Work'));
      // A re-added Space persists again (its writes were not left blocked).
      await s.switchSpace(s.spaces.firstWhere((e) => e.name == 'Work').id);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(storage.keys.any((k) => k.startsWith('sp.${work.id}.')), isTrue);
      // Renaming keeps it on the server.
      expect(await s.renameSpace('Work 2'), isNull);
      expect(seen.any((e) => e.startsWith('PROPPATCH /dav/c/')), isTrue);
      expect(s.currentOnServer, isTrue);
      expect(await s.renameSpace('Work'), isNull);
      // Restart: still signed in, the space reconnects without asking again.
      final c2 = catalogWithPlanning(
        storage,
        davBase: Uri.parse('https://fake.test/dav/'),
        httpClient: client,
      );
      expect(c2.account?.user, 'tm');
      // Sign out keeps the spaces as local copies.
      await s.signOut();
      expect(s.accountUser, isNull);
      expect(s.spaces.every((e) => !e.onServer), isTrue);
      expect(SpaceCatalog(storage).account, isNull);
      // Another user cannot replace the account while one is signed in.
      await s.signIn('tm', 'pw');
      await s.signIn('other', 'pw');
      expect(s.syncMessage, startsWith('Could not sign in'));
      expect(s.accountUser, 'tm');
    });

    test('sign-in links a space connected by hand and takes server names', () async {
      final server = FakeCalDav();
      final client = MockClient((r) async {
        if (r.method == 'PROPFIND' && r.url.path == '/dav/tm/') {
          return http.Response(
            '<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
            '<response><href>/dav/c/</href><propstat><prop>'
            '<displayname>Server Name</displayname>'
            '<resourcetype><collection/><C:calendar/></resourcetype>'
            '</prop></propstat></response></multistatus>',
            207,
          );
        }
        return server.respond(r);
      });
      final storage = MemoryStorage();
      final c = catalogWithPlanning(
        storage,
        planningSeed: FakeSource(sample),
        davBase: Uri.parse('https://fake.test/dav/'),
        httpClient: client,
      );
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await s.load();
      // The Planning space was connected to the collection by hand.
      await s.connect('c/', 'tm', 'pw');
      expect(storage.read('davdart.server.v1'), contains('"password":"pw"'));
      await s.signIn('tm', 'pw');
      // No duplicate: the hand-connected space is the account space now.
      expect(s.spaces, hasLength(1));
      expect(s.spaces.single.id, 'planning');
      expect(s.spaces.single.onServer, isTrue);
      expect(s.spaces.single.name, 'Server Name');
      expect(storage.read('davdart.server.v1'), isNot(contains('pw')));
      expect(s.connected, isTrue);
      expect(s.notes, hasLength(3));
      // Signing out of a linked Planning forgets its sync bases too.
      await s.signOut();
      expect(storage.read('davdart.lastserver.v1'), isEmpty);
      expect(storage.read('davdart.server.v1'), isEmpty);
    });

    test(
      'folders: contain notes, scope Board and List, move, delete',
      () async {
        final storage = MemoryStorage();
        final src = SpaceNoteSource(
          Space(SpaceConfig(id: 's', name: 'S'), PersistentNoteStore(storage)),
          flags: storage,
        );
        final s = AppState(src);
        await s.load();
        await s.addFolder('Deployment', text: 'Agents: deploy on Fridays');
        final folder = s.scope!;
        expect(AppState.isFolder(folder), isTrue);
        expect(s.scopeUid, folder.uid);
        expect(s.peekUid, isNull);
        await s.addNote('Ship it', parentUid: folder.uid, status: 'todo');
        await s.addNote('Elsewhere', status: 'todo'); // selecting it leaves
        expect(s.scopeUid, isNull); // the folder, as it is outside it
        s.openFolder(folder.uid);
        expect(s.tree.roots.map((n) => n.note.summary), [
          'Deployment',
          'Elsewhere',
        ]);
        // Board and List show notes, never folders, and only inside the scope.
        expect(s.filtered.map((n) => n.summary), ['Ship it']);
        expect(s.tags, isEmpty); // kind-folder is not a user tag
        s.openFolder(null);
        expect(s.filtered.map((n) => n.summary).toSet(), {
          'Ship it',
          'Elsewhere',
        });
        // Move a note into the folder, then back to the top.
        final other = s.notes.firstWhere((n) => n.summary == 'Elsewhere');
        await s.updateNote(other.uid, setParent: true, parentUid: folder.uid);
        expect(s.tree.find(other.uid)!.parent!.note.uid, folder.uid);
        // Cannot move a folder into its own child.
        final child = s.notes.firstWhere((n) => n.summary == 'Ship it');
        await s.updateNote(folder.uid, setParent: true, parentUid: child.uid);
        expect(s.tree.find(folder.uid)!.parent, isNull);
        await s.updateNote(other.uid, setParent: true, parentUid: null);
        expect(s.tree.find(other.uid)!.parent, isNull);
        // An invalid move is dropped but the rest of the edit still saves.
        await s.updateNote(
          folder.uid,
          title: 'Deploy',
          setParent: true,
          parentUid: child.uid,
        );
        expect(s.tree.find(folder.uid)!.note.summary, 'Deploy');
        expect(s.tree.find(folder.uid)!.parent, isNull);
        // Showing a note outside the open folder leaves the folder.
        s.openFolder(folder.uid);
        s.select(other.uid);
        expect(s.scopeUid, isNull);
        // Editing tags keeps the folder marker.
        await s.updateNote(folder.uid, tags: ['infra']);
        expect(AppState.isFolder(s.tree.find(folder.uid)!.note), isTrue);
        expect(s.tags, ['infra']);
        // Deleting the open folder clears the scope; its notes move up.
        s.openFolder(folder.uid);
        await s.deleteNote(folder.uid);
        expect(s.scopeUid, isNull);
        expect(s.tree.roots.map((n) => n.note.summary).toSet(), {
          'Ship it',
          'Elsewhere',
        });
      },
    );

    test('move a folder and its notes to another space', () async {
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage);
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await s.load();
      await s.addFolder('Deploy', text: 'agents: be careful');
      final folder = s.scope!;
      await s.addNote('Ship', parentUid: folder.uid, status: 'doing');
      final ship = s.notes.firstWhere((n) => n.summary == 'Ship');
      await s.addNote('Check', parentUid: ship.uid, status: 'todo');
      await s.createSpace('Other');
      final otherId = s.currentSpaceId!;
      await s.switchSpace('planning');
      expect(s.notes, hasLength(3));
      expect(await s.moveToSpace(folder.uid, 'planning'), isNull);
      expect(await s.moveToSpace(folder.uid, otherId), 3);
      expect(s.notes, isEmpty);
      await s.switchSpace(otherId);
      expect(s.notes.map((n) => n.summary).toSet(), {
        'Deploy',
        'Ship',
        'Check',
      });
      final d = s.notes.firstWhere((n) => n.summary == 'Deploy');
      expect(AppState.isFolder(d), isTrue);
      expect(d.description, 'agents: be careful');
      expect(s.tree.roots.single.note.uid, d.uid);
      final sh = s.notes.firstWhere((n) => n.summary == 'Ship');
      expect(s.tree.find(sh.uid)!.parent!.note.uid, d.uid);
      expect(PlanItem.fromNote(sh).status, 'doing');
      expect(s.tree.find(sh.uid)!.children.single.note.summary, 'Check');
    });

    testWidgets('new folder dialog, scope bar and the sidebar tree', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final src = SpaceNoteSource(
        Space(SpaceConfig(id: 's', name: 'S'), PersistentNoteStore(storage)),
        flags: storage,
      );
      final state = AppState(src);
      await t.pumpWidget(DavdartApp(state: state));
      await t.pumpAndSettle();
      state.setSection(Section.notes);
      await t.pumpAndSettle();
      await t.tap(byAction('New folder'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('new-folder-title')), 'Planning');
      await t.enterText(
        find.byKey(const Key('new-folder-text')),
        'Keep it short',
      );
      await t.tap(find.byKey(const Key('new-folder-add')));
      await t.pumpAndSettle();
      // The folder exists and is the open scope; the main area stays Home.
      final folder = state.notes.firstWhere((n) => n.summary == 'Planning');
      expect(folder.description, 'Keep it short');
      expect(state.scopeUid, folder.uid);
      expect(find.byKey(const Key('home-page')), findsOneWidget);
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

    testWidgets('in-place edit changes the title', (t) async {
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
      await t.pump();
      await t.tap(find.byKey(const Key('edit-save-action')));
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
      final c = catalogWithPlanning(storage, planningSeed: FakeSource(sample));
      final state = AppState(
        c.sourceFor(c.current!),
        prefs: storage,
        catalog: c,
      );
      state.setSection(Section.notes);
      await t.pumpWidget(DavdartApp(state: state));
      await t.pumpAndSettle();
      expect(find.text('Planning'), findsWidgets);
      await t.tap(find.byKey(const Key('rail-spaces')));
      await t.pumpAndSettle();
      await t.tap(find.text('New Space…'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('space-name')), 'Inbox');
      await t.tap(find.byKey(const Key('space-create')));
      await t.pumpAndSettle();
      expect(find.text('Inbox'), findsWidgets);
      expect(find.byKey(const Key('home-page')), findsOneWidget);
    });

    testWidgets('space menu renames and deletes', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: FakeSource(sample));
      final state = AppState(
        c.sourceFor(c.current!),
        prefs: storage,
        catalog: c,
      );
      state.setSection(Section.notes);
      await t.pumpWidget(DavdartApp(state: state));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rail-spaces')));
      await t.pumpAndSettle();
      expect(find.text('Delete this space…'), findsOneWidget);
      await t.tap(find.text('New Space…'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('space-name')), 'Inbox');
      await t.tap(find.byKey(const Key('space-create')));
      await t.pumpAndSettle();
      // The Spaces panel stays open: no second press (it would fold it).
      await t.tap(find.text('Rename this Space…'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('space-rename-name')), 'Later');
      await t.tap(find.byKey(const Key('space-rename')));
      await t.pumpAndSettle();
      expect(state.currentSpaceName, 'Later');
      await t.tap(find.text('Delete this space…'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('space-delete')));
      await t.pumpAndSettle();
      expect(state.currentSpaceName, 'Planning');
      expect(state.spaces, hasLength(1));
    });

    test('search across spaces finds notes and opens the hit', () async {
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: FakeSource(sample));
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await s.load();
      await s.createSpace('Inbox');
      await s.addNote('Loose idea about decisions');
      final hits = await s.searchAllSpaces('DECISIONS', allSpaces: true);
      expect(hits.map((h) => h.space.name).toSet(), {'Planning', 'Inbox'});
      expect(await s.searchAllSpaces('  '), isEmpty);
      final planning = hits.firstWhere((h) => h.space.id == 'planning');
      await s.openHit(planning);
      expect(s.currentSpaceName, 'Planning');
      expect(s.peekUid, planning.note.uid);
    });

    testWidgets('rail Search lists the open Space only', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: FakeSource(sample));
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await s.load();
      await s.createSpace('Inbox');
      await s.addNote('Loose idea about decisions');
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rail-search')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('search-all-field')), 'decisions');
      await t.pumpAndSettle();
      // Only the open Space's hit: "Build decisions" is in Planning.
      expect(find.text('Loose idea about decisions'), findsWidgets);
      expect(find.textContaining('Build decisions'), findsNothing);
    });

    test('searchAllSpaces defaults to the open Space only', () async {
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: FakeSource(sample));
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await s.load();
      await s.createSpace('Inbox');
      await s.addNote('Loose idea about decisions');
      expect(s.currentSpaceName, 'Inbox');
      final here = await s.searchAllSpaces('DECISIONS');
      expect(here.map((h) => h.space.name).toSet(), {'Inbox'});
      final all = await s.searchAllSpaces('DECISIONS', allSpaces: true);
      expect(all.map((h) => h.space.name).toSet(), {'Planning', 'Inbox'});
    });

    testWidgets('search narrows the list', (t) async {
      await pump(t);
      await listTab(t);
      await t.tap(find.byKey(const Key('rail-search')));
      await t.pumpAndSettle();
      await t.enterText(find.byType(FTextField), 'loose');
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

  group('shell frame', () {
    Future<AppState> multi(WidgetTester t, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: FakeSource(sample));
      c.add('Inbox');
      final state = AppState(
        c.sourceFor(c.current!),
        prefs: storage,
        catalog: c,
      );
      state.setSection(Section.notes);
      await t.pumpWidget(DavdartApp(state: state));
      await t.pumpAndSettle();
      return state;
    }

    testWidgets('wide: rail and inset panel are shown', (t) async {
      await pump(t);
      expect(find.byKey(const Key('icon-rail')), findsOneWidget);
      expect(find.byKey(const Key('shell-panel')), findsOneWidget);
    });

    testWidgets('rail selects the section and shows the active state', (
      t,
    ) async {
      final state = await multi(t, const Size(1400, 900));
      expect(state.section, Section.notes);
      // The active item is a tab painted in the activeItem token.
      expect(
        find.descendant(
          of: find.byKey(const Key('rail-notes')),
          matching: find.byKey(const Key('rail-tab')),
        ),
        findsOneWidget,
      );
      final painter =
          t.widget<CustomPaint>(find.byKey(const Key('rail-tab'))).painter!
              as RailTabPainter;
      expect(painter.fill, Tokens.light.activeItem);
      expect(
        find.descendant(
          of: find.byKey(const Key('rail-views')),
          matching: find.byKey(const Key('rail-tab')),
        ),
        findsNothing,
      );
      await t.tap(find.byKey(const Key('rail-views')));
      await t.pumpAndSettle();
      expect(find.text('No saved views yet'), findsOneWidget);
      await t.tap(find.byKey(const Key('rail-settings')));
      await t.pumpAndSettle();
      expect(find.text('APPEARANCE'), findsOneWidget);
      await t.tap(find.byKey(const Key('rail-notes')));
      await t.pumpAndSettle();
      expect(find.text('Core slice'), findsWidgets);
    });

    testWidgets('the open section collapses the panel and reopens', (t) async {
      final state = await multi(t, const Size(1400, 900));
      final prefs = state.prefs!;
      expect(find.byType(Sidebar), findsOneWidget);
      await t.tap(find.byKey(const Key('rail-notes')));
      await t.pumpAndSettle();
      expect(state.sidebarCollapsed, isTrue);
      expect(find.byType(Sidebar), findsNothing);
      expect(AppState(FakeSource(sample), prefs: prefs).sidebarCollapsed, true);
      // The content takes the freed width.
      expect(
        t.getSize(find.byType(TopBar)).width,
        t.getSize(find.byKey(const Key('shell-panel'))).width -
            2 * Tokens.light.borders.hairline,
      );
      // Another icon while collapsed reopens that section.
      await t.tap(find.byKey(const Key('rail-views')));
      await t.pumpAndSettle();
      expect(state.sidebarCollapsed, isFalse);
      expect(state.section, Section.views);
      expect(find.byType(Sidebar), findsOneWidget);
      // The same icon again collapses; pressing it once more reopens it.
      await t.tap(find.byKey(const Key('rail-views')));
      await t.pumpAndSettle();
      expect(find.byType(Sidebar), findsNothing);
      await t.tap(find.byKey(const Key('rail-views')));
      await t.pumpAndSettle();
      expect(state.section, Section.views);
      expect(find.byType(Sidebar), findsOneWidget);
      expect(
        AppState(FakeSource(sample), prefs: prefs).sidebarCollapsed,
        false,
      );
    });

    testWidgets('collapsed: the active icon is a plain highlight', (t) async {
      final state = await multi(t, const Size(1400, 900));
      await t.tap(find.byKey(const Key('rail-notes')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rail-tab')), findsNothing);
      final box =
          t
                  .widget<Container>(
                    find.descendant(
                      of: find.byKey(const Key('rail-notes')),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(box.color, Tokens.light.activeItem);
      expect(state.section, Section.notes);
    });

    testWidgets('the narrow side menu ignores the collapsed state', (t) async {
      final state = await multi(t, const Size(500, 900));
      state.setSidebarCollapsed(true);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('menu')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('side-header')), findsOneWidget);
    });

    testWidgets('dragging the edge resizes within limits and persists', (
      t,
    ) async {
      final state = await multi(t, const Size(1400, 900));
      final z = Tokens.light.sizes;
      double width() => t.getSize(find.byType(DockedSidebar)).width;
      final handle = find.byKey(const Key('sidebar-handle'));
      expect(width(), z.sidebar);
      await t.drag(handle, const Offset(100, 0));
      await t.pumpAndSettle();
      expect(width(), z.sidebar + 100);
      expect(
        AppState(FakeSource(sample), prefs: state.prefs).sidebarWidth,
        z.sidebar + 100,
      );
      await t.drag(handle, const Offset(-900, 0));
      await t.pumpAndSettle();
      expect(width(), z.sidebarMin);
      await t.drag(handle, const Offset(900, 0));
      await t.pumpAndSettle();
      expect(width(), z.sidebarMax);
      // Double-click restores the default and forgets the saved width.
      await t.tap(handle);
      await t.pump(kDoubleTapMinTime);
      await t.tap(handle);
      await t.pumpAndSettle();
      expect(width(), z.sidebar);
      expect(
        AppState(FakeSource(sample), prefs: state.prefs).sidebarWidth,
        isNull,
      );
    });

    testWidgets('a saved width outside the limits is clamped', (t) async {
      final storage = MemoryStorage();
      storage.write('davdart.sidebar.width.v1', '9999');
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        DavdartApp(state: AppState(FakeSource(sample), prefs: storage)),
      );
      await t.pumpAndSettle();
      expect(
        t.getSize(find.byType(DockedSidebar)).width,
        Tokens.light.sizes.sidebarMax,
      );
    });

    testWidgets('the active tab sits flush against the panel', (t) async {
      await multi(t, const Size(1400, 900));
      final tab = find.byKey(const Key('rail-tab'));
      final p = t.widget<CustomPaint>(tab).painter! as RailTabPainter;
      final box = t.getRect(tab);
      final panel = t.getRect(find.byKey(const Key('shell-panel')));
      final body = p.body(box.size).shift(box.topLeft);
      // Its right edge ends at the panel's inner edge (over the border) and
      // it is as tall as the item, so the panel border is covered there.
      expect(body.right, panel.left + Tokens.light.borders.hairline);
      expect(body.top, box.top);
      expect(body.height, Tokens.light.sizes.railItem);
      expect(p.fill, Tokens.light.panel);
      expect(p.radius, Tokens.light.radii.tab);
      // The tab spans the rail margin: item right + margin == panel left.
      expect(box.right + p.margin, panel.left);
    });

    testWidgets('rail tooltips open to the right, centred on the icon', (
      t,
    ) async {
      await multi(t, const Size(1400, 900));
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(t.getCenter(find.byKey(const Key('rail-settings'))));
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      final tip = find.text('Settings');
      expect(tip, findsOneWidget);
      final icon = t.getRect(find.byKey(const Key('rail-settings')));
      final text = t.getRect(tip);
      expect(text.left, greaterThan(icon.right));
      expect(text.center.dy, closeTo(icon.center.dy, 1));
      // Colours come from the tooltip tokens.
      final tk = Tokens.light;
      expect(DefaultTextStyle.of(t.element(tip)).style.color, tk.tooltipText);
      final style = FTheme.of(t.element(tip)).tooltipStyle;
      expect((style.decoration as ShapeDecoration).color, tk.tooltipBackground);
    });

    test('tooltip colours are inverted per theme and fed from tokens', () {
      for (final b in Brightness.values) {
        final tk = b == Brightness.dark ? Tokens.dark : Tokens.light;
        final style = buildTheme(b, touch: false).tooltipStyle;
        expect(
          (style.decoration as ShapeDecoration).color,
          tk.tooltipBackground,
        );
        expect(style.textStyle.color, tk.tooltipText);
      }
      expect(Tokens.light.tooltipBackground, isNot(Tokens.light.panel));
      expect(Tokens.dark.tooltipBackground, isNot(Tokens.dark.panel));
      expect(
        Tokens.light.tooltipBackground.computeLuminance(),
        lessThan(Tokens.light.panel.computeLuminance()),
      );
      expect(
        Tokens.dark.tooltipBackground.computeLuminance(),
        greaterThan(Tokens.dark.panel.computeLuminance()),
      );
    });

    testWidgets('the section persists in prefs', (t) async {
      final state = await multi(t, const Size(1400, 900));
      state.setSection(Section.views);
      final again = AppState(FakeSource(sample), prefs: state.prefs);
      expect(again.section, Section.views);
    });

    testWidgets('the Spaces panel lists the current Space first', (t) async {
      final state = await multi(t, const Size(1400, 900));
      state.setSection(Section.views);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rail-spaces')));
      await t.pumpAndSettle();
      expect(state.section, Section.spaces);
      expect(find.text('On this device only'), findsNWidgets(2));
      expect(find.text('New Space…'), findsOneWidget);
      expect(find.text('Rename this Space…'), findsOneWidget);
      final planning = t.getTopLeft(find.byKey(const Key('space-planning')));
      final inbox = t.getTopLeft(
        find.byKey(Key('space-${state.spaces.last.id}')),
      );
      expect(planning.dy, lessThan(inbox.dy)); // current first
      expect(
        find.descendant(
          of: find.byKey(const Key('space-planning')),
          matching: find.byIcon(FLucideIcons.check),
        ),
        findsOneWidget,
      );
    });

    testWidgets('picking a Space switches and shows Notes', (t) async {
      final state = await multi(t, const Size(1400, 900));
      state.setSection(Section.settings);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rail-spaces')));
      await t.pumpAndSettle();
      final inboxId = state.spaces.firstWhere((s) => s.name == 'Inbox').id;
      await t.tap(find.byKey(Key('space-$inboxId')));
      await t.pumpAndSettle();
      expect(state.currentSpaceName, 'Inbox');
      expect(state.section, Section.notes);
      expect(find.text('New Space…'), findsNothing); // popup closed
      await t.tap(find.byKey(const Key('rail-spaces')));
      await t.pumpAndSettle();
      final inbox = t.getTopLeft(find.byKey(Key('space-$inboxId')));
      final planning = t.getTopLeft(find.byKey(const Key('space-planning')));
      expect(inbox.dy, lessThan(planning.dy)); // Inbox is now first
    });

    testWidgets(
      'rail order: logo, Home, Notes, Tasks, Calendar, then the tools',
      (t) async {
        await pump(t);
        expect(find.byKey(const Key('logo-slot')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('logo-slot')),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'davdart',
            ),
          ),
          findsOneWidget,
        );
        // The mark is as wide as the rail icon glyphs, on the same centre line.
        final tk = tokensOf(t.element(find.byKey(const Key('icon-rail'))));
        final mark = find.byKey(const Key('logo-mark'));
        expect(t.getSize(mark).width, tk.icons.rail);
        final glyph = find.descendant(
          of: find.byKey(const Key('rail-notes')),
          matching: find.byType(Icon),
        );
        expect(t.getSize(glyph).width, tk.icons.rail);
        expect(
          (t.getCenter(mark).dx - t.getCenter(glyph).dx).abs(),
          lessThan(1),
        );
        final keys = [
          'logo-slot',
          'rail-home',
          'rail-notes',
          'rail-tasks',
          'rail-events',
          'rail-search',
          'rail-views',
          'rail-spaces',
          'rail-settings',
        ];
        final ys = [for (final k in keys) t.getTopLeft(find.byKey(Key(k))).dy];
        expect(ys, [...ys]..sort());
        expect(
          find.byKey(const Key('rail-account')),
          findsNothing,
        ); // can't sign in
        // The logo does nothing when tapped.
        await t.tap(find.byKey(const Key('logo-slot')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('rail-spaces')), findsOneWidget);
        expect(find.text('New Space…'), findsNothing);
      },
    );

    test('a saved picker selection falls back to a list', () {
      // Spaces and Projects lead the rail but are not landing pages.
      for (final saved in ['spaces', 'projects']) {
        final storage = MemoryStorage();
        storage.write('davdart.section.v1', saved);
        expect(
          AppState(FakeSource(sample), prefs: storage).section,
          Section.notes,
          reason: saved,
        );
      }
      // A list section still restores as itself.
      final storage = MemoryStorage();
      storage.write('davdart.section.v1', 'tasks');
      expect(
        AppState(FakeSource(sample), prefs: storage).section,
        Section.tasks,
      );
    });

    testWidgets('the Search section lists hits across Spaces', (t) async {
      final state = await multi(t, const Size(1400, 900));
      await t.tap(find.byKey(const Key('rail-search')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('search-all-field')), 'decisions');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('hit-a')), findsOneWidget);
      await t.tap(find.byKey(const Key('hit-a')));
      await t.pumpAndSettle();
      expect(state.peekUid, 'a');
    });

    testWidgets('Account and Settings sections show server items', (t) async {
      await pump(t);
      await t.tap(find.byKey(const Key('rail-settings')));
      await t.pumpAndSettle();
      expect(find.text('ABOUT'), findsOneWidget);
    });

    testWidgets('the panel and rail take their colours from tokens', (t) async {
      await pump(t);
      final panel = t.widget<Container>(find.byKey(const Key('shell-panel')));
      expect((panel.decoration as BoxDecoration).color, Tokens.light.panel);
      expect(Tokens.light.frame, isNot(Tokens.light.panel));
      expect(Tokens.dark.frame, isNot(Tokens.dark.panel));
    });

    testWidgets('narrow: no rail, menu button and bottom bar instead', (
      t,
    ) async {
      await pump(t, size: const Size(420, 800));
      expect(find.byKey(const Key('icon-rail')), findsNothing);
      expect(find.byKey(const Key('shell-panel')), findsNothing);
      expect(find.byKey(const Key('space-chip')), findsOneWidget);
      expect(find.byKey(const Key('menu')), findsOneWidget);
      expect(find.byKey(const Key('mobile-bar')), findsOneWidget);
    });
  });

  group('narrow layout', () {
    testWidgets('side menu, full-screen items, Back', (t) async {
      await pump(t, size: const Size(420, 800));
      await t.tap(find.byKey(const Key('menu')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('side-menu')), findsOneWidget);
      await t.tap(find.text('Core slice').last);
      await t.pumpAndSettle();
      // The menu closed and the note fills the screen.
      expect(find.byKey(const Key('side-menu')), findsNothing);
      expect(find.text('Body text'), findsOneWidget);
      expect(find.text('BACKLOG'), findsNothing);
      // No arrow in the item header on narrow: the bottom bar's Back.
      expect(byAction('Close'), findsNothing);
      await t.tap(find.byKey(const Key('bar-back')));
      await t.pumpAndSettle();
      expect(find.text('Body text'), findsNothing);
    });
  });

  group('narrow sections', () {
    testWidgets('the side menu reaches the other sections', (t) async {
      final sem = t.ensureSemantics();
      await pump(t, size: const Size(420, 800));
      await t.tap(find.byKey(const Key('space-chip')));
      await t.pumpAndSettle();
      // The picker is the Projects panel, the open Space its first row; with
      // one fixed source there is no other Space to list.
      expect(find.byKey(const Key('projects-all')), findsOneWidget);
      await t.tap(find.byKey(const Key('menu')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('menu')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rail-views')));
      await t.pumpAndSettle();
      expect(find.text('No saved views yet'), findsOneWidget);
      await t.tap(find.byKey(const Key('rail-notes')));
      await t.pumpAndSettle();
      expect(find.text('Core slice'), findsWidgets);
      sem.dispose();
    });
  });

  group('sidebar fixes', () {
    testWidgets('tags drawer chips activate by keyboard', (t) async {
      final sem = t.ensureSemantics();
      await pump(t, size: const Size(1400, 420));
      expect(t.takeException(), isNull);
      final tag = find.byKey(const Key('tag-planning'));
      // Tags start collapsed in the bottom drawer: open it first.
      final head = find.textContaining('Tags (');
      await t.tap(head);
      await t.pumpAndSettle();
      expect(tag, findsOneWidget);
      final node = t.getSemantics(tag);
      expect(node.label, contains('Tag planning'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
      await t.tap(tag);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rail-views')));
      await t.pumpAndSettle();
      expect(find.text('Save this view'), findsOneWidget);
      sem.dispose();
    });

    testWidgets('chevron toggles and is a labelled button', (t) async {
      final sem = t.ensureSemantics();
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      // The tree view: the list is the Notes panel's default now.
      final storage = MemoryStorage();
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      final s = AppState(
        SpaceNoteSource(
          space,
          seed: FakeSource([
            Note(
              uid: 'f',
              summary: 'Plans',
              categories: const [AppState.folderTag],
            ),
            Note(uid: 'n', summary: 'In the folder', parentUid: 'f'),
          ]),
        ),
        prefs: storage,
      );
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('notes-view-tree')));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Collapse'), findsWidgets);
      await t.tap(find.bySemanticsLabel('Collapse').first);
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Expand'), findsWidgets);
      await t.tap(find.bySemanticsLabel('Expand').first);
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Collapse'), findsWidgets);
      expect(s.notesView, NotesView.tree);
      sem.dispose();
    });

    testWidgets('the tab page gives way to the dock when the window grows', (
      t,
    ) async {
      await pump(t, size: const Size(420, 800));
      await t.tap(find.byKey(const Key('menu')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('side-menu')), findsOneWidget);
      t.view.physicalSize = const Size(1400, 900);
      await t.pumpAndSettle();
      expect(find.byType(Sidebar), findsOneWidget); // docked only
      expect(find.byKey(const Key('mobile-bar')), findsNothing);
      expect(find.byKey(const Key('side-menu')), findsNothing);
    });
  });

  testWidgets('a 320px phone does not overflow', (t) async {
    await pump(t, size: const Size(320, 640));
    expect(t.takeException(), isNull);
    await listTab(t);
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
