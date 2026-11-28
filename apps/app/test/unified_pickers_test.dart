import 'package:davdart_app/ui/property/property_defs.dart';
import 'package:davdart_app/ui/property/property_dialog.dart';
import 'package:davdart_app/ui/task_menu.dart';
import 'package:davdart_app/ui/event_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

BuildContext _ctx(WidgetTester t) =>
    t.element(find.byKey(const Key('home-page')));

void main() {
  group('property definitions', () {
    test('every property has one label, icon and set-entry', () {
      expect(Props.status.setLabel, 'Set status');
      expect(Props.priority.setLabel, 'Set priority');
      expect(Props.due.setLabel, 'Set due');
      expect(Props.labels.label, 'labels');
      expect(Props.parent.label, 'belongs to');
    });

    test('status words and priority buckets round-trip', () {
      expect(statusWordOf('doing'), 'in-process');
      expect(statusWordOf('todo'), 'needs-action');
      for (final b in const ['high', 'medium', 'low']) {
        expect(priorityBucket(priorityOfBucket(b)), b);
      }
      expect(priorityBucket(null), 'none');
    });

    test('the option lists agree with the status words', () {
      expect(
        [for (final o in taskStatusOptions()) o.label],
        [for (final e in statusWords) e.$2],
      );
      expect(
        taskStatusOptions(blocked: true).singleWhere((o) => !o.enabled).value,
        'done',
      );
      expect(
        [
          for (final o in priorityOptions<int>((b) => priorityOfBucket(b)!))
            o.value,
        ],
        [1, 5, 9],
      );
    });
  });

  group('menus read the shared options', () {
    testWidgets('the task status submenu lists the picker words', (t) async {
      final s = await pumpHomeApp(t, tasks: [mkTask('t', summary: 'Fix it')]);
      await t.tap(
        find.descendant(of: _k('nav-card-t'), matching: find.text('Fix it')),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      await t.tap(_k('menu-task-status'));
      await t.pumpAndSettle();
      for (final e in statusWords) {
        expect(_k('menu-task-status-${e.$1}'), findsOneWidget);
        expect(
          find.descendant(
            of: _k('menu-task-status-${e.$1}'),
            matching: find.text(e.$2),
          ),
          findsOneWidget,
        );
      }
      await t.tap(_k('menu-task-status-doing'));
      await t.pumpAndSettle();
      expect(s.taskById('t')!.boardStatus, 'doing');
    });

    testWidgets('a task menu moves it through the shared parent picker', (
      t,
    ) async {
      await pumpHomeApp(t, tasks: [mkTask('t', summary: 'Fix it')]);
      await t.tap(
        find.descendant(of: _k('nav-card-t'), matching: find.text('Fix it')),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      expect(_k('menu-move-folder'), findsOneWidget);
      await t.tap(_k('menu-move-folder'));
      await t.pumpAndSettle();
      expect(_k('property-parent-move-top'), findsOneWidget);
    });
  });

  group('new item dialogs use the shared rows', () {
    testWidgets('a new task takes status, priority and labels', (t) async {
      final s = await pumpTasksApp(t);
      showNewTaskDialog(_ctx(t), s);
      await t.pumpAndSettle();
      for (final k in [
        'property-status',
        'property-priority',
        'property-due',
        'property-start',
        'property-tags',
        'property-parent',
      ]) {
        expect(_k(k), findsOneWidget, reason: k);
      }
      await t.enterText(_k('new-task-title'), 'Made here');
      await t.tap(_k('property-priority'));
      await t.pumpAndSettle();
      await t.tap(_k('property-option-new-priority-1'));
      await t.pumpAndSettle();
      await t.tap(_k('property-status'));
      await t.pumpAndSettle();
      await t.tap(_k('property-option-new-status-doing'));
      await t.pumpAndSettle();
      await t.tap(_k('new-task-add'));
      await t.pumpAndSettle();
      final task = s.tasks.singleWhere((k) => k.summary == 'Made here');
      expect(task.priority, 1);
      expect(task.boardStatus, 'doing');
    });

    testWidgets('a new event takes a status', (t) async {
      final s = await pumpTasksApp(t);
      showNewEventDialog(_ctx(t), s);
      await t.pumpAndSettle();
      await t.enterText(_k('new-event-title'), 'Event here');
      await t.tap(_k('property-status'));
      await t.pumpAndSettle();
      await t.tap(_k('property-option-new-event-status-CONFIRMED'));
      await t.pumpAndSettle();
      await t.tap(_k('new-event-add'));
      await t.pumpAndSettle();
      final e = s.events.singleWhere((k) => k.summary == 'Event here');
      expect(e.status, 'CONFIRMED');
    });
  });

  testWidgets('showMoveToParentDialog shows the picker for a task', (t) async {
    final s = await pumpTasksApp(t, tasks: [mkTask('t', summary: 'Fix it')]);
    showMoveToParentDialog(_ctx(t), s, 't');
    await t.pumpAndSettle();
    expect(_k('property-parent-move-top'), findsOneWidget);
  });
}
