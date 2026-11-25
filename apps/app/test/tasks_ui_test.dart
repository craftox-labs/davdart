import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/note_draft.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'catalog_helper.dart';
import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

/// Text inside the Tasks side panel.
Finder _panelText(String x) => find.descendant(
  of: find.byKey(const Key('tasks-view')),
  matching: find.text(x),
);

/// A widget inside the Tasks side panel (Home shows tasks too).
Finder _p(String k) =>
    find.descendant(of: find.byKey(const Key('tasks-view')), matching: _k(k));

List<Note> _notes() => [
  Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
  Note(uid: 'a', summary: 'Alpha', parentUid: 'f', description: 'body'),
];

List<Task> _tasks() => [
  mkTask('late', summary: 'Late one', days: -2, tags: ['home']),
  mkTask('today', summary: 'Today one', days: 0, parent: 'f'),
  mkTask('soon', summary: 'Soon one', days: 3),
  mkTask('nodate', summary: 'Whenever'),
  mkTask('done', summary: 'Finished', status: 'COMPLETED', days: -1),
];

Future<AppState> _tab(
  WidgetTester t, {
  Size size = const Size(1280, 900),
}) async {
  final s = await pumpTasksApp(t, notes: _notes(), tasks: _tasks(), size: size);
  s.openTasksPanel();
  await t.pumpAndSettle();
  return s;
}

void main() {
  group('Tasks view', () {
    testWidgets('the rail Tasks item lists the tasks in the side panel', (
      t,
    ) async {
      final s = await pumpTasksApp(t, notes: _notes(), tasks: _tasks());
      expect(_k('tasks-view'), findsNothing);
      await t.tap(_k('rail-tasks'));
      await t.pumpAndSettle();
      expect(s.section, Section.tasks);
      expect(s.tabs, isEmpty);
      expect(_k('tasks-view'), findsOneWidget);
      expect(
        find.descendant(of: _k('side-header'), matching: find.text('Tasks')),
        findsOneWidget,
      );
      expect(_k('new-task'), findsOneWidget);
      expect(_k('home-today'), findsOneWidget);
    });

    testWidgets('a task row opens per the open setting', (t) async {
      final s = await _tab(t);
      await t.tap(_p('task-row-soon'));
      await t.pumpAndSettle();
      expect(s.peekUid, 'soon');
      s.setOpenMode(OpenMode.main);
      await t.tap(_p('task-row-nodate'));
      await t.pumpAndSettle();
      expect(s.mainTaskUid, 'nodate');
    });

    testWidgets('New task opens the dialog; adding creates the task', (
      t,
    ) async {
      final s = await _tab(t);
      final before = s.tasks.length;
      await t.tap(_k('new-task'));
      await t.pumpAndSettle();
      expect(s.tasks.length, before);
      expect(_k('task-quick-add'), findsNothing);
      expect(_k('new-task-title'), findsOneWidget);
      await t.enterText(_k('new-task-title'), 'Brand new');
      await t.tap(_k('new-task-add'));
      await t.pumpAndSettle();
      expect(_k('new-task-title'), findsNothing);
      final k = s.tasks.firstWhere((k) => k.summary == 'Brand new');
      expect(_p('task-row-${k.uid}'), findsOneWidget);
    });

    testWidgets('groups, open filter hides Completed, All shows it', (t) async {
      final s = await _tab(t);
      for (final g in ['overdue', 'today', 'upcoming', 'no-date']) {
        expect(_p('tasks-$g-toggle'), findsOneWidget, reason: g);
      }
      expect(_p('tasks-completed-toggle'), findsNothing);
      expect(_p('task-row-late'), findsOneWidget);
      expect(_p('task-row-done'), findsNothing);
      await t.tap(_p('tasks-filter-all'));
      await t.pumpAndSettle();
      expect(s.taskFilter, TaskFilter.all);
      expect(_p('tasks-completed-toggle'), findsOneWidget);
      expect(_p('task-row-done'), findsOneWidget);
      await t.tap(_p('tasks-filter-completed'));
      await t.pumpAndSettle();
      expect(_p('task-row-late'), findsNothing);
      expect(_p('tasks-overdue-toggle'), findsNothing);
      expect(_p('task-row-done'), findsOneWidget);
    });

    testWidgets('a group collapses and persists', (t) async {
      final prefs = MemoryStorage();
      final s = await pumpTasksApp(
        t,
        notes: _notes(),
        tasks: _tasks(),
        prefs: prefs,
      );
      s.openTasksPanel();
      await t.pumpAndSettle();
      await t.tap(_p('tasks-overdue-toggle'));
      await t.pumpAndSettle();
      expect(_p('task-row-late'), findsNothing);
      expect(_p('task-row-today'), findsOneWidget);
      expect(prefs.read('davdart.tasks.overdue.collapsed.v1'), 'true');
    });

    testWidgets('rows show a due chip, tags, and checkbox completes', (
      t,
    ) async {
      final s = await _tab(t);
      expect(
        find.descendant(of: _p('task-row-late'), matching: find.text('#home')),
        findsOneWidget,
      );
      expect(_p('due-late'), findsOneWidget);
      expect(_p('due-nodate'), findsNothing);
      await t.tap(_p('task-check-soon'));
      await t.pumpAndSettle();
      expect(s.taskById('soon')!.isCompleted, isTrue);
      expect(_p('task-row-soon'), findsNothing);
    });

    testWidgets('tag and folder filters narrow the list', (t) async {
      final s = await _tab(t);
      s.setTaskTagFilter('home');
      await t.pumpAndSettle();
      expect(_p('task-row-late'), findsOneWidget);
      expect(_p('task-row-today'), findsNothing);
      s.setTaskTagFilter('home');
      s.openFolder('f');
      await t.pumpAndSettle();
      expect(_p('task-row-today'), findsOneWidget);
      expect(_p('task-row-late'), findsNothing);
      s.openFolder(null);
      await t.pumpAndSettle();
      expect(_p('task-row-late'), findsOneWidget);
      expect(_k('tasks-tags-drawer'), findsOneWidget);
      expect(_k('tasks-tag-filter'), findsNothing);
      expect(_p('tasks-folder-filter'), findsOneWidget);
    });

    testWidgets('no match and empty messages', (t) async {
      final s = await _tab(t);
      s.openFolder('a'); // a note with no tasks under it
      await t.pumpAndSettle();
      expect(_p('tasks-no-match'), findsOneWidget);
      final e = await pumpTasksApp(t);
      e.openTasksPanel();
      await t.pumpAndSettle();
      expect(_p('tasks-empty'), findsOneWidget);
      expect(_k('task-quick-add'), findsNothing);
    });

    testWidgets('click follows the open setting; double click promotes', (
      t,
    ) async {
      final s = await _tab(t);
      await t.tap(_panelText('Soon one'));
      await t.pumpAndSettle();
      expect(s.peekUid, 'soon');
      expect(_k('task-detail'), findsOneWidget);
      s.setOpenMode(OpenMode.main);
      await t.tap(_panelText('Whenever'));
      await t.pumpAndSettle();
      expect(s.mainTaskUid, 'nodate');
      expect(_k('tab-t:nodate'), findsOneWidget);
      s.openTasksPanel();
      s.setOpenMode(OpenMode.peek);
      await t.pumpAndSettle();
      final late = find.descendant(
        of: _p('task-row-late'),
        matching: find.text('Late one'),
      );
      await t.tap(late);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(late);
      await t.pumpAndSettle();
      expect(s.mainTaskUid, 'late');
      expect(s.peekUid, isNot('late'));
    });

    testWidgets('right-click menu: open, complete, due, delete confirm', (
      t,
    ) async {
      final s = await _tab(t);
      await t.tap(_panelText('Soon one'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      for (final k in [
        'menu-open-peek',
        'menu-open-main',
        'menu-task-toggle',
        'menu-task-due',
        'menu-move-space',
        'menu-delete',
      ]) {
        // Move to space only with another Space.
        if (k == 'menu-move-space') continue;
        expect(_k(k), findsOneWidget, reason: k);
      }
      await t.tap(_p('menu-open-main'));
      await t.pumpAndSettle();
      expect(s.mainTaskUid, 'soon');
      s.openTasksPanel();
      await t.pumpAndSettle();
      // Complete.
      await t.tap(_panelText('Today one'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_p('menu-task-toggle'));
      await t.pumpAndSettle();
      expect(s.taskById('today')!.isCompleted, isTrue);
      // Set due tomorrow through the submenu, then clear it.
      await t.tap(_panelText('Whenever'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_p('menu-task-due'));
      await t.pumpAndSettle();
      await t.tap(_p('menu-task-due-tomorrow'));
      await t.pumpAndSettle();
      expect(s.taskById('nodate')!.due, dueIn(1));
      expect(
        find.descendant(
          of: _p('task-row-nodate'),
          matching: find.text('Tomorrow'),
        ),
        findsOneWidget,
      );
      await t.tap(_panelText('Whenever'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_p('menu-task-due'));
      await t.pumpAndSettle();
      await t.tap(_p('menu-task-due-clear'));
      await t.pumpAndSettle();
      expect(s.taskById('nodate')!.due, isNull);
      // Delete asks first.
      await t.tap(_panelText('Whenever'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_p('menu-delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete task?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(s.taskById('nodate'), isNotNull);
      await t.tap(_panelText('Whenever'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_p('menu-delete'));
      await t.pumpAndSettle();
      await t.tap(_k('delete-confirm'));
      await t.pumpAndSettle();
      expect(s.taskById('nodate'), isNull);
    });

    testWidgets('a pick-a-date dialog sets the due date', (t) async {
      final s = await _tab(t);
      await t.tap(_panelText('Whenever'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_p('menu-task-due'));
      await t.pumpAndSettle();
      await t.tap(_p('menu-task-due-pick'));
      await t.pumpAndSettle();
      // The test font is wider than the real one: the calendar header may
      // overflow here, which says nothing about the app.
      t.takeException();
      expect(_k('task-date-calendar'), findsOneWidget);
      final n = DateTime.now();
      // A day of this month that is not today.
      final day = n.day == 15 ? 16 : 15;
      await t.tap(find.text('$day').last);
      await t.pumpAndSettle();
      expect(s.taskById('nodate')!.due, ICalDate.date(n.year, n.month, day));
    });

    testWidgets('a repeating task row has a disabled checkbox', (t) async {
      await pumpTasksApp(
        t,
        tasks: [mkTask('r', rrule: 'FREQ=DAILY', days: 0)],
      ).then((s) async {
        s.openTasksPanel();
        await t.pumpAndSettle();
        expect(t.widget<FCheckbox>(_p('task-check-r')).enabled, isFalse);
        await t.tap(_panelText('r'), buttons: kSecondaryButton);
        await t.pumpAndSettle();
        expect(_p('menu-task-toggle'), findsNothing);
      });
    });

    testWidgets('the tab persists per Space and survives a reload', (t) async {
      final prefs = MemoryStorage();
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      final s = await pumpTasksApp(
        t,
        notes: _notes(),
        tasks: _tasks(),
        prefs: prefs,
        into: space,
      );
      s.openTasksPanel();
      s.openTaskTab('soon');
      await t.pumpAndSettle();
      await pumpTasksApp(
        t,
        notes: _notes(),
        tasks: _tasks(),
        prefs: prefs,
        into: space,
      );
      await t.pumpAndSettle();
      expect(_k('tab-t:soon'), findsOneWidget);
    });

    testWidgets('a dropped task tab is pruned when the task is deleted', (
      t,
    ) async {
      final s = await _tab(t);
      s.openTaskTab('soon');
      await t.pumpAndSettle();
      expect(s.mainTaskUid, 'soon');
      await t.runAsync(() => s.deleteTask('soon'));
      await t.pumpAndSettle();
      expect(s.tabs, isEmpty);
      expect(s.mainTaskUid, isNull);
    });

    for (final w in [320.0, 880.0, 1280.0, 1911.0]) {
      testWidgets('no overflow at $w', (t) async {
        final s = await _tab(t, size: Size(w, 900));
        if (_k('menu').evaluate().isNotEmpty) {
          // Narrow: the panel is in the side menu, which openTasksPanel
          // (the Home "All tasks" link) opened.
          expect(_k('side-menu'), findsOneWidget);
        }
        await t.tap(_k('tasks-filter-all'));
        await t.pumpAndSettle();
        expect(s.section, Section.tasks);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('task detail', () {
    testWidgets(
      'read view: status, due, priority, tags, description, repeats',
      (t) async {
        final s = await pumpTasksApp(
          t,
          notes: _notes(),
          tasks: [
            mkTask(
              'k',
              summary: 'Detail me',
              days: -1,
              priority: 1,
              tags: ['x'],
              parent: 'a',
              description: 'Some text',
              rrule: 'FREQ=WEEKLY;BYDAY=MO',
            ),
          ],
        );
        s.select('k');
        await t.pumpAndSettle();
        expect(_k('task-detail'), findsOneWidget);
        Finder inDetail(Finder f) =>
            find.descendant(of: _k('task-detail'), matching: f);
        expect(
          find.descendant(
            of: _k('peek-toolbar'),
            matching: find.text('Detail me'),
          ),
          findsOneWidget,
        );
        expect(inDetail(find.text('Detail me')), findsNothing);
        expect(inDetail(find.text('Some text')), findsOneWidget);
        expect(inDetail(find.text('x')), findsOneWidget);
        expect(_k('task-due'), findsOneWidget);
        expect(find.text('high'), findsOneWidget);
        expect(find.textContaining('FREQ=WEEKLY;BYDAY=MO'), findsOneWidget);
        // The parent trail is no longer a header breadcrumb; the parent row stays.
        expect(find.text('Alpha'), findsWidgets);
      },
    );

    testWidgets('status menu changes the status', (t) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('k', summary: 'S')]);
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('task-status-menu'));
      await t.pumpAndSettle();
      await t.tap(find.text('in-process').last);
      await t.pumpAndSettle();
      expect(s.taskById('k')!.status, 'IN-PROCESS');
    });

    testWidgets('edit, save, due and priority', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: _notes(),
        tasks: [mkTask('k', summary: 'Edit me')],
      );
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      expect(s.taskDraftFor('k'), isNotNull);
      expect(t.widget<FButton>(_k('edit-save')).onPress, isNull);
      await t.enterText(_k('edit-title'), 'Edited');
      await t.pump();
      expect(_k('dirty-indicator'), findsOneWidget);
      s.taskDraftFor('k')!
        ..setDue(dueIn(2))
        ..setPriority(5);
      await t.pump();
      await t.tap(_k('edit-save'));
      await t.pumpAndSettle();
      final k = s.taskById('k')!;
      expect(k.summary, 'Edited');
      expect(k.due, dueIn(2));
      expect(k.priority, 5);
      expect(s.taskDraftFor('k'), isNull);
    });

    testWidgets('the date field and priority select drive the draft', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('k', summary: 'Fields', days: 1)],
      );
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      expect(_k('edit-due'), findsOneWidget);
      expect(_k('edit-priority'), findsOneWidget);
      await t.tap(_k('edit-priority'));
      await t.pumpAndSettle();
      await t.tap(find.text('high').last);
      await t.pumpAndSettle();
      expect(s.taskDraftFor('k')!.priority, 1);
    });

    testWidgets('empty title cannot be saved', (t) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('k')]);
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), '  ');
      await t.pump();
      expect(t.widget<FButton>(_k('edit-save')).onPress, isNull);
    });

    testWidgets('dirty guard: keep editing, discard, save', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [
          mkTask('k', summary: 'Guard'),
          mkTask('m', summary: 'Other'),
        ],
      );
      s.select('k');
      await t.pumpAndSettle();
      s.startTaskEdit('k');
      s.taskDraftFor('k')!.titleController.text = 'Changed';
      s.leaveGuard = () async => DraftChoice.keep;
      await s.openNote('m');
      expect(s.peekUid, 'k');
      s.leaveGuard = () async => DraftChoice.discard;
      await s.openNote('m');
      expect(s.peekUid, 'm');
      expect(s.taskById('k')!.summary, 'Guard');
      s.select('k');
      s.startTaskEdit('k');
      s.taskDraftFor('k')!.titleController.text = 'Saved';
      s.leaveGuard = () async => DraftChoice.save;
      await t.runAsync(() => s.openNote('m'));
      await t.pumpAndSettle();
      expect(s.taskById('k')!.summary, 'Saved');
    });

    testWidgets('the draft survives promoting to the main area', (t) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('k', summary: 'Moves')]);
      s.select('k');
      await t.pumpAndSettle();
      s.startTaskEdit('k');
      s.taskDraftFor('k')!.titleController.text = 'Typed';
      s.promote();
      await t.pumpAndSettle();
      expect(s.mainTaskUid, 'k');
      expect(s.taskDraftFor('k')!.titleController.text, 'Typed');
      expect(s.tabDirty(const DocTab.task('k')), isTrue);
      s.leaveGuard = () async => DraftChoice.keep;
      await s.closeTab(const DocTab.task('k'));
      expect(s.tabs, isNotEmpty);
    });

    testWidgets('parent select lists notes and other tasks', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: _notes(),
        tasks: [
          mkTask('k', summary: 'Kid'),
          mkTask('p', summary: 'Parent'),
        ],
      );
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      await t.tap(_k('edit-parent'));
      await t.pumpAndSettle();
      expect(find.textContaining('Parent'), findsWidgets);
      await t.tap(find.textContaining('Parent  (task)').last);
      await t.pumpAndSettle();
      expect(s.taskDraftFor('k')!.parent, 'p');
      await t.tap(_k('edit-save'));
      await t.pumpAndSettle();
      expect(s.taskById('k')!.parentUid, 'p');
    });

    testWidgets('child tasks list with add, also on the parent note', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        notes: _notes(),
        tasks: [
          mkTask('p', summary: 'Parent', parent: 'a'),
          mkTask('c1', summary: 'Child one', parent: 'p'),
        ],
      );
      s.select('p');
      await t.pumpAndSettle();
      expect(_k('child-task-c1'), findsOneWidget);
      await t.enterText(_k('task-quick-add-p'), 'Child two');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(s.tasksByParent('p'), hasLength(2));
      // The parent note shows the task that sits under it.
      s.select('a');
      await t.pumpAndSettle();
      expect(_k('child-task-p'), findsOneWidget);
    });

    testWidgets('read-only Space shows the task non-editable', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('k', summary: 'Look', days: 1)],
        readOnly: true,
      );
      s.select('k');
      await t.pumpAndSettle();
      expect(_k('task-detail'), findsOneWidget);
      expect(_k('edit-note'), findsNothing);
      expect(_k('delete-note'), findsNothing);
      expect(_k('task-status-menu'), findsNothing);
      expect(_k('task-status-text'), findsOneWidget);
      for (final c in t.widgetList<FCheckbox>(_k('task-check-k'))) {
        expect(c.enabled, isFalse);
      }
      expect(_k('task-quick-add-k'), findsNothing);
      s.startTaskEdit('k');
      expect(s.taskDraftFor('k'), isNull);
    });

    testWidgets('delete from the toolbar asks first', (t) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('k', summary: 'Bye')]);
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('delete-note'));
      await t.pumpAndSettle();
      expect(find.text('Delete task?'), findsOneWidget);
      await t.tap(_k('delete-confirm'));
      await t.pumpAndSettle();
      expect(s.taskById('k'), isNull);
      expect(s.peekUid, isNull);
    });

    testWidgets('as a main tab the title and header tab show', (t) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('k', summary: 'Full')]);
      s.openTaskTab('k');
      await t.pumpAndSettle();
      expect(_k('main-note'), findsOneWidget);
      expect(_k('task-detail'), findsOneWidget);
      expect(_k('tab-t:k'), findsOneWidget);
    });

    for (final w in [320.0, 880.0, 1280.0, 1911.0]) {
      testWidgets('no overflow at $w', (t) async {
        final s = await pumpTasksApp(
          t,
          notes: _notes(),
          tasks: [
            mkTask(
              'k',
              summary: 'A fairly long task title that must wrap nicely',
              days: -1,
              tags: ['one', 'two'],
              parent: 'a',
              description: 'text',
              rrule: 'FREQ=WEEKLY',
            ),
            mkTask('c', summary: 'Kid', parent: 'k'),
          ],
          size: Size(w, 900),
        );
        s.select('k');
        await t.pumpAndSettle();
        s.startTaskEdit('k');
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('overflow with long content', () {
    final long =
        'An exceedingly long task title that goes on and on '
        'without any sensible place to stop at all, really';
    for (final w in [880.0, 1280.0, 1911.0]) {
      testWidgets('home strip, tasks view, menu and detail at $w', (t) async {
        final s = await pumpTasksApp(
          t,
          notes: _notes(),
          tasks: [
            for (var i = 0; i < 6; i++)
              mkTask(
                'l$i',
                summary: '$long $i',
                days: i - 2,
                tags: ['alpha-tag', 'beta-tag-longer', 'gamma'],
                priority: 1,
                description: long * 3,
              ),
          ],
          size: Size(w, 900),
        );
        expect(t.takeException(), isNull);
        s.openTasksPanel();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(
          find
              .descendant(of: _k('task-row-l1'), matching: find.byType(Text))
              .first,
          buttons: kSecondaryButton,
        );
        await t.pumpAndSettle();
        expect(_k('menu-task-toggle'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tapAt(const Offset(2, 2));
        await t.pumpAndSettle();
        s.openTaskTab('l1');
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        s.startTaskEdit('l1');
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('search, tree and moves', () {
    Future<AppState> catalogApp(WidgetTester t) async {
      t.view.physicalSize = const Size(1500, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: SeedNotes(_notes()));
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      return s;
    }

    testWidgets('a task hit shows an icon and opens the task', (t) async {
      final s = await catalogApp(t);
      await t.runAsync(() => s.addTask('Zebra errand'));
      final uid = s.tasks.single.uid;
      await t.tap(_k('rail-search'));
      await t.pumpAndSettle();
      await t.enterText(_k('search-all-field'), 'zebra');
      await t.pumpAndSettle();
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(_k('hit-$uid'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('hit-$uid'),
          matching: find.byIcon(FLucideIcons.listChecks),
        ),
        findsOneWidget,
      );
      await t.tap(_k('hit-$uid'));
      await t.pumpAndSettle();
      expect(s.peekUid, uid);
      expect(s.selectedTaskUid, uid);
    });

    testWidgets('a task hit follows the open-in-main setting', (t) async {
      final s = await catalogApp(t);
      await t.runAsync(() => s.addTask('Quokka'));
      final uid = s.tasks.single.uid;
      s.setOpenMode(OpenMode.main);
      final hits = await t.runAsync(() => s.searchAllSpaces('quokka'));
      expect(hits!.single.isTask, isTrue);
      await t.runAsync(() => s.openHit(hits.single));
      await t.pumpAndSettle();
      expect(s.mainTaskUid, uid);
    });

    testWidgets('tasks are not in the file tree; a note menu adds one', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        notes: _notes(),
        tasks: [mkTask('k', summary: 'Hidden task', parent: 'f')],
      );
      expect(
        find.descendant(
          of: _k('drop-root'),
          matching: find.text('Hidden task'),
        ),
        findsNothing,
      );
      await t.tap(
        find.descendant(of: _k('drop-root'), matching: find.text('Plans')),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      await t.tap(_k('menu-new-task-inside'));
      await t.pumpAndSettle();
      await t.enterText(_k('new-task-title'), 'Inside Plans');
      await t.tap(_k('new-task-add'));
      await t.pumpAndSettle();
      final made = s.tasks.firstWhere((k) => k.summary == 'Inside Plans');
      expect(made.parentUid, 'f');
    });

    testWidgets('a task dropped on a Space in the popup moves there', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      t.view.physicalSize = const Size(1500, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: SeedNotes(_notes()));
      final other = c.add('Other');
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      await t.runAsync(() => s.addTask('Mover'));
      s.openTasksPanel();
      await t.pumpAndSettle();
      final uid = s.tasks.single.uid;
      final from = t.getCenter(_k('task-row-$uid'));
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
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(s.taskById(uid), isNull);
    });

    testWidgets('Move to space dialog lists the other Spaces', (t) async {
      t.view.physicalSize = const Size(1500, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: SeedNotes(_notes()));
      final other = c.add('Other');
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      await t.runAsync(() => s.addTask('Mover'));
      s.openTasksPanel();
      await t.pumpAndSettle();
      await t.tap(_panelText('Mover'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_k('menu-move-space'));
      await t.pumpAndSettle();
      expect(_k('move-to-${other.id}'), findsOneWidget);
    });
  });

  group('boot matrix with tasks', () {
    for (final size in const [
      Size(320, 700),
      Size(880, 900),
      Size(1280, 900),
      Size(1911, 1000),
    ]) {
      for (final variant in ['home', 'tasks-tab', 'task-peek', 'task-tab']) {
        testWidgets('boots: $size $variant', (t) async {
          final s = await pumpTasksApp(
            t,
            notes: _notes(),
            tasks: _tasks(),
            size: size,
          );
          switch (variant) {
            case 'tasks-tab':
              s.openTasksPanel();
            case 'task-peek':
              s.select('soon');
            case 'task-tab':
              s.openTaskTab('late');
          }
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        });
      }
    }
  });
}
