import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Note _note(
  String uid,
  String title, {
  String? status,
  String? priority,
  int day = 1,
}) => Note(
  uid: uid,
  summary: title,
  description: [
    if (status != null) 'status: $status',
    if (priority != null) 'priority: $priority',
    if (status != null || priority != null) '',
    'body',
  ].join('\n'),
  categories: [if (status != null) 'status-$status'],
  created: DateTime.utc(2026, 1, day),
);

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    _note('a', 'Old low', status: 'todo', priority: 'low', day: 1),
    _note('b', 'Plain', status: 'todo', day: 2),
    _note('c', 'New high', status: 'todo', priority: 'high', day: 3),
    _note('d', 'Mid', status: 'todo', priority: 'medium', day: 4),
    _note('e', 'Plain two', status: 'todo', day: 5),
    _note('s', 'Stray', status: 'in_progress', day: 6),
    _note('x', 'Stray two', status: 'wip', day: 7),
    _note('k', 'Cut', status: 'canceled', day: 8),
    _note('p', 'No status', priority: 'high', day: 9),
  ];
}

Finder _k(String k) => find.byKey(Key(k));

Future<AppState> _pump(WidgetTester t) async =>
    pumpHomeApp(t, notes: await _Seed().load());

void main() {
  test('review sits between doing and done in the fixed order', () {
    expect(boardOrder, [
      'backlog',
      'todo',
      'doing',
      'blocked',
      'review',
      'done',
      'canceled',
    ]);
    expect(statusColumn('review'), 'review');
  });

  group('columns', () {
    late AppState s;
    setUp(() async {
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      s = AppState(SpaceNoteSource(space, seed: _Seed()));
      await s.load();
    });

    test('fixed statuses in use, then Other, then no status', () {
      expect(
        [for (final c in s.columns()) c.$1],
        ['todo', 'canceled', 'other', 'notes'],
      );
      expect(
        [for (final c in s.columns(includeNoStatus: false)) c.$1],
        ['todo', 'canceled', 'other'],
      );
      final other = s.columns().firstWhere((c) => c.$1 == 'other').$2;
      expect([for (final n in other) n.uid], ['s', 'x']);
    });

    test('Other never rewrites the stray notes', () {
      expect(PlanItem.fromNote(s.tree.find('s')!.note).status, 'in_progress');
    });

    test('a column sorts priority first, then creation', () {
      final todo = s.columns().first.$2;
      expect([for (final n in todo) n.uid], ['c', 'd', 'a', 'b', 'e']);
    });
  });

  group('priority', () {
    test('setNotePriority writes the body line and keeps the header', () async {
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      final s = AppState(SpaceNoteSource(space, seed: _Seed()));
      await s.load();
      await s.setNotePriority('b', 'high');
      var p = PlanItem.fromNote(s.tree.find('b')!.note);
      expect(p.priority, 1);
      expect(p.status, 'todo');
      expect(p.text, 'body');
      await s.setNotePriority('b', null);
      p = PlanItem.fromNote(s.tree.find('b')!.note);
      expect(p.priorityWord, isNull);
      expect(p.status, 'todo');
    });

    testWidgets('the card shows the priority and the menu sets it', (t) async {
      final s = await _pump(t);
      s.setView(ViewMode.board);
      await t.pumpAndSettle();
      expect(_k('card-priority-c'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(_k('card-priority-b'), findsNothing);
      await t.tap(
        find.descendant(
          of: _k('board-drop-todo'),
          matching: find.text('Plain'),
        ),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      expect(_k('menu-status'), findsOneWidget);
      await t.tap(_k('menu-priority'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-priority-medium'));
      await t.pumpAndSettle();
      expect(PlanItem.fromNote(s.tree.find('b')!.note).priorityWord, 'medium');
      expect(
        find.descendant(
          of: _k('card-priority-b'),
          matching: find.text('Medium'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the priority row picks a word at once, and Undo puts it '
        'back', (t) async {
      final s = await _pump(t);
      s.select('b');
      await t.pumpAndSettle();
      expect(_k('property-priority'), findsOneWidget);
      await t.tap(_k('property-priority'));
      await t.pumpAndSettle();
      await t.tap(_k('property-option-priority-low'));
      await t.pumpAndSettle();
      expect(PlanItem.fromNote(s.tree.find('b')!.note).priorityWord, 'low');
      expect(PlanItem.fromNote(s.tree.find('b')!.note).status, 'todo');
      expect(find.text('Priority of "Plain" set to Low'), findsOneWidget);
      await t.tap(_k('board-undo'));
      await t.pumpAndSettle();
      expect(PlanItem.fromNote(s.tree.find('b')!.note).priorityWord, isNull);
      expect(PlanItem.fromNote(s.tree.find('b')!.note).status, 'todo');
    });
  });

  group('Other column', () {
    testWidgets('shows the stray words and is not a drop target', (t) async {
      final s = await _pump(t);
      s.setView(ViewMode.board);
      await t.pumpAndSettle();
      expect(find.text('OTHER'), findsOneWidget);
      expect(find.text('CANCELED'), findsOneWidget);
      expect(find.text('Stray'), findsWidgets);
      expect(find.text('Stray two'), findsWidgets);
      expect(_k('board-drop-other'), findsNothing);
      expect(_k('board-drop-canceled'), findsOneWidget);
      expect(_k('board-drop-backlog'), findsNothing, reason: 'unused');
    });
  });
}
