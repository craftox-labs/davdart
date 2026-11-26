import 'package:davdart/davdart.dart';
import 'package:davdart_app/ui/home_board.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));

  testWidgets('Tasks focus shows a board with a column per status', (t) async {
    await pumpHomeApp(
      t,
      tasks: [
        mkTask('a', summary: 'Open bug', status: 'NEEDS-ACTION'),
        mkTask('b', summary: 'Busy bug', status: 'IN-PROCESS'),
        mkTask('c', summary: 'Fixed bug', status: 'COMPLETED'),
      ],
    );
    expect(find.byType(HomeBoard), findsNothing);
    await showTasksBoard(t);
    await t.pumpAndSettle();
    expect(find.byType(HomeBoard), findsOneWidget);
    for (final c in ['todo', 'doing', 'done']) {
      expect(_k('board-drop-$c'), findsOneWidget);
    }
    expect(_k('board-drop-backlog'), findsNothing);
    expect(
      find.descendant(
        of: _k('board-drop-todo'),
        matching: find.text('Open bug'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _k('board-drop-doing'),
        matching: find.text('Busy bug'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _k('board-drop-done'),
        matching: find.text('Fixed bug'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'taskColumns follows the tag filter and keeps empty core columns, not backlog',
    (t) async {
      final state = await pumpHomeApp(
        t,
        tasks: [
          mkTask('a', summary: 'Tagged', tags: ['bug']),
          mkTask('b', summary: 'Plain'),
        ],
      );
      state.setTaskTagFilter('bug');
      state.setHomeKind(HomeKind.tasks);
      final cols = state.homeColumns();
      expect([for (final c in cols) c.$1], ['todo', 'doing', 'done']);
      expect([for (final x in cols[0].$2) x.title], ['Tagged']);
      expect(cols[1].$2, isEmpty);
    },
  );

  testWidgets(
    'backlog and blocked tags get columns; canceled has its own column',
    (t) async {
      final state = await pumpHomeApp(
        t,
        tasks: [
          mkTask('a', summary: 'Later', tags: ['status-backlog']),
          mkTask('b', summary: 'Stuck', tags: ['status-blocked']),
          mkTask('c', summary: 'Dropped', status: 'CANCELLED'),
          mkTask('r', summary: 'Shipped', tags: ['status-review']),
        ],
      );
      state.setHomeKind(HomeKind.tasks);
      expect([for (final c in state.homeColumns()) c.$1],
          ['backlog', 'todo', 'doing', 'blocked', 'review', 'done', 'canceled']);
      final cols = {for (final c in state.homeColumns()) c.$1: c.$2};
      expect([for (final x in cols['review']!) x.title], ['Shipped']);
      expect([for (final x in cols['backlog']!) x.title], ['Later']);
      expect([for (final x in cols['blocked']!) x.title], ['Stuck']);
      expect([for (final x in cols['canceled']!) x.title], ['Dropped']);
      expect(cols['done'], isEmpty);
    },
  );

  testWidgets('phone: one collapsible section per status, titles only', (
    t,
  ) async {
    await pumpHomeApp(
      t,
      size: const Size(400, 800),
      tasks: [
        mkTask('a', summary: 'Busy bug', status: 'IN-PROCESS'),
        mkTask('b', summary: 'Open bug'),
      ],
    );
    await showTasksBoard(t);
    await t.pumpAndSettle();
    expect(_k('board-accordion'), findsOneWidget);
    expect(find.text('Busy bug'), findsOneWidget); // doing starts open
    expect(find.text('Open bug'), findsNothing); // todo starts collapsed
  });

  testWidgets('wide Home: + adds the focus type, chevron lists all three', (
    t,
  ) async {
    await pumpHomeApp(t);
    // Day leads with an event; the chevron lists note, task and event.
    await t.tap(_k('home-add-more'));
    await t.pumpAndSettle();
    for (final k in ['home-add-event', 'home-add-note', 'home-add-task']) {
      expect(_k(k), findsOneWidget);
    }
    // Event, note, task: the order of the Day, Board and Tasks views.
    expect(
      t.getTopLeft(_k('home-add-event')).dy,
      lessThan(t.getTopLeft(_k('home-add-note')).dy),
    );
    expect(
      t.getTopLeft(_k('home-add-note')).dy,
      lessThan(t.getTopLeft(_k('home-add-task')).dy),
    );
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await showTasksBoard(t);
    await t.pumpAndSettle();
    await t.tap(_k('home-add'));
    await t.pumpAndSettle();
    expect(_k('new-task-title'), findsOneWidget);
    await pumpHomeApp(t, size: const Size(400, 800));
    expect(_k('home-add'), findsNothing);
    expect(_k('home-add-more'), findsNothing);
  });
}
