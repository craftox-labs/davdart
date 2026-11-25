import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

const _phone = Size(390, 844);

Finder _k(String k) => find.byKey(Key(k));

/// The check that marks the current choice of a submenu.
Finder _marked(String k) =>
    find.descendant(of: _k(k), matching: find.byIcon(FLucideIcons.check));

Note _note(String uid, String title, {String? priority}) => Note(
  uid: uid,
  summary: title,
  description: [
    if (priority != null) 'priority: $priority',
    'status: todo',
    '',
    'body',
  ].join('\n'),
  categories: const ['status-todo'],
  lastModified: DateTime.utc(2026, 1, 1),
);

String? _word(AppState s, String uid) =>
    PlanItem.fromNote(s.tree.find(uid)!.note).priorityWord;

void main() {
  tearDown(() => AppState.debugDefaultFocus = HomeFocus.day);

  group('task context menu', () {
    testWidgets('each priority is set, cleared and marked current', (
      t,
    ) async {
      AppState.debugDefaultFocus = HomeFocus.board;
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('t', summary: 'Fix it')],
      );
      Future<void> openSubmenu() async {
        await t.tap(
          find.descendant(of: _k('nav-card-t'), matching: find.text('Fix it')),
          buttons: kSecondaryButton,
        );
        await t.pumpAndSettle();
        expect(_k('menu-priority'), findsOneWidget);
        await t.tap(_k('menu-priority'));
        await t.pumpAndSettle();
      }

      await openSubmenu();
      // A task with no priority: No priority is the current row.
      expect(_marked('menu-priority-none'), findsOneWidget);
      for (final (bucket, p) in [('high', 1), ('medium', 5), ('low', 9)]) {
        await t.tap(_k('menu-priority-$bucket'));
        await t.pumpAndSettle();
        expect(s.taskById('t')!.priority, p, reason: bucket);
        await openSubmenu();
        expect(_marked('menu-priority-$bucket'), findsOneWidget, reason: bucket);
        expect(_marked('menu-priority-none'), findsNothing, reason: bucket);
      }
      await t.tap(_k('menu-priority-none'));
      await t.pumpAndSettle();
      expect(s.taskById('t')!.priority, isNull);
      await openSubmenu();
      expect(_marked('menu-priority-none'), findsOneWidget);
    });
  });

  group('note context menu', () {
    testWidgets('each priority word is set, cleared and marked current', (
      t,
    ) async {
      AppState.debugDefaultFocus = HomeFocus.board;
      final s = await pumpTasksApp(
        t,
        notes: [_note('n', 'Alpha', priority: 'medium')],
      );
      Future<void> openSubmenu() async {
        await t.tap(
          find.descendant(of: _k('nav-card-n'), matching: find.text('Alpha')),
          buttons: kSecondaryButton,
        );
        await t.pumpAndSettle();
        expect(_k('menu-priority'), findsOneWidget);
        await t.tap(_k('menu-priority'));
        await t.pumpAndSettle();
      }

      await openSubmenu();
      expect(_marked('menu-priority-medium'), findsOneWidget);
      await t.tap(_k('menu-priority-high'));
      await t.pumpAndSettle();
      expect(_word(s, 'n'), 'high');
      await openSubmenu();
      expect(_marked('menu-priority-high'), findsOneWidget);
      expect(_marked('menu-priority-medium'), findsNothing);
      await t.tap(_k('menu-priority-low'));
      await t.pumpAndSettle();
      expect(_word(s, 'n'), 'low');
      await openSubmenu();
      await t.tap(_k('menu-priority-none'));
      await t.pumpAndSettle();
      expect(_word(s, 'n'), isNull);
      // The rest of the header is kept.
      final p = PlanItem.fromNote(s.tree.find('n')!.note);
      expect(p.status, 'todo');
      expect(p.text, 'body');
      await openSubmenu();
      expect(_marked('menu-priority-none'), findsOneWidget);
    });
  });

  group('phone menu sheet', () {
    testWidgets('a task: drill-in rows set, clear and mark the priority', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('k1', summary: 'Pay rent', priority: 1)],
        size: _phone,
      );
      s.openTaskTab('k1');
      await t.pumpAndSettle();
      await t.tap(_k('item-more'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-priority'));
      await t.pumpAndSettle();
      expect(_marked('menu-priority-high'), findsOneWidget);
      await t.tap(_k('menu-priority-low'));
      await t.pumpAndSettle();
      expect(_k('menu-sheet'), findsNothing);
      expect(s.taskById('k1')!.priority, 9);
      await t.pump(const Duration(seconds: 6)); // the undo toast leaves
      await t.pumpAndSettle();
      await t.tap(_k('item-more'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-priority'));
      await t.pumpAndSettle();
      expect(_marked('menu-priority-low'), findsOneWidget);
      await t.tap(_k('menu-priority-none'));
      await t.pumpAndSettle();
      expect(s.taskById('k1')!.priority, isNull);
    });

    testWidgets('a note: drill-in rows set, clear and mark the priority word', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final s = await pumpTasksApp(
        t,
        notes: [_note('n', 'Alpha', priority: 'high')],
        size: _phone,
      );
      await s.openNote('n');
      await t.pumpAndSettle();
      await t.tap(_k('item-more'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-priority'));
      await t.pumpAndSettle();
      expect(_marked('menu-priority-high'), findsOneWidget);
      await t.tap(_k('menu-priority-medium'));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 6)); // the undo toast leaves
      await t.pumpAndSettle();
      expect(_word(s, 'n'), 'medium');
      await t.tap(_k('item-more'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-priority'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-priority-none'));
      await t.pumpAndSettle();
      expect(_word(s, 'n'), isNull);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      await t.tap(_k('item-more'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-priority'));
      await t.pumpAndSettle();
      expect(_marked('menu-priority-none'), findsOneWidget);
    });
  });
}
