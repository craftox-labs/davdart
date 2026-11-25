import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

void main() {
  tearDown(() => AppState.debugDefaultFocus = HomeFocus.day);

  // The web (and any non-desktop platform) used to stack submenus over
  // their row, so run the popup on android as well as linux.
  for (final p in [TargetPlatform.linux, TargetPlatform.android]) {
    testWidgets('task popup: submenus open to the right ($p)', (t) async {
      debugDefaultTargetPlatformOverride = p;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      AppState.debugDefaultFocus = HomeFocus.board;
      final s = await pumpTasksApp(t, tasks: [mkTask('t', summary: 'Fix it')]);
      await t.tap(
        find.descendant(of: _k('nav-card-t'), matching: find.text('Fix it')),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      for (final k in ['menu-task-status', 'menu-priority']) {
        final parent = t.getRect(_k(k));
        await t.tap(_k(k));
        await t.pumpAndSettle();
        final child = t.getRect(
          _k(
            k == 'menu-priority'
                ? 'menu-priority-high'
                : 'menu-task-status-todo',
          ),
        );
        expect(child.left, greaterThanOrEqualTo(parent.right - 1));
        expect(child.top, greaterThanOrEqualTo(parent.top - 1));
      }
      await t.tap(_k('menu-priority-medium'));
      await t.pumpAndSettle();
      expect(s.taskById('t')!.priority, 5);
    });
  }

  testWidgets('phone sheet: submenus are flat rows and tappable', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final s = await pumpTasksApp(
      t,
      tasks: [mkTask('k1', summary: 'Pay rent', priority: 1)],
      size: const Size(390, 844),
    );
    s.openTaskTab('k1');
    await t.pumpAndSettle();
    await t.tap(_k('item-more'));
    await t.pumpAndSettle();
    expect(_k('menu-sheet'), findsOneWidget);
    expect(find.text('Set status: todo'), findsOneWidget);
    expect(find.text('Set priority: High'), findsOneWidget);
    expect(_k('menu-priority'), findsNothing);
    await t.tap(_k('menu-priority-low'));
    await t.pumpAndSettle();
    expect(s.taskById('k1')!.priority, 9);
    expect(_k('menu-sheet'), findsNothing);
  });
}
