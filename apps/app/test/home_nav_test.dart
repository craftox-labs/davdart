import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/key_nav.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Future<void> _press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _shift(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(k);
  await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.pump(const Duration(milliseconds: 50));
}

final _j = LogicalKeyboardKey.keyJ;
final _k_ = LogicalKeyboardKey.keyK;
final _h = LogicalKeyboardKey.keyH;
final _l = LogicalKeyboardKey.keyL;

Note _note(String uid, String status) => Note(
  uid: uid,
  summary: 'Note $uid',
  description: 'status: $status\nbody',
  categories: ['status-$status'],
  lastModified: DateTime.now().toUtc(),
);

String? _cur(AppState s) => s.nav.cursorId(KeyNav.homeList);

Future<AppState> _home(
  WidgetTester t, {
  List<Task>? tasks,
  List<Event>? events,
  Size size = const Size(1280, 900),
}) async {
  final s = await pumpTasksApp(
    t,
    size: size,
    notes: [_note('n1', 'todo'), _note('n2', 'todo'), _note('n3', 'doing')],
    tasks: tasks ?? [mkTask('a', days: 0), mkTask('b', days: 0)],
    events: events ?? [mkEvent('e1', days: 0, hour: 9)],
  );
  await s.activateTab(null);
  await t.pumpAndSettle();
  s.nav.focusArea(NavArea.main, list: KeyNav.homeList, byKey: true);
  await t.pump();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Home grid, cards side by side', () {
    testWidgets('j k stay in the card; h l move between cards and columns', (
      t,
    ) async {
      final s = await _home(t);
      expect(_cur(s), 'task-a');
      await _press(t, _j);
      expect(_cur(s), 'task-b');
      await _press(t, _j); // clamps
      expect(_cur(s), 'task-b');
      await _press(t, _l); // same row number in the Events card, clamped
      expect(_cur(s), 'event-row-e1');
      await _press(t, _j);
      expect(_cur(s), 'event-row-e1');
      await _press(t, _k_);
      await _press(t, _h); // row 1 of Events is row 1 of Tasks
      expect(_cur(s), 'task-a');
    });

    testWidgets('} and { jump between Tasks, Events and Board', (t) async {
      final s = await _home(t);
      await _shift(t, LogicalKeyboardKey.bracketRight);
      expect(_cur(s), 'event-row-e1');
      await _shift(t, LogicalKeyboardKey.bracketRight);
      expect(_cur(s), 'card-n1'); // first card of the first column
      await _shift(t, LogicalKeyboardKey.bracketRight); // last section: stays
      expect(_cur(s), 'card-n1');
      await _shift(t, LogicalKeyboardKey.bracketLeft);
      expect(_cur(s), 'event-row-e1');
      await _shift(t, LogicalKeyboardKey.bracketLeft);
      expect(_cur(s), 'task-a');
      await _shift(t, LogicalKeyboardKey.bracketLeft); // first: stays
      expect(_cur(s), 'task-a');
    });

    testWidgets('board: j k inside a column, h l across columns', (t) async {
      final s = await _home(t);
      await _shift(t, LogicalKeyboardKey.bracketRight);
      await _shift(t, LogicalKeyboardKey.bracketRight);
      expect(_cur(s), 'card-n1');
      await _press(t, _j);
      expect(_cur(s), 'card-n2');
      await _press(t, _j); // column end: no flow when not stacked
      expect(_cur(s), 'card-n2');
      await _press(t, _l); // doing column, row 2 clamps to its only card
      expect(_cur(s), 'card-n3');
      await _press(t, _l); // rightmost: the area moves (no peek: stays)
      expect(s.nav.area, NavArea.main);
      await _press(t, _h);
      expect(_cur(s), 'card-n1');
      await _press(t, _h); // leftmost column: h moves to the panel
      expect(s.nav.area, NavArea.panel);
    });

    testWidgets('gg and G cover the whole Home; Enter and o open', (t) async {
      final s = await _home(t);
      await _shift(t, LogicalKeyboardKey.keyG);
      expect(_cur(s), 'card-n3');
      await _press(t, LogicalKeyboardKey.enter);
      expect(s.peekUid, 'n3');
      await _press(t, LogicalKeyboardKey.keyG);
      await _press(t, LogicalKeyboardKey.keyG);
      expect(_cur(s), 'task-a');
    });

    testWidgets('x completes a task row; O opens in main', (t) async {
      final s = await _home(t);
      await _press(t, LogicalKeyboardKey.keyX);
      await t.pumpAndSettle();
      expect(s.taskById('a')!.isClosed, isTrue);
    });

    testWidgets('completing the cursor task lands on the previous row', (
      t,
    ) async {
      final s = await _home(
        t,
        tasks: [mkTask('a', days: 0), mkTask('b', days: 0)],
      );
      await _press(t, _j);
      expect(_cur(s), 'task-b');
      await _press(t, LogicalKeyboardKey.keyX);
      await t.pumpAndSettle();
      expect(s.taskById('b')!.isClosed, isTrue);
      expect(_cur(s), 'task-a');
      await _press(t, _l); // h and l still work
      expect(_cur(s), 'event-row-e1');
      await _press(t, _h);
      expect(_cur(s), 'task-a');
    });

    testWidgets('completing the last task row moves on, keys keep working', (
      t,
    ) async {
      final s = await _home(t, tasks: [mkTask('a', days: 0)]);
      await _press(t, LogicalKeyboardKey.keyX);
      await t.pumpAndSettle();
      expect(s.taskById('a')!.isClosed, isTrue);
      expect(_cur(s), 'event-row-e1'); // the next block
      await _press(t, _j);
      expect(_cur(s), 'event-row-e1');
      await _shift(t, LogicalKeyboardKey.bracketRight);
      expect(_cur(s), 'card-n1');
      await _press(t, _l); // h and l work on the board
      expect(_cur(s), 'card-n3');
    });

    testWidgets('an empty card is skipped by } and h l', (t) async {
      final s = await _home(t, events: const []);
      await _shift(t, LogicalKeyboardKey.bracketRight);
      expect(_cur(s), 'card-n1');
      await _shift(t, LogicalKeyboardKey.bracketLeft);
      expect(_cur(s), 'task-a');
      await _press(t, _l); // no Events rows: nothing to the right
      expect(_cur(s), 'task-a');
    });

    testWidgets('no tasks and no events: } lands on the board', (t) async {
      final s = await _home(t, tasks: const [], events: const []);
      await _shift(t, LogicalKeyboardKey.bracketRight);
      expect(_cur(s), 'card-n1');
    });
  });

  group('Home grid, cards stacked', () {
    testWidgets('j k flow from Tasks into Events and the board and back', (
      t,
    ) async {
      final s = await _home(t, size: const Size(500, 900));
      expect(s.nav.homeStacked, isTrue);
      expect(_cur(s), 'task-a');
      await _press(t, _j);
      expect(_cur(s), 'task-b');
      await _press(t, _j); // end of Tasks: into Events
      expect(_cur(s), 'event-row-e1');
      // End of Events: into the board. On the accordion only the open
      // (doing) section has reachable cards; todo is closed.
      await _press(t, _j);
      expect(_cur(s), 'card-n3');
      await _press(t, _k_);
      expect(_cur(s), 'event-row-e1');
      await _press(t, _k_);
      expect(_cur(s), 'task-b');
    });

    testWidgets('l does not hop between stacked cards', (t) async {
      final s = await _home(t, size: const Size(500, 900));
      await _press(t, _l);
      expect(_cur(s), 'task-a');
    });
  });

  group('focus modality', () {
    testWidgets('cursor and area mark show after a key, hide on a click', (
      t,
    ) async {
      final s = await _home(t);
      await _press(t, _j);
      expect(s.nav.shown, isTrue);
      expect(_k('area-mark-main'), findsOneWidget);
      await t.tap(_k('home-today-tasks-a'));
      await t.pumpAndSettle();
      expect(s.nav.shown, isFalse);
      expect(_k('area-mark-main'), findsNothing);
      expect(_k('area-mark-peek'), findsNothing);
      // The handler is still alive: the next key shows the cursor again.
      expect(FocusManager.instance.primaryFocus, s.nav.node);
      await _press(t, _j);
      expect(s.nav.shown, isTrue);
    });

    testWidgets('a click on empty space hides it and keeps the keys', (
      t,
    ) async {
      final s = await _home(t);
      await _press(t, _j);
      await t.tapAt(const Offset(640, 880));
      await t.pumpAndSettle();
      expect(s.nav.shown, isFalse);
      expect(FocusManager.instance.primaryFocus, s.nav.node);
      await _press(t, _j);
      expect(s.nav.shown, isTrue);
    });

    testWidgets('Esc hides first, then moves the area up; a key shows again', (
      t,
    ) async {
      final s = await _home(t);
      await _press(t, _j);
      final at = _cur(s);
      await _press(t, LogicalKeyboardKey.escape);
      expect(s.nav.shown, isFalse);
      expect(s.nav.area, NavArea.main);
      await _press(t, LogicalKeyboardKey.escape);
      expect(s.nav.area, NavArea.panel);
      await _press(t, _l);
      expect(s.nav.area, NavArea.main);
      expect(_cur(s), at);
      expect(s.nav.shown, isTrue);
    });
  });

  group('Today card headers', () {
    for (final size in [const Size(1280, 900), const Size(500, 900)]) {
      testWidgets(
        'actions sit at the right edge of the card at ${size.width}',
        (t) async {
          await _home(t, size: size);
          for (final slug in ['tasks', 'events']) {
            final card = t.getRect(_k('home-today-$slug'));
            final add = t.getRect(_k('home-today-$slug-add'));
            final link = t.getRect(_k('home-today-$slug-all'));
            // The '+' ends at the card's padded right edge, the link just left
            // of it; neither floats in the middle.
            expect(card.right - add.right, lessThan(20), reason: slug);
            expect(add.left - link.right, lessThan(12), reason: slug);
            expect(link.left, greaterThan(card.center.dx), reason: slug);
            // Title and count stay at the left.
            expect(
              t.getRect(_k('home-today-$slug-count')).left - card.left,
              lessThan(card.width / 2),
            );
          }
        },
      );
    }
  });
}
