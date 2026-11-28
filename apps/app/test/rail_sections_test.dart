import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/shell_frame.dart';
import 'package:davdart_app/ui/surface.dart';
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
      expect(_header('Calendar'), findsOneWidget);
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

  group('Home on the rail', () {
    final home = _k('rail-home');
    final railTab = _k('rail-tab');

    /// The fill of a rail item marked without joining the panel: the shared
    /// Surface painted in [Tokens.activeItem], like a collapsed section.
    Color? fillOf(WidgetTester t, Finder item) {
      final box = t.widget<DecoratedBox>(
        find
            .descendant(
              of: find.descendant(of: item, matching: find.byType(Surface)),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    testWidgets('a press shows Home, folds the panel and marks Home', (
      t,
    ) async {
      final prefs = MemoryStorage();
      final s = await pumpTasksApp(t, tasks: [mkTask('a')], prefs: prefs);
      s.openTaskTab('a');
      await t.pumpAndSettle();
      expect(s.atHome, isFalse);
      expect(s.sidebarCollapsed, isFalse);
      await t.tap(home);
      await t.pumpAndSettle();
      expect(s.activeTab, isNull);
      expect(s.atHome, isTrue);
      expect(_k('home-page'), findsOneWidget);
      expect(s.sidebarCollapsed, isTrue);
      expect(_k('side-header'), findsNothing);
      expect(prefs.read('davdart.sidebar.collapsed.v1'), 'true');
      // Marked as the current place, never as a tab joined to the panel.
      expect(t.widget<SectionButton>(home).active, isTrue);
      expect(find.descendant(of: home, matching: railTab), findsNothing);
      expect(fillOf(t, home), Tokens.light.activeItem);
      // Already Home with the panel folded: a second press changes nothing.
      await t.tap(home);
      await t.pumpAndSettle();
      expect(s.atHome, isTrue);
      expect(s.sidebarCollapsed, isTrue);
      await _end(t);
    });

    testWidgets('the folded panel stays folded when an item opens', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a')],
        size: const Size(1400, 900),
      );
      await t.tap(home);
      await t.pumpAndSettle();
      expect(s.sidebarCollapsed, isTrue);
      s.openTaskTab('a');
      await t.pumpAndSettle();
      expect(s.activeTab, isNotNull, reason: 'the item page opens');
      expect(s.sidebarCollapsed, isTrue, reason: 'the panel stays folded');
      expect(t.widget<SectionButton>(home).active, isFalse);
      await _end(t);
    });

    testWidgets('the folded state persists', (t) async {
      final prefs = MemoryStorage();
      await pumpTasksApp(t, prefs: prefs, size: const Size(1400, 900));
      await t.tap(home);
      await t.pumpAndSettle();
      final again = AppState(
        (await pumpTasksApp(
          t,
          prefs: prefs,
          size: const Size(1400, 900),
        )).source,
        prefs: prefs,
      );
      expect(again.sidebarCollapsed, isTrue);
      await _end(t);
    });

    testWidgets('folded at Home, only Home is lit', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a')],
        size: const Size(1400, 900),
      );
      expect(s.section, Section.notes);
      await t.tap(home);
      await t.pumpAndSettle();
      expect(s.atHome, isTrue);
      expect(s.sidebarCollapsed, isTrue);
      expect(t.widget<SectionButton>(home).active, isTrue);
      // The folded panel's section is not lit as well.
      expect(t.widget<SectionButton>(_k('rail-notes')).active, isFalse);
      expect(fillOf(t, _k('rail-notes')), isNull);
      await _end(t);
    });

    testWidgets('unfolding lights the reopened section again', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a')],
        size: const Size(1400, 900),
      );
      await t.tap(home);
      await t.pumpAndSettle();
      expect(t.widget<SectionButton>(_k('rail-notes')).active, isFalse);
      await t.tap(_k('rail-notes'));
      await t.pumpAndSettle();
      expect(s.sidebarCollapsed, isFalse);
      expect(t.widget<SectionButton>(_k('rail-notes')).active, isTrue);
      expect(
        find.descendant(of: _k('rail-notes'), matching: railTab),
        findsOneWidget,
      );
      await _end(t);
    });

    testWidgets('another rail press reopens its section over Home', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a')],
        size: const Size(1400, 900),
      );
      await t.tap(home);
      await t.pumpAndSettle();
      expect(s.sidebarCollapsed, isTrue);
      await t.tap(_k('rail-tasks'));
      await t.pumpAndSettle();
      expect(s.sidebarCollapsed, isFalse);
      expect(s.section, Section.tasks);
      expect(_header('Tasks'), findsOneWidget);
      // The panel is peek-only: the main area stays Home.
      expect(s.atHome, isTrue);
      expect(t.widget<SectionButton>(home).active, isTrue);
      expect(find.descendant(of: home, matching: railTab), findsNothing);
      expect(
        find.descendant(of: _k('rail-tasks'), matching: railTab),
        findsOneWidget,
      );
      // Home folds the panel; the same section's press reopens it.
      await t.tap(home);
      await t.pumpAndSettle();
      expect(s.sidebarCollapsed, isTrue);
      await t.tap(_k('rail-tasks'));
      await t.pumpAndSettle();
      expect(s.sidebarCollapsed, isFalse);
      expect(s.section, Section.tasks);
      await _end(t);
    });

    testWidgets('reaching Home another way leaves the panel alone', (t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a')],
        size: const Size(1400, 900),
      );
      s.openTaskTab('a');
      await t.pumpAndSettle();
      // The tab strip's fixed Home tab.
      await t.tap(_k('tab-home'));
      await t.pumpAndSettle();
      expect(s.atHome, isTrue);
      expect(s.sidebarCollapsed, isFalse);
      expect(_header('Notes'), findsOneWidget);
      // The palette and 'Go to' route: AppState.showHome.
      s.openTaskTab('a');
      await t.pumpAndSettle();
      s.showHome();
      await t.pumpAndSettle();
      expect(s.atHome, isTrue);
      expect(s.sidebarCollapsed, isFalse);
      // A panel folded earlier also stays folded.
      s.setSidebarCollapsed(true);
      await t.pumpAndSettle();
      s.openTaskTab('a');
      await t.pumpAndSettle();
      s.showHome();
      await t.pumpAndSettle();
      expect(s.sidebarCollapsed, isTrue);
      await _end(t);
    });

    testWidgets('narrow: a press closes the menu and shows Home', (t) async {
      final prefs = MemoryStorage();
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('a')],
        prefs: prefs,
        size: const Size(500, 900),
      );
      s.openTaskTab('a');
      await t.pumpAndSettle();
      await t.tap(_k('menu'));
      await t.pumpAndSettle();
      await t.tap(home);
      await t.pumpAndSettle();
      expect(s.atHome, isTrue);
      expect(_k('home-page'), findsOneWidget);
      expect(_k('side-menu'), findsNothing);
      // No docked panel: the phone writes no fold pref.
      expect(s.sidebarCollapsed, isFalse);
      expect(prefs.read('davdart.sidebar.collapsed.v1'), isNull);
      await _end(t);
    });
  });
}
