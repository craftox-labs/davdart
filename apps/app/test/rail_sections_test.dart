import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Finder _header(String text) =>
    find.descendant(of: _k('side-header'), matching: find.text(text));

/// Tears the app down and lets forui's tooltip hide timers run out.
Future<void> _end(WidgetTester t) async {
  await t.pump(const Duration(seconds: 1));
}

void main() {
  group('rail sections', () {
    testWidgets('Notes keeps the tree and its header actions', (t) async {
      final s = await pumpTasksApp(t, notes: const []);
      expect(s.section, Section.notes);
      expect(_header('Notes'), findsOneWidget);
      expect(find.text('Files'), findsNothing);
      expect(_k('new-note'), findsOneWidget);
      expect(_k('new-folder'), findsOneWidget);
      expect(_k('new-task'), findsNothing);
    });

    testWidgets('each section supplies its own header and actions', (t) async {
      await pumpTasksApp(t, tasks: [mkTask('a')]);
      await t.tap(_k('rail-tasks'));
      await t.pumpAndSettle();
      expect(_header('Tasks'), findsOneWidget);
      expect(_k('new-task'), findsOneWidget);
      expect(_k('new-note'), findsNothing);
      await t.tap(_k('rail-events'));
      await t.pumpAndSettle();
      expect(_header('Events'), findsOneWidget);
      expect(_k('new-event'), findsOneWidget);
      expect(_k('new-task'), findsNothing);
      expect(_k('new-note'), findsNothing);
      await _end(t);
    });

    testWidgets('Events shows an empty state without events', (t) async {
      await pumpTasksApp(t);
      await t.tap(_k('rail-events'));
      await t.pumpAndSettle();
      expect(_k('events-panel'), findsOneWidget);
      expect(find.text('No events yet'), findsOneWidget);
      await _end(t);
    });

    testWidgets('the selection survives collapse, expand and Space reset', (
      t,
    ) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('a')]);
      await t.tap(_k('rail-tasks'));
      await t.pumpAndSettle();
      await t.tap(_k('rail-tasks')); // folds the panel
      await t.pumpAndSettle();
      expect(s.sidebarCollapsed, isTrue);
      expect(s.section, Section.tasks);
      await t.tap(_k('rail-tasks'));
      await t.pumpAndSettle();
      expect(s.sidebarCollapsed, isFalse);
      expect(_k('tasks-view'), findsOneWidget);
      s.setTaskFilter(TaskFilter.all);
      s.keepListSection();
      expect(s.section, Section.tasks);
      s.setSection(Section.settings);
      s.keepListSection();
      expect(s.section, Section.notes);
      await _end(t);
    });

    testWidgets('the section persists per viewer', (t) async {
      final prefs = MemoryStorage();
      await pumpTasksApp(t, prefs: prefs);
      await t.tap(_k('rail-events'));
      await t.pumpAndSettle();
      expect(prefs.read('davdart.section.v1'), 'events');
      final s2 = AppState(
        (await pumpTasksApp(t, prefs: prefs)).source,
        prefs: prefs,
      );
      expect(s2.section, Section.events);
      await _end(t);
    });

    for (final w in [320.0, 600.0, 1280.0]) {
      testWidgets('Tasks and Events panels do not overflow at $w', (t) async {
        final s = await pumpTasksApp(
          t,
          tasks: [
            mkTask('a', days: -1, tags: ['a-long-tag-name']),
          ],
          size: Size(w, 900),
        );
        for (final sec in ['tasks', 'events']) {
          if (w < 880) {
            await t.tap(_k('menu'));
            await t.pumpAndSettle();
            await t.tap(_k('rail-$sec'));
          } else {
            await t.tap(_k('rail-$sec'));
          }
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '$sec at $w');
          if (w >= 880) continue;
          await t.tap(_k('menu'));
          await t.pumpAndSettle();
          s.setSection(Section.notes);
        }
        await _end(t);
      });
    }
  });
}
