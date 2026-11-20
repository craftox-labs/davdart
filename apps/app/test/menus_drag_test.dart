import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
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

    testWidgets('the home tab toggles Board and List', (t) async {
      final s = await _pump(t);
      final before = s.view;
      await t.tap(_k('tab-home'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_k('menu-home-toggle-view'));
      await t.pumpAndSettle();
      expect(s.view, isNot(before));
    });

    testWidgets('a board column adds a note in its status', (t) async {
      final s = await _pump(t);
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
      final s = await _pump(t);
      s.setView(ViewMode.board);
      await t.pumpAndSettle();
      final card = find.descendant(
        of: _k('board-drop-backlog'),
        matching: find.text('Alpha'),
      );
      await _drag(t, t.getCenter(card), t.getCenter(_k('board-drop-doing')));
      expect(PlanItem.fromNote(s.tree.find('a')!.note).status, 'doing');
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
    });

    testWidgets('a note dropped on a Space in the popup moves there', (
      t,
    ) async {
      final storage = MemoryStorage();
      final c = SpaceCatalog(storage, planningSeed: _Seed());
      final other = c.add('Other');
      final s = AppState(c.sourceFor(c.current), prefs: storage, catalog: c);
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
  });
}
