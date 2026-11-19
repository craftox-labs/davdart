import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Seed implements NoteSource {
  _Seed([this.skip = const {}]);
  final Set<String> skip;
  @override
  Future<List<Note>> load() async => [
    for (final n in [
      Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
      Note(
        uid: 'a',
        summary: 'Alpha',
        parentUid: 'f',
        description: 'status: todo\n\nAlpha body',
        categories: ['status-todo'],
      ),
      Note(uid: 'b', summary: 'Beta', description: 'Beta body'),
    ])
      if (!skip.contains(n.uid)) n,
  ];
}

AppState _state({
  MemoryStorage? prefs,
  Set<String> skip = const {},
  LayoutSide? side,
}) {
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s = AppState(
    SpaceNoteSource(space, seed: _Seed(skip)),
    prefs: prefs ?? MemoryStorage(),
  );
  if (side != null) s.setLayoutSide(side);
  return s;
}

Future<AppState> _pump(
  WidgetTester t, {
  Size size = const Size(1500, 900),
  LayoutSide? side,
  AppState? state,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final s = state ?? _state(side: side);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

Finder _k(String k) => find.byKey(Key(k));
Finder _close(String tab) =>
    find.descendant(of: _k(tab), matching: _k('tab-close'));

void main() {
  group('tab list', () {
    test('codes round-trip and bad input is ignored', () {
      final l = TabList()..decode('["n:a","v:x","q:y","n:",5]');
      expect(l.tabs, [const DocTab.note('a'), const DocTab.view('x')]);
      expect(TabList()..decode('not json'), isA<TabList>());
      expect((TabList()..decode(l.encode())).tabs, l.tabs);
    });

    test('closing returns the right neighbour, else the left, else null', () {
      final l = TabList()
        ..add(const DocTab.note('a'))
        ..add(const DocTab.note('b'))
        ..add(const DocTab.note('c'));
      expect(l.remove(const DocTab.note('b')), const DocTab.note('c'));
      expect(l.remove(const DocTab.note('c')), const DocTab.note('a'));
      expect(l.remove(const DocTab.note('a')), isNull);
    });
  });

  group('tab strip', () {
    testWidgets('home tab is pinned and not closable', (t) async {
      final s = await _pump(t);
      expect(_k('tab-strip'), findsOneWidget);
      expect(_k('tab-home'), findsOneWidget);
      expect(s.activeTab, isNull);
      expect(_close('tab-home'), findsNothing);
      expect(
        find.descendant(of: _k('tab-home'), matching: find.text('Notes')),
        findsOneWidget,
      );
      s.openNoteTab('a');
      await t.pumpAndSettle();
      expect(_k('tab-home'), findsOneWidget);
      expect(_close('tab-home'), findsNothing);
    });

    testWidgets('maximise creates no strip tab; opening a note tab does', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      expect(_k('tab-n:a'), findsNothing);
      await t.tap(_k('pane-size'));
      await t.pumpAndSettle();
      expect(s.maximised, isTrue);
      expect(s.tabs, isEmpty);
      await t.tap(_k('pane-size'));
      await t.pumpAndSettle();
      expect(s.tabs, isEmpty);
      s.openNoteTab('a');
      s.openNoteTab('a');
      await t.pumpAndSettle();
      expect(_k('tab-n:a'), findsOneWidget);
      expect(s.activeTab, const DocTab.note('a'));
      expect(s.maximised, isFalse);
      // Home shows the list again; the tab stays open, note still selected.
      await t.tap(_k('tab-home'));
      await t.pumpAndSettle();
      expect(s.tabs, hasLength(1));
      expect(s.activeTab, isNull);
      await t.tap(_k('tab-n:a'));
      await t.pumpAndSettle();
      expect(s.activeTab, const DocTab.note('a'));
      expect(s.selectedUid, 'a');
      // Maximise and minimise keep the strip tabs unchanged.
      s.maximise();
      s.minimise();
      expect(s.tabs, hasLength(1));
    });

    testWidgets('closing the active tab activates its neighbour, then home', (
      t,
    ) async {
      final s = await _pump(t);
      s.openNoteTab('a');
      s.openNoteTab('b');
      await t.pumpAndSettle();
      expect(s.tabs, [const DocTab.note('a'), const DocTab.note('b')]);
      expect(s.activeTab, const DocTab.note('b'));
      await t.tap(_close('tab-n:b'));
      await t.pumpAndSettle();
      expect(s.activeTab, const DocTab.note('a'));
      expect(s.selectedUid, 'a');
      await t.tap(_close('tab-n:a'));
      await t.pumpAndSettle();
      expect(s.activeTab, isNull);
      expect(s.tabs, isEmpty);
      expect(s.maximised, isFalse);
      expect(_k('tab-n:a'), findsNothing);
    });

    testWidgets('a dirty tab asks before closing', (t) async {
      final s = await _pump(t);
      s.openNoteTab('a');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), 'Changed');
      await t.pump();
      expect(
        find.descendant(of: _k('tab-n:a'), matching: _k('tab-dirty')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _k('detail-tab'), matching: _k('tab-dirty')),
        findsOneWidget,
      );
      await t.tap(_close('tab-n:a'));
      await t.pumpAndSettle();
      expect(_k('leave-discard'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(s.tabs, hasLength(1));
      expect(s.dirty, isTrue);
      await t.tap(_close('tab-n:a'));
      await t.pumpAndSettle();
      await t.tap(_k('leave-discard'));
      await t.pumpAndSettle();
      expect(s.tabs, isEmpty);
      expect(s.activeTab, isNull);
    });

    testWidgets('+ opens a new note in a tab', (t) async {
      final s = await _pump(t);
      await t.tap(_k('tab-new'));
      await t.pumpAndSettle();
      await t.enterText(_k('new-note-title'), 'Fresh');
      await t.tap(_k('new-note-add'));
      await t.pumpAndSettle();
      expect(s.maximised, isFalse);
      expect(s.selected?.summary, 'Fresh');
      expect(s.activeTab, DocTab.note(s.selectedUid!));
      expect(s.tabs, hasLength(1));
    });

    testWidgets('applying a saved view opens and focuses a view tab', (
      t,
    ) async {
      final s = await _pump(t);
      s.setQuery('alpha');
      await s.saveView('Alphas');
      await t.pumpAndSettle();
      final v = s.savedViews.single;
      s.applyView(v);
      s.applyView(v);
      await t.pumpAndSettle();
      expect(s.tabs, [DocTab.view(v.uid)]);
      expect(s.activeTab, DocTab.view(v.uid));
      expect(
        find.descendant(
          of: _k('tab-v:${v.uid}'),
          matching: find.text('Alphas'),
        ),
        findsOneWidget,
      );
      await t.tap(_close('tab-v:${v.uid}'));
      await t.pumpAndSettle();
      expect(s.tabs, isEmpty);
    });

    testWidgets('Ctrl+W closes the active tab', (t) async {
      final s = await _pump(t);
      s.openNoteTab('a');
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyW);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expect(s.tabs, isEmpty);
    });

    testWidgets('many tabs shrink to the minimum and scroll', (t) async {
      final s = await _pump(t, size: const Size(1300, 900));
      for (final u in ['a', 'b', 'f']) {
        s.openNoteTab(u);
      }
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(_k('tab-scroll'), findsOneWidget);
    });

    testWidgets('open tabs are restored per Space, dropping missing notes', (
      t,
    ) async {
      final prefs = MemoryStorage();
      final first = _state(prefs: prefs);
      await first.load();
      first.openNoteTab('a');
      first.openNoteTab('b');
      expect(first.tabs, hasLength(2));
      final second = _state(prefs: prefs, skip: {'a'});
      await second.load();
      expect(second.tabs, [const DocTab.note('b')]);
      expect(second.activeTab, isNull);
      await _pump(t, state: second);
      expect(_k('tab-n:b'), findsOneWidget);
      expect(_k('tab-n:a'), findsNothing);
      // The pruned list was stored again.
      final third = _state(prefs: prefs);
      await third.load();
      expect(third.tabs, [const DocTab.note('b')]);
    });

    testWidgets('mirrored layout keeps the strip and the maximised pane', (
      t,
    ) async {
      final s = await _pump(t, side: LayoutSide.end);
      s.openNoteTab('a');
      await t.pumpAndSettle();
      expect(_k('tab-strip'), findsOneWidget);
      s.maximise();
      await t.pumpAndSettle();
      expect(_k('tab-strip'), findsNothing);
      expect(_k('full-page'), findsOneWidget);
      s.minimise();
      await t.pumpAndSettle();
      final panel = t.getRect(_k('shell-panel'));
      final strip = t.getRect(_k('tab-strip'));
      // The strip is in the header row, over the panel's top edge.
      expect(strip.bottom - Tokens.light.borders.hairline, panel.top);
      expect(strip.right, lessThanOrEqualTo(panel.right));
      expect(t.takeException(), isNull);
    });

    testWidgets('narrow layout has no strip', (t) async {
      final s = await _pump(t, size: const Size(400, 800));
      s.openNoteTab('a');
      await t.pumpAndSettle();
      expect(_k('tab-strip'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}
