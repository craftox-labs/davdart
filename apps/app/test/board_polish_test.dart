import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/key_nav.dart';
import 'package:davdart_app/ui/board_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'catalog_helper.dart';
import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Task _done(int i, {String? status}) => Task(
  uid: 'd$i',
  summary: 'Done $i',
  status: status ?? 'COMPLETED',
  lastModified: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
);

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));

  group('backlog column only when used', () {
    testWidgets('task board hides an empty backlog, shows a used one', (
      t,
    ) async {
      final s = await pumpHomeApp(t, tasks: [mkTask('a')]);
      s.setHomeKind(HomeKind.tasks);
      expect(
        [for (final c in s.homeColumns()) c.$1],
        ['todo', 'doing', 'done'],
      );
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(_k('board-drop-backlog'), findsNothing);
      await s.setTaskStatus('a', 'backlog');
      await t.pumpAndSettle();
      expect(_k('board-drop-backlog'), findsOneWidget);
      expect(s.homeColumns().first.$1, 'backlog');
    });

    testWidgets('phone accordion has no empty backlog section', (t) async {
      await pumpHomeApp(t, size: const Size(400, 800), tasks: [mkTask('a')]);
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(_k('board-acc-backlog'), findsNothing);
      expect(_k('board-acc-todo'), findsOneWidget);
    });

    testWidgets('a hidden backlog is still reachable by the status menu', (
      t,
    ) async {
      final s = await pumpHomeApp(t, tasks: [mkTask('a')]);
      await s.setTaskStatus('a', 'backlog');
      expect(s.taskById('a')!.boardStatus, 'backlog');
    });
  });

  group('done cap', () {
    test('boardCapped orders newest first and cuts at the cap', () {
      final items = [for (var i = 0; i < 14; i++) _done(i)];
      final cut = boardCapped('done', items, (x) => x.lastModified);
      expect(cut.length, boardDoneCap);
      expect(cut.first.uid, 'd13');
      expect(cut.last.uid, 'd4');
      expect(
        boardCapped('done', items, (x) => x.lastModified, showAll: true).length,
        14,
      );
      expect(boardCapped('todo', items, (x) => x.lastModified).length, 14);
    });

    testWidgets('wide: Show all (X) expands the done column', (t) async {
      await pumpHomeApp(
        t,
        size: const Size(1280, 1600),
        tasks: [for (var i = 0; i < 13; i++) _done(i)],
      );
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(_k('board-done-show-all'), findsOneWidget);
      expect(find.text('Show all (13)'), findsOneWidget);
      expect(_k('task-card-d12'), findsOneWidget);
      expect(_k('task-card-d2'), findsNothing);
      await t.tap(_k('board-done-show-all'));
      await t.pumpAndSettle();
      expect(_k('board-done-show-all'), findsNothing);
      expect(_k('task-card-d2'), findsOneWidget);
      expect(_k('task-card-d0'), findsOneWidget);
    });

    testWidgets('no control at or under the cap', (t) async {
      await pumpHomeApp(t, tasks: [for (var i = 0; i < 10; i++) _done(i)]);
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(_k('board-done-show-all'), findsNothing);
    });

    testWidgets('phone accordion: capped with Show all', (t) async {
      await pumpHomeApp(
        t,
        size: const Size(400, 1600),
        tasks: [for (var i = 0; i < 12; i++) _done(i)],
      );
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(find.text('Show all (12)'), findsOneWidget);
      await t.ensureVisible(_k('board-done-show-all'));
      await t.tap(_k('board-done-show-all'));
      await t.pumpAndSettle();
      expect(_k('board-done-show-all'), findsNothing);
    });
  });

  group('task card priority and due', () {
    testWidgets('shown when set, omitted when not', (t) async {
      await pumpHomeApp(
        t,
        tasks: [
          mkTask('p', priority: 1, days: 3),
          mkTask('late', days: -2),
          mkTask('bare'),
        ],
      );
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(_k('card-priority-p'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(_k('card-due-p'), findsOneWidget);
      expect(_k('card-priority-late'), findsNothing);
      expect(_k('card-due-late'), findsOneWidget);
      expect(_k('card-priority-bare'), findsNothing);
      expect(_k('card-due-bare'), findsNothing);
    });

    testWidgets('overdue due uses the error colour; done never', (t) async {
      await pumpHomeApp(
        t,
        tasks: [
          mkTask('late', days: -2),
          mkTask('fin', days: -2, status: 'COMPLETED'),
        ],
      );
      await showTasksBoard(t);
      await t.pumpAndSettle();
      Color col(String uid) => t
          .widget<Text>(
            find.descendant(
              of: _k('card-due-$uid'),
              matching: find.byType(Text),
            ),
          )
          .style!
          .color!;
      expect(col('late'), isNot(col('fin')));
    });

    testWidgets('phone cards show the meta line too, flag without word', (
      t,
    ) async {
      await pumpHomeApp(
        t,
        size: const Size(400, 800),
        tasks: [mkTask('a', priority: 5, days: 0)],
      );
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(find.text('Medium'), findsNothing);
      expect(_k('card-priority-a'), findsOneWidget);
      expect(_k('card-due-a'), findsOneWidget);
    });
  });

  group('show all follow-ups', () {
    testWidgets('keyboard rows follow Show all and Show fewer', (t) async {
      AppState.debugDefaultFocus = HomeFocus.board;
      addTearDown(() => AppState.debugDefaultFocus = HomeFocus.day);
      final s = await pumpHomeApp(
        t,
        size: const Size(1280, 2400),
        notes: [
          for (var i = 0; i < 13; i++)
            Note(
              uid: 'n$i',
              summary: 'Note $i',
              categories: const ['status-done'],
              lastModified: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
            ),
        ],
      );
      int rows() => s.nav
          .rowsOf(KeyNav.homeList)
          .where((e) => e.id.startsWith('card-'))
          .length;
      expect(rows(), boardDoneCap);
      await t.tap(_k('board-done-show-all'));
      await t.pumpAndSettle();
      expect(rows(), 13);
      await t.tap(_k('board-done-show-fewer'));
      await t.pumpAndSettle();
      expect(rows(), boardDoneCap);
      expect(_k('board-done-show-all'), findsOneWidget);
    });

    testWidgets('Show fewer collapses the done column again', (t) async {
      await pumpHomeApp(
        t,
        size: const Size(1280, 1600),
        tasks: [for (var i = 0; i < 12; i++) _done(i)],
      );
      await showTasksBoard(t);
      await t.pumpAndSettle();
      await t.tap(_k('board-done-show-all'));
      await t.pumpAndSettle();
      expect(_k('task-card-d0'), findsOneWidget);
      await t.tap(_k('board-done-show-fewer'));
      await t.pumpAndSettle();
      expect(_k('task-card-d0'), findsNothing);
    });

    test('a Space change clears Show all', () async {
      final prefs = MemoryStorage();
      final c = catalogWithPlanning(prefs, planningSeed: SeedNotes(const []));
      final s = AppState(c.sourceFor(c.current!), prefs: prefs, catalog: c);
      await s.load();
      s.nav.boardOpen[boardDoneAllKey] = true;
      await s.createSpace('Inbox');
      expect(s.nav.boardOpen.containsKey(boardDoneAllKey), isFalse);
    });

    testWidgets('meta line wraps instead of overflowing at 320', (t) async {
      await pumpHomeApp(
        t,
        size: const Size(320, 800),
        tasks: [
          Task(
            uid: 'w',
            summary: 'Wrap',
            priority: 5,
            due: const ICalDate('20200102T093000Z'),
            lastModified: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(t.getRect(_k('card-due-w')).right, lessThanOrEqualTo(320));
    });
  });

  group('home column toggle', () {
    testWidgets('hidden columns are saved and the last one stays', (t) async {
      final prefs = MemoryStorage();
      final s = await pumpHomeApp(t, prefs: prefs, tasks: [mkTask('a')]);
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(_k('board-drop-doing'), findsOneWidget);
      await t.tap(_k('home-cols'));
      await t.pumpAndSettle();
      await t.tap(_k('home-col-doing'));
      await t.pumpAndSettle();
      expect(_k('board-drop-doing'), findsNothing);
      expect(_k('board-drop-todo'), findsOneWidget);
      expect(s.homeHiddenCols(), {'doing'});
      s.toggleHomeCol('todo');
      s.toggleHomeCol('done');
      expect(s.homeColumns().map((c) => c.$1), ['done']);
      s.toggleHomeCol('done'); // the last one stays
      expect(s.homeColumns().map((c) => c.$1), ['done']);
      s.toggleHomeCol('doing');
      expect(s.homeColumns().map((c) => c.$1), ['doing', 'done']);
    });

    testWidgets('note board hides columns', (t) async {
      final s = await pumpHomeApp(
        t,
        notes: [
          Note(
            uid: 'n1',
            summary: 'One',
            categories: const ['status-todo', 'red'],
          ),
          Note(
            uid: 'n2',
            summary: 'Two',
            categories: const ['status-doing', 'blue'],
          ),
        ],
      );
      expect([for (final c in s.homeColumns()) c.$1], ['todo', 'doing']);
      s.toggleHomeCol('todo');
      expect([for (final c in s.homeColumns()) c.$1], ['doing']);
    });

    testWidgets('absent hidden column stays listed; counts match the board', (
      t,
    ) async {
      final s = await pumpHomeApp(t, tasks: [mkTask('a')]);
      s.setHomeKind(HomeKind.tasks);
      s.toggleHomeCol('blocked'); // absent: still saved
      final (names, hidden, _) = s.homeColumnChoices();
      expect(names, ['todo', 'doing', 'done', 'blocked']);
      expect(hidden, isEmpty);
      for (final c in ['todo', 'doing', 'done']) {
        s.toggleHomeCol(c);
      }
      expect(s.homeColumnChoices().$2, {'todo', 'doing'});
      expect(s.homeColumns().length, 1);
    });

    testWidgets('hidden columns survive a rebuilt state', (t) async {
      final prefs = MemoryStorage();
      final s = await pumpHomeApp(
        t,
        prefs: prefs,
        tasks: [
          mkTask('a', tags: ['red']),
        ],
      );
      s.toggleHomeCol('doing');
      final s2 = await pumpHomeApp(
        t,
        prefs: prefs,
        tasks: [
          mkTask('a', tags: ['red']),
        ],
      );
      expect(s2.homeHiddenCols(), {'doing'});
    });

    testWidgets('toggle is a header icon: wide only, badge when hidden', (
      t,
    ) async {
      final s = await pumpHomeApp(t, tasks: [mkTask('a')]);
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(_k('home-cols'), findsOneWidget);
      expect(_k('home-cols-badge'), findsNothing);
      s.toggleHomeCol('doing');
      await t.pumpAndSettle();
      expect(_k('home-cols-badge'), findsOneWidget);
      expect(_k('home-cols'), findsOneWidget);
    });

    testWidgets('phone layout has no toggle', (t) async {
      await pumpHomeApp(t, size: const Size(320, 800), tasks: [mkTask('a')]);
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(_k('home-cols'), findsNothing);
    });

    testWidgets('absent hidden column is unchecked and counted hidden', (
      t,
    ) async {
      final s = await pumpHomeApp(t, tasks: [mkTask('a')]);
      s.toggleHomeCol('blocked');
      await showTasksBoard(t);
      await t.pumpAndSettle();
      expect(
        find.descendant(of: _k('home-cols-badge'), matching: find.text('1')),
        findsOneWidget,
      );
      await t.tap(_k('home-cols'));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: _k('home-col-blocked'),
          matching: find.byIcon(FLucideIcons.check),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _k('home-col-todo'),
          matching: find.byIcon(FLucideIcons.check),
        ),
        findsOneWidget,
      );
    });
  });
}
