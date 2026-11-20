import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/note_draft.dart';
import 'package:davdart_app/state/note_drag.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/board_view.dart';
import 'package:davdart_app/ui/list_view.dart';
import 'package:davdart_app/ui/note_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha', description: 'Alpha body'),
    Note(uid: 'b', summary: 'Beta', description: 'Beta body'),
    Note(uid: 'c', summary: 'Gamma', description: 'Gamma body'),
  ];
}

Future<AppState> _pump(
  WidgetTester t, {
  MemoryStorage? prefs,
  Size size = const Size(1500, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s = AppState(
    SpaceNoteSource(space, seed: _Seed()),
    prefs: prefs ?? MemoryStorage(),
  );
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

Finder _k(String k) => find.byKey(Key(k));
Future<void> _later(WidgetTester t) =>
    t.runAsync(() => Future.delayed(AppState.doubleClickWindow * 2));

void main() {
  group('Open notes in setting', () {
    test('defaults to peek and persists', () {
      final p = MemoryStorage();
      final s = AppState(_Seed2(), prefs: p);
      expect(s.openMode, OpenMode.peek);
      s.setOpenMode(OpenMode.main);
      expect(AppState(_Seed2(), prefs: p).openMode, OpenMode.main);
      s.setOpenMode(OpenMode.peek);
      expect(p.read('davdart.open.mode.v1'), isNull);
    });

    testWidgets('Settings offers it', (t) async {
      final s = await _pump(t);
      s.setSection(Section.settings);
      await t.pumpAndSettle();
      expect(find.text('Open notes in'), findsOneWidget);
      final radios = find.descendant(
        of: _k('open-mode'),
        matching: find.byType(FRadio),
      );
      await t.tap(radios.last);
      await t.pumpAndSettle();
      expect(s.openMode, OpenMode.main);
    });

    testWidgets('a board card click follows the setting', (t) async {
      final s = await _pump(t);
      s.setView(ViewMode.board);
      await t.pumpAndSettle();
      final card = find.descendant(
        of: find.byType(BoardView),
        matching: find.text('Alpha'),
      );
      await t.tap(card);
      await t.pumpAndSettle();
      expect(s.peekUid, 'a');
      expect(s.tabs, isEmpty);
      s.setOpenMode(OpenMode.main);
      await _later(t);
      await t.tap(
        find.descendant(
          of: find.byType(BoardView),
          matching: find.text('Beta'),
        ),
      );
      await t.pumpAndSettle();
      expect(s.activeTab, const DocTab.note('b'));
      expect(s.peekUid, 'a');
    });

    testWidgets('a list row click follows the setting', (t) async {
      final s = await _pump(t);
      s.setView(ViewMode.list);
      s.setOpenMode(OpenMode.main);
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(
          of: find.byType(NoteListView),
          matching: find.text('Gamma'),
        ),
      );
      await t.pumpAndSettle();
      expect(s.activeTab, const DocTab.note('c'));
    });

    testWidgets('a tree entry click follows the setting', (t) async {
      final s = await _pump(t);
      await t.tap(find.text('Alpha').last);
      await t.pumpAndSettle();
      expect(s.peekUid, 'a');
    });

    testWidgets('a quick second click promotes to main', (t) async {
      final s = await _pump(t);
      final row = find.descendant(
        of: find.byType(BoardView),
        matching: find.text('Alpha'),
      );
      await t.tap(row);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(row);
      await t.pumpAndSettle();
      expect(s.activeTab, const DocTab.note('a'));
      expect(s.peekUid, isNull);
    });

    testWidgets('double-clicking the peek tab promotes it', (t) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      await t.tap(_k('detail-tab'));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(_k('detail-tab'));
      await t.pumpAndSettle();
      expect(s.activeTab, const DocTab.note('a'));
    });
  });

  group('note context menu', () {
    testWidgets(
      'right-click on a card offers both opens whatever the setting',
      (t) async {
        for (final mode in OpenMode.values) {
          final s = await _pump(t, prefs: MemoryStorage());
          s.setOpenMode(mode);
          await t.pumpAndSettle();
          final card = find.descendant(
            of: find.byType(BoardView),
            matching: find.text('Beta'),
          );
          await t.tap(card, buttons: kSecondaryButton);
          await t.pumpAndSettle();
          expect(_k('menu-open-peek'), findsOneWidget);
          expect(_k('menu-open-main'), findsOneWidget);
          expect(_k('menu-edit'), findsOneWidget);
          expect(_k('menu-delete'), findsOneWidget);
          expect(_k('menu-close'), findsNothing);
          await t.tap(_k('menu-open-main'));
          await t.pumpAndSettle();
          expect(s.activeTab, const DocTab.note('b'));
          await t.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets('open in peek from the menu with Main as the setting', (
      t,
    ) async {
      final s = await _pump(t);
      s.setOpenMode(OpenMode.main);
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(
          of: find.byType(BoardView),
          matching: find.text('Alpha'),
        ),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      await t.tap(_k('menu-open-peek'));
      await t.pumpAndSettle();
      expect(s.peekUid, 'a');
      expect(s.tabs, isEmpty);
    });

    testWidgets('long-press opens it on a list row', (t) async {
      final s = await _pump(t);
      s.setView(ViewMode.list);
      await t.pumpAndSettle();
      await t.longPress(
        find.descendant(
          of: find.byType(NoteListView),
          matching: find.text('Beta'),
        ),
      );
      await t.pumpAndSettle();
      expect(_k('menu-open-peek'), findsOneWidget);
      expect(s.peekUid, isNull);
    });

    testWidgets('peek tab and main tab menus offer Close', (t) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      await t.tap(_k('detail-tab'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-close'), findsOneWidget);
      await t.tap(_k('menu-close'));
      await t.pumpAndSettle();
      expect(s.peekUid, isNull);
      s.openNoteTab('b');
      await t.pumpAndSettle();
      await t.tap(_k('tab-n:b'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_k('menu-close'));
      await t.pumpAndSettle();
      expect(s.tabs, isEmpty);
    });

    testWidgets('Delete from the menu asks, then deletes', (t) async {
      final s = await _pump(t);
      await t.tap(
        find.descendant(
          of: find.byType(BoardView),
          matching: find.text('Gamma'),
        ),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      await t.tap(_k('menu-delete'));
      await t.pumpAndSettle();
      await t.tap(_k('delete-confirm'));
      await t.pumpAndSettle();
      expect(s.tree.find('c'), isNull);
    });
  });

  group('main tab strip', () {
    test('TabList.move reorders and clamps', () {
      final l = TabList()
        ..add(const DocTab.note('a'))
        ..add(const DocTab.note('b'))
        ..add(const DocTab.note('c'));
      expect(l.move(const DocTab.note('c'), 0), isTrue);
      expect(l.tabs.map((e) => e.id), ['c', 'a', 'b']);
      expect(l.move(const DocTab.note('c'), 99), isTrue);
      expect(l.tabs.map((e) => e.id), ['a', 'b', 'c']);
      expect(l.move(const DocTab.note('c'), 2), isFalse);
      expect(l.move(const DocTab.note('z'), 0), isFalse);
    });

    testWidgets('dragging a tab reorders and persists', (t) async {
      final prefs = MemoryStorage();
      final s = await _pump(t, prefs: prefs);
      s.openNoteTab('a');
      s.openNoteTab('b');
      s.openNoteTab('c');
      await t.pumpAndSettle();
      final g = await t.startGesture(t.getCenter(_k('tab-n:c')));
      await t.pump();
      await g.moveTo(t.getCenter(_k('tab-n:a')) + const Offset(-4, 0));
      await t.pump();
      await g.moveTo(t.getCenter(_k('tab-n:a')));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(s.tabs.map((e) => e.id), ['c', 'a', 'b']);
      expect(
        (AppState(
          _Seed2(),
          prefs: prefs,
        )..moveTab(const DocTab.note('x'), 0)).tabs,
        isEmpty,
      );
      expect(prefs.data.values.any((v) => v.contains('n:c')), isTrue);
    });

    testWidgets('middle-click closes a tab', (t) async {
      final s = await _pump(t);
      s.openNoteTab('a');
      s.openNoteTab('b');
      await t.pumpAndSettle();
      await t.tap(_k('tab-n:a'), buttons: kMiddleMouseButton);
      await t.pumpAndSettle();
      expect(s.tabs, [const DocTab.note('b')]);
    });

    testWidgets('dragging the peek tab onto the strip still promotes', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      final g = await t.startGesture(t.getCenter(_k('detail-drag')));
      await t.pump();
      await g.moveTo(t.getCenter(_k('tab-home')));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(s.activeTab, const DocTab.note('a'));
    });

    test('the drag payload carries uid and source', () {
      const d = NoteDrag('a', NoteDragSource.tree);
      expect(d.uid, 'a');
      expect(d.source, NoteDragSource.tree);
    });
  });

  group('review fixes', () {
    testWidgets('Edit starts a draft on the opened note', (t) async {
      final s = await _pump(t);
      await t.tap(
        find.descendant(
          of: find.byType(BoardView),
          matching: find.text('Beta'),
        ),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      await t.tap(_k('menu-edit'));
      await t.pumpAndSettle();
      expect(s.peekUid, 'b');
      expect(s.draftFor('b'), isNotNull);
    });

    testWidgets('Edit does not start a draft when keep editing wins', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      s.startEdit('a');
      s.draftFor('a')!.titleController.text = 'Changed';
      s.leaveGuard = () async => DraftChoice.keep;
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(
          of: find.byType(BoardView),
          matching: find.text('Beta'),
        ),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      await t.tap(_k('menu-edit'));
      await t.pumpAndSettle();
      expect(s.peekUid, 'a');
      expect(s.draftFor('b'), isNull);
    });

    testWidgets('middle-click on a dirty tab asks first', (t) async {
      final s = await _pump(t);
      s.openNoteTab('a');
      s.startEdit('a');
      s.draftFor('a')!.titleController.text = 'Changed';
      var asked = 0;
      s.leaveGuard = () async {
        asked++;
        return DraftChoice.keep;
      };
      await t.pumpAndSettle();
      await t.tap(_k('tab-n:a'), buttons: kMiddleMouseButton);
      await t.pumpAndSettle();
      expect(asked, 1);
      expect(s.tabs, [const DocTab.note('a')]);
    });

    testWidgets('a search hit has a menu with both opens', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = SpaceCatalog(storage, planningSeed: _Seed());
      c.add('Inbox');
      final s = AppState(c.sourceFor(c.current), prefs: storage, catalog: c);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      await t.tap(_k('rail-search'));
      await t.pumpAndSettle();
      await t.enterText(_k('search-all-field'), 'Alpha');
      await t.pumpAndSettle();
      await t.tap(_k('hit-a'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-open-peek'), findsOneWidget);
      expect(_k('menu-open-main'), findsOneWidget);
      expect(_k('menu-delete'), findsNothing);
      await t.tap(_k('menu-open-main'));
      await t.pumpAndSettle();
      expect(s.activeTab, const DocTab.note('a'));
    });

    testWidgets('an empty peek has no menu', (t) async {
      final s = await _pump(t);
      expect(s.peekUid, isNull);
      expect(
        find.descendant(
          of: _k('detail-header'),
          matching: find.byType(NoteContextMenu),
        ),
        findsNothing,
      );
      s.select('a');
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: _k('detail-header'),
          matching: find.byType(NoteContextMenu),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a click on an entry then the peek tab is not a double', (
      t,
    ) async {
      final s = await _pump(t);
      await t.tap(
        find.descendant(
          of: find.byType(BoardView),
          matching: find.text('Alpha'),
        ),
      );
      await t.pumpAndSettle();
      expect(s.peekUid, 'a');
      await t.tap(_k('detail-tab'));
      await t.pumpAndSettle();
      expect(s.tabs, isEmpty);
    });

    testWidgets('dragging a tab rightward reorders', (t) async {
      final s = await _pump(t);
      s.openNoteTab('a');
      s.openNoteTab('b');
      s.openNoteTab('c');
      await t.pumpAndSettle();
      final g = await t.startGesture(t.getCenter(_k('tab-n:a')));
      await t.pump();
      await g.moveTo(t.getCenter(_k('tab-n:c')) + const Offset(4, 0));
      await t.pump();
      await g.moveTo(t.getCenter(_k('tab-n:c')) + const Offset(8, 0));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(s.tabs.map((e) => e.id), ['b', 'c', 'a']);
    });

    testWidgets('dragging a note tab onto a view tab reorders', (t) async {
      final s = await _pump(t);
      s.setQuery('alpha');
      await s.saveView('Alphas');
      final v = s.savedViews.single;
      s.openNoteTab('a');
      s.openNoteTab('b');
      s.applyView(v);
      await t.pumpAndSettle();
      expect(s.tabs.last, DocTab.view(v.uid));
      final g = await t.startGesture(t.getCenter(_k('tab-n:a')));
      await t.pump();
      await g.moveTo(t.getCenter(_k('tab-v:${v.uid}')) + const Offset(4, 0));
      await t.pump();
      await g.moveTo(t.getCenter(_k('tab-v:${v.uid}')) + const Offset(8, 0));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(s.tabs.map((e) => e.code), ['n:b', 'v:${v.uid}', 'n:a']);
    });
  });

  group('peek loose ends', () {
    test('focusing a main tab does not prompt about a dirty peek', () async {
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      final s = AppState(SpaceNoteSource(space, seed: _Seed2()));
      await s.load();
      var asked = 0;
      s.leaveGuard = () async {
        asked++;
        return DraftChoice.keep;
      };
      s.openNoteTab('a');
      s.select('b');
      s.startEdit('b');
      s.draftFor('b')!.titleController.text = 'Changed';
      await s.openNote('a'); // already a tab: just focus it
      expect(asked, 0);
      expect(s.peekUid, 'b');
      await s.openNote('c'); // replaces the dirty peek: asks
      expect(asked, 1);
      expect(s.peekUid, 'b');
    });

    test('moving a note to another Space does not drop its draft', () async {
      final storage = MemoryStorage();
      final c = SpaceCatalog(storage);
      final s = AppState(c.sourceFor(c.current), prefs: storage, catalog: c);
      await s.load();
      await s.addNote('Ship');
      final uid = s.notes.firstWhere((n) => n.summary == 'Ship').uid;
      await s.createSpace('Other');
      final otherId = s.currentSpaceId!;
      await s.switchSpace('planning');
      s.select(uid);
      s.startEdit(uid);
      s.draftFor(uid)!.titleController.text = 'Ship it';
      s.leaveGuard = () async => DraftChoice.keep;
      expect(await s.moveToSpace(uid, otherId), isNull);
      expect(s.draftFor(uid)?.titleController.text, 'Ship it');
      expect(s.tree.find(uid), isNotNull);
    });
  });
}

class _Seed2 implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha'),
    Note(uid: 'b', summary: 'Beta'),
    Note(uid: 'c', summary: 'Gamma'),
  ];
}
