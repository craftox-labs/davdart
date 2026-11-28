import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:davdart_app/state/event_rules.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _note(String uid, String title, {double? rank, String? priority}) => Note(
  uid: uid,
  summary: title,
  description: [
    if (priority != null) 'priority: $priority',
    'status: todo',
    '',
    'body',
  ].join('\n'),
  categories: const ['status-todo'],
  lastModified: DateTime.utc(2026, 1, 1),
)..rank = rank;

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

String? _status(AppState s, String uid) =>
    PlanItem.fromNote(s.tree.find(uid)!.note).status;

void main() {
  setUp(() {
    LocalZone.use('Asia/Bangkok');
  });
  tearDown(() {
    LocalZone.use(null);
  });

  testWidgets('drop in another column toasts the item, Undo restores status', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final s = await pumpHomeApp(
      t,
      notes: [
        _note('a', 'Alpha', rank: 4),
        Note(uid: 'k', summary: 'Busy', description: 'status: doing\n\nx'),
      ],
    );
    await _drag(
      t,
      t.getCenter(_k('nav-card-a')),
      t.getCenter(_k('board-drop-doing')),
    );
    expect(_status(s, 'a'), 'doing');
    expect(find.text('Moved "Alpha" to doing'), findsOneWidget);
    await t.tap(_k('board-undo'));
    await t.pumpAndSettle();
    expect(_status(s, 'a'), 'todo');
    expect(s.tree.find('a')!.note.rank, 4);
  });

  testWidgets(
    'rank-only move says "in", Undo restores rank (null stays null)',
    (t) async {
      final s = await pumpHomeApp(
        t,
        notes: [_note('a', 'Alpha'), _note('b', 'Beta')],
      );
      expect(s.tree.find('b')!.note.rank, isNull);
      await s.placeBoardItem('b', 'todo', index: 0);
      await t.pumpAndSettle();
      expect(s.tree.find('b')!.note.rank, isNotNull);
      expect(find.text('Moved "Beta" in todo'), findsOneWidget);
      await t.tap(_k('board-undo'));
      await t.pumpAndSettle();
      expect(s.tree.find('b')!.note.rank, isNull);
      expect(_status(s, 'b'), 'todo');
    },
  );

  testWidgets('task menu Set priority toasts, Undo restores', (t) async {
    final s = await pumpHomeApp(
      t,
      tasks: [mkTask('t', summary: 'Fix it', priority: 5)],
    );
    await t.tap(
      find.descendant(of: _k('nav-card-t'), matching: find.text('Fix it')),
      buttons: kSecondaryButton,
    );
    await t.pumpAndSettle();
    await t.tap(_k('menu-priority'));
    await t.pumpAndSettle();
    await t.tap(_k('menu-priority-high'));
    await t.pumpAndSettle();
    expect(s.taskById('t')!.priority, 1);
    expect(find.text('Priority of "Fix it" set to High'), findsOneWidget);
    await t.tap(_k('board-undo'));
    await t.pumpAndSettle();
    expect(s.taskById('t')!.priority, 5);
  });

  testWidgets('a second change replaces the first undo; other edits stay', (
    t,
  ) async {
    final s = await pumpHomeApp(
      t,
      notes: [_note('a', 'Alpha'), _note('b', 'Beta')],
    );
    await s.setStatus('a', 'doing');
    final first = s.pendingUndo!;
    await s.setNotePriority('b', 'low');
    await t.pumpAndSettle();
    expect(identical(s.pendingUndo, first), isFalse);
    expect(find.text('Priority of "Beta" set to Low'), findsOneWidget);
    // The stale undo does nothing.
    await s.undoBoard(first);
    expect(_status(s, 'a'), 'doing');
    // A text edit in between survives the undo of the priority.
    await s.updateNote('b', title: 'Beta2');
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect(s.tree.find('b')!.note.summary, 'Beta2');
    expect(PlanItem.fromNote(s.tree.find('b')!.note).priorityWord, isNull);
  });

  testWidgets('undo of a move out of Done restores COMPLETED and percent', (
    t,
  ) async {
    final done = DateTime.utc(2026, 3, 4, 5, 6);
    final s = await pumpHomeApp(
      t,
      tasks: [
        Task(
          uid: 'd',
          summary: 'Shipped',
          status: 'COMPLETED',
          percentComplete: 100,
          completed: done,
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    expect(await s.setTaskStatus('d', 'doing'), isTrue);
    expect(s.taskById('d')!.completed, isNull);
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    final k = s.taskById('d')!;
    expect(k.status, 'COMPLETED');
    expect(k.completed, done);
    expect(k.percentComplete, 100);
  });

  testWidgets('undo of a drop restores neighbouring ranks too', (t) async {
    final s = await pumpHomeApp(
      t,
      notes: [
        _note('a', 'Alpha'),
        _note('b', 'Beta', rank: 2),
        _note('c', 'Gamma'),
      ],
    );
    final before = {
      for (final u in ['a', 'b', 'c']) u: s.tree.find(u)!.note.rank,
    };
    await s.placeBoardItem('c', 'todo', index: 0);
    await t.pumpAndSettle();
    expect({
      for (final u in ['a', 'b', 'c']) u: s.tree.find(u)!.note.rank,
    }, isNot(before));
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect({
      for (final u in ['a', 'b', 'c']) u: s.tree.find(u)!.note.rank,
    }, before);
  });

  testWidgets('undo back into Done respects the completion blocker', (t) async {
    final s = await pumpHomeApp(
      t,
      tasks: [
        Task(
          uid: 'r',
          summary: 'Weekly',
          status: 'COMPLETED',
          percentComplete: 100,
          completed: DateTime.utc(2026, 3, 4),
          rrule: 'FREQ=WEEKLY',
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    expect(await s.setTaskStatus('r', 'todo'), isTrue);
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect(s.taskById('r')!.status, 'NEEDS-ACTION');
    expect(s.error, contains('repeats'));
  });

  testWidgets('note priority undo restores a raw non-word line', (t) async {
    final s = await pumpHomeApp(
      t,
      notes: [_note('a', 'Alpha', priority: '3 (urgent)')],
    );
    await s.setNotePriority('a', 'high');
    expect(PlanItem.fromNote(s.tree.find('a')!.note).priorityWord, 'high');
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect(
      PlanItem.fromNote(s.tree.find('a')!.note).fields['priority'],
      '3 (urgent)',
    );
  });

  testWidgets('a due date pick toasts, Undo puts the old day back', (t) async {
    final s = await pumpTasksApp(
      t,
      tasks: [mkTask('t', summary: 'Fix it', days: 2)],
    );
    expect(await s.setTaskDue('t', dueIn(5)), isTrue);
    expect(s.taskById('t')!.due, dueIn(5));
    await t.pumpAndSettle();
    expect(find.text('Due date of "Fix it" changed'), findsOneWidget);
    await t.tap(_k('board-undo'));
    await t.pumpAndSettle();
    expect(s.taskById('t')!.due, dueIn(2));
    // Clearing it is undone the same way.
    expect(await s.setTaskDue('t', null), isTrue);
    await t.pumpAndSettle();
    expect(find.text('Due date of "Fix it" cleared'), findsOneWidget);
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect(s.taskById('t')!.due, dueIn(2));
  });

  testWidgets('a start date pick toasts, Undo clears it again', (t) async {
    final s = await pumpTasksApp(t, tasks: [mkTask('t', summary: 'Fix it')]);
    expect(await s.setTaskStart('t', dueIn(1)), isTrue);
    expect(s.taskById('t')!.dtstart, dueIn(1));
    await t.pumpAndSettle();
    expect(find.text('Start date of "Fix it" changed'), findsOneWidget);
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect(s.taskById('t')!.dtstart, isNull);
  });

  testWidgets('labels and the parent pick toast, Undo restores them', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      tasks: [
        mkTask('p', summary: 'Parent'),
        mkTask('c', summary: 'Child', tags: ['a']),
      ],
    );
    expect(await s.setTaskTags('c', ['b', 'd']), isTrue);
    expect(s.taskTagsOf(s.taskById('c')!), ['b', 'd']);
    await t.pumpAndSettle();
    expect(find.text('Labels of "Child" changed'), findsOneWidget);
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect(s.taskTagsOf(s.taskById('c')!), ['a']);
    expect(await s.setTaskParent('c', 'p'), isTrue);
    expect(s.taskById('c')!.parentUid, 'p');
    await t.pumpAndSettle();
    expect(find.text('Moved "Child"'), findsOneWidget);
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect(s.taskById('c')!.parentUid, isNull);
  });

  testWidgets('a parent move the rules refuse changes nothing', (t) async {
    final s = await pumpTasksApp(
      t,
      tasks: [
        mkTask('p', summary: 'Parent'),
        mkTask('c', summary: 'Child', parent: 'p'),
      ],
    );
    expect(await s.setTaskParent('p', 'c'), isFalse);
    expect(s.taskById('p')!.parentUid, isNull);
  });

  testWidgets('an event status pick toasts, Undo puts it back', (t) async {
    final s = await pumpTasksApp(
      t,
      events: [mkEvent('e', summary: 'Standup', status: 'CONFIRMED')],
    );
    expect(await s.setEventStatus('e', 'TENTATIVE'), isTrue);
    await t.pumpAndSettle();
    expect(s.eventById('e')!.status, 'TENTATIVE');
    expect(find.text('Status of "Standup" set to tentative'), findsOneWidget);
    await t.tap(_k('board-undo'));
    await t.pumpAndSettle();
    expect(s.eventById('e')!.status, 'CONFIRMED');
    // Clearing it is undone too.
    expect(await s.setEventStatus('e', null), isTrue);
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect(s.eventById('e')!.status, 'CONFIRMED');
  });

  testWidgets('an event when pick toasts, Undo puts the time back', (t) async {
    final s = await pumpTasksApp(
      t,
      events: [mkEvent('e', summary: 'Standup', days: 0, hour: 9)],
    );
    final before = eventWhenOf(s.eventById('e')!);
    final moved = eventStartMoved(before, minutes: 14 * 60);
    expect(await s.setEventWhen('e', moved), isTrue);
    await t.pumpAndSettle();
    expect(eventWhenOf(s.eventById('e')!).start.hour, 14);
    expect(find.text('When of "Standup" changed'), findsOneWidget);
    await t.tap(_k('board-undo'));
    await t.pumpAndSettle();
    final back = eventWhenOf(s.eventById('e')!);
    expect(back, before);
    // All day and back through the Undo restores the timed fields.
    expect(await s.setEventWhen('e', eventAllDaySwitched(back, true)), isTrue);
    expect(s.eventById('e')!.allDay, isTrue);
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect(s.eventById('e')!.allDay, isFalse);
    expect(eventWhenOf(s.eventById('e')!), before);
  });

  testWidgets('clearing an event repeat restores it and its exceptions', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      events: [
        Event(
          uid: 'e',
          summary: 'Weekly',
          dtstart: ICalDate('20261201T090000Z'),
          dtend: ICalDate('20261201T100000Z'),
          rrule: 'FREQ=WEEKLY',
          exdates: ['EXDATE:20261208T090000Z'],
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    expect(await s.setEventRrule('e', null), isTrue);
    await t.pumpAndSettle();
    expect(s.eventById('e')!.rrule, isNull);
    expect(s.eventById('e')!.exdates, isEmpty);
    expect(find.text('Repeat of "Weekly" cleared'), findsOneWidget);
    await t.tap(_k('board-undo'));
    await t.pumpAndSettle();
    expect(s.eventById('e')!.rrule, 'FREQ=WEEKLY');
    expect(s.eventById('e')!.exdates, ['EXDATE:20261208T090000Z']);
  });

  testWidgets('undo of an item deleted meanwhile does nothing', (t) async {
    final s = await pumpHomeApp(
      t,
      notes: [_note('a', 'Alpha')],
      tasks: [mkTask('t', summary: 'Fix', priority: 5)],
    );
    await s.setStatus('a', 'doing');
    final u1 = s.pendingUndo!;
    await s.deleteNote('a');
    await s.undoBoard(u1);
    expect(s.tree.find('a'), isNull);
    await s.setTaskPriority('t', 1);
    final u2 = s.pendingUndo!;
    await s.deleteTask('t');
    await s.undoBoard(u2);
    expect(s.taskById('t'), isNull);
  });
}
