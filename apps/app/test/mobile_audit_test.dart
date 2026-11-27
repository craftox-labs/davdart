// A layout audit of every narrow screen at phone widths: 320, 360 and 390 px
// wide (800 high). Each screen is visited with realistic long data — long
// titles and summaries, many tags, due dates, nesting — and checked for two
// things:
//
//  1. no RenderFlex/overflow exception was thrown (`tester.takeException()`);
//  2. the main selector rows span the content width (compared with a second
//     full-width control beside them, or with their reference row).
//
// A test that fails on a real defect stays here but is marked
// `skip: 'DEFECT: ...'` with the measured numbers, so the file runs green and
// the defects are listed one by one. The table is in
// docs/2026-11-25-mobile-audit.md. apps/app/lib is not changed.
import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/list_view.dart';
import 'package:davdart_app/ui/segmented.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_helper.dart';
import 'tasks_helper.dart';

const _heights = 800.0;
const _widths = [320.0, 360.0, 390.0];

Finder _k(String k) => find.byKey(Key(k));

String _px(double v) => v.toStringAsFixed(1);

Rect _rect(WidgetTester t, String key) => t.getRect(_k(key));

String _box(WidgetTester t, String key) {
  final r = _rect(t, key);
  return '$key ${_px(r.left)}..${_px(r.right)} (w ${_px(r.width)})';
}

/// Fails with the exception text (which names the overflow amount) when a
/// screen overflowed.
void _clean(WidgetTester t, String screen, double w) {
  final ex = t.takeException();
  expect(
    ex,
    isNull,
    reason:
        '$screen @${_px(w)}px threw: '
        '${ex is FlutterError ? ex.message : ex}',
  );
}

/// Fails when the screen did not render (a navigation miss would make the
/// overflow check meaningless).
void _present(WidgetTester t, String screen, double w, Finder f) {
  expect(
    f,
    findsWidgets,
    reason: '$screen @${_px(w)}px: $f not found, the screen did not show',
  );
}

/// Fails when the control at [control] does not span the same width as
/// [ref], another full-width control beside it, within 1 px.
void _spans(
  WidgetTester t,
  String screen,
  double w,
  Finder control,
  String ref,
) {
  final c = t.getRect(control);
  final r = _rect(t, ref);
  expect(
    (c.width - r.width).abs() <= 1,
    isTrue,
    reason:
        '$screen @${_px(w)}px: control ${_px(c.left)}..${_px(c.right)} '
        '(w ${_px(c.width)}) does not span the content width of '
        '${_box(t, ref)}',
  );
}

const _long =
    'Quarterly planning review with the whole team and the client observers';
const _tags = ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight'];

List<Note> _notes() => [
  Note(
    uid: 'f1',
    summary: 'A project folder with a fairly long name for the tree',
    categories: const ['kind-folder'],
    created: DateTime.utc(2026, 1, 1),
    lastModified: DateTime.utc(2026, 1, 1),
  ),
  Note(
    uid: 'f2',
    summary: 'A nested subfolder with a long name too',
    parentUid: 'f1',
    categories: const ['kind-folder'],
    created: DateTime.utc(2026, 1, 2),
    lastModified: DateTime.utc(2026, 1, 2),
  ),
  Note(
    uid: 'n1',
    summary: '$_long, note one',
    parentUid: 'f2',
    description:
        'status: todo\npriority: high\n\nA long body paragraph. '
        'It keeps going for a while so the card snippet and the list row '
        'have something to show.\n\nAnd a second paragraph.',
    categories: ['status-todo', ..._tags],
    created: DateTime.utc(2026, 1, 3),
    lastModified: DateTime.utc(2026, 1, 3),
  ),
  Note(
    uid: 'n2',
    summary: '$_long, note two',
    description: 'status: doing\npriority: medium\n\nBody of note two.',
    categories: ['status-doing', ..._tags],
    created: DateTime.utc(2026, 1, 4),
    lastModified: DateTime.utc(2026, 1, 4),
  ),
  Note(
    uid: 'n3',
    summary: 'A note in a status word outside the fixed set',
    description: 'status: waiting\n\nBody of note three.',
    categories: ['status-waiting', 'x', 'y'],
    created: DateTime.utc(2026, 1, 5),
    lastModified: DateTime.utc(2026, 1, 5),
  ),
];

List<Task> _tasks() => [
  mkTask(
    't1',
    summary: '$_long, task one',
    days: -2,
    priority: 1,
    tags: _tags,
    parent: 'f2',
    description: 'Task body that runs on a bit to fill a row.',
  ),
  mkTask('t2', summary: '$_long, task two', days: 0, tags: _tags),
  mkTask(
    't3',
    summary: 'A third task, undated and long enough to wrap',
    tags: const ['one', 'two'],
  ),
];

List<Event> _events() => [
  mkEvent('e1', summary: '$_long, event one', days: 0, location: 'Room 4'),
  mkEvent(
    'e2',
    summary: 'A second event with a long summary as well',
    days: 2,
    hour: 15,
    tags: _tags,
  ),
];

Future<AppState> _pump(WidgetTester t, double w) async {
  return pumpTasksApp(
    t,
    notes: _notes(),
    tasks: _tasks(),
    events: _events(),
    size: Size(w, _heights),
  );
}

/// Pumps an app with a Spaces catalog, which the search needs (search covers
/// every Space of the catalog).
Future<AppState> _pumpWithCatalog(WidgetTester t, double w) async {
  t.view.physicalSize = Size(w, _heights);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final storage = MemoryStorage();
  final c = catalogWithPlanning(storage, planningSeed: SeedNotes(_notes()));
  final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

/// Opens the narrow side menu drawer.
Future<void> _drawer(WidgetTester t, AppState s, Section section) async {
  s.setSection(section);
  await t.pumpAndSettle();
  await t.tap(_k('menu'));
  await t.pumpAndSettle();
}

/// Opens `bar-add` and picks [entry] ('add-note', 'add-task', 'add-event').
Future<void> _addDialog(WidgetTester t, String entry) async {
  await t.tap(_k('bar-add'));
  await t.pumpAndSettle();
  await t.tap(_k(entry));
  await t.pumpAndSettle();
}

void main() {
  // The audit is only worth anything if an overflow in this harness reaches
  // takeException().
  testWidgets('the audit detects an overflow', (t) async {
    await t.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 40,
            child: Row(
              children: [
                SizedBox(width: 200, height: 10),
                SizedBox(width: 200, height: 10),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      t.takeException(),
      isNotNull,
      reason: 'a 400 px row in a 100 px box must be reported',
    );
  });

  for (final w in _widths) {
    final at = '@${w.toInt()}px';

    testWidgets('notes tree in the side menu $at', (t) async {
      final s = await _pump(t, w);
      await _drawer(t, s, Section.notes);
      _present(t, 'notes tree', w, _k('nav-notes-n1'));
      _clean(t, 'notes tree', w);
    });

    testWidgets('notes list $at', (t) async {
      final s = await _pump(t, w);
      s.setView(ViewMode.list);
      await s.saveView('Everything');
      s.applyView(s.savedViews.single);
      await t.pumpAndSettle();
      expect(find.byType(NoteListView), findsOneWidget);
      _present(
        t,
        'notes list',
        w,
        find.descendant(
          of: find.byType(NoteListView),
          matching: find.textContaining('note one'),
        ),
      );
      _clean(t, 'notes list', w);
    });

    testWidgets('tasks panel $at', (t) async {
      final s = await _pump(t, w);
      await _drawer(t, s, Section.tasks);
      _present(t, 'tasks panel', w, _k('tasks-view'));
      _present(t, 'tasks panel', w, _k('task-row-t1'));
      _clean(t, 'tasks panel', w);
      // The filter segmented control and the folder selector both ask for the
      // full content width on a phone (the panel's own rule, see
      // Segmented.fullWidth and the folder selector in _Filters).
      _spans(
        t,
        'tasks panel',
        w,
        find.byType(Segmented<TaskFilter>),
        'tasks-folder-filter',
      );
    });

    testWidgets('events panel $at', (t) async {
      final s = await _pump(t, w);
      await _drawer(t, s, Section.events);
      _present(t, 'events panel', w, _k('events-view'));
      _present(t, 'events panel', w, _k('event-row-e1'));
      _clean(t, 'events panel', w);
    });

    testWidgets('search $at', (t) async {
      await _pumpWithCatalog(t, w);
      await t.tap(_k('bar-search'));
      await t.pumpAndSettle();
      await t.enterText(_k('search-all-field'), 'planning');
      await t.pumpAndSettle();
      _present(t, 'search', w, _k('hit-n1'));
      _clean(t, 'search', w);
    });

    testWidgets('account $at', (t) async {
      // Account only shows when signing in is possible (a Spaces catalog).
      final s = await _pumpWithCatalog(t, w);
      await _drawer(t, s, Section.account);
      _present(t, 'account', w, find.text('Sign in…'));
      _clean(t, 'account', w);
    });

    testWidgets('settings $at', (t) async {
      final s = await _pump(t, w);
      await _drawer(t, s, Section.settings);
      _present(t, 'settings', w, _k('open-mode'));
      _clean(t, 'settings', w);
    });

    testWidgets('note detail $at', (t) async {
      final s = await _pump(t, w);
      await s.openNote('n1');
      await t.pumpAndSettle();
      _present(t, 'note detail', w, _k('peek-toolbar'));
      _present(t, 'note detail', w, find.textContaining('note one'));
      _clean(t, 'note detail', w);
    });

    testWidgets('task detail $at', (t) async {
      final s = await _pump(t, w);
      await s.openNote('t1');
      await t.pumpAndSettle();
      _present(t, 'task detail', w, _k('peek-toolbar'));
      _present(t, 'task detail', w, find.textContaining('task one'));
      _clean(t, 'task detail', w);
    });

    testWidgets('event detail $at', (t) async {
      final s = await _pump(t, w);
      await s.openNote('e1');
      await t.pumpAndSettle();
      _present(t, 'event detail', w, _k('peek-toolbar'));
      _present(t, 'event detail', w, find.textContaining('event one'));
      _clean(t, 'event detail', w);
    });

    testWidgets('space chip opens the picker $at', (t) async {
      await _pump(t, w);
      await t.tap(_k('space-chip'));
      await t.pumpAndSettle();
      _present(t, 'space chip', w, _k('projects-view'));
      _clean(t, 'space chip', w);
    });

    testWidgets('open items grid $at', (t) async {
      final s = await _pump(t, w);
      await s.openNote('n1');
      s.openTaskTab('t1');
      s.openEventTab('e1');
      await t.pumpAndSettle();
      await t.tap(_k('bar-count'));
      await t.pumpAndSettle();
      _present(t, 'open grid', w, _k('open-grid'));
      _clean(t, 'open grid', w);
    });

    testWidgets('new note dialog $at', (t) async {
      await _pump(t, w);
      await _addDialog(t, 'add-note');
      _present(t, 'new note dialog', w, _k('new-note-title'));
      _clean(t, 'new note dialog', w);
    });

    testWidgets('new task dialog $at', (t) async {
      await _pump(t, w);
      await _addDialog(t, 'add-task');
      _present(t, 'new task dialog', w, _k('new-task-title'));
      _clean(t, 'new task dialog', w);
    });

    testWidgets('new event dialog $at', (t) async {
      await _pump(t, w);
      await _addDialog(t, 'add-event');
      _present(t, 'new event dialog', w, _k('new-event-title'));
      _clean(t, 'new event dialog', w);
    });
  }
}
