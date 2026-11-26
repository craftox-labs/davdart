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
  Size size = const Size(1700, 900),
  bool board = false,
}) async {
  AppState.debugDefaultFocus = board ? HomeFocus.board : HomeFocus.day;
  final s = await pumpHomeApp(
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
  tearDown(() => AppState.debugDefaultFocus = HomeFocus.day);

  group('Home grid, cards side by side', () {
    testWidgets('j k flow Events into Tasks; h l do not hop', (t) async {
      final s = await _home(t);
      expect(_cur(s), 'event-row-e1'); // Events come first
      await _press(t, _l); // one stacked column: nothing beside
      expect(_cur(s), 'event-row-e1');
      await _press(t, _j);
      expect(_cur(s), 'task-a');
      await _press(t, _j);
      expect(_cur(s), 'task-b');
      await _press(t, _j); // last row: stays
      expect(_cur(s), 'task-b');
      await _press(t, _k_);
      await _press(t, _k_);
      expect(_cur(s), 'event-row-e1');
    });

    testWidgets('} and { jump between Events and Tasks', (t) async {
      final s = await _home(t);
      await _shift(t, LogicalKeyboardKey.bracketRight);
      expect(_cur(s), 'task-a');
      await _shift(t, LogicalKeyboardKey.bracketRight); // last section: stays
      expect(_cur(s), 'task-a');
      await _shift(t, LogicalKeyboardKey.bracketLeft);
      expect(_cur(s), 'event-row-e1');
      await _shift(t, LogicalKeyboardKey.bracketLeft); // first: stays
      expect(_cur(s), 'event-row-e1');
    });

    testWidgets('Board focus: j k inside a column, h l across columns', (
      t,
    ) async {
      final s = await _home(t, board: true, tasks: const []);
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

    testWidgets('gg and G cover the Day rows and the Board; Enter opens', (
      t,
    ) async {
      final s = await _home(t);
      await _shift(t, LogicalKeyboardKey.keyG);
      expect(_cur(s), 'task-b');
      await _press(t, LogicalKeyboardKey.enter);
      expect(s.peekUid, isNotNull);
      await _press(t, LogicalKeyboardKey.keyG);
      await _press(t, LogicalKeyboardKey.keyG);
      expect(_cur(s), 'event-row-e1');
      final b = await _home(t, board: true, tasks: const []);
      await _shift(t, LogicalKeyboardKey.keyG);
      expect(_cur(b), 'card-n3');
    });

    testWidgets('x completes a task row; O opens in main', (t) async {
      final s = await _home(t);
      await _press(t, _j); // from the event to task-a
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
      await _press(t, _j);
      expect(_cur(s), 'task-b');
      await _press(t, LogicalKeyboardKey.keyX);
      await t.pumpAndSettle();
      expect(s.taskById('b')!.isClosed, isTrue);
      expect(_cur(s), 'task-a');
      await _press(t, _k_);
      expect(_cur(s), 'event-row-e1');
    });

    testWidgets('completing the last task row moves on, keys keep working', (
      t,
    ) async {
      final s = await _home(t, tasks: [mkTask('a', days: 0)]);
      await _press(t, _j);
      expect(_cur(s), 'task-a');
      await _press(t, LogicalKeyboardKey.keyX);
      await t.pumpAndSettle();
      expect(s.taskById('a')!.isClosed, isTrue);
      expect(_cur(s), 'event-row-e1'); // the previous block
      await _press(t, _j);
      expect(s.nav.area, NavArea.main);
    });

    testWidgets('an empty card is skipped by } and h l', (t) async {
      final s = await _home(t, events: const []);
      await _shift(t, LogicalKeyboardKey.bracketRight);
      expect(_cur(s), 'task-a'); // no Events rows: stays
      await _press(t, _l); // nothing to the right
      expect(_cur(s), 'task-a');
    });
  });

  group('Home grid, cards stacked', () {
    testWidgets('j k flow from Events into Tasks and back', (t) async {
      final s = await _home(t, size: const Size(500, 900));
      expect(s.nav.homeStacked, isTrue);
      expect(_cur(s), 'event-row-e1');
      await _press(t, _j);
      expect(_cur(s), 'task-a');
      await _press(t, _j);
      expect(_cur(s), 'task-b');
      await _press(t, _j); // end of Tasks: stays
      expect(_cur(s), 'task-b');
      await _press(t, _k_);
      await _press(t, _k_);
      expect(_cur(s), 'event-row-e1');
    });

    testWidgets('Board accordion: opening todo makes its cards reachable', (
      t,
    ) async {
      final s = await _home(t, size: const Size(500, 900), board: true, tasks: const []);
      expect(_cur(s), 'card-n3'); // only the open (doing) section
      await t.tap(find.byKey(const Key('board-acc-todo-toggle')));
      await t.pumpAndSettle();
      await _press(t, LogicalKeyboardKey.keyG);
      await _press(t, LogicalKeyboardKey.keyG);
      expect(_cur(s), 'card-n1');
      await _press(t, _j);
      expect(_cur(s), 'card-n2');
    });

    testWidgets('l does not hop between stacked sections', (t) async {
      final s = await _home(t, size: const Size(500, 900));
      await _press(t, _l);
      expect(_cur(s), 'event-row-e1');
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

  group('Section headers', () {
    for (final size in [const Size(1280, 900), const Size(500, 900)]) {
      testWidgets(
        'link and + sit at the right end of the header at ${size.width}',
        (t) async {
          await _home(t, size: size);
          for (final slug in ['tasks', 'events']) {
            final card = t.getRect(_k('home-today-$slug'));
            final toggle = t.getRect(_k('home-today-$slug-toggle'));
            final add = t.getRect(_k('home-today-$slug-add'));
            final link = t.getRect(_k('home-today-$slug-all'));
            // The header is outside the card, above it, as wide as the card.
            expect(
              toggle.bottom,
              lessThanOrEqualTo(card.top + 0.5),
              reason: slug,
            );
            expect(card.right - add.right, lessThan(20), reason: slug);
            expect(add.left - link.right, lessThan(12), reason: slug);
            expect(link.left, greaterThan(card.center.dx), reason: slug);
            expect(toggle.left - card.left, lessThan(card.width / 2));
          }
        },
      );
    }
  });
}
