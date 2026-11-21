import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

void main() {
  for (final w in [1280.0, 2400.0]) {
    testWidgets('item page at $w: wide column, title on its left edge', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('k1', summary: 'Pay rent')],
        size: Size(w, 900),
      );
      s.openTaskTab('k1');
      await t.pumpAndSettle();
      final column = t.getRect(_k('task-detail'));
      // A task's header starts with its checkbox, then the title.
      final check = t.getRect(
        find.descendant(of: _k('main-note'), matching: _k('task-check-k1')),
      );
      final cap = Tokens.light.sizes.pageMax;
      expect(cap, greaterThanOrEqualTo(1100));
      expect(column.width, lessThanOrEqualTo(cap + 0.5));
      if (w > 2000) expect(column.width, closeTo(cap, 0.5));
      // The header's first element lines up with the content column.
      expect(check.left, closeTo(column.left, 0.5));
      expect(t.takeException(), isNull);
    });

    testWidgets('a note at $w: title on the content column too', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          Note(uid: 'n1', summary: 'Alpha', description: 'Body text here'),
        ],
        size: Size(w, 900),
      );
      await s.openNote('n1', mode: OpenMode.main);
      await t.pumpAndSettle();
      final title = t.getRect(
        find.descendant(of: _k('main-note'), matching: _k('pane-title')),
      );
      final body = t.getRect(find.text('Body text here'));
      expect(title.left, closeTo(body.left, 0.5));
      expect(t.takeException(), isNull);
    });
  }
}
