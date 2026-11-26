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
final _h = LogicalKeyboardKey.keyH;
final _l = LogicalKeyboardKey.keyL;

String? _cur(AppState s) => s.nav.cursorId(KeyNav.homeList);

/// The project's Board tab, narrowed to tasks, focused on the keyboard.
Future<AppState> _board(WidgetTester t) async {
  final s = await pumpHomeApp(
    t,
    tasks: [
      mkTask('a', summary: 'A', days: 0),
      mkTask('b', summary: 'B', days: 0),
      mkTask('c', summary: 'C', days: 0, status: 'IN-PROCESS'),
    ],
  );
  await showTasksBoard(t);
  s.nav.focusArea(NavArea.main, list: KeyNav.homeList, byKey: true);
  await t.pump();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('j k move inside a column; h l cross columns', (t) async {
    final s = await _board(t);
    expect(_cur(s), 'card-a');
    await _press(t, _j);
    expect(_cur(s), 'card-b');
    await _press(t, _j); // column end: no flow when not stacked
    expect(_cur(s), 'card-b');
    await _press(t, _l); // doing column's only card
    expect(_cur(s), 'card-c');
    await _press(t, _l); // right edge: stays in the board
    expect(s.nav.area, NavArea.main);
    expect(_cur(s), 'card-c');
    await _press(t, _h);
    expect(_cur(s), 'card-a');
  });

  testWidgets('gg and G cover the columns; Enter opens the card', (t) async {
    final s = await _board(t);
    await _shift(t, LogicalKeyboardKey.keyG);
    expect(_cur(s), 'card-c');
    await _press(t, LogicalKeyboardKey.keyG);
    await _press(t, LogicalKeyboardKey.keyG);
    expect(_cur(s), 'card-a');
    await _press(t, LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(s.peekUid, 'a');
  });

  testWidgets('x completes the cursor task', (t) async {
    final s = await _board(t);
    await _press(t, _j);
    expect(_cur(s), 'card-b');
    await _press(t, LogicalKeyboardKey.keyX);
    await t.pumpAndSettle();
    expect(s.taskById('b')!.isClosed, isTrue);
    // It moves to Done; the cursor keeps it.
    expect(_cur(s), 'card-b');
  });

  testWidgets('focus modality shows after a key and hides on a click', (
    t,
  ) async {
    final s = await _board(t);
    await _press(t, _j);
    expect(s.nav.shown, isTrue);
    expect(_k('area-mark-main'), findsOneWidget);
    await t.tap(_k('nav-card-a'));
    await t.pumpAndSettle();
    expect(s.nav.shown, isFalse);
    expect(_k('area-mark-main'), findsNothing);
    expect(FocusManager.instance.primaryFocus, s.nav.node);
    await _press(t, _j);
    expect(s.nav.shown, isTrue);
  });
}
