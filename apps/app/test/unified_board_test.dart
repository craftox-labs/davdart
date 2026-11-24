import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _note(
  String uid, {
  String? status = 'todo',
  String? priority,
  DateTime? created,
  String? title,
}) => Note(
  uid: uid,
  summary: title ?? 'Note $uid',
  description: [
    if (status != null) 'status: $status',
    if (priority != null) 'priority: $priority',
    if (status != null || priority != null) '',
    'body',
  ].join('\n'),
  categories: [if (status != null) 'status-$status'],
  created: created,
  lastModified: DateTime.now().toUtc(),
);

List<String> _titles(AppState s, String col) => [
  for (final i in s.homeColumns(all: true).firstWhere((c) => c.$1 == col).$2)
    i.title,
];

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() {
    LocalZone.use(null);
    AppState.debugDefaultFocus = HomeFocus.day;
  });

  group('sort order', () {
    final d1 = DateTime.utc(2026, 1, 1), d2 = DateTime.utc(2026, 1, 2);

    BoardItem n(String uid, {String? p, DateTime? created, String? title}) =>
        BoardItem.note(
          _note(uid, priority: p, created: created ?? d1, title: title),
        );
    BoardItem k(String uid, {int? p, int? days, DateTime? created}) =>
        BoardItem.task(
          Task(
            uid: uid,
            summary: 'Task $uid',
            priority: p,
            due: days == null ? null : dueIn(days),
            created: created ?? d1,
          ),
        );
    List<String> order(List<BoardItem> items) => [
      for (final i in ([...items]..sort(compareBoardItems))) i.uid,
    ];

    test('priority first for notes and tasks alike, then unset', () {
      expect(
        order([
          n('none'),
          k('low', p: 9),
          n('med', p: 'medium'),
          k('high', p: 2),
          n('high2', p: 'high', created: d2),
        ]),
        ['high', 'high2', 'med', 'low', 'none'],
      );
    });

    test('task numbers group 1-4 high, 5 medium, 6-9 low', () {
      expect(k('a', p: 4).priorityWord, 'high');
      expect(k('a', p: 5).priorityWord, 'medium');
      expect(k('a', p: 6).priorityWord, 'low');
      expect(k('a').priorityWord, isNull);
      // Same bucket: 1 and 4 tie, so they fall through to creation.
      expect(order([k('b', p: 4, created: d2), k('a', p: 1, created: d1)]), [
        'a',
        'b',
      ]);
    });

    test('due date earliest first, undated after dated, overdue not first', () {
      expect(
        order([
          k('none'),
          k('late', days: 5),
          k('overdue', days: -3),
          k('soon', days: 1),
        ]),
        ['overdue', 'soon', 'late', 'none'],
      );
      // A higher priority still beats an earlier due date.
      expect(order([k('early', p: 9, days: -9), k('urgent', p: 1, days: 9)]), [
        'urgent',
        'early',
      ]);
    });

    test('creation oldest first, then title', () {
      expect(order([n('b', created: d2), n('a', created: d1)]), ['a', 'b']);
      expect(order([n('x', title: 'Zed'), n('y', title: 'Abe')]), ['y', 'x']);
    });

    test('no manual rank yet (stage 2 seam)', () {
      expect(n('a').rank, isNull);
      expect(k('a').rank, isNull);
    });
  });

  group('merged board', () {
    testWidgets('notes and tasks with a status, grouped by status', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          _note('n1', status: 'todo'),
          _note('n2', status: 'doing'),
          _note('plain', status: null),
        ],
        tasks: [
          mkTask('t1', summary: 'Bug'),
          mkTask('t2', status: 'COMPLETED'),
        ],
      );
      final cols = {for (final c in s.homeColumns()) c.$1: c.$2};
      expect(cols.keys, ['todo', 'doing', 'done']);
      expect(_titles(s, 'todo'), ['Note n1', 'Bug']);
      expect([for (final i in cols['todo']!) i.isTask], [false, true]);
      // A note without a status never appears.
      expect([
        for (final c in cols.values)
          for (final i in c) i.uid,
      ], isNot(contains('plain')));
    });

    testWidgets('Done: newest modified first; canceled has its own column', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        tasks: [
          Task(
            uid: 'old',
            summary: 'Old',
            status: 'COMPLETED',
            lastModified: DateTime.utc(2026, 1, 1),
          ),
          Task(
            uid: 'new',
            summary: 'New',
            status: 'COMPLETED',
            lastModified: DateTime.utc(2026, 2, 1),
          ),
          mkTask('c', status: 'CANCELLED'),
        ],
      );
      expect(s.homeColumns().map((c) => c.$1), ['done', 'canceled']);
    });
  });

  group('kind filter', () {
    testWidgets('narrows the board; Tasks keeps the core columns', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [_note('n1', status: 'review')],
        tasks: [mkTask('t1', summary: 'Bug')],
      );
      expect(s.homeKind, HomeKind.all);
      expect(s.homeColumns().map((c) => c.$1), ['todo', 'review']);
      s.setHomeKind(HomeKind.notes);
      expect(s.homeColumns().map((c) => c.$1), ['review']);
      s.setHomeKind(HomeKind.tasks);
      expect(s.homeColumns().map((c) => c.$1), ['todo', 'doing', 'done']);
      expect([for (final i in s.homeItems) i.isTask], [true]);
    });

    testWidgets('dropdown: inactive on Day, glyph follows the kind', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [_note('n1')],
        tasks: [mkTask('t1', summary: 'Bug')],
      );
      // Day: the square keeps its place but does nothing.
      expect(_k('home-kind-icon-all'), findsOneWidget);
      await t.tap(_k('home-kind'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(_k('home-kind-tasks'), findsNothing);
      await t.tap(_k('home-focus-board'));
      await t.pumpAndSettle();
      await t.tap(_k('home-kind'));
      await t.pumpAndSettle();
      for (final k in ['all', 'notes', 'tasks']) {
        expect(_k('home-kind-$k'), findsOneWidget);
      }
      await t.tap(_k('home-kind-notes'));
      await t.pumpAndSettle();
      expect(s.homeKind, HomeKind.notes);
      expect(_k('home-kind-icon-notes'), findsOneWidget);
      expect(_k('card-kind-n1'), findsOneWidget);
      expect(_k('card-kind-t1'), findsNothing);
      await t.tap(_k('home-kind'));
      await t.pumpAndSettle();
      await t.tap(_k('home-kind-all'));
      await t.pumpAndSettle();
      expect(_k('card-kind-n1'), findsOneWidget);
      expect(_k('card-kind-t1'), findsOneWidget);
      expect(_k('home-kind-icon-all'), findsOneWidget);
    });

    testWidgets('+ leads with add-task on Tasks, add-note otherwise', (
      t,
    ) async {
      await pumpTasksApp(t);
      await t.tap(_k('home-focus-board'));
      await t.pumpAndSettle();
      await t.tap(_k('home-add'));
      await t.pumpAndSettle();
      expect(_k('new-task-title'), findsNothing);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      await t.tap(_k('home-kind'));
      await t.pumpAndSettle();
      await t.tap(_k('home-kind-tasks'));
      await t.pumpAndSettle();
      await t.tap(_k('home-add'));
      await t.pumpAndSettle();
      expect(_k('new-task-title'), findsOneWidget);
    });

    testWidgets('kind is remembered per Space; All clears it', (t) async {
      final prefs = MemoryStorage();
      final s = await pumpTasksApp(t, prefs: prefs);
      s.setHomeKind(HomeKind.notes);
      await t.pumpWidget(const SizedBox());
      final again = await pumpTasksApp(t, prefs: prefs);
      expect(again.homeKind, HomeKind.notes);
      again.setHomeKind(HomeKind.all);
      expect(
        prefs.read('davdart.home.kind.v1.default') ??
            prefs.read('davdart.home.kind.v1.s'),
        isNull,
      );
    });
  });

  group('pref migration', () {
    MemoryStorage legacy() => MemoryStorage()
      ..write('davdart.home.focus.v1.default', 'tasks')
      ..write('davdart.home.focus.v1.s', 'tasks')
      ..write('davdart.home.hidden.v1.tasks.default', 'doing')
      ..write('davdart.home.hidden.v1.tasks.s', 'doing');

    testWidgets("a saved 'tasks' focus loads as Board with Tasks", (t) async {
      final s = await pumpTasksApp(t, prefs: legacy(), tasks: [mkTask('a')]);
      expect(s.homeFocus, HomeFocus.board);
      expect(s.homeKind, HomeKind.tasks);
      expect(_k('home-kind-icon-tasks'), findsOneWidget);
      expect(find.byType(Column), findsWidgets);
      // The old Tasks view's hidden columns still apply.
      expect(s.homeHiddenCols(), {'doing'});
      expect(_k('board-drop-doing'), findsNothing);
      expect(_k('board-drop-todo'), findsOneWidget);
    });

    testWidgets('leaving the Board keeps the kind the old pref implied', (
      t,
    ) async {
      final s = await pumpTasksApp(t, prefs: legacy());
      s.setHomeFocus(HomeFocus.day);
      expect(s.homeFocus, HomeFocus.day);
      expect(s.homeKind, HomeKind.tasks);
      s.setHomeKind(HomeKind.all);
      expect(s.homeKind, HomeKind.all);
    });

    testWidgets('choosing All on a legacy pref sticks', (t) async {
      final s = await pumpTasksApp(t, prefs: legacy());
      s.setHomeKind(HomeKind.all);
      expect(s.homeKind, HomeKind.all);
    });
  });
}
