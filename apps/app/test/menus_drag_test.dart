import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';

import 'catalog_helper.dart';

import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/note_draft.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/home_board.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
    Note(uid: 'h', summary: 'Sub', parentUid: 'f', categories: ['kind-folder']),
    Note(uid: 'g', summary: 'Ideas', categories: ['kind-folder']),
    Note(
      uid: 'a',
      summary: 'Alpha',
      parentUid: 'f',
      description: 'status: backlog\nbody',
      categories: ['status-backlog'],
    ),
    Note(
      uid: 'b',
      summary: 'Beta',
      description: 'status: doing\nbody',
      categories: ['status-doing'],
    ),
    Note(uid: 'c', summary: 'Gamma'),
  ];
}

class _Plain implements NoteSource {
  @override
  Future<List<Note>> load() async => [Note(uid: 'p', summary: 'Plain')];
}

Future<AppState> _pump(
  WidgetTester t, {
  AppState? state,
  TargetPlatform platform = TargetPlatform.linux,
}) async {
  t.view.physicalSize = const Size(1500, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s =
      state ??
      AppState(SpaceNoteSource(space, seed: _Seed()), prefs: MemoryStorage());
  // These are the tree's drags: the Notes panel's tree view.
  s.setNotesView(NotesView.tree);
  s.setSection(Section.notes); // the old Day | Board main view, not Home
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

/// The board lives on a project's Board tab now: its cards are seeded into a
/// synthetic project.
Future<AppState> _pumpBoard(WidgetTester t) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final s = await pumpHomeApp(t, notes: await _Seed().load());
  s.setNotesView(NotesView.tree);
  return s;
}

Finder _k(String k) => find.byKey(Key(k));
Finder _tree(String text) =>
    find.descendant(of: _k('drop-root'), matching: find.text(text));

/// A mouse drag from [from] to [to], through a pause so targets see it.
Future<void> _drag(WidgetTester t, Offset from, Offset to) async {
  final g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
  await t.pump();
  await g.moveTo(from + const Offset(0, 12));
  await t.pump();
  await g.moveTo(to);
  await t.pump();
  await g.moveTo(to + const Offset(1, 1));
  await t.pump();
  await g.up();
  await t.pumpAndSettle();
}

String? _parent(AppState s, String uid) => s.tree.find(uid)?.parent?.note.uid;

void main() {
  group('moveNote', () {
    late AppState s;
    setUp(() async {
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      s = AppState(SpaceNoteSource(space, seed: _Seed()));
      await s.load();
    });

    test('a stale error does not make a valid move report failure', () async {
      s.error = 'old';
      expect(await s.moveNote('b', 'f'), isTrue);
      expect(s.error, isNull);
    });

    test('reparents and moves to the top', () async {
      expect(await s.moveNote('b', 'f'), isTrue);
      expect(_parent(s, 'b'), 'f');
      expect(await s.moveNote('b', null), isTrue);
      expect(_parent(s, 'b'), isNull);
    });

    test('refuses itself, a descendant and a no-op', () async {
      expect(await s.moveNote('f', 'f'), isFalse);
      expect(await s.moveNote('f', 'h'), isFalse);
      expect(await s.moveNote('a', 'f'), isFalse); // already there
      expect(await s.moveNote('b', null), isFalse); // already top
      expect(await s.moveNote('zz', 'f'), isFalse);
      expect(_parent(s, 'f'), isNull);
    });
  });

  group('tab closing', () {
    late AppState s;
    setUp(() async {
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      s = AppState(SpaceNoteSource(space, seed: _Seed()));
      await s.load();
      for (final u in ['a', 'b', 'c']) {
        s.openNoteTab(u);
      }
    });

    test('close others keeps one and focuses it', () async {
      await s.closeOtherTabs(const DocTab.note('b'));
      expect(s.tabs, [const DocTab.note('b')]);
      expect(s.activeTab, const DocTab.note('b'));
    });

    test('close to the right keeps the left ones', () async {
      await s.closeTabsToRight(const DocTab.note('a'));
      expect(s.tabs, [const DocTab.note('a')]);
    });
  });

  group('nested menus', () {
    testWidgets('a board card opens only its own menu', (t) async {
      final s = await _pumpBoard(t);
      s.setView(ViewMode.board);
      await t.pumpAndSettle();
      final card = find.byKey(const ValueKey('nav-card-a'));
      await t.tap(card, buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-open-peek'), findsOneWidget);
      expect(_k('menu-card-new-backlog'), findsOneWidget);
      expect(_k('menu-board-new-backlog'), findsNothing);
    });

    testWidgets('a tree row opens only its own menu', (t) async {
      await _pump(t);
      await t.tap(_tree('Gamma'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-open-peek'), findsOneWidget);
      expect(_k('menu-tree-new-note'), findsNothing);
    });

    testWidgets('a tab opens only its own menu', (t) async {
      final s = await _pump(t);
      s.openNoteTab('a');
      s.openNoteTab('b');
      await t.pumpAndSettle();
      await t.tap(_k('tab-n:b'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-close'), findsOneWidget);
      expect(_k('menu-home-toggle-view'), findsNothing);
    });
  });

  group('right-click menus', () {
    testWidgets('a folder offers new inside, move and no status', (t) async {
      await _pump(t);
      await t.tap(_tree('Plans'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-new-note-inside'), findsOneWidget);
      expect(_k('menu-new-folder-inside'), findsOneWidget);
      expect(_k('menu-move-folder'), findsOneWidget);
      expect(_k('menu-copy-id'), findsOneWidget);
      expect(_k('menu-status'), findsNothing);
    });

    testWidgets('a note sets its status from a submenu', (t) async {
      final s = await _pump(t);
      await t.tap(_tree('Gamma'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-status'), findsOneWidget);
      await t.tap(_k('menu-status'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-status-done'));
      await t.pumpAndSettle();
      expect(PlanItem.fromNote(s.tree.find('c')!.note).status, 'done');
    });

    testWidgets('move to folder moves the note', (t) async {
      final s = await _pump(t);
      await t.tap(_tree('Gamma'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_k('menu-move-folder'));
      await t.pumpAndSettle();
      await t.tap(_k('move-folder-g'));
      await t.pumpAndSettle();
      expect(_parent(s, 'c'), 'g');
    });

    testWidgets('the empty tree area offers new note and folder', (t) async {
      await _pump(t);
      final at = t.getBottomLeft(_k('drop-root')) + const Offset(40, -40);
      await t.tapAt(at, buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-tree-new-note'), findsOneWidget);
      expect(_k('menu-tree-new-folder'), findsOneWidget);
    });

    testWidgets('a main tab offers close others and to the right', (t) async {
      final s = await _pump(t);
      s.openNoteTab('a');
      s.openNoteTab('b');
      s.openNoteTab('c');
      await t.pumpAndSettle();
      await t.tap(_k('tab-n:b'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-close-others'), findsOneWidget);
      await t.tap(_k('menu-close-right'));
      await t.pumpAndSettle();
      expect(s.tabs.map((e) => e.id), ['a', 'b']);
    });

    testWidgets('the home tab has no Board/List toggle', (t) async {
      final s = await _pump(t);
      expect(s.view, ViewMode.board);
      await t.tap(_k('tab-home'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-home-toggle-view'), findsNothing);
    });

    testWidgets('Home stays a board whatever the persisted mode', (t) async {
      final s = await _pumpBoard(t);
      s.setView(ViewMode.list);
      await t.pumpAndSettle();
      expect(find.byType(HomeBoard), findsOneWidget);
      expect(_k('board-drop-notes'), findsNothing);
      // No Board/List view toggle up there whatever mode is persisted: the
      // one "Board" in the top bar is the project's own tab pill (the pill
      // moved into the page header row).
      final top = find.byKey(const Key('top-bar'));
      expect(
        find.descendant(of: top, matching: find.text('List')),
        findsNothing,
      );
      expect(
        find.descendant(of: top, matching: _k('proj-tab-board')),
        findsOneWidget,
      );
      expect(s.columns().map((c) => c.$1), contains('notes'));
      expect(
        s.columns(includeNoStatus: false).map((c) => c.$1),
        isNot(contains('notes')),
      );
    });

    testWidgets('a saved board view keeps the no-status column', (t) async {
      final s = await _pump(t);
      s.setView(ViewMode.board);
      await t.runAsync(() => s.saveView('Board'));
      s.applyView(s.savedViews.single);
      await t.pumpAndSettle();
      expect(_k('board-drop-notes'), findsOneWidget);
    });

    testWidgets('Home with only plain notes shows the empty state', (t) async {
      t.view.physicalSize = const Size(1500, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      await t.pumpWidget(
        DavdartApp(state: AppState(SpaceNoteSource(space, seed: _Plain()))),
      );
      await t.pumpAndSettle();
      // The Home tab is the dashboard now; the board lives in a project.
      expect(find.byKey(const Key('home-page')), findsOneWidget);
      expect(find.text('No notes'), findsNothing);
    });

    testWidgets('a board column adds a note in its status', (t) async {
      final s = await _pumpBoard(t);
      s.setView(ViewMode.board);
      await t.pumpAndSettle();
      await t.tap(find.text('DOING'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-board-new-doing'), findsOneWidget);
    });

    testWidgets('a saved view has a menu', (t) async {
      final s = await _pump(t);
      s.setQuery('Alpha');
      await s.saveView('Mine');
      s.setSection(Section.views);
      await t.pumpAndSettle();
      await t.tap(find.text('Mine'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-view-rename-Mine'), findsOneWidget);
      await t.tap(_k('menu-view-delete-Mine'));
      await t.pumpAndSettle();
      expect(s.savedViews, isEmpty);
    });
  });

  group('drag to move', () {
    testWidgets('a tree entry dropped on a folder moves into it', (t) async {
      final s = await _pump(t);
      await _drag(t, t.getCenter(_tree('Gamma')), t.getCenter(_tree('Ideas')));
      expect(_parent(s, 'c'), 'g');
    });

    testWidgets('dropping on the tree area moves to the top', (t) async {
      final s = await _pump(t);
      final blank = t.getBottomLeft(_k('drop-root')) + const Offset(40, -40);
      await _drag(t, t.getCenter(_tree('Alpha')), blank);
      expect(_parent(s, 'a'), isNull);
    });

    testWidgets('a folder cannot be dropped into its own descendant', (
      t,
    ) async {
      final s = await _pump(t);
      await _drag(t, t.getCenter(_tree('Plans')), t.getCenter(_tree('Sub')));
      expect(_parent(s, 'f'), isNull);
      expect(_parent(s, 'h'), 'f');
    });

    testWidgets('a plain click still opens and does not move', (t) async {
      final s = await _pump(t);
      await t.tap(_tree('Gamma'));
      await t.pumpAndSettle();
      expect(s.peekUid, 'c');
      expect(_parent(s, 'c'), isNull);
    });

    testWidgets('on a phone platform a drag does not start a note drag', (
      t,
    ) async {
      final s = await _pump(t, platform: TargetPlatform.android);
      final from = t.getCenter(_tree('Gamma'));
      final g = await t.startGesture(from);
      await g.moveTo(t.getCenter(_tree('Ideas')));
      await g.up();
      await t.pumpAndSettle();
      expect(_parent(s, 'c'), isNull);
    });

    testWidgets('a board card dropped on a column sets its status', (t) async {
      final s = await _pumpBoard(t);
      s.setView(ViewMode.board);
      await t.pumpAndSettle();
      final card = find.byKey(const ValueKey('nav-card-a'));
      final target = t.getRect(_k('board-drop-doing'));
      await _drag(
        t,
        t.getCenter(card),
        Offset(target.center.dx, target.bottom - 20),
      );
      expect(PlanItem.fromNote(s.tree.find('a')!.note).status, 'doing');
    });

    testWidgets('a card clears its status from the menu', (t) async {
      final s = await _pumpBoard(t);
      await t.tap(
        find.descendant(
          of: _k('board-drop-backlog'),
          matching: find.text('Alpha'),
        ),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      await t.tap(_k('menu-status'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-status-none'));
      await t.pumpAndSettle();
      expect(PlanItem.fromNote(s.tree.find('a')!.note).status, isNull);
      expect(
        s.tree.find('a')!.note.categories,
        isNot(contains('status-backlog')),
      );
    });

    testWidgets('the peek tab still promotes onto the strip', (t) async {
      final s = await _pump(t);
      s.select('c');
      await t.pumpAndSettle();
      await _drag(
        t,
        t.getCenter(_k('detail-drag')),
        t.getCenter(_k('tab-home')),
      );
      expect(s.activeTab, const DocTab.note('c'));
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('a note dropped on a Space in the popup moves there', (
      t,
    ) async {
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: _Seed());
      final other = c.add('Other');
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await _pump(t, state: s);
      final g = await t.startGesture(
        t.getCenter(_tree('Gamma')),
        kind: PointerDeviceKind.mouse,
      );
      await t.pump();
      await g.moveTo(t.getCenter(_tree('Gamma')) + const Offset(0, 12));
      await t.pump();
      await g.moveTo(t.getCenter(_k('rail-spaces')));
      await t.pump();
      await g.moveTo(t.getCenter(_k('rail-spaces')) + const Offset(1, 1));
      await t.pumpAndSettle();
      expect(_k('space-drop-${other.id}'), findsOneWidget);
      await g.moveTo(t.getCenter(_k('space-drop-${other.id}')));
      await t.pump();
      await g.moveTo(
        t.getCenter(_k('space-drop-${other.id}')) + const Offset(1, 1),
      );
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(s.tree.find('c'), isNull);
    });

    testWidgets('a folder dropped on a Space asks first; cancel keeps it', (
      t,
    ) async {
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: _Seed());
      final other = c.add('Other');
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await _pump(t, state: s);
      final from = t.getCenter(_tree('Plans'));
      final g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
      await t.pump();
      await g.moveTo(from + const Offset(0, 12));
      await t.pump();
      await g.moveTo(t.getCenter(_k('rail-spaces')));
      await t.pump();
      await g.moveTo(t.getCenter(_k('rail-spaces')) + const Offset(1, 1));
      await t.pumpAndSettle();
      final target = t.getCenter(_k('space-drop-${other.id}'));
      await g.moveTo(target);
      await t.pump();
      await g.moveTo(target + const Offset(1, 1));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(find.text('Move folder?'), findsOneWidget);
      expect(find.textContaining('"Other"'), findsOneWidget);
      expect(s.tree.find('f'), isNotNull);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(s.tree.find('f'), isNotNull);
    });
  });

  group('renaming and view tab menus', () {
    testWidgets('renaming a non-current Space does not switch to it', (
      t,
    ) async {
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: _Seed());
      final other = c.add('Other');
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await _pump(t, state: s);
      final before = c.current;
      await t.tap(_k('rail-spaces'));
      await t.pumpAndSettle();
      await t.tap(_k('space-${other.id}'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_k('menu-space-rename-${other.id}'));
      await t.pumpAndSettle();
      await t.enterText(_k('space-rename-name'), 'Renamed');
      await t.tap(_k('space-rename'));
      await t.pumpAndSettle();
      expect(c.current, before);
      expect(c.spaces.firstWhere((x) => x.id == other.id).name, 'Renamed');
    });

    testWidgets('a view tab menu opens, renames and removes the view', (
      t,
    ) async {
      final s = await _pump(t);
      s.setQuery('Alpha');
      await t.runAsync(() => s.saveView('Vw'));
      s.applyView(s.savedViews.single);
      await t.pumpAndSettle();
      await t.tap(find.text('Vw').last, buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-tab-open-view'), findsOneWidget);
      expect(_k('menu-tab-rename-view'), findsOneWidget);
      await t.tap(_k('menu-tab-delete-view'));
      await t.pumpAndSettle();
      expect(s.savedViews, isEmpty);
    });
  });

  group('closeAllTabs', () {
    test('stops when the unsaved-changes prompt cancels a close', () async {
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      final s = AppState(SpaceNoteSource(space, seed: _Seed()));
      await s.load();
      s.openNoteTab('a');
      s.openNoteTab('b');
      s.openNoteTab('c');
      s.startEdit('b');
      s.draftFor('b')!.titleController.text = 'Changed';
      s.leaveGuard = () async => DraftChoice.keep;
      await s.closeAllTabs();
      expect(s.tabs, [const DocTab.note('b'), const DocTab.note('c')]);
      s.leaveGuard = () async => DraftChoice.discard;
      await s.closeAllTabs();
      expect(s.tabs, isEmpty);
    });

    for (final mode in ['others', 'right']) {
      test('close $mode stops when the prompt cancels', () async {
        final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
        final s = AppState(SpaceNoteSource(space, seed: _Seed()));
        await s.load();
        s.openNoteTab('a');
        s.openNoteTab('b');
        s.openNoteTab('c');
        s.startEdit('b');
        s.draftFor('b')!.titleController.text = 'Changed';
        s.leaveGuard = () async => DraftChoice.keep;
        const a = DocTab.note('a');
        if (mode == 'others') {
          await s.closeOtherTabs(a);
        } else {
          await s.closeTabsToRight(a);
        }
        // 'b' stays (cancelled); 'c' is not closed after the cancel.
        expect(s.tabs, [a, const DocTab.note('b'), const DocTab.note('c')]);
        s.leaveGuard = () async => DraftChoice.discard;
        if (mode == 'others') {
          await s.closeOtherTabs(a);
        } else {
          await s.closeTabsToRight(a);
        }
        expect(s.tabs, [a]);
      });
    }
  });
}
