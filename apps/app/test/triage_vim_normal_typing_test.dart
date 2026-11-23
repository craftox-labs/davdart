import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

// Triage of bug a1ac1dfb: typing ordinary text into the note editor with Vim
// NORMAL active must not throw.
Finder _k(String k) => find.byKey(Key(k));

LogicalKeyboardKey _lk(String c) {
  if (c == ' ') return LogicalKeyboardKey.space;
  if (c == ',') return LogicalKeyboardKey.comma;
  return LogicalKeyboardKey.findKeyByKeyId(
        0x00000000000 + c.toLowerCase().codeUnitAt(0),
      ) ??
      LogicalKeyboardKey.keyA;
}

void main() {
  for (final text in ['body line from cod test', 'test,cod', 'Test note A']) {
    testWidgets('NORMAL-mode typing "$text" does not throw', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final AppState s = await pumpTasksApp(
        t,
        notes: [
          Note(
            uid: 'n1',
            summary: 'Note one',
            description: 'hello world\nsecond',
          ),
        ],
      );
      s.openNoteTab('n1');
      await t.pumpAndSettle();
      s.startEdit('n1');
      await t.pumpAndSettle();
      await t.tap(_k('edit-body'));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      for (final c in text.split('')) {
        final up = c != c.toLowerCase();
        if (up) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await t.sendKeyDownEvent(_lk(c), character: c);
        await t.sendKeyUpEvent(_lk(c));
        if (up) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
