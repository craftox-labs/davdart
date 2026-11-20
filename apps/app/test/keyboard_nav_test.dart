import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_action.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/key_bindings.dart';
import 'package:davdart_app/state/key_nav.dart';
import 'package:davdart_app/ui/app_actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

const _ms = Duration(milliseconds: 50);

Future<void> _press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pump(_ms);
}

Future<void> _shift(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(k);
  await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.pump(_ms);
}

final _j = LogicalKeyboardKey.keyJ;
final _k_ = LogicalKeyboardKey.keyK;

/// Task uids top to bottom as drawn in the Tasks panel.
List<String> _tasksShown(WidgetTester t, Iterable<String> uids) {
  final l = uids.toList();
  l.sort(
    (a, b) => t
        .getTopLeft(_k('task-row-$a'))
        .dy
        .compareTo(t.getTopLeft(_k('task-row-$b')).dy),
  );
  return l;
}

Note _folder(String uid, String name) =>
    Note(uid: uid, summary: name, categories: const ['kind-folder']);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('key tokens and bindings', () {
    test('the registry has no two actions on one key', () {
      final seen = <String, String>{};
      final s = AppState(SeedNotes(const []), prefs: MemoryStorage());
      for (final a in buildActions(s)) {
        for (final k in a.shortcuts) {
          expect(seen[k], isNull, reason: '$k on ${a.id} and ${seen[k]}');
          seen[k] = a.id;
        }
      }
      // Every other binding is a prefix-free sequence or a single key.
      for (final k in seen.keys.where(isBareKeyLabel)) {
        final parts = k.split(' ');
        for (var i = 1; i < parts.length; i++) {
          expect(
            seen.containsKey(parts.sublist(0, i).join(' ')),
            isFalse,
            reason: '$k hides a shorter binding',
          );
        }
      }
    });

    test('vim off drops letter bindings and keeps named keys', () {
      final s = AppState(SeedNotes(const []), prefs: MemoryStorage());
      final on = KeyBindings(buildActions(s), vim: true);
      final off = KeyBindings(buildActions(s), vim: false);
      expect(on.resolve([], 'j').action?.id, 'nav.down');
      expect(off.resolve([], 'j').action, isNull);
      expect(off.resolve([], 'Down').action?.id, 'nav.down');
      expect(off.resolve([], 'Enter').action?.id, 'nav.open');
      expect(on.resolve([], 'g').keys, ['g']);
      expect(off.resolve([], 'g').keys, isNull);
      expect(on.resolve(['g'], 't').action?.id, 'go.tasks');
      expect(on.resolve(['g'], 'j').action, isNull);
    });
  });

  group('setting', () {
    testWidgets(
      'Vim keys is on by default, persists, and the switch flips it',
      (t) async {
        final prefs = MemoryStorage();
        final s = await pumpTasksApp(t, prefs: prefs);
        expect(s.vimKeys, isTrue);
        s.setSection(Section.settings);
        await t.pumpAndSettle();
        expect(_k('vim-keys'), findsOneWidget);
        await t.tap(_k('vim-keys'));
        await t.pumpAndSettle();
        expect(s.vimKeys, isFalse);
        expect(prefs.read('davdart.vim.keys.v1'), 'false');
        final again = AppState(SeedNotes(const []), prefs: prefs);
        expect(again.vimKeys, isFalse);
        s.setVimKeys(true);
        expect(prefs.read('davdart.vim.keys.v1'), isNull);
      },
    );

    testWidgets('keys are inert when it is off; arrows and Enter still work', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a'), mkTask('b'), mkTask('c')],
      );
      s.setSection(Section.tasks);
      s.setVimKeys(false);
      await t.pumpAndSettle();
      final order = _tasksShown(t, ['a', 'b', 'c']);
      await _press(t, _j);
      await _press(t, LogicalKeyboardKey.keyG);
      await _press(t, LogicalKeyboardKey.keyT);
      expect(s.nav.cursorId('tasks'), isNull);
      expect(s.section, Section.tasks);
      await _press(t, LogicalKeyboardKey.arrowDown);
      expect(s.nav.cursorId('tasks'), order[0]);
      await _press(t, LogicalKeyboardKey.arrowDown);
      expect(s.nav.cursorId('tasks'), order[1]);
      await _press(t, LogicalKeyboardKey.enter);
      expect(s.peekUid, order[1]);
      // The palette chord is unaffected.
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump(_ms);
      expect(_k('palette'), findsOneWidget);
      await _press(t, LogicalKeyboardKey.escape);
    });
  });

  group('areas', () {
    testWidgets('h and l walk rail, panel, main, peek and skip hidden ones', (
      t,
    ) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('a')]);
      s.setSection(Section.tasks);
      await t.pumpAndSettle();
      expect(s.nav.area, NavArea.panel);
      expect(s.nav.ring, [NavArea.rail, NavArea.panel, NavArea.main]);
      await _press(t, LogicalKeyboardKey.keyL);
      expect(s.nav.area, NavArea.main);
      await _press(t, LogicalKeyboardKey.keyL); // no peek: stays
      expect(s.nav.area, NavArea.main);
      await _press(t, LogicalKeyboardKey.keyH);
      await _press(t, LogicalKeyboardKey.keyH);
      expect(s.nav.area, NavArea.rail);
      await _press(t, LogicalKeyboardKey.keyH);
      expect(s.nav.area, NavArea.rail);
      // With a peek the ring grows by one at the end.
      s.select('a');
      await t.pumpAndSettle();
      expect(s.nav.ring.last, NavArea.peek);
      await _press(t, LogicalKeyboardKey.keyL);
      await _press(t, LogicalKeyboardKey.keyL);
      await _press(t, LogicalKeyboardKey.keyL);
      expect(s.nav.area, NavArea.peek);
      // Esc goes up a level at a time.
      await _press(t, LogicalKeyboardKey.escape);
      expect(s.nav.area, NavArea.main);
      await _press(t, LogicalKeyboardKey.escape);
      expect(s.nav.area, NavArea.panel);
      // A folded panel is skipped.
      s.setSidebarCollapsed(true);
      await t.pumpAndSettle();
      await _press(t, LogicalKeyboardKey.keyH);
      expect(s.nav.area, NavArea.rail);
      await _press(t, LogicalKeyboardKey.keyL);
      expect(s.nav.area, NavArea.main);
    });

    testWidgets('the focused area is marked once the keyboard is used', (
      t,
    ) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('a')]);
      s.setSection(Section.tasks);
      await t.pumpAndSettle();
      expect(_k('area-mark-panel'), findsNothing);
      await _press(t, _j);
      expect(_k('area-mark-panel'), findsOneWidget);
      await _press(t, LogicalKeyboardKey.keyL);
      expect(_k('area-mark-panel'), findsNothing);
      expect(_k('area-mark-main'), findsOneWidget);
    });

    testWidgets('a click moves the area and the cursor', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a'), mkTask('b')],
        notes: [Note(uid: 'n', summary: 'Note')],
      );
      s.setSection(Section.tasks);
      await t.pumpAndSettle();
      await t.tap(_k('task-row-b'));
      await t.pump(const Duration(milliseconds: 500));
      expect(s.nav.area, NavArea.panel);
      expect(s.nav.cursorId('tasks'), 'b');
      await t.tap(_k('rail-notes'));
      await t.pumpAndSettle();
      expect(s.nav.area, NavArea.rail);
      expect(s.nav.cursorId(KeyNav.railList), 'notes');
      await t.tapAt(t.getCenter(find.byType(FScaffold)));
      await t.pump(const Duration(milliseconds: 500));
      expect(s.nav.area, NavArea.main);
    });
  });

  group('lists', () {
    testWidgets('Notes tree: j k gg G clamp; h and l fold and step', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          _folder('f', 'Folder'),
          Note(uid: 'a', summary: 'Alpha', parentUid: 'f'),
          Note(uid: 'z', summary: 'Zed'),
        ],
      );
      expect(s.section, Section.notes);
      await _press(t, _k_); // from nothing: the first row
      expect(s.nav.cursorId('notes'), 'f');
      await _press(t, _k_);
      expect(s.nav.cursorId('notes'), 'f');
      await _press(t, _j);
      expect(s.nav.cursorId('notes'), 'a');
      await _press(t, _j);
      await _press(t, _j);
      await _press(t, _j);
      expect(s.nav.cursorId('notes'), 'z');
      await _press(t, LogicalKeyboardKey.keyG);
      await _press(t, LogicalKeyboardKey.keyG);
      expect(s.nav.cursorId('notes'), 'f');
      await _shift(t, LogicalKeyboardKey.keyG);
      expect(s.nav.cursorId('notes'), 'z');
      // h on a child goes to the parent; h on an open folder folds it.
      s.nav.setCursor('notes', 'a');
      await t.pump();
      await _press(t, LogicalKeyboardKey.keyH);
      expect(s.nav.cursorId('notes'), 'f');
      await _press(t, LogicalKeyboardKey.keyH);
      expect(s.collapsed, contains('f'));
      await t.pump();
      await _press(t, _j);
      expect(s.nav.cursorId('notes'), 'z'); // 'a' is hidden now
      s.nav.setCursor('notes', 'f');
      await _press(t, LogicalKeyboardKey.keyL); // expands
      expect(s.collapsed, isNot(contains('f')));
      await _press(t, LogicalKeyboardKey.keyL); // steps in
      expect(s.nav.cursorId('notes'), 'a');
      await _press(t, LogicalKeyboardKey.keyL); // a leaf: focus moves right
      expect(s.nav.area, NavArea.main);
    });

    testWidgets('the cursor survives a rebuild and clamps when rows go', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a'), mkTask('b'), mkTask('c')],
      );
      s.setSection(Section.tasks);
      await t.pumpAndSettle();
      final order = _tasksShown(t, ['a', 'b', 'c']);
      await _shift(t, LogicalKeyboardKey.keyG);
      expect(s.nav.cursorId('tasks'), order[2]);
      s.setTaskFilter(TaskFilter.all);
      await t.pumpAndSettle();
      expect(s.nav.cursorId('tasks'), order[2]);
      await s.deleteTask(order[2]);
      await t.pumpAndSettle();
      expect(s.nav.cursorId('tasks'), order[1]); // clamped to the last row
      await _press(t, _j);
      expect(s.nav.cursorId('tasks'), order[1]);
    });

    testWidgets('Tasks: counts, Enter, o, O, x, D, e', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a'), mkTask('b'), mkTask('c')],
      );
      s.setSection(Section.tasks);
      await t.pumpAndSettle();
      final order = _tasksShown(t, ['a', 'b', 'c']);
      await _press(t, LogicalKeyboardKey.digit2);
      expect(_k('key-pending'), findsOneWidget);
      await _press(t, _j);
      expect(_k('key-pending'), findsNothing);
      expect(s.nav.cursorId('tasks'), order[1]); // 2j from nothing: 2nd row
      await _press(t, LogicalKeyboardKey.enter);
      expect(s.peekUid, order[1]);
      expect(s.mainItemUid, isNull);
      await _shift(t, LogicalKeyboardKey.keyO);
      expect(s.mainItemUid, order[1]);
      await _press(t, _k_);
      await _press(t, LogicalKeyboardKey.keyO);
      expect(s.peekUid, order[0]);
      // x completes the task under the cursor, again reopens it.
      s.nav.focusArea(NavArea.panel, list: 'tasks');
      await t.pump();
      s.nav.setCursor('tasks', order[2]);
      await _press(t, LogicalKeyboardKey.keyX);
      expect(s.taskById(order[2])!.isClosed, isTrue);
      await t.pumpAndSettle();
      // Completed tasks leave the Open list; the cursor clamps.
      expect(s.nav.cursorId('tasks'), isNot(order[2]));
      // D asks before deleting the cursor task.
      s.nav.setCursor('tasks', order[0]);
      await _shift(t, LogicalKeyboardKey.keyD);
      await t.pumpAndSettle();
      expect(find.text('Delete task?'), findsOneWidget);
      expect(s.taskById(order[0]), isNotNull);
      await t.tap(_k('delete-confirm'));
      await t.pumpAndSettle();
      expect(s.taskById(order[0]), isNull);
      // e edits the cursor task, opening it first.
      final left = s.nav.cursorId('tasks')!;
      await _press(t, LogicalKeyboardKey.keyE);
      await t.pump(const Duration(milliseconds: 300));
      expect(s.taskDraftFor(left), isNotNull);
      expect(s.peekUid == left || s.mainItemUid == left, isTrue);
    });

    testWidgets('Events: j k move, Enter opens the event', (t) async {
      final s = await pumpTasksApp(
        t,
        events: [
          mkEvent('e1', days: 2),
          mkEvent('e2', days: 3),
          mkEvent('e3', days: 4),
        ],
      );
      s.setSection(Section.events);
      await t.pumpAndSettle();
      await _press(t, _j);
      expect(s.nav.cursorId('events'), 'event-row-e1');
      await _press(t, _j);
      await _press(t, _j);
      await _press(t, _j);
      expect(s.nav.cursorId('events'), 'event-row-e3');
      await _press(t, _k_);
      await _press(t, LogicalKeyboardKey.enter);
      expect(s.peekUid, 'e2');
    });

    testWidgets('Home cards form one list; Enter opens a row', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a', days: 0)],
        events: [mkEvent('e1', days: 0)],
      );
      await s.activateTab(null);
      await t.pumpAndSettle();
      s.nav.focusArea(NavArea.main, list: KeyNav.homeList);
      await t.pump();
      expect(s.nav.cursorId(KeyNav.homeList), 'task-a');
      await _press(t, _j);
      expect(s.nav.cursorId(KeyNav.homeList), 'event-row-e1');
      await _press(t, LogicalKeyboardKey.enter);
      expect(s.peekUid, 'e1');
    });

    testWidgets('rail: j k move over sections, Enter picks one', (t) async {
      final s = await pumpTasksApp(t);
      await _press(t, LogicalKeyboardKey.keyH);
      expect(s.nav.area, NavArea.rail);
      expect(s.nav.cursorId(KeyNav.railList), 'notes');
      await _press(t, _j);
      await _press(t, _j);
      expect(s.nav.cursorId(KeyNav.railList), 'events');
      await _press(t, LogicalKeyboardKey.enter);
      expect(s.section, Section.events);
      expect(s.nav.area, NavArea.panel);
    });
  });

  group('sequences', () {
    testWidgets('g t, g n, g h and friends jump', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n', summary: 'N')],
        tasks: [mkTask('a')],
      );
      Future<void> go(LogicalKeyboardKey k) async {
        await _press(t, LogicalKeyboardKey.keyG);
        expect(_k('key-pending'), findsOneWidget);
        await _press(t, k);
        expect(_k('key-pending'), findsNothing);
      }

      await go(LogicalKeyboardKey.keyT);
      expect(s.section, Section.tasks);
      expect(s.nav.area, NavArea.panel);
      await go(LogicalKeyboardKey.keyE);
      expect(s.section, Section.events);
      await go(LogicalKeyboardKey.keyV);
      expect(s.section, Section.views);
      await go(LogicalKeyboardKey.keyS);
      expect(s.section, Section.search);
      await go(LogicalKeyboardKey.keyN);
      expect(s.section, Section.notes);
      s.openNoteTab('n');
      await t.pumpAndSettle();
      await go(LogicalKeyboardKey.keyH);
      expect(s.activeTab, isNull);
    });

    testWidgets('a pending key times out after a second; Esc cancels', (
      t,
    ) async {
      final s = await pumpTasksApp(t);
      await _press(t, LogicalKeyboardKey.keyG);
      expect(s.nav.pending, ['g']);
      await t.pump(const Duration(milliseconds: 1100));
      expect(s.nav.pending, isEmpty);
      await _press(t, LogicalKeyboardKey.keyT); // alone: nothing
      expect(s.section, Section.notes);
      await _press(t, LogicalKeyboardKey.keyG);
      await _press(t, LogicalKeyboardKey.escape);
      expect(s.nav.pending, isEmpty);
      await _press(t, LogicalKeyboardKey.keyT);
      expect(s.section, Section.notes);
      // A wrong second key cancels without running anything.
      await _press(t, LogicalKeyboardKey.keyG);
      await _press(t, LogicalKeyboardKey.keyJ);
      expect(s.nav.pending, isEmpty);
      expect(s.section, Section.notes);
    });
  });

  group('text fields', () {
    testWidgets('a field keeps every key; Esc leaves it', (t) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('a'), mkTask('b')]);
      s.setSection(Section.tasks);
      await t.pumpAndSettle();
      await t.tap(_k('task-quick-add'));
      await t.pump(_ms);
      final field = FocusManager.instance.primaryFocus;
      await _press(t, _j);
      await _press(t, LogicalKeyboardKey.keyG);
      await _press(t, LogicalKeyboardKey.keyT);
      await _shift(t, LogicalKeyboardKey.keyD);
      expect(s.nav.cursorId('tasks'), isNull);
      expect(s.nav.pending, isEmpty);
      expect(FocusManager.instance.primaryFocus, field);
      expect(find.text('Delete task?'), findsNothing);
      await _press(t, LogicalKeyboardKey.escape);
      expect(FocusManager.instance.primaryFocus, s.nav.node);
      await _press(t, _j);
      expect(s.nav.cursorId('tasks'), isNotNull);
    });

    testWidgets('the title field of an edit takes j too', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n', summary: 'Note')],
      );
      s.select('n');
      await t.pumpAndSettle();
      s.startEdit('n');
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(_k('edit-title'));
      await t.pump(_ms);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
      );
      await _press(t, _j);
      await _press(t, LogicalKeyboardKey.keyP);
      expect(s.nav.cursorId('notes'), isNull);
      expect(s.peekCollapsed, isFalse);
      expect(s.peekUid, 'n');
    });
  });

  group('other keys', () {
    testWidgets('/ focuses search, n opens the new dialog, : the palette', (
      t,
    ) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('a')]);
      await _press(t, LogicalKeyboardKey.slash);
      await t.pumpAndSettle();
      expect(s.section, Section.search);
      expect(s.nav.searchNode.hasFocus, isTrue);
      await _press(t, LogicalKeyboardKey.escape);
      s.setSection(Section.tasks);
      await t.pumpAndSettle();
      await _press(t, LogicalKeyboardKey.keyN);
      await t.pumpAndSettle();
      expect(find.byType(FDialog), findsOneWidget);
      await _press(t, LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      await _shift(t, LogicalKeyboardKey.semicolon);
      expect(_k('palette'), findsOneWidget);
    });

    testWidgets('p toggles the peek, P promotes, [ ] and q work on tabs', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          Note(uid: 'n', summary: 'N'),
          Note(uid: 'm', summary: 'M'),
        ],
      );
      s.select('n');
      await t.pumpAndSettle();
      await _press(t, LogicalKeyboardKey.keyP);
      expect(s.peekCollapsed, isTrue);
      await _press(t, LogicalKeyboardKey.keyP);
      expect(s.peekCollapsed, isFalse);
      await _shift(t, LogicalKeyboardKey.keyP);
      expect(s.mainNoteUid, 'n');
      s.openNoteTab('m');
      await t.pumpAndSettle();
      await _press(t, LogicalKeyboardKey.bracketLeft);
      expect(s.mainNoteUid, 'n');
      await _press(t, LogicalKeyboardKey.bracketRight);
      expect(s.mainNoteUid, 'm');
      await _press(t, LogicalKeyboardKey.keyQ);
      await t.pumpAndSettle();
      expect(s.tabs.length, 1);
      // x on a note page in main closes the tab.
      s.nav.focusArea(NavArea.main);
      await _press(t, LogicalKeyboardKey.keyX);
      await t.pumpAndSettle();
      expect(s.tabs, isEmpty);
    });

    testWidgets('Ctrl+K and Cmd+K still open the palette', (t) async {
      await pumpTasksApp(t);
      for (final mod in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await t.sendKeyDownEvent(mod);
        await t.sendKeyEvent(LogicalKeyboardKey.keyK);
        await t.sendKeyUpEvent(mod);
        await t.pump(_ms);
        expect(_k('palette'), findsOneWidget);
        await _press(t, LogicalKeyboardKey.escape);
        expect(_k('palette'), findsNothing);
      }
    });

    testWidgets('keys do nothing while the palette is open', (t) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('a')]);
      s.setSection(Section.tasks);
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump(_ms);
      await _press(t, _j);
      expect(s.nav.cursorId('tasks'), isNull);
      await _press(t, LogicalKeyboardKey.escape);
    });
  });

  group('help', () {
    testWidgets('? lists every registered shortcut by group; Esc closes', (
      t,
    ) async {
      final s = await pumpTasksApp(t);
      await _shift(t, LogicalKeyboardKey.slash);
      await t.pumpAndSettle();
      expect(_k('keyboard-help'), findsOneWidget);
      for (final g in ['Navigation', 'Open', 'Edit', 'Go to', 'Panes']) {
        expect(find.text(g), findsOneWidget, reason: g);
      }
      for (final a in buildActions(s)) {
        if (a.shortcuts.isEmpty) continue;
        expect(find.text(a.shortcuts.join(' / ')), findsWidgets, reason: a.id);
        expect(find.text(a.title), findsWidgets, reason: a.id);
      }
      for (final (keys, _) in knownShortcuts) {
        expect(find.text(keys), findsOneWidget);
      }
      await _press(t, LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(_k('keyboard-help'), findsNothing);
    });

    testWidgets('the palette action opens it, also with Vim keys off', (
      t,
    ) async {
      final s = await pumpTasksApp(t);
      s.setVimKeys(false);
      await t.pump();
      final c = ActionContext(s, t.element(find.byType(FScaffold)));
      buildActions(s).firstWhere((a) => a.id == 'help.keyboard').run(c);
      await t.pumpAndSettle();
      expect(_k('keyboard-help'), findsOneWidget);
      expect(find.textContaining('Vim keys are off'), findsOneWidget);
    });
  });

  group('phone', () {
    testWidgets('keys are safe on a 320px phone: no overflow', (t) async {
      final s = await pumpTasksApp(
        t,
        size: const Size(320, 640),
        tasks: [mkTask('a')],
      );
      expect(s.nav.ring, [NavArea.main]);
      await _press(t, _j);
      await _press(t, LogicalKeyboardKey.keyL);
      await _press(t, LogicalKeyboardKey.keyH);
      await _press(t, LogicalKeyboardKey.keyG);
      await _press(t, LogicalKeyboardKey.keyT);
      await _shift(t, LogicalKeyboardKey.slash);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await _press(t, LogicalKeyboardKey.escape);
    });
  });
}
