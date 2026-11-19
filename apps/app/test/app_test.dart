import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/persistent_store.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/list_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class FakeSource implements NoteSource {
  FakeSource(this.notes);
  final List<Note> notes;
  @override
  Future<List<Note>> load() async => notes;
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
