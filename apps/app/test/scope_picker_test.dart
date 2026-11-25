import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

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
  _folder('loose', 'Loose notes'),
];

Future<AppState> _app(WidgetTester t, Size size) async {
  final s = await pumpTasksApp(t, size: size, notes: _seed);
  await s.activateTab(null);
  await t.pumpAndSettle();
  return s;
}

String _text(WidgetTester t, String key) => t.widget<Text>(_k(key)).data!;

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

      testWidgets('the pill sheet: Everything, projects, then Spaces', (
        t,
      ) async {
        final s = await _app(t, size);
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsOneWidget);
        // Everything, then the projects, then the Space sheet's own rows
        // (one fixed source here).
        final sheetSpaces = find.text('One fixed notes source');
        expect(sheetSpaces, findsOneWidget);
        expect(_k('scope-pick-all'), findsOneWidget);
        expect(_k('scope-pick-p1'), findsOneWidget);
        expect(_k('scope-pick-p2'), findsOneWidget);
        expect(
          t.getRect(_k('scope-pick-all')).top,
          lessThan(t.getRect(sheetSpaces).top),
        );
        // One tap on a project scopes to it and closes the sheet.
        await t.tap(_k('scope-pick-p2'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(s.scopeUid, 'p2');
        expect(_text(t, 'scope-pill-project'), 'Beta');
        // Everything clears the scope.
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        await t.tap(_k('scope-pick-all'));
        await t.pumpAndSettle();
        expect(s.scopeUid, isNull);
        expect(_text(t, 'scope-pill-space'), 'Spaces');
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

      testWidgets('the sheet\'s folder dialogs open from the pill', (t) async {
        final s = await _app(t, size);
        s.openFolder('p1');
        await t.pumpAndSettle();
        // Edit folder: the sheet closes and its dialog opens.
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        await t.tap(_k('scope-edit'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(find.text('Edit folder'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        // Delete folder: the confirm dialog opens.
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        await t.tap(_k('scope-delete'));
        await t.pumpAndSettle();
        expect(find.text('Delete note?'), findsOneWidget);
        expect(_k('delete-confirm'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(s.scopeUid, 'p1');
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

      testWidgets('the folder actions are in the sheet, not the top bar', (
        t,
      ) async {
        final s = await _app(t, size);
        s.openFolder('p1');
        await t.pumpAndSettle();
        expect(_k('scope-more'), findsNothing);
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        expect(_k('scope-edit'), findsOneWidget);
        expect(_k('scope-delete'), findsOneWidget);
        await t.tap(_k('scope-close'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(s.scopeUid, isNull);
        _noError(t);
      });
    });
  }
}
