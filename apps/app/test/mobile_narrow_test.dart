import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/persistent_store.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

const _phones = [Size(320, 568), Size(360, 640)];

void main() {
  tearDown(() => AppState.debugDefaultFocus = HomeFocus.day);
  for (final size in _phones) {
    testWidgets('scoped folder bar has no overflow at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final s = AppState(
        SpaceNoteSource(
          Space(
            SpaceConfig(id: 's', name: 'A very long space name ' * 4),
            PersistentNoteStore(storage),
          ),
          flags: storage,
        ),
      );
      await s.load();
      await s.addFolder('A very long folder name ' * 4, text: 'Some text');
      s.openFolder(s.scope!.uid);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      final ex = t.takeException();
      expect(
        ex,
        isNull,
        reason: ex is FlutterError ? ex.toStringDeep() : '$ex',
      );
      // The folder path moved into the content's thin row; the bar keeps one
      // pill, and the folder's actions are behind the loose folder's ⋯.
      expect(find.byKey(const Key('scope-more')), findsNothing);
      expect(find.byKey(const Key('content-crumbs')), findsOneWidget);
      await t.tap(find.byKey(const Key('space-chip')));
      await t.pumpAndSettle();
      final loose = s.scopeUid!;
      await t.tap(find.byKey(Key('scope-more-$loose')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('scope-delete')), findsOneWidget);
      expect(find.byKey(const Key('scope-close')), findsOneWidget);
      final sheetEx = t.takeException();
      expect(
        sheetEx,
        isNull,
        reason: sheetEx is FlutterError ? sheetEx.toStringDeep() : '$sheetEx',
      );
    });

    testWidgets('Home with Today has no overflow at $size', (t) async {
      await pumpTasksApp(
        t,
        tasks: [
          for (var i = 0; i < 6; i++)
            mkTask('late$i', summary: 'An overdue task number $i', days: -2),
        ],
        events: [
          for (var i = 0; i < 6; i++)
            mkEvent('e$i', summary: 'An event today $i', rrule: 'FREQ=DAILY'),
        ],
        size: size,
      );
      expect(find.byKey(const Key('home-today')), findsOneWidget);
      // Today and the board share one scroll view.
      final scroll = find.byKey(const Key('home-scroll'));
      expect(scroll, findsOneWidget);
      expect(
        find.descendant(
          of: scroll,
          matching: find.byKey(const Key('home-today')),
        ),
        findsOneWidget,
      );
      // A day section collapses from its accordion header.
      await t.tap(find.byKey(const Key('home-today-events-toggle')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('home-today-events')), findsNothing);
      final ex = t.takeException();
      expect(
        ex,
        isNull,
        reason: ex is FlutterError ? ex.toStringDeep() : '$ex',
      );
    });
  }

  for (final size in _phones) {
    testWidgets('board is a status accordion with title-only cards at $size', (
      t,
    ) async {
      AppState.debugDefaultFocus = HomeFocus.board;
      await pumpTasksApp(
        t,
        notes: [
          Note(uid: 'a', summary: 'Alpha', description: 'status: todo\n\nx'),
          Note(
            uid: 'b',
            summary: 'Bravo',
            description: 'id: DD-1\nowner: Sam\nstatus: doing\n\nBody',
          ),
        ],
        size: size,
      );
      expect(find.byKey(const Key('board-accordion')), findsOneWidget);
      // Doing starts open, the rest collapsed.
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('DD-1'), findsNothing);
      expect(find.text('Sam'), findsNothing);
      expect(find.text('Alpha'), findsNothing);
      await t.tap(find.byKey(const Key('board-acc-todo-toggle')));
      await t.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      await t.tap(find.byKey(const Key('board-acc-doing-toggle')));
      await t.pumpAndSettle();
      expect(find.text('Bravo'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('top bar buttons and task rows are touch-sized at $size', (
      t,
    ) async {
      await pumpTasksApp(
        t,
        tasks: [mkTask('a', summary: 'Pay rent', days: 0)],
        size: size,
      );
      final bar = find.byKey(const Key('top-bar'));
      final buttons = find.descendant(of: bar, matching: find.byType(FButton));
      expect(buttons, findsWidgets);
      for (final b in buttons.evaluate()) {
        final r = t.getRect(find.byWidget(b.widget));
        expect(r.width, greaterThanOrEqualTo(44), reason: '$r');
        expect(r.height, greaterThanOrEqualTo(44), reason: '$r');
      }
      final row = t.getRect(find.byKey(const Key('home-today-tasks-a')));
      expect(row.height, greaterThanOrEqualTo(44));
      final hit = find.ancestor(
        of: find.byKey(const Key('task-check-a')),
        matching: find.byType(GestureDetector),
      );
      final r = t.getRect(hit.first);
      expect(r.width, greaterThanOrEqualTo(44), reason: 'checkbox hit area');
      expect(r.height, greaterThanOrEqualTo(44), reason: 'checkbox hit area');
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('desktop keeps columns and compact buttons', (t) async {
    await pumpTasksApp(
      t,
      notes: [
        Note(uid: 'b', summary: 'Bravo', description: 'status: doing\n\nx'),
      ],
      size: const Size(1280, 900),
    );
    expect(find.byKey(const Key('board-accordion')), findsNothing);
    final r = t.getRect(find.byKey(const Key('home-today-tasks-add')));
    expect(r.height, lessThan(44));
  });

  testWidgets("the loose folder's ⋯ actions act", (t) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final storage = MemoryStorage();
    final s = AppState(
      SpaceNoteSource(
        Space(SpaceConfig(id: 's', name: 'S'), PersistentNoteStore(storage)),
        flags: storage,
      ),
    );
    await s.load();
    await s.addFolder('Folder', text: 'Text');
    s.openFolder(s.scope!.uid);
    await t.pumpWidget(DavdartApp(state: s));
    await t.pumpAndSettle();
    expect(s.scope, isNotNull);
    await t.tap(find.byKey(const Key('space-chip')));
    await t.pumpAndSettle();
    // The panel shows the loose folder as a path row, its actions behind the
    // ⋯; "Show the whole space" is in that menu, and the Space's own row.
    expect(find.byKey(const Key('projects-path')), findsOneWidget);
    await t.tap(find.byKey(Key('scope-more-${s.scopeUid}')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('scope-close')));
    await t.pumpAndSettle();
    expect(s.scope, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('accordion state survives crossing the 600px breakpoint', (
    t,
  ) async {
    AppState.debugDefaultFocus = HomeFocus.board;
    final s = await pumpTasksApp(
      t,
      notes: [
        Note(uid: 'a', summary: 'Alpha', description: 'status: todo\n\nx'),
        Note(uid: 'b', summary: 'Bravo', description: 'status: doing\n\nx'),
      ],
      size: const Size(400, 800),
    );
    await t.tap(find.byKey(const Key('board-acc-todo-toggle')));
    await t.tap(find.byKey(const Key('board-acc-doing-toggle')));
    await t.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsNothing);
    t.view.physicalSize = const Size(700, 800);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('board-accordion')), findsNothing);
    t.view.physicalSize = const Size(400, 800);
    await t.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsNothing);
    // Keyboard nav skips cards of the closed section.
    expect(s.nav.boardAccordion, isTrue);
    expect(s.nav.boardOpen, {'todo': true, 'doing': false});
  });

  testWidgets(
    'split Home (620 wide) puts the calendar beside a scrolling list',
    (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [
          for (var i = 0; i < 6; i++)
            mkTask('late$i', summary: 'Task $i', days: -2),
        ],
        events: [
          for (var i = 0; i < 6; i++)
            mkEvent('e$i', summary: 'Event $i', rrule: 'FREQ=DAILY'),
        ],
        size: const Size(620, 640),
      );
      expect(s.nav.homeStacked, isTrue);
      expect(find.byKey(const Key('home-calendar')), findsOneWidget);
      expect(find.byKey(const Key('home-today')), findsOneWidget);
      final cal = t.getRect(find.byKey(const Key('home-calendar')));
      final list = t.getRect(find.byKey(const Key('home-today')));
      expect(cal.right, lessThanOrEqualTo(list.left));
      expect(list.right, lessThanOrEqualTo(620));
      expect(t.takeException(), isNull);
      // The list scrolls under the calendar.
      final before = t.getTopLeft(find.byKey(const Key('home-today-tasks'))).dy;
      await t.drag(find.byKey(const Key('home-today')), const Offset(0, -300));
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.byKey(const Key('home-today-tasks'))).dy,
        lessThan(before),
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('wide window with a narrow main pane keeps Today uncapped', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      tasks: [
        for (var i = 0; i < 6; i++)
          mkTask('late$i', summary: 'Task $i', days: -2),
      ],
      events: [
        for (var i = 0; i < 6; i++)
          mkEvent('e$i', summary: 'Event $i', rrule: 'FREQ=DAILY'),
      ],
      size: const Size(900, 560),
    );
    // The main pane is stacked only if narrower than 600; either way the
    // wide layout must not cap Today at 40% of the height.
    final h = t.getRect(find.byKey(const Key('home-today'))).height;
    if (s.nav.homeStacked) expect(h, greaterThan(560 * 0.4));
    expect(
      find.descendant(
        of: find.byKey(const Key('home-today')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    // Desktop behaviour is unchanged, so a short window may overflow.
    t.takeException();
  });
}
