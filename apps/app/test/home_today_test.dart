import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/task_parts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

final _now = DateTime.now().toUtc();

List<Note> _notes() => [
  Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
  Note(
    uid: 'a',
    summary: 'Alpha',
    parentUid: 'f',
    description: 'status: doing\nbody',
    categories: ['status-doing'],
    lastModified: _now.subtract(const Duration(hours: 2)),
  ),
  Note(
    uid: 'b',
    summary: 'Beta',
    description: 'status: backlog\nbody',
    categories: ['status-backlog'],
    lastModified: _now.subtract(const Duration(days: 1, hours: 1)),
  ),
];

Finder _k(String k) => find.byKey(Key(k));

void main() {
  test('dueLabel', () {
    final now = DateTime(2026, 11, 20, 10);
    String l(int d) {
      final x = DateTime(2026, 11, 20).add(Duration(days: d));
      return dueLabel(
        Task(uid: 'x', due: ICalDate.date(x.year, x.month, x.day)),
        now,
      );
    }

    expect(l(0), 'Today');
    expect(l(1), 'Tomorrow');
    expect(l(-1), 'Yesterday');
    expect(l(4), 'Tue 24');
    expect(l(-3), 'Tue 17');
    expect(l(20), 'Thu 10 Dec');
    expect(dueLabel(Task(uid: 'x'), now), '');
  });

  test('dueOfDay keeps time and zone, all-day stays a date', () {
    final day = DateTime.utc(2026, 12, 5);
    final tz = dueOfDay(
      day,
      const ICalDate('20261120T093000', ';TZID=Europe/Berlin'),
    );
    expect(tz.value, '20261205T093000');
    expect(tz.params, ';TZID=Europe/Berlin');
    expect(
      dueOfDay(day, const ICalDate('20261120T093000Z')).value,
      '20261205T093000Z',
    );
    expect(
      dueOfDay(day, ICalDate.date(2026, 11, 20)),
      ICalDate.date(2026, 12, 5),
    );
    expect(dueOfDay(day), ICalDate.date(2026, 12, 5));
  });

  testWidgets('shows Doing rows and the Tasks panel, no Recently changed', (
    t,
  ) async {
    await pumpTasksApp(t, notes: _notes());
    expect(_k('home-today'), findsOneWidget);
    expect(_k('home-today-doing-a'), findsOneWidget);
    expect(_k('home-today-doing-b'), findsNothing);
    expect(_k('home-today-tasks'), findsOneWidget);
    expect(_k('home-today-recently-changed'), findsNothing);
    expect(_k('home-tasks-empty'), findsOneWidget);
    expect(_k('task-quick-add'), findsOneWidget);
  });

  testWidgets('Tasks panel: overdue, today, then next by due date, max 6', (
    t,
  ) async {
    await pumpTasksApp(
      t,
      tasks: [
        mkTask('later', days: 9),
        mkTask('nodate'),
        mkTask('late', days: -2),
        mkTask('today', days: 0),
        mkTask('soon', days: 2),
        mkTask('w2', days: 3),
        mkTask('w3', days: 4),
        mkTask('w4', days: 5),
        mkTask('done', days: -5, status: 'COMPLETED'),
      ],
    );
    final order = [
      for (final e
          in find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key as ValueKey<String>).value.startsWith(
                      'home-today-tasks-',
                    ),
              )
              .evaluate())
        (e.widget.key as ValueKey<String>).value.substring(17),
    ]..remove('toggle');
    expect(order, ['late', 'today', 'soon', 'w2', 'w3', 'w4']);
    expect(_k('home-today-tasks-done'), findsNothing);
    expect(_k('home-tasks-all'), findsOneWidget);
    expect(find.text('All tasks (8 open)'), findsOneWidget);
    // Overdue chip uses the error colour, due today the muted one.
    Color chipColor(String uid) => t
        .widget<Text>(
          find.descendant(of: _k('due-$uid'), matching: find.byType(Text)),
        )
        .style!
        .color!;
    expect(chipColor('late'), Tokens.light.error);
    expect(chipColor('today'), Tokens.light.muted);
    expect(find.text('Today'), findsWidgets);
  });

  testWidgets('checkbox completes a task and it leaves the panel', (t) async {
    final s = await pumpTasksApp(t, tasks: [mkTask('a', days: 0)]);
    await t.tap(_k('task-check-a'));
    await t.pumpAndSettle();
    expect(s.taskById('a')!.isCompleted, isTrue);
    expect(_k('home-today-tasks-a'), findsNothing);
  });

  testWidgets('a repeating task has a disabled checkbox with a reason', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      tasks: [mkTask('r', days: 0, rrule: 'FREQ=WEEKLY')],
    );
    expect(t.widget<FCheckbox>(_k('task-check-r')).enabled, isFalse);
    expect(_k('task-check-tip-r'), findsOneWidget);
    await t.tap(_k('task-check-r'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(s.taskById('r')!.isCompleted, isFalse);
    expect(s.taskCompletionBlockerFor('r'), isNotNull);
  });

  testWidgets('quick add creates an open task with no due date', (t) async {
    final s = await pumpTasksApp(t);
    await t.enterText(_k('task-quick-add'), 'Buy milk');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    final k = s.tasks.single;
    expect(k.summary, 'Buy milk');
    expect(k.due, isNull);
    expect(k.isClosed, isFalse);
    expect(_k('home-today-tasks-${k.uid}'), findsOneWidget);
  });

  testWidgets('empty Space: Tasks panel with quick add, no Doing', (t) async {
    await pumpTasksApp(t);
    expect(_k('home-today-doing'), findsNothing);
    expect(_k('home-today-tasks'), findsOneWidget);
    expect(_k('home-tasks-all'), findsNothing);
  });

  testWidgets('hidden when read-only and without tasks', (t) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = AppState(SeedNotes(const []), prefs: MemoryStorage());
    await t.pumpWidget(DavdartApp(state: s));
    await t.pumpAndSettle();
    expect(_k('home-today'), findsNothing);
  });

  testWidgets('read-only Space with tasks still lists them, checkbox off', (
    t,
  ) async {
    await pumpTasksApp(t, tasks: [mkTask('a', days: 0)], readOnly: true);
    expect(_k('home-today-tasks-a'), findsOneWidget);
    expect(t.widget<FCheckbox>(_k('task-check-a')).enabled, isFalse);
    expect(_k('task-quick-add'), findsNothing);
  });

  testWidgets('Doing panel hidden when nothing is doing', (t) async {
    await pumpTasksApp(t, notes: [_notes()[2]]);
    expect(_k('home-today-doing'), findsNothing);
    expect(_k('home-today-tasks'), findsOneWidget);
  });

  testWidgets('collapse persists', (t) async {
    final prefs = MemoryStorage();
    await pumpTasksApp(t, notes: _notes(), prefs: prefs);
    await t.tap(_k('home-today-toggle'));
    await t.pumpAndSettle();
    expect(_k('home-today-doing'), findsNothing);
    expect(_k('home-today'), findsOneWidget);
    expect(prefs.read('davdart.home.today.collapsed.v1'), 'true');
    await pumpTasksApp(t, notes: _notes(), prefs: prefs);
    expect(_k('home-today-doing'), findsNothing);
    expect(_k('home-today-toggle'), findsOneWidget);
  });

  testWidgets('Tasks panel collapses on its own', (t) async {
    final prefs = MemoryStorage();
    await pumpTasksApp(t, tasks: [mkTask('a', days: 0)], prefs: prefs);
    await t.tap(_k('home-today-tasks-toggle'));
    await t.pumpAndSettle();
    expect(_k('home-today-tasks-a'), findsNothing);
    expect(prefs.read('davdart.home.today.tasks.collapsed.v1'), 'true');
  });

  testWidgets('respects folder scope', (t) async {
    final s = await pumpTasksApp(
      t,
      notes: _notes(),
      tasks: [
        mkTask('in', days: 0, parent: 'f'),
        mkTask('out', days: 0),
      ],
    );
    expect(_k('home-today-tasks-out'), findsOneWidget);
    s.openFolder('f');
    await t.pumpAndSettle();
    expect(_k('home-today-tasks-in'), findsOneWidget);
    expect(_k('home-today-tasks-out'), findsNothing);
  });

  testWidgets('click opens the note, and a task per the setting', (t) async {
    final s = await pumpTasksApp(
      t,
      notes: _notes(),
      tasks: [mkTask('k', days: 0)],
    );
    await t.tap(_k('home-today-doing-a'));
    await t.pumpAndSettle();
    expect(s.peekUid ?? s.mainNoteUid, 'a');
    await t.tap(find.text('k').first);
    await t.pumpAndSettle();
    expect(s.peekUid, 'k');
    expect(_k('task-detail'), findsOneWidget);
  });

  testWidgets('not shown on a saved-view tab', (t) async {
    final s = await pumpTasksApp(t, notes: _notes());
    await t.runAsync(() => s.saveView('V'));
    s.applyView(s.savedViews.single);
    await t.pumpAndSettle();
    expect(s.activeTab, isNotNull);
    expect(_k('home-today'), findsNothing);
  });

  for (final w in [320.0, 880.0, 1280.0, 1911.0]) {
    testWidgets('no overflow at $w', (t) async {
      await pumpTasksApp(
        t,
        notes: _notes(),
        tasks: [
          mkTask('late', summary: 'A rather long overdue task title', days: -2),
          mkTask('today', days: 0, tags: ['home']),
        ],
        size: Size(w, 900),
      );
      expect(_k('home-today'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
