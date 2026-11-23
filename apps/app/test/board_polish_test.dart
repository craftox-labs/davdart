import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/key_nav.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/board_layout.dart';
import 'package:davdart_app/ui/home_day.dart';
import 'package:davdart_app/ui/theme.dart';
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

  group('Day shows dated tasks only', () {
    testWidgets('undated tasks are gone; overdue only on today', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [
          mkTask('undated'),
          mkTask('today', days: 0),
          mkTask('late', days: -3),
          mkTask('next', days: 1),
          mkTask('lateDone', days: -3, status: 'COMPLETED'),
        ],
      );
      expect(_k('home-today-tasks-undated'), findsNothing);
      expect(_k('home-today-tasks-nodate'), findsNothing);
      expect(_k('home-today-tasks-today'), findsOneWidget);
      expect(_k('home-today-tasks-late'), findsOneWidget);
      expect(_k('home-today-tasks-lateDone'), findsNothing);
      final n = DateTime.now().add(const Duration(days: 1));
      s.selectHomeDay(DateTime.utc(n.year, n.month, n.day));
      await t.pumpAndSettle();
      expect(_k('home-today-tasks-next'), findsOneWidget);
      expect(_k('home-today-tasks-late'), findsNothing);
      expect(_k('home-today-tasks-today'), findsNothing);
      expect(_k('home-today-tasks-undated'), findsNothing);
    });

    testWidgets('timezone edge: a UTC evening due is the next viewer day', (
      t,
    ) async {
      LocalZone.use('Pacific/Auckland'); // UTC+13 in November
      final s = await pumpTasksApp(
        t,
        tasks: [
          // 21 Nov 09:00 in Auckland, still 20 Nov in UTC.
          Task(
            uid: 'z',
            summary: 'Late UTC',
            due: const ICalDate('20261120T200000Z'),
            lastModified: DateTime.utc(2026, 11, 1),
          ),
          // 22 Nov 09:00 Auckland: overdue never, due on another day.
          Task(
            uid: 'y',
            summary: 'Later UTC',
            due: const ICalDate('20261121T200000Z'),
            lastModified: DateTime.utc(2026, 11, 1),
          ),
        ],
      );
      final clock = DateTime.utc(2026, 11, 20, 20, 30); // 21 Nov 09:30 there
      final tk = Tokens.light;
      await t.pumpWidget(
        FTheme(
          data: buildTheme(Brightness.light, touch: false, tokens: tk),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TokensScope(
              tokens: tk,
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => SizedBox(
                      width: 900,
                      height: 800,
                      child: HomeDayFocus(state: s, now: () => clock),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(_k('home-today-tasks-z'), findsOneWidget);
      expect(_k('home-today-tasks-y'), findsNothing);
    });
  });

  group('backlog column only when used', () {
    testWidgets('task board hides an empty backlog, shows a used one', (
      t,
    ) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('a')]);
      expect(
        [for (final c in s.taskColumns()) c.$1],
        ['todo', 'doing', 'done'],
      );
      await t.tap(_k('home-focus-tasks'));
      await t.pumpAndSettle();
      expect(_k('task-board-col-backlog'), findsNothing);
      await s.setTaskStatus('a', 'backlog');
      await t.pumpAndSettle();
      expect(_k('task-board-col-backlog'), findsOneWidget);
      expect(s.taskColumns().first.$1, 'backlog');
    });

    testWidgets('phone accordion has no empty backlog section', (t) async {
      await pumpTasksApp(t, size: const Size(400, 800), tasks: [mkTask('a')]);
      await t.tap(_k('home-focus-tasks'));
      await t.pumpAndSettle();
      expect(_k('board-acc-backlog'), findsNothing);
      expect(_k('board-acc-todo'), findsOneWidget);
    });

    testWidgets('a hidden backlog is still reachable by the status menu', (
      t,
    ) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('a')]);
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
      await pumpTasksApp(
        t,
        size: const Size(1280, 1600),
        tasks: [for (var i = 0; i < 13; i++) _done(i)],
      );
      await t.tap(_k('home-focus-tasks'));
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
      await pumpTasksApp(t, tasks: [for (var i = 0; i < 10; i++) _done(i)]);
      await t.tap(_k('home-focus-tasks'));
      await t.pumpAndSettle();
      expect(_k('board-done-show-all'), findsNothing);
    });

    testWidgets('phone accordion: capped with Show all', (t) async {
      await pumpTasksApp(
        t,
        size: const Size(400, 1600),
        tasks: [for (var i = 0; i < 12; i++) _done(i)],
      );
      await t.tap(_k('home-focus-tasks'));
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
      await pumpTasksApp(
        t,
        tasks: [
          mkTask('p', priority: 1, days: 3),
          mkTask('late', days: -2),
          mkTask('bare'),
        ],
      );
      await t.tap(_k('home-focus-tasks'));
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
      await pumpTasksApp(
        t,
        tasks: [
          mkTask('late', days: -2),
          mkTask('fin', days: -2, status: 'COMPLETED'),
        ],
      );
      await t.tap(_k('home-focus-tasks'));
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

    testWidgets('phone cards show the meta line too', (t) async {
      await pumpTasksApp(
        t,
        size: const Size(400, 800),
        tasks: [mkTask('a', priority: 5, days: 0)],
      );
      await t.tap(_k('home-focus-tasks'));
      await t.pumpAndSettle();
      expect(find.text('Medium'), findsOneWidget);
      expect(_k('card-due-a'), findsOneWidget);
    });
  });

  group('show all follow-ups', () {
    testWidgets('keyboard rows follow Show all and Show fewer', (t) async {
      AppState.debugDefaultFocus = HomeFocus.board;
      addTearDown(() => AppState.debugDefaultFocus = HomeFocus.day);
      final s = await pumpTasksApp(
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
      final s = await pumpTasksApp(
        t,
        size: const Size(1280, 1600),
        tasks: [for (var i = 0; i < 12; i++) _done(i)],
      );
      await t.tap(_k('home-focus-tasks'));
      await t.pumpAndSettle();
      await t.tap(_k('board-done-show-all'));
      await t.pumpAndSettle();
      expect(_k('task-card-d0'), findsOneWidget);
      await t.tap(_k('board-done-show-fewer'));
      await t.pumpAndSettle();
      expect(_k('task-card-d0'), findsNothing);
      expect(s.nav.taskBoardOpen.containsKey(boardDoneAllKey), isFalse);
    });

    test('a Space change clears Show all', () async {
      final prefs = MemoryStorage();
      final c = catalogWithPlanning(prefs, planningSeed: SeedNotes(const []));
      final s = AppState(c.sourceFor(c.current!), prefs: prefs, catalog: c);
      await s.load();
      s.nav.taskBoardOpen[boardDoneAllKey] = true;
      s.nav.boardOpen[boardDoneAllKey] = true;
      await s.createSpace('Inbox');
      expect(s.nav.taskBoardOpen.containsKey(boardDoneAllKey), isFalse);
      expect(s.nav.boardOpen.containsKey(boardDoneAllKey), isFalse);
    });

    testWidgets('meta line wraps instead of overflowing at 320', (t) async {
      await pumpTasksApp(
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
      await t.tap(_k('home-focus-tasks'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(t.getRect(_k('card-due-w')).right, lessThanOrEqualTo(320));
    });
  });

  group('home tag filter and column toggle', () {
    testWidgets('tag filter narrows cards, clears, and is saved per Space', (
      t,
    ) async {
      final prefs = MemoryStorage();
      final s = await pumpTasksApp(
        t,
        prefs: prefs,
        tasks: [
          mkTask('a', tags: ['red']),
          mkTask('b', tags: ['blue']),
        ],
      );
      await t.tap(_k('home-focus-tasks'));
      await t.pumpAndSettle();
      expect(_k('task-card-a'), findsOneWidget);
      expect(_k('task-card-b'), findsOneWidget);
      await t.tap(_k('home-tag-filter'));
      await t.pumpAndSettle();
      await t.tap(_k('home-tag-red'));
      await t.pumpAndSettle();
      expect(_k('task-card-a'), findsOneWidget);
      expect(_k('task-card-b'), findsNothing);
      expect(s.homeTag(HomeFocus.tasks), 'red');
      await t.tap(_k('home-tag-clear'));
      await t.pumpAndSettle();
      expect(_k('task-card-b'), findsOneWidget);
      expect(s.homeTag(HomeFocus.tasks), isNull);
    });

    testWidgets('hidden columns are saved and the last one stays', (t) async {
      final prefs = MemoryStorage();
      final s = await pumpTasksApp(t, prefs: prefs, tasks: [mkTask('a')]);
      await t.tap(_k('home-focus-tasks'));
      await t.pumpAndSettle();
      expect(_k('task-board-col-doing'), findsOneWidget);
      await t.tap(_k('home-cols'));
      await t.pumpAndSettle();
      await t.tap(_k('home-col-doing'));
      await t.pumpAndSettle();
      expect(_k('task-board-col-doing'), findsNothing);
      expect(_k('task-board-col-todo'), findsOneWidget);
      expect(s.homeHiddenCols(HomeFocus.tasks), {'doing'});
      s.toggleHomeCol(HomeFocus.tasks, 'todo');
      s.toggleHomeCol(HomeFocus.tasks, 'done');
      expect(s.taskColumns().map((c) => c.$1), ['done']);
      s.toggleHomeCol(HomeFocus.tasks, 'done'); // the last one stays
      expect(s.taskColumns().map((c) => c.$1), ['done']);
      s.toggleHomeCol(HomeFocus.tasks, 'doing');
      expect(s.taskColumns().map((c) => c.$1), ['doing', 'done']);
    });

    testWidgets('note board filters by tag and hides columns', (t) async {
      final s = await pumpTasksApp(
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
      await t.tap(_k('home-focus-board'));
      await t.pumpAndSettle();
      expect([for (final c in s.homeColumns()) c.$1], ['todo', 'doing']);
      s.setHomeTag(HomeFocus.board, 'red');
      expect(s.homeColumns().expand((c) => c.$2).map((n) => n.uid), ['n1']);
      s.setHomeTag(HomeFocus.board, null);
      s.toggleHomeCol(HomeFocus.board, 'todo');
      expect([for (final c in s.homeColumns()) c.$1], ['doing']);
    });

    testWidgets('absent hidden column stays listed; counts match the board', (
      t,
    ) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('a')]);
      s.toggleHomeCol(HomeFocus.tasks, 'blocked'); // absent: still saved
      final (names, hidden) = s.homeColumnChoices(HomeFocus.tasks);
      expect(names, ['todo', 'doing', 'done', 'blocked']);
      expect(hidden, isEmpty);
      for (final c in ['todo', 'doing', 'done']) {
        s.toggleHomeCol(HomeFocus.tasks, c);
      }
      expect(s.homeColumnChoices(HomeFocus.tasks).$2, {'todo', 'doing'});
      expect(s.taskColumns().length, 1);
    });

    testWidgets('tag and hidden columns survive a rebuilt state', (t) async {
      final prefs = MemoryStorage();
      final s = await pumpTasksApp(
        t,
        prefs: prefs,
        tasks: [
          mkTask('a', tags: ['red']),
        ],
      );
      s.setHomeTag(HomeFocus.tasks, 'red');
      s.toggleHomeCol(HomeFocus.tasks, 'doing');
      final s2 = await pumpTasksApp(
        t,
        prefs: prefs,
        tasks: [
          mkTask('a', tags: ['red']),
        ],
      );
      expect(s2.homeTag(HomeFocus.tasks), 'red');
      expect(s2.homeHiddenCols(HomeFocus.tasks), {'doing'});
      expect(s2.homeTag(HomeFocus.board), isNull);
    });

    testWidgets('bar wraps at phone width without overflow', (t) async {
      await pumpTasksApp(
        t,
        size: const Size(320, 800),
        tasks: [
          mkTask('a', tags: ['a-very-long-tag-name-indeed-yes']),
        ],
      );
      await t.tap(_k('home-focus-tasks'));
      await t.pumpAndSettle();
      await t.tap(_k('home-tag-filter'));
      await t.pumpAndSettle();
      await t.tap(_k('home-tag-a-very-long-tag-name-indeed-yes'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(_k('home-tag-clear'), findsOneWidget);
    });
  });
}
