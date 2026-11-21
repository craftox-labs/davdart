import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/key_nav.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Future<void> _press(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

Note _long(String uid) => Note(
  uid: uid,
  summary: 'Long $uid',
  description: [for (var i = 0; i < 80; i++) 'Paragraph $i of text.']
      .join('\n\n'),
);

double _offset(AppState s, NavArea a) =>
    s.nav.pageScroll(a).positions.last.pixels;

void main() {
  testWidgets('j and k scroll a focused main item page, G and gg jump', (
    t,
  ) async {
    final s = await pumpTasksApp(t, notes: [_long('n1')]);
    await s.openNote('n1', mode: OpenMode.main);
    await t.pumpAndSettle();
    s.nav.focusArea(NavArea.main);
    s.nav.node.requestFocus();
    await t.pump();
    expect(_offset(s, NavArea.main), 0);
    await _press(t, LogicalKeyboardKey.keyJ);
    final one = _offset(s, NavArea.main);
    expect(one, greaterThan(0));
    await _press(t, LogicalKeyboardKey.keyJ);
    expect(_offset(s, NavArea.main), greaterThan(one));
    await _press(t, LogicalKeyboardKey.arrowDown);
    final three = _offset(s, NavArea.main);
    await _press(t, LogicalKeyboardKey.keyK);
    expect(_offset(s, NavArea.main), lessThan(three));
    // A count scrolls further.
    await _press(t, LogicalKeyboardKey.digit5);
    await _press(t, LogicalKeyboardKey.keyJ);
    expect(_offset(s, NavArea.main), greaterThan(three + 100));
    // End and G jump to the bottom, gg and Home to the top.
    await _press(t, LogicalKeyboardKey.end);
    final max = s.nav.pageScroll(NavArea.main).positions.last.maxScrollExtent;
    expect(_offset(s, NavArea.main), max);
    await _press(t, LogicalKeyboardKey.keyG);
    await _press(t, LogicalKeyboardKey.keyG);
    expect(_offset(s, NavArea.main), 0);
    await _press(t, LogicalKeyboardKey.home);
    expect(_offset(s, NavArea.main), 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('a short page does not scroll and lists still move the cursor', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      notes: [Note(uid: 's', summary: 'Short', description: 'tiny')],
      tasks: [mkTask('a'), mkTask('b')],
    );
    await s.openNote('s', mode: OpenMode.main);
    await t.pumpAndSettle();
    s.nav.focusArea(NavArea.main);
    s.nav.node.requestFocus();
    await t.pump();
    await _press(t, LogicalKeyboardKey.keyJ);
    expect(_offset(s, NavArea.main), 0);
    // In the panel's list j still moves the cursor, not the page.
    s.setSection(Section.tasks);
    await t.pumpAndSettle();
    s.nav.focusArea(NavArea.panel, list: 'tasks');
    s.nav.node.requestFocus();
    await t.pump();
    expect(s.nav.area, NavArea.panel);
    final before = s.nav.cursorEntry('tasks')?.id;
    await _press(t, LogicalKeyboardKey.keyJ);
    await _press(t, LogicalKeyboardKey.keyJ);
    expect(s.nav.cursorEntry('tasks')?.id, isNot(before));
    expect(_offset(s, NavArea.main), 0);
  });

  testWidgets('j and k scroll a focused peek page', (t) async {
    final s = await pumpTasksApp(t, notes: [_long('n1')]);
    s.select('n1');
    await t.pumpAndSettle();
    s.nav.focusArea(NavArea.peek);
    s.nav.node.requestFocus();
    await t.pump();
    await _press(t, LogicalKeyboardKey.keyJ);
    expect(_offset(s, NavArea.peek), greaterThan(0));
    await _press(t, LogicalKeyboardKey.keyK);
    expect(_offset(s, NavArea.peek), 0);
    expect(t.takeException(), isNull);
  });
}
