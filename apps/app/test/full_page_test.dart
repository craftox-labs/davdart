import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';

import 'catalog_helper.dart';

import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
    Note(
      uid: 'a',
      summary: 'Alpha',
      parentUid: 'f',
      description: 'status: todo\n\nAlpha body',
      categories: ['status-todo'],
    ),
    Note(uid: 'b', summary: 'Beta', description: 'Beta body'),
  ];
}

late Space space;

Future<AppState> _pump(
  WidgetTester t, {
  Size size = const Size(1500, 900),
  bool select = true,
  LayoutSide? side,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final state = AppState(
    SpaceNoteSource(space, seed: _Seed()),
    prefs: MemoryStorage(),
  );
  if (side != null) state.setLayoutSide(side);
  await t.pumpWidget(DavdartApp(state: state));
  await t.pumpAndSettle();
  if (select) {
    state.select('a');
    await t.pumpAndSettle();
  }
  return state;
}

Finder _k(String k) => find.byKey(Key(k));
Future<void> _settle(WidgetTester t) => t.pumpAndSettle();

Future<void> _type(WidgetTester t, String key, String text) async {
  await t.enterText(_k(key), text);
  await t.pump();
}

Future<List<String>> _titles() async => [
  for (final n in await space.notes()) n.summary,
];

void main() {
  setUp(() => AppState.debugDefaultFocus = HomeFocus.board);
  tearDown(() => AppState.debugDefaultFocus = HomeFocus.day);
  group('peek and main area', () {
    testWidgets('Promote moves the peek note to a main tab, peek empties', (
      t,
    ) async {
      final s = await _pump(t);
      expect(_k('detail-pane'), findsOneWidget);
      expect(_k('pane-size'), findsNothing);
      await t.tap(_k('peek-promote'));
      await _settle(t);
      expect(s.peekUid, isNull);
      expect(s.tabs, [const DocTab.note('a')]);
      expect(s.activeTab, const DocTab.note('a'));
      expect(_k('detail-pane'), findsNothing);
      expect(_k('main-note'), findsOneWidget);
      expect(find.text('TODO'), findsNothing);
      expect(_k('tab-strip'), findsOneWidget);
    });

    testWidgets('a main tab shows in the main area, not the peek', (t) async {
      final s = await _pump(t);
      s.openNoteTab('b');
      await _settle(t);
      expect(s.activeTab, const DocTab.note('b'));
      expect(s.peekUid, 'a');
      expect(_k('main-note'), findsOneWidget);
      expect(
        find.descendant(of: _k('main-note'), matching: find.text('Beta')),
        findsWidgets,
      );
      expect(
        find.descendant(of: _k('peek-view'), matching: find.text('Alpha')),
        findsWidgets,
      );
      // Tapping the tab again, or home and back, never moves it to the peek.
      await t.tap(_k('tab-home'));
      await _settle(t);
      await t.tap(_k('tab-n:b'));
      await _settle(t);
      expect(s.peekUid, 'a');
      expect(s.activeTab, const DocTab.note('b'));
    });

    testWidgets('a note open in a tab is focused there, not peeked', (t) async {
      final s = await _pump(t);
      s.openNoteTab('b');
      await t.tap(_k('tab-home'));
      await _settle(t);
      s.select('b');
      await _settle(t);
      expect(s.peekUid, 'a');
      expect(s.activeTab, const DocTab.note('b'));
    });

    testWidgets('opening a tab for the peeked note closes the peek', (t) async {
      final s = await _pump(t);
      s.openNoteTab('a');
      await _settle(t);
      expect(s.peekUid, isNull);
      expect(_k('detail-pane'), findsNothing);
    });

    testWidgets('Collapse keeps the note; Expand brings it back', (t) async {
      final s = await _pump(t);
      final open = t.getRect(_k('detail-pane'));
      await t.tap(_k('peek-collapse'));
      await _settle(t);
      expect(s.peekCollapsed, isTrue);
      expect(s.peekUid, 'a');
      expect(_k('detail-pane'), findsNothing);
      expect(_k('peek-expand'), findsOneWidget);
      await t.tap(_k('peek-expand'));
      await _settle(t);
      expect(s.peekCollapsed, isFalse);
      expect(t.getRect(_k('detail-pane')), open);
      expect(_k('peek-expand'), findsNothing);
    });

    testWidgets('a new peek while collapsed expands it', (t) async {
      final s = await _pump(t);
      s.setPeekCollapsed(true);
      await _settle(t);
      s.select('b');
      await _settle(t);
      expect(s.peekCollapsed, isFalse);
      expect(_k('detail-pane'), findsOneWidget);
    });

    testWidgets('dragging the peek tab onto the strip promotes it', (t) async {
      final s = await _pump(t);
      final g = await t.startGesture(t.getCenter(_k('detail-drag')));
      await t.pump();
      await g.moveTo(t.getCenter(_k('tab-home')));
      await t.pump();
      await g.up();
      await _settle(t);
      expect(s.peekUid, isNull);
      expect(s.activeTab, const DocTab.note('a'));
    });

    testWidgets('dragging the peek tab onto the main area promotes it', (
      t,
    ) async {
      final s = await _pump(t);
      final g = await t.startGesture(t.getCenter(_k('detail-drag')));
      await t.pump();
      await g.moveTo(t.getCenter(find.text('TODO').first));
      await t.pump();
      await g.up();
      await _settle(t);
      expect(s.activeTab, const DocTab.note('a'));
    });

    testWidgets('a collapsed peek shows again below the wide layout', (
      t,
    ) async {
      final s = await _pump(t);
      s.setPeekCollapsed(true);
      t.view.physicalSize = const Size(500, 900);
      await _settle(t);
      expect(find.text('Alpha body'), findsOneWidget);
    });

    testWidgets('a new folder leaves the peek and its draft alone', (t) async {
      final s = await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Changed');
      await s.addFolder('F');
      await _settle(t);
      expect(_k('leave-discard'), findsNothing);
      expect(s.peekUid, 'a');
      expect(s.dirtyFor('a'), isTrue);
    });

    testWidgets('switching to a saved-view tab and back keeps the peek', (
      t,
    ) async {
      final s = await _pump(t);
      s.setQuery('alpha');
      await s.saveView('Alphas');
      final v = s.savedViews.single;
      s.applyView(v);
      s.openNoteTab('b');
      await _settle(t);
      expect(s.peekUid, 'a');
      await t.tap(_k('tab-v:${v.uid}'));
      await _settle(t);
      expect(s.activeTab, DocTab.view(v.uid));
      expect(s.peekUid, 'a');
      expect(_k('detail-pane'), findsOneWidget);
      await t.tap(_k('tab-n:b'));
      await _settle(t);
      await t.tap(_k('tab-home'));
      await _settle(t);
      s.openFolder(null);
      expect(s.peekUid, 'a');
    });

    testWidgets('narrow layout: no peek or Promote, a tab is a page', (
      t,
    ) async {
      final s = await _pump(t, size: const Size(500, 900));
      expect(_k('peek-promote'), findsNothing);
      s.openNoteTab('b');
      await _settle(t);
      expect(_k('main-note'), findsOneWidget);
    });

    testWidgets('mirrored layout keeps the pane; Promote and Collapse work', (
      t,
    ) async {
      final s = await _pump(t, side: LayoutSide.end);
      final pane = t.getTopLeft(_k('detail-pane'));
      expect(pane.dx, lessThan(300));
      await t.tap(_k('peek-collapse'));
      await _settle(t);
      expect(_k('peek-expand'), findsOneWidget);
      await t.tap(_k('peek-expand'));
      await _settle(t);
      expect(t.getTopLeft(_k('detail-pane')), pane);
      await t.tap(_k('peek-promote'));
      await _settle(t);
      expect(s.activeTab, const DocTab.note('a'));
    });
  });

  testWidgets('section titles stay in the same place across sections', (
    t,
  ) async {
    final s = await _pump(t, select: false);
    final ys = <Section, double>{};
    final xs = <Section, double>{};
    for (final (sec, label) in [
      (Section.notes, 'Notes'),
      (Section.views, 'Views'),
      (Section.search, 'Search'),
    ]) {
      s.setSection(sec);
      await _settle(t);
      final o = t.getTopLeft(find.text(label).first);
      ys[sec] = o.dy;
      xs[sec] = o.dx;
    }
    expect(
      ys.values.toSet().length,
      1,
      reason: 'titles at different heights: $ys',
    );
    expect(xs.values.toSet().length, 1, reason: 'titles at different x: $xs');
  });

  group('leaving a Space with unsaved edits', () {
    testWidgets('asks first; keep stays, discard switches', (t) async {
      t.view.physicalSize = const Size(1500, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: _Seed());
      final other = c.add('Other');
      final startId = c.current!;
      final s = AppState(c.sourceFor(startId), prefs: storage, catalog: c);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      s.select('a');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Changed');
      expect(s.dirty, isTrue);

      final stay = s.switchSpace(other.id);
      await _settle(t);
      expect(find.text('Unsaved changes'), findsWidgets);
      await t.tap(find.text('Keep editing'));
      await _settle(t);
      expect(await stay, isFalse);
      expect(s.currentSpaceId, startId);
      expect(s.dirty, isTrue);

      final go = s.switchSpace(other.id);
      await _settle(t);
      await t.tap(_k('leave-discard'));
      await _settle(t);
      expect(await go, isTrue);
      expect(s.currentSpaceId, other.id);
      expect(s.dirty, isFalse);
    });
  });

  group('in-place editing', () {
    testWidgets('edit, Save writes title, status, tags and text', (t) async {
      final s = await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      expect(_k('dirty-indicator'), findsNothing);
      await _type(t, 'edit-title', 'Alpha 2');
      await _type(t, 'edit-tags', 'x, y');
      await _type(t, 'edit-body', 'New body');
      expect(_k('dirty-indicator'), findsOneWidget);
      await t.tap(_k('edit-save-action'));
      await _settle(t);
      expect(s.activeDraft, isNull);
      final n = (await space.notes()).firstWhere((n) => n.uid == 'a');
      expect(n.summary, 'Alpha 2');
      expect(n.categories, containsAll(['x', 'y', 'status-todo']));
      expect(PlanItem.fromNote(n).text, 'New body');
      expect(PlanItem.fromNote(n).status, 'todo');
      // The card's snippet and the detail body both show it.
      expect(find.text('New body'), findsNWidgets(2));
    });

    testWidgets('Ctrl+S saves', (t) async {
      await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Via keys');
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyS);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _settle(t);
      expect(await _titles(), contains('Via keys'));
    });

    testWidgets('Discard drops the edit', (t) async {
      final s = await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Nope');
      await t.tap(_k('edit-cancel-action'));
      await _settle(t);
      await t.tap(find.text('Discard'));
      await _settle(t);
      expect(s.activeDraft, isNull);
      expect(await _titles(), isNot(contains('Nope')));
      expect(find.text('Alpha'), findsWidgets);
    });

    testWidgets('empty title cannot be saved', (t) async {
      await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', '  ');
      await _settle(t);
      expect(find.text('A title is required'), findsOneWidget);
      await t.tap(_k('edit-save-action'));
      await _settle(t);
      expect(await _titles(), contains('Alpha'));
    });

    testWidgets('dirty guard: keep editing, discard, save', (t) async {
      final s = await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Changed');
      await t.tap(find.text('Beta').first);
      await _settle(t);
      expect(find.text('Unsaved changes'), findsWidgets);
      expect(_k('leave-save'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await _settle(t);
      expect(s.peekUid, 'a');
      expect(s.dirty, isTrue);
      // Past the double-click window, so this is a plain click again.
      await t.runAsync(() => Future.delayed(AppState.doubleClickWindow * 2));
      await t.tap(find.text('Beta').first);
      await _settle(t);
      await t.tap(_k('leave-discard'));
      await _settle(t);
      expect(s.peekUid, 'b');
      expect(await _titles(), isNot(contains('Changed')));
      // Save path, from changing the selection.
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Beta 2');
      await t.tap(find.text('Alpha').first);
      await _settle(t);
      await t.tap(_k('leave-save'));
      await _settle(t);
      expect(s.peekUid, 'a');
      expect(await _titles(), contains('Beta 2'));
    });

    testWidgets('the draft survives promoting', (t) async {
      final s = await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Kept');
      await t.tap(_k('peek-promote'));
      await _settle(t);
      expect(s.dirtyFor('a'), isTrue);
      expect(
        t
            .widget<EditableText>(
              find.descendant(
                of: _k('edit-title'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Kept',
      );
    });
  });
}
