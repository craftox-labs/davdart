import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Opens the side menu with the Projects panel (the pill's picker).
Future<void> _openPicker(WidgetTester t) async {
  await t.tap(_k('space-chip'));
  await t.pumpAndSettle();
  expect(_k('side-menu'), findsOneWidget);
  expect(_k('projects-view'), findsOneWidget);
}

void main() {
  for (final size in _sizes) {
    group('narrow scope pill at $size', () {
      testWidgets('the page title, and no crumb anywhere in the bar', (
        t,
      ) async {
        await _app(t, size);
        expect(_text(t, 'top-title'), 'Home');
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
          // The closed bar names the page, not the folder scope.
          expect(_text(t, 'top-title'), 'Home');
          // A project is the page's own level: no crumb row.
          expect(_k('content-crumbs'), findsNothing);
          // Opening the project as a page names the project.
          s.openNoteTab('p1');
          await t.pumpAndSettle();
          expect(_text(t, 'top-title'), 'Alpha project');
          expect(
            find.descendant(of: _k('top-bar'), matching: _k('crumb-folder')),
            findsNothing,
          );
          _noError(t);
        },
      );

      testWidgets('the pill opens the Projects panel: the Space, then the '
          'projects', (t) async {
        final s = await _app(t, size);
        await _openPicker(t);
        // The first row is the open Space itself (no project), then the
        // projects. With one fixed source there is no other Space to list.
        expect(
          find.descendant(
            of: _k('projects-all'),
            matching: find.text('Spaces'),
          ),
          findsOneWidget,
        );
        expect(find.text('No project'), findsOneWidget);
        expect(_k('project-p1'), findsOneWidget);
        expect(_k('project-p2'), findsOneWidget);
        expect(
          t.getRect(_k('projects-all')).top,
          lessThan(t.getRect(_k('project-p1')).top),
        );
        // One tap on a project scopes to it and closes the menu.
        await t.tap(_k('project-p2'));
        await t.pumpAndSettle();
        expect(_k('side-menu'), findsNothing);
        expect(s.scopeUid, 'p2');
        expect(_text(t, 'top-title'), 'Beta');
        // The Space's own row clears the scope again.
        await _openPicker(t);
        await t.tap(_k('projects-all'));
        await t.pumpAndSettle();
        expect(s.scopeUid, isNull);
        expect(_text(t, 'top-title'), 'Home');
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
        expect(_text(t, 'top-title'), 'Outside note');
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
        // Back returns to Home, which is personal (scope cleared).
        await t.tap(_k('bar-back'));
        await t.pumpAndSettle();
        expect(s.activeTab, isNull);
        expect(s.scopeUid, isNull);
        expect(_k('content-crumbs'), findsNothing);
        _noError(t);
      });

      testWidgets('a project card enters it on Overview', (t) async {
        final s = await _app(t, size);
        s.openFolder('p1');
        await t.pumpAndSettle();
        await _openPicker(t);
        // The panel is a flat list of cards: no chevrons or view rows.
        expect(_k('project-p1'), findsOneWidget);
        expect(_k('project-view-p1-overview'), findsNothing);
        expect(_k('project-toggle-p1'), findsNothing);
        expect(_k('projects-folder-sub'), findsNothing);
        await t.tap(_k('project-p1'));
        await t.pumpAndSettle();
        expect(s.scopeUid, 'p1');
        expect(s.mainProjectUid, 'p1');
        expect(_k('side-menu'), findsNothing, reason: 'the pick closed it');
        expect(_k('overview-page'), findsOneWidget);
        // The project's own switcher is in the page.
        await t.tap(_k('proj-tab-notes'));
        await t.pumpAndSettle();
        expect(s.mainProjectUid, 'p1');
        expect(_k('proj-notes-tab'), findsOneWidget);
        _noError(t);
      });

      testWidgets('the panel lists recent projects first', (t) async {
        final s = await _app(t, size);
        await _openPicker(t);
        // The listed order (by creation) is p1 then p2.
        expect(
          t.getRect(_k('project-p1')).top,
          lessThan(t.getRect(_k('project-p2')).top),
        );
        await t.tap(_k('menu'));
        await t.pumpAndSettle();
        // Opened in that order, the newest comes first in the panel.
        s.openFolder('p1');
        await t.pumpAndSettle();
        s.openFolder('p2');
        await t.pumpAndSettle();
        await _openPicker(t);
        expect(
          t.getRect(_k('project-p2')).top,
          lessThan(t.getRect(_k('project-p1')).top),
        );
        _noError(t);
      });

      testWidgets('a loose folder has no row of its own', (t) async {
        final s = await _app(t, size);
        s.openFolder('loose');
        await t.pumpAndSettle();
        await _openPicker(t);
        // Folders are reached through the Notes tree, not here: no path row,
        // no folder rows, and no project row marked.
        expect(_k('projects-path'), findsNothing);
        expect(_k('projects-here'), findsNothing);
        expect(_k('projects-folder-sub'), findsNothing);
        expect(_k('projects-all'), findsOneWidget);
        expect(s.scopeUid, 'loose', reason: 'the picker picked nothing');
        // The whole-Space row clears the scope.
        await t.tap(_k('projects-all'));
        await t.pumpAndSettle();
        expect(s.scopeUid, isNull);
        _noError(t);
      });

      testWidgets('the \u22ef opens that folder\'s dialogs', (t) async {
        final s = await _app(t, size);
        s.openFolder('p1');
        await t.pumpAndSettle();
        // Edit folder, from the selected row's \u22ef.
        await _openPicker(t);
        expect(_k('scope-edit'), findsNothing, reason: 'behind the \u22ef');
        await t.tap(_k('scope-more-p1'));
        await t.pumpAndSettle();
        await t.tap(_k('scope-edit'));
        await t.pumpAndSettle();
        expect(find.text('Edit project'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        // Delete folder, same route: the confirm dialog, for this folder.
        await t.tap(_k('scope-more-p1'));
        await t.pumpAndSettle();
        await t.tap(_k('scope-delete'));
        await t.pumpAndSettle();
        expect(find.text('Delete project?'), findsOneWidget);
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
        await _openPicker(t);
        // Beta is not the scope: no \u22ef, but a long press still offers its
        // actions.
        expect(_k('scope-more-p2'), findsNothing);
        await t.longPress(_k('project-p2'));
        await t.pumpAndSettle();
        expect(_k('menu-project-delete-p2'), findsOneWidget);
        await t.tap(_k('menu-project-delete-p2'));
        await t.pumpAndSettle();
        expect(find.text('Delete project?'), findsOneWidget);
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
          // Back to the project itself: a new item opens as a page and would
          // be the next one's parent.
          s.openFolder('p1');
          await t.pumpAndSettle();
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

        await add('add-note', 'new-note-title', 'new-note-add');
        expect(
          s.notes.firstWhere((e) => e.summary == 'In the project').parentUid,
          'p1',
        );
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
        expect(find.text('Search this Space'), findsOneWidget);
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
        // The bar names the view; its crumb row stays.
        expect(_text(t, 'top-title'), 'My list');
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
          findsWidgets,
        );
        _noError(t);
      });

      testWidgets(
        'the folder actions are behind the \u22ef, not in the top bar',
        (t) async {
          final s = await _app(t, size);
          s.openFolder('p1');
          await t.pumpAndSettle();
          // The wide bar's folder menu is not on the phone bar.
          expect(_k('scope-more'), findsNothing);
          await _openPicker(t);
          // No rows of its own: the actions live behind the selected row's \u22ef.
          expect(_k('scope-edit'), findsNothing);
          expect(_k('scope-close'), findsNothing);
          expect(_k('scope-more-p1'), findsOneWidget);
          await t.tap(_k('scope-more-p1'));
          await t.pumpAndSettle();
          expect(_k('scope-edit'), findsOneWidget);
          expect(_k('scope-delete'), findsOneWidget);
          // "Show the whole space" is in the \u22ef menu too.
          expect(_k('scope-close'), findsOneWidget);
          await t.tap(_k('scope-close'));
          await t.pumpAndSettle();
          expect(s.scopeUid, isNull);
          _noError(t);
        },
      );
    });
  }

  testWidgets('a lone real Space is not called a fixed source', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final storage = MemoryStorage();
    final c = catalogWithPlanning(storage);
    final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
    await s.load();
    await t.pumpWidget(DavdartApp(state: s));
    await t.pumpAndSettle();
    await t.tap(_k('menu'));
    await t.pumpAndSettle();
    await t.tap(_k('rail-spaces'));
    await t.pumpAndSettle();
    // Readable, writable and switchable: only a catalog-less source is a
    // fixed one.
    expect(_k('space-${SpaceCatalog.planningId}'), findsOneWidget);
    expect(find.text('One fixed notes source'), findsNothing);
    _noError(t);
  });

  testWidgets('the Spaces panel switches Space, on the phone too', (t) async {
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
    await t.tap(_k('menu'));
    await t.pumpAndSettle();
    await t.tap(_k('rail-spaces'));
    await t.pumpAndSettle();
    // The open Space is marked; the other one switches on a tap.
    expect(_k('space-$inbox'), findsOneWidget);
    expect(_k('space-${SpaceCatalog.planningId}'), findsOneWidget);
    await t.tap(_k('space-${SpaceCatalog.planningId}'));
    await t.pumpAndSettle();
    expect(s.currentSpaceId, SpaceCatalog.planningId);
    _noError(t);
  });
}
