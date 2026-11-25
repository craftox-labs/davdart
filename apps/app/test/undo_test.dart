import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
    AppState.debugDefaultFocus = HomeFocus.board;
  });
  tearDown(() {
    LocalZone.use(null);
    AppState.debugDefaultFocus = HomeFocus.day;
  });

  testWidgets('drop in another column toasts the item, Undo restores status', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final s = await pumpTasksApp(
      t,
      notes: [
        _note('a', 'Alpha', rank: 4),
        Note(uid: 'k', summary: 'Busy', description: 'status: doing\n\nx'),
      ],
    );
    await t.tap(_k('home-focus-board'));
    await t.pumpAndSettle();
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
      final s = await pumpTasksApp(
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
    final s = await pumpTasksApp(
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
    final s = await pumpTasksApp(
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
}
