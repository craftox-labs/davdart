import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/action_match.dart';
import 'package:davdart_app/state/app_action.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/palette_model.dart';
import 'package:davdart_app/state/palette_recents.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/app_actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

AppAction _a(AppState s, String id) =>
    buildActions(s).firstWhere((a) => a.id == id);

bool _on(AppState s, String id) => _a(s, id).enabled(s);

Future<void> _chord(WidgetTester t, LogicalKeyboardKey mod) async {
  await t.sendKeyDownEvent(mod);
  await t.sendKeyEvent(LogicalKeyboardKey.keyK);
  await t.sendKeyUpEvent(mod);
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _open(WidgetTester t) => _chord(t, LogicalKeyboardKey.controlLeft);

Future<void> _type(WidgetTester t, String q) async {
  await t.enterText(_k('palette-field'), q);
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _end(WidgetTester t) => t.pump(const Duration(seconds: 1));

AppState _twoSpaces() {
  final m = MemoryStorage()
    ..write('davdart.space.v1', '{"notes":{}}')
    ..write(
      'davdart.spaces.v1',
      '[{"id":"sp-1","name":"One"},{"id":"sp-2","name":"Two"}]',
    );
  final c = SpaceCatalog(m);
  return AppState(c.sourceFor(c.current!), prefs: m, catalog: c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('matching', () {
    test('every word must match title or keywords', () {
      expect(matchScore('new task', 'New task', ['add']), isNotNull);
      expect(matchScore('add task', 'New task', ['add']), isNotNull);
      expect(matchScore('new zebra', 'New task', ['add']), isNull);
      expect(matchScore('', 'anything'), 0);
    });

    test('prefix beats word start beats inside beats keyword', () {
      final pre = matchScore('go', 'Go to Tasks')!;
      final word = matchScore('go', 'Please go')!;
      final inside = matchScore('go', 'Algorithm')!;
      final kw = matchScore('go', 'Tasks', ['golf'])!;
      expect(pre, greaterThan(word));
      expect(word, greaterThan(inside));
      expect(inside, greaterThan(kw));
    });

    test('ranking is stable for equal scores', () {
      final items = ['b task', 'a task', 'c task'];
      expect(rankBy('task', items, (s) => s), items);
      expect(rankBy('b', ['xb', 'b', 'xxb'], (s) => s).first, 'b');
    });
  });

  group('recents', () {
    test('keeps the last five, newest first, no duplicates', () {
      final r = PaletteRecents(MemoryStorage());
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'c']) {
        r.add(id);
      }
      expect(r.read(), ['c', 'f', 'e', 'd', 'b']);
    });

    test('a damaged value reads as empty', () {
      final m = MemoryStorage()..write(PaletteRecents.key, '{nope');
      expect(PaletteRecents(m).read(), isEmpty);
    });
  });

  group('registry', () {
    test('ids are unique and cover the required actions', () {
      final ids = buildActions(_twoSpaces()).map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in [
        'go.home',
        'go.notes',
        'go.tasks',
        'go.events',
        'go.views',
        'go.search',
        'note.new',
        'folder.new',
        'task.new',
        'event.new',
        'space.new',
        'peek.toggle',
        'peek.promote',
        'tab.close',
        'tab.next',
        'tab.previous',
        'setting.open-mode',
        'go.settings',
        'go.account',
        'sync.now',
        'spaces.refresh',
        'help.keyboard',
        'palette.open',
        'item.delete',
        'task.toggle',
        'item.move-space',
      ]) {
        expect(ids, contains(id));
      }
    });

    test('the Space submenu has one entry per Space; the open one is off', () {
      final s = _twoSpaces();
      final sw = buildActions(s).where((a) => a.id.startsWith('space.switch.'));
      expect(sw.map((a) => a.id), ['space.switch.sp-1', 'space.switch.sp-2']);
      expect(sw.first.enabled(s), isFalse);
      expect(sw.last.enabled(s), isTrue);
      expect(sw.last.title, contains('Two'));
    });

    test('shortcut hint picks the platform label', () {
      final a = _a(_twoSpaces(), 'palette.open');
      expect(a.shortcutHint(apple: false), 'Ctrl+K');
      expect(a.shortcutHint(apple: true), '⌘K');
    });

    testWidgets('selection decides the item actions', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n', summary: 'Note one')],
        tasks: [
          mkTask('a'),
          mkTask('d', status: 'COMPLETED'),
        ],
        events: [mkEvent('e')],
      );
      expect(_on(s, 'item.delete'), isFalse);
      expect(_on(s, 'task.toggle'), isFalse);
      expect(_on(s, 'peek.toggle'), isFalse);
      expect(_on(s, 'tab.close'), isFalse);
      s.select('n');
      expect(_on(s, 'item.delete'), isTrue);
      expect(_on(s, 'task.toggle'), isFalse);
      expect(_on(s, 'note.move-folder'), isTrue);
      expect(_on(s, 'peek.toggle'), isTrue);
      s.select('a');
      expect(_on(s, 'task.toggle'), isTrue);
      expect(_on(s, 'note.move-folder'), isFalse);
      expect(_a(s, 'task.toggle').title, 'Complete selected task');
      s.select('d');
      expect(_a(s, 'task.toggle').title, 'Reopen selected task');
      s.select('e');
      expect(_on(s, 'item.delete'), isTrue);
      expect(_on(s, 'task.toggle'), isFalse);
      s.select(null);
      s.openNoteTab('n');
      expect(_on(s, 'tab.close'), isTrue);
      expect(_on(s, 'item.delete'), isTrue);
      await _end(t);
    });

    testWidgets('actions call the existing state methods', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n', summary: 'Note one')],
        tasks: [mkTask('a')],
      );
      final c = ActionContext(s, t.element(find.byType(Shell)));
      await _a(s, 'go.tasks').run(c);
      expect(s.section, Section.tasks);
      await _a(s, 'setting.open-mode').run(c);
      expect(s.openMode, OpenMode.main);
      expect(_a(s, 'setting.open-mode').title, contains('Peek instead'));
      s.select('a');
      await _a(s, 'task.toggle').run(c);
      expect(s.taskById('a')!.isClosed, isTrue);
      await _a(s, 'peek.promote').run(c);
      expect(s.mainTaskUid, 'a');
      s.openNoteTab('n');
      await _a(s, 'tab.next').run(c);
      expect(s.activeTab, isNull); // wraps to Home
      await _a(s, 'tab.previous').run(c);
      expect(s.mainNoteUid, 'n');
      await _a(s, 'go.home').run(c);
      expect(s.activeTab, isNull);
      await _end(t);
    });
  });

  group('go to project', () {
    Note folder(
      String uid,
      String name, {
      String? parent,
      bool container = false,
    }) => Note(
      uid: uid,
      summary: name,
      parentUid: parent,
      categories: [folderTag, if (container) projectsTag],
    );

    final notes = [
      folder('c', 'Projects', container: true),
      folder('p1', 'Alpha', parent: 'c'),
      folder('p2', 'Beta', parent: 'c'),
      Note(uid: 'n1', summary: 'Loose', description: 'x'),
    ];

    testWidgets('lists the projects; picking one scopes to it', (t) async {
      final s = await pumpTasksApp(t, notes: notes);
      await _open(t);
      await _type(t, 'go to project');
      expect(_k('palette-row-project.go.p1'), findsOneWidget);
      expect(_k('palette-row-project.go.p2'), findsOneWidget);
      // Nothing to go back to yet.
      expect(_k('palette-row-project.go.all'), findsNothing);
      await t.tap(_k('palette-row-project.go.p2'));
      await t.pump(const Duration(milliseconds: 50));
      expect(s.scopeUid, 'p2');
      // The open project drops out; the whole Space row appears.
      await _open(t);
      await _type(t, 'go to project');
      expect(_k('palette-row-project.go.p2'), findsNothing);
      await t.tap(_k('palette-row-project.go.all'));
      await t.pump(const Duration(milliseconds: 50));
      expect(s.scopeUid, isNull);
      await _end(t);
    });

    testWidgets('a dirty edit is asked about before the scope moves', (
      t,
    ) async {
      final s = await pumpTasksApp(t, notes: notes);
      await s.openNote('n1', mode: OpenMode.peek);
      await t.pumpAndSettle();
      s.startEdit('n1');
      await t.pumpAndSettle();
      s.draftFor('n1')!.titleController.text = 'Edited';
      await t.pumpAndSettle();
      expect(s.dirtyFor('n1'), isTrue);
      await _open(t);
      await _type(t, 'go to project');
      await t.tap(_k('palette-row-project.go.p1'));
      await t.pumpAndSettle();
      // Guarded like go.home: the leave dialog first, scope still unset.
      expect(find.text('Unsaved changes'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(s.scopeUid, isNull);
      expect(s.dirtyFor('n1'), isTrue);
      await _end(t);
    });

    testWidgets('recent projects lead', (t) async {
      final s = await pumpTasksApp(t, notes: notes);
      s.openFolder('p1');
      s.openFolder('p2');
      s.openFolder(null);
      await t.pump(const Duration(milliseconds: 50));
      await _open(t);
      await _type(t, 'go to project');
      expect(
        t.getTopLeft(_k('palette-row-project.go.p2')).dy,
        lessThan(t.getTopLeft(_k('palette-row-project.go.p1')).dy),
      );
      await _end(t);
    });
  });

  group('palette', () {
    for (final (name, mod) in [
      ('Ctrl+K', LogicalKeyboardKey.controlLeft),
      ('Meta+K', LogicalKeyboardKey.metaLeft),
    ]) {
      testWidgets('$name opens it with the field focused; Esc closes', (
        t,
      ) async {
        await pumpTasksApp(t);
        expect(_k('palette'), findsNothing);
        await _chord(t, mod);
        expect(_k('palette'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump(const Duration(milliseconds: 50));
        expect(_k('palette'), findsNothing);
        await _end(t);
      });
    }

    testWidgets('type, arrows and Enter run an action', (t) async {
      final s = await pumpTasksApp(t);
      await _open(t);
      await _type(t, 'go to');
      // Go to Home, Notes, Tasks, ... in registry order.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump(const Duration(milliseconds: 50));
      expect(_k('palette'), findsNothing);
      expect(s.section, Section.tasks);
      await _end(t);
    });

    testWidgets('a click runs the row; recents persist and lead', (t) async {
      final prefs = MemoryStorage();
      final s = await pumpTasksApp(t, prefs: prefs);
      await _open(t);
      await _type(t, 'events');
      await t.tap(_k('palette-row-go.events'));
      await t.pump(const Duration(milliseconds: 50));
      expect(s.section, Section.events);
      expect(PaletteRecents(prefs).read(), ['go.events']);
      await _open(t);
      expect(find.text('RECENT'), findsOneWidget);
      final recent = t.getTopLeft(_k('palette-row-go.events')).dy;
      final other = t.getTopLeft(_k('palette-row-palette.open')).dy;
      expect(recent, lessThan(other));
      await _end(t);
    });

    testWidgets('shows shortcut hints and "No matches"', (t) async {
      await pumpTasksApp(t);
      await _open(t);
      expect(find.text('Ctrl+K'), findsWidgets);
      await _type(t, 'zzzzqqq');
      expect(_k('palette-empty'), findsOneWidget);
      expect(find.text('No matches'), findsOneWidget);
      await _end(t);
    });

    testWidgets('item hits open through openMode', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n', summary: 'Milk notes')],
        tasks: [mkTask('a', summary: 'Buy milk')],
        events: [mkEvent('e', summary: 'Milk run')],
      );
      await _open(t);
      await _type(t, 'milk');
      expect(find.text('NOTES'), findsOneWidget);
      expect(find.text('TASKS'), findsWidgets); // also Home's header
      expect(find.text('EVENTS'), findsWidgets);
      await t.tap(_k('palette-row-a'));
      await t.pump(const Duration(milliseconds: 50));
      expect(s.peekUid, 'a');
      expect(s.mainTaskUid, isNull);
      s.setOpenMode(OpenMode.main);
      await _open(t);
      await _type(t, 'milk');
      await t.tap(_k('palette-row-e'));
      await t.pump(const Duration(milliseconds: 50));
      expect(s.mainEventUid, 'e');
      await _end(t);
    });

    testWidgets('Enter on an item opens it', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n', summary: 'Zebra plan')],
      );
      await _open(t);
      await _type(t, 'zebra');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump(const Duration(milliseconds: 50));
      expect(s.peekUid, 'n');
      await _end(t);
    });

    testWidgets('a phone-width screen has no overflow', (t) async {
      await pumpTasksApp(
        t,
        size: const Size(360, 640),
        notes: [Note(uid: 'n', summary: 'A very long note title ' * 8)],
      );
      await _open(t);
      expect(_k('palette'), findsOneWidget);
      expect(t.getSize(_k('palette')).width, lessThanOrEqualTo(360));
      await _type(t, 'long note');
      await t.pump(const Duration(milliseconds: 50));
      expect(t.takeException(), isNull);
      await _end(t);
    });

    testWidgets('wide screen: centred, at most 560 wide', (t) async {
      await pumpTasksApp(t);
      await _open(t);
      final r = t.getRect(_k('palette'));
      expect(r.width, lessThanOrEqualTo(560));
      expect(r.center.dx, closeTo(640, 1));
      await _end(t);
    });

    testWidgets('the chord opens it from a text field, other keys stay', (
      t,
    ) async {
      final s = await pumpTasksApp(t);
      s.setSection(Section.search);
      await t.pumpAndSettle();
      final f = find.byType(FTextField).first;
      await t.tap(f);
      await t.pump();
      await t.enterText(f, 'kk w s');
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyEvent(LogicalKeyboardKey.keyW);
      await t.pump(const Duration(milliseconds: 50));
      expect(_k('palette'), findsNothing);
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: f, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'kk w s',
      );
      await _open(t);
      expect(_k('palette'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump(const Duration(milliseconds: 50));
      // Focus returned to the search field.
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: f, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await _end(t);
    });

    testWidgets('paletteEntries: empty query lists enabled actions only', (
      t,
    ) async {
      final s = await pumpTasksApp(t);
      final e = paletteEntries(s, buildActions(s), '');
      expect(e.any((x) => x.id == 'item.delete'), isFalse);
      expect(e.any((x) => x.id == 'go.tasks'), isTrue);
      await _end(t);
    });
  });
}
