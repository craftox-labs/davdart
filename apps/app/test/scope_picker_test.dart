import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'catalog_helper.dart';
import 'tasks_helper.dart';

const _sizes = [Size(320, 568), Size(390, 844)];

Finder _k(String k) => find.byKey(Key(k));

void _noError(WidgetTester t) {
  final ex = t.takeException();
  expect(ex, isNull, reason: ex is FlutterError ? ex.toStringDeep() : '$ex');
}

Note _folder(
  String uid,
  String name, {
  String? parent,
  bool container = false,
}) => Note(
  uid: uid,
  summary: name,
  parentUid: parent,
  categories: [folderTag, if (container) projectsTag],
);

final _seed = [
  _folder('c', 'Projects', container: true),
  _folder('p1', 'Alpha project', parent: 'c'),
  _folder('p2', 'Beta', parent: 'c'),
  _folder('sub', 'Design', parent: 'p1'),
  _folder('deep', 'Details', parent: 'sub'),
  _folder('loose', 'Loose notes'),
  Note(uid: 'in-p1', summary: 'Inside note', parentUid: 'p1'),
  Note(uid: 'outside', summary: 'Outside note'),
];

Future<AppState> _app(WidgetTester t, Size size) async {
  final s = await pumpTasksApp(
    t,
    size: size,
    notes: _seed,
    tasks: [
      mkTask('t-in', summary: 'In project', parent: 'p1'),
      mkTask('t-out', summary: 'Outside task'),
    ],
    events: [mkEvent('e-out', summary: 'Outside event')],
  );
  await s.activateTab(null);
  await t.pumpAndSettle();
  return s;
}

String _text(WidgetTester t, String key) => t.widget<Text>(_k(key)).data!;

/// The app over a real catalog Space (Search needs one), with [_seed].
Future<AppState> _catalogApp(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final storage = MemoryStorage();
  final c = catalogWithPlanning(storage, planningSeed: SeedNotes(_seed));
  final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
  await s.load();
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

void main() {
  for (final size in _sizes) {
    group('narrow scope pill at $size', () {
      testWidgets('the Space alone, and no crumb anywhere in the bar', (
        t,
      ) async {
        await _app(t, size);
        expect(_text(t, 'scope-pill-space'), 'Spaces');
        expect(_k('scope-pill-project'), findsNothing);
        // Logo left, pill, sync right.
        expect(
          t.getRect(_k('top-logo')).right,
          lessThan(t.getRect(_k('space-chip')).left),
        );
        expect(
          t.getRect(find.byIcon(FLucideIcons.refreshCw)).left,
          greaterThan(t.getRect(_k('space-chip')).right),
        );
        // No folder, no view: no thin row either.
        expect(_k('content-crumbs'), findsNothing);
        _noError(t);
      });

      testWidgets(
        'a project scope: Space › Project, same bar on every screen',
        (t) async {
          final s = await _app(t, size);
          s.openFolder('p1');
          await t.pumpAndSettle();
          // The Space name gives way to its icon; the project is named.
          expect(_k('scope-pill-space'), findsNothing);
          expect(_text(t, 'scope-pill-project'), 'Alpha project');
          expect(
            find.descendant(
              of: _k('space-chip'),
              matching: find.byIcon(FLucideIcons.layoutGrid),
            ),
            findsOneWidget,
          );
          // A project is the pill's own level: no crumb row.
          expect(_k('content-crumbs'), findsNothing);
          // Opening the project as a page keeps the pill as it was.
          s.openNoteTab('p1');
          await t.pumpAndSettle();
          expect(_text(t, 'scope-pill-project'), 'Alpha project');
          expect(
            find.descendant(of: _k('top-bar'), matching: _k('crumb-folder')),
            findsNothing,
          );
          _noError(t);
        },
      );

      testWidgets('below a project the crumbs move into the content', (
        t,
      ) async {
        final s = await _app(t, size);
        s.openFolder('sub');
        await t.pumpAndSettle();
        // The pill still says Space › Project (the project of the scope).
        expect(_text(t, 'scope-pill-project'), 'Alpha project');
        // The path below it is in the content's thin row.
        expect(_k('content-crumbs'), findsOneWidget);
        expect(_text(t, 'crumb-folder'), 'Design');
        expect(
          find.descendant(of: _k('top-bar'), matching: _k('content-crumbs')),
          findsNothing,
        );
        expect(
          t.getRect(_k('content-crumbs')).top,
          greaterThanOrEqualTo(t.getRect(_k('top-bar')).bottom - 1),
        );
        // A folder outside every project shows its path too.
        s.openFolder('loose');
        await t.pumpAndSettle();
        expect(_k('scope-pill-project'), findsNothing);
        expect(_text(t, 'crumb-folder'), 'Loose notes');
        // Back at the Space root the row goes.
        s.openFolder(null);
        await t.pumpAndSettle();
        expect(_k('content-crumbs'), findsNothing);
        _noError(t);
      });

      testWidgets('the sheet: the Space itself first, then the projects', (
        t,
      ) async {
        final s = await _app(t, size);
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsOneWidget);
        // The first row is the open Space itself (no project), then the
        // projects. With one fixed source there is no other Space to list.
        expect(
          find.descendant(
            of: _k('scope-pick-all'),
            matching: find.text('Spaces'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _k('scope-pick-all'),
            matching: find.text('No project'),
          ),
          findsOneWidget,
        );
        expect(find.text('One fixed notes source'), findsNothing);
        expect(_k('scope-pick-p1'), findsOneWidget);
        expect(_k('scope-pick-p2'), findsOneWidget);
        expect(
          t.getRect(_k('scope-pick-all')).top,
          lessThan(t.getRect(_k('scope-pick-p1')).top),
        );
        // One tap on a project scopes to it and closes the sheet.
        await t.tap(_k('scope-pick-p2'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(s.scopeUid, 'p2');
        expect(_text(t, 'scope-pill-project'), 'Beta');
        // The Space's own row clears the scope again.
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        await t.tap(_k('scope-pick-all'));
        await t.pumpAndSettle();
        expect(s.scopeUid, isNull);
        expect(_text(t, 'scope-pill-space'), 'Spaces');
        _noError(t);
      });

      testWidgets('an item outside the scope keeps it on narrow', (t) async {
        final s = await _app(t, size);
        s.openFolder('p1');
        await t.pumpAndSettle();
        // A note outside the project opens as the page it is, scope intact.
        await s.openNote('outside');
        await t.pumpAndSettle();
        expect(s.scopeUid, 'p1');
        expect(_text(t, 'scope-pill-project'), 'Alpha project');
        expect(find.text('Outside note'), findsWidgets);
        // Scope-dependent screens still ignore it, and count only what is in.
        expect(s.filtered.map((n) => n.uid), isNot(contains('outside')));
        expect(s.filteredTasks.map((t) => t.uid), ['t-in']);
        // A task and an event outside the project keep it too.
        await s.openTask('t-out');
        await t.pumpAndSettle();
        expect(s.scopeUid, 'p1');
        await s.openEvent('e-out');
        await t.pumpAndSettle();
        expect(s.scopeUid, 'p1');
        // Back returns to that scope's screens, still scoped.
        await t.tap(_k('bar-back'));
        await t.pumpAndSettle();
        expect(s.activeTab, isNull);
        expect(s.scopeUid, 'p1');
        expect(_text(t, 'scope-pill-project'), 'Alpha project');
        expect(_k('content-crumbs'), findsNothing, reason: 'a project level');
        _noError(t);
      });

      testWidgets('the picker drills into a project\'s folders', (t) async {
        final s = await _app(t, size);
        s.openFolder('p1');
        await t.pumpAndSettle();
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        // At the project: its own folders, one level, nothing to go up to.
        expect(_k('scope-pick-folder-sub'), findsOneWidget);
        expect(_k('scope-pick-folder-deep'), findsNothing);
        expect(_k('scope-pick-up'), findsNothing);
        expect(_k('scope-pick-here'), findsNothing);
        await t.tap(_k('scope-pick-folder-sub'));
        await t.pumpAndSettle();
        expect(s.scopeUid, 'sub');
        // One level down: the way up, the folder in scope (marked), and its
        // own folders.
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        expect(
          find.descendant(
            of: _k('scope-pick-up'),
            matching: find.text('Alpha project'),
          ),
          findsOneWidget,
        );
        final here = _k('scope-pick-here');
        expect(t.widget<FItem>(here).selected, isTrue);
        expect(
          find.descendant(of: here, matching: find.text('Design')),
          findsOneWidget,
        );
        expect(_k('scope-pick-folder-deep'), findsOneWidget);
        // The marked folder's ⋯ offers its own actions.
        await t.tap(_k('scope-more-sub'));
        await t.pumpAndSettle();
        expect(_k('scope-edit'), findsOneWidget);
        await t.tap(_k('menu-back'));
        await t.pumpAndSettle();
        // Up one level goes back to the project.
        await t.tap(_k('scope-pick-up'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(s.scopeUid, 'p1');
        _noError(t);
      });

      testWidgets('the sheet lists recent projects first', (t) async {
        final s = await _app(t, size);
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        // The listed order (by creation) is p1 then p2.
        expect(
          t.getRect(_k('scope-pick-p1')).top,
          lessThan(t.getRect(_k('scope-pick-p2')).top),
        );
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();
        // Opened in that order, the newest comes first in the sheet.
        s.openFolder('p1');
        await t.pumpAndSettle();
        s.openFolder('p2');
        await t.pumpAndSettle();
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        expect(
          t.getRect(_k('scope-pick-p2')).top,
          lessThan(t.getRect(_k('scope-pick-p1')).top),
        );
        _noError(t);
      });

      testWidgets('a loose folder is its own selected row in the sheet', (
        t,
      ) async {
        final s = await _app(t, size);
        s.openFolder('loose');
        await t.pumpAndSettle();
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        // Its own path row is the scope: no project row is marked, and
        // Everything is not marked either.
        final path = _k('scope-pick-path');
        expect(path, findsOneWidget);
        expect(t.widget<FItem>(path).selected, isTrue);
        expect(t.widget<FItem>(_k('scope-pick-all')).selected, isFalse);
        for (final p in ['p1', 'p2']) {
          expect(t.widget<FItem>(_k('scope-pick-$p')).selected, isFalse);
        }
        expect(
          find.descendant(of: path, matching: find.text('Loose notes')),
          findsOneWidget,
        );
        // Tapping it keeps the scope and closes the sheet.
        await t.tap(path);
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(s.scopeUid, 'loose');
        // Inside a project the project row carries the mark instead.
        s.openFolder('sub');
        await t.pumpAndSettle();
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        expect(_k('scope-pick-path'), findsNothing);
        expect(t.widget<FItem>(_k('scope-pick-p1')).selected, isTrue);
        _noError(t);
      });

      testWidgets('the ⋯ opens that folder\'s dialogs from the pill', (
        t,
      ) async {
        final s = await _app(t, size);
        s.openFolder('p1');
        await t.pumpAndSettle();
        // Edit folder, from the selected row's ⋯.
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        expect(_k('scope-edit'), findsNothing, reason: 'behind the ⋯');
        await t.tap(_k('scope-more-p1'));
        await t.pumpAndSettle();
        await t.tap(_k('scope-edit'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(find.text('Edit folder'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        // Delete folder, same route: the confirm dialog, for this folder.
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        await t.tap(_k('scope-more-p1'));
        await t.pumpAndSettle();
        await t.tap(_k('scope-delete'));
        await t.pumpAndSettle();
        expect(find.text('Delete note?'), findsOneWidget);
        expect(
          find.textContaining('Alpha project'),
          findsWidgets,
          reason: 'the confirm names the folder',
        );
        expect(_k('delete-confirm'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(s.scopeUid, 'p1');
        _noError(t);
      });

      testWidgets('a long press on a project row opens its actions', (t) async {
        final s = await _app(t, size);
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        // Beta is not the scope: no ⋯, but a long press still offers them.
        expect(_k('scope-more-p2'), findsNothing);
        await t.longPress(_k('scope-pick-p2'));
        await t.pumpAndSettle();
        expect(_k('scope-edit'), findsOneWidget);
        expect(_k('scope-delete'), findsOneWidget);
        await t.tap(_k('scope-delete'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(find.text('Delete note?'), findsOneWidget);
        expect(find.textContaining('Beta'), findsWidgets);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(s.scopeUid, isNull, reason: 'the long press picked nothing');
        _noError(t);
      });

      testWidgets('the + menu adds inside the open project', (t) async {
        final s = await _app(t, size);
        s.openFolder('p1');
        await t.pumpAndSettle();
        Future<void> add(String entry, String titleKey, String addKey) async {
          await t.tap(_k('bar-add'));
          await t.pumpAndSettle();
          await t.tap(_k(entry));
          await t.pumpAndSettle();
          await t.enterText(_k(titleKey), 'In the project');
          await t.pumpAndSettle();
          await t.tap(_k(addKey));
          await t.pumpAndSettle();
          // A note or event opens as its page; back out for the next add.
          await t.tap(_k('bar-back'));
          await t.pumpAndSettle();
        }

        await add('add-task', 'new-task-title', 'new-task-add');
        expect(
          s.tasks.firstWhere((e) => e.summary == 'In the project').parentUid,
          'p1',
        );
        await add('add-event', 'new-event-title', 'new-event-add');
        expect(
          s.events.firstWhere((e) => e.summary == 'In the project').parentUid,
          'p1',
        );
        await add('add-note', 'new-note-title', 'new-note-add');
        expect(
          s.notes.firstWhere((e) => e.summary == 'In the project').parentUid,
          'p1',
        );
        _noError(t);
      });

      testWidgets('Search stays inside the project until told otherwise', (
        t,
      ) async {
        final s = await _catalogApp(t, size);
        s.openFolder('p1');
        await t.pumpAndSettle();
        await t.tap(_k('bar-search'));
        await t.pumpAndSettle();
        // Inside a folder scope the toggle sits above the field.
        expect(_k('search-scope-toggle'), findsOneWidget);
        expect(
          find.text('Search this project'),
          findsOneWidget,
          reason: 'hint follows the choice',
        );
        await t.enterText(_k('search-all-field'), 'note');
        await t.pumpAndSettle();
        final results = _k('side-menu');
        expect(
          find.descendant(of: results, matching: find.text('Inside note')),
          findsWidgets,
        );
        expect(
          find.descendant(of: results, matching: find.text('Outside note')),
          findsNothing,
        );
        // Whole space: the loose note is found too.
        await t.tap(_k('search-scope-space'));
        await t.pumpAndSettle();
        expect(find.text('Search this space'), findsOneWidget);
        expect(
          find.descendant(of: results, matching: find.text('Outside note')),
          findsWidgets,
        );
        expect(
          find.descendant(of: results, matching: find.text('Inside note')),
          findsWidgets,
        );
        // Back to the project narrows it again.
        await t.tap(_k('search-scope-project'));
        await t.pumpAndSettle();
        expect(
          find.descendant(of: results, matching: find.text('Outside note')),
          findsNothing,
        );
        // The scope changes under the open panel: the search follows it, and
        // the choice goes back to This project.
        await t.tap(_k('search-scope-space'));
        await t.pumpAndSettle();
        s.openFolder('p2');
        await t.pumpAndSettle();
        expect(find.text('Search this project'), findsOneWidget);
        expect(find.text('No matches'), findsOneWidget);
        expect(
          find.descendant(of: results, matching: find.text('Inside note')),
          findsNothing,
        );
        // The state call behind it does the same.
        expect(
          (await s.searchAllSpaces(
            'note',
            scopeUid: 'p1',
          )).map((h) => h.note.uid),
          ['in-p1'],
        );
        expect(
          (await s.searchAllSpaces('note')).map((h) => h.note.uid),
          containsAll(['in-p1', 'outside']),
        );
        _noError(t);
      });

      testWidgets('a saved view keeps its name in the content row', (t) async {
        final s = await _app(t, size);
        s.setView(ViewMode.list);
        await t.runAsync(() => s.saveView('My list'));
        s.applyView(s.savedViews.single);
        await t.pumpAndSettle();
        expect(s.activeViewName, 'My list');
        // The bar still says the Space; the view's name is in the row.
        expect(_text(t, 'scope-pill-space'), 'Spaces');
        expect(_k('content-crumbs'), findsOneWidget);
        expect(
          find.descendant(
            of: _k('content-crumbs'),
            matching: find.text('My list'),
          ),
          findsWidgets,
        );
        expect(
          find.descendant(of: _k('top-bar'), matching: find.text('My list')),
          findsNothing,
        );
        _noError(t);
      });

      testWidgets('the folder actions are behind the ⋯, not in the top bar', (
        t,
      ) async {
        final s = await _app(t, size);
        s.openFolder('p1');
        await t.pumpAndSettle();
        // The wide bar's folder menu is not on the phone bar.
        expect(_k('scope-more'), findsNothing);
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        // No rows of its own: the actions live behind the selected row's ⋯.
        expect(_k('scope-edit'), findsNothing);
        expect(_k('scope-close'), findsNothing);
        expect(_k('scope-more-p1'), findsOneWidget);
        await t.tap(_k('scope-more-p1'));
        await t.pumpAndSettle();
        expect(_k('scope-edit'), findsOneWidget);
        expect(_k('scope-delete'), findsOneWidget);
        // "Show the whole space" belongs to the wide bar's menu only: the
        // picker's first row already goes back to the whole Space.
        expect(_k('scope-close'), findsNothing);
        await t.tap(_k('menu-back'));
        await t.pumpAndSettle();
        expect(_k('scope-edit'), findsNothing);
        await t.tap(_k('scope-pick-all'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(s.scopeUid, isNull);
        _noError(t);
      });
    });
  }

  testWidgets('the picker lists the other Spaces only', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final storage = MemoryStorage();
    final c = catalogWithPlanning(storage);
    final inbox = c.add('Inbox').id;
    final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
    await s.load();
    await s.switchSpace(inbox);
    await t.pumpWidget(DavdartApp(state: s));
    await t.pumpAndSettle();
    await t.tap(_k('space-chip'));
    await t.pumpAndSettle();
    // The open Space is the picker's own first row, not a switcher row.
    expect(_k('space-$inbox'), findsNothing);
    expect(_k('space-${SpaceCatalog.planningId}'), findsOneWidget);
    await t.tap(_k('space-${SpaceCatalog.planningId}'));
    await t.pumpAndSettle();
    expect(_k('menu-sheet'), findsNothing);
    expect(s.currentSpaceId, SpaceCatalog.planningId);
    _noError(t);
  });
}
