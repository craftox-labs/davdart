import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

final _notes = [
  Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
  Note(uid: 'sub', summary: 'Sub', parentUid: 'f', categories: ['kind-folder']),
  Note(uid: 'in', summary: 'Inside note', parentUid: 'sub'),
  Note(uid: 'out', summary: 'Outside note'),
];

Future<AppState> _app(WidgetTester t, {Size? size}) async {
  AppState.debugDefaultFocus = HomeFocus.day;
  final s = await pumpTasksApp(
    t,
    size: size ?? const Size(1280, 900),
    notes: _notes,
    tasks: [
      mkTask('t-in', days: 0, parent: 'in'),
      mkTask('t-deep', days: 0, parent: 't-in'),
      mkTask('t-out', days: 0),
    ],
    events: [
      mkEvent('e-in', parent: 'sub'),
      mkEvent('e-out', hour: 11),
    ],
  );
  await s.activateTab(null);
  await t.pumpAndSettle();
  return s;
}

void main() {

  group('scope everywhere', () {
    testWidgets('folder scope shows items under it on Day, hides others', (
      t,
    ) async {
      final s = await _app(t);
      expect(_k('home-today-tasks-t-out'), findsOneWidget);
      s.openFolder('f');
      await t.pumpAndSettle();
      expect(_k('home-today-tasks-t-in'), findsOneWidget);
      expect(_k('home-today-tasks-t-deep'), findsOneWidget);
      expect(_k('home-today-tasks-t-out'), findsNothing);
      expect(s.scopedEvents.map((e) => e.uid), ['e-in']);
      expect(s.filteredEvents.map((e) => e.uid), ['e-in']);
      expect(s.filteredTasks.map((k) => k.uid), ['t-in', 't-deep']);
      expect(s.openTasks().map((k) => k.uid).toSet(), {'t-in', 't-deep'});
      s.openFolder(null);
      await t.pumpAndSettle();
      expect(s.scopedEvents.length, 2);
      expect(s.filteredEvents.length, 2);
      expect(_k('home-today-tasks-t-out'), findsOneWidget);
    });

    testWidgets('the Tasks panel follows the one scope', (t) async {
      final s = await _app(t);
      s.openFolder('f');
      s.openTasksPanel();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('task-row-t-in')), findsOneWidget);
      expect(find.byKey(const Key('task-row-t-out')), findsNothing);
    });

    testWidgets('scope clears when its folder is deleted', (t) async {
      final s = await _app(t);
      s.openFolder('f');
      await s.deleteNote('f');
      await t.pumpAndSettle();
      expect(s.scopeUid, isNull);
      expect(s.scopedEvents.length, 2);
    });

    testWidgets('a saved view with a folder sets the scope', (t) async {
      final s = await _app(t);
      s.openFolder('f');
      expect(await t.runAsync(() => s.saveView('Plans view')), isNull);
      s.openFolder(null);
      s.applyView(s.savedViews.single);
      await t.pumpAndSettle();
      expect(s.scopeUid, 'f');
      expect(s.scopedEvents.map((e) => e.uid), ['e-in']);
    });
  });

  group('filter chip', () {
    testWidgets('hidden with no filter', (t) async {
      await _app(t);
      expect(_k('filter-chips'), findsNothing);
    });

    testWidgets('search chip appears and its x clears the search', (t) async {
      final s = await _app(t);
      s.setQuery('foo');
      await t.pumpAndSettle();
      expect(_k('filter-chip-search'), findsOneWidget);
      expect(find.text('search "foo"'), findsOneWidget);
      expect(_k('filter-chip-folder'), findsNothing);
      await t.tap(_k('clear-filter-search'));
      await t.pumpAndSettle();
      expect(s.query, '');
      expect(_k('filter-chips'), findsNothing);
    });

    testWidgets('folder is not in the chip; breadcrumb clears it', (t) async {
      final s = await _app(t);
      s.openFolder('f');
      await t.pumpAndSettle();
      expect(_k('filter-chips'), findsNothing);
      expect(_k('crumb-folder'), findsOneWidget);
      s.setQuery('bar');
      await t.pumpAndSettle();
      expect(_k('filter-chip-search'), findsOneWidget);
      expect(_k('filter-chip-folder'), findsNothing);
      await t.tap(_k('scope-close'));
      await t.pumpAndSettle();
      expect(s.scopeUid, isNull);
      expect(s.query, 'bar');
      expect(_k('filter-chip-search'), findsOneWidget);
    });

    testWidgets('chip is slim and sits in the switcher row on wide', (t) async {
      final s = await _app(t);
      s.setQuery('foo');
      await t.pumpAndSettle();
      final chip = t.getRect(_k('filter-chip-search'));
      final sw = t.getRect(_k('home-focus'));
      expect(chip.height, lessThanOrEqualTo(28));
      expect(chip.left, greaterThan(sw.right));
      expect(chip.center.dy, closeTo(sw.center.dy, 8));
    });

    testWidgets('chip sits on a slim line above the switcher on phone', (
      t,
    ) async {
      final s = await _app(t, size: const Size(390, 800));
      s.setQuery('foo');
      await t.pumpAndSettle();
      final chip = t.getRect(_k('filter-chip-search'));
      final sw = t.getRect(_k('home-focus'));
      expect(chip.bottom, lessThanOrEqualTo(sw.top));
      expect(chip.height, lessThanOrEqualTo(28));
      expect(chip.left, closeTo(sw.left, 1));
    });

    testWidgets('phone Home button clears a search, keeps the folder', (
      t,
    ) async {
      final s = await _app(t, size: const Size(390, 800));
      s.openFolder('f');
      s.setQuery('foo');
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Home'));
      await t.pumpAndSettle();
      expect(s.query, '');
      expect(s.scopeUid, 'f');
      expect(_k('filter-chip-search'), findsNothing);
      expect(_k('filter-chip-folder'), findsNothing);
    });
  });
}
