import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

/// A desktop window narrow enough that the main area is the width a 1265-wide
/// window leaves it (the project Board the live check saw blank).
const _desktop = Size(1265, 800);

/// The Space every project here lives in: a Projects container with a project
/// [project] holding a task and a note in two statuses, and an empty project
/// [emptyProject] beside it.
const _container = 'c';
const _project = 'a';
const _emptyProject = 'b';

final _tree = [
  Note(
    uid: _container,
    summary: 'Projects',
    categories: [folderTag, projectsTag],
  ),
  Note(
    uid: _project,
    summary: 'Alpha',
    parentUid: _container,
    categories: [folderTag],
  ),
  Note(
    uid: _emptyProject,
    summary: 'Beta',
    parentUid: _container,
    categories: [folderTag],
  ),
];

/// The live route to a project's Board: the Projects panel's row, then the
/// page header's Board pill (never [AppState.setProjectTab]).
Future<AppState> _openBoard(WidgetTester t, String uid) async {
  final s = await pumpTasksApp(
    t,
    notes: [
      ..._tree,
      Note(
        uid: 'n1',
        summary: 'Write the brief',
        parentUid: _project,
        description: 'status: doing\n\nA first line',
      ),
    ],
    tasks: [mkTask('t1', summary: 'Ship the build', parent: _project)],
    size: _desktop,
  );
  s.setSection(Section.projects);
  await t.pumpAndSettle();
  await t.tap(_k('project-$uid'));
  await t.pumpAndSettle();
  await t.tap(_k('proj-tab-board'));
  await t.pumpAndSettle();
  expect(s.mainProjectUid, uid);
  expect(s.projectTab(uid), ProjectTab.board);
  return s;
}

/// Whether [inner] sits inside [outer] with a real size: the check a pixel
/// histogram misses on faint text and a card at the top of the page.
void _fits(Rect inner, Rect outer, {required String reason}) {
  expect(inner.height, greaterThan(0), reason: reason);
  expect(inner.width, greaterThan(0), reason: reason);
  expect(outer.contains(inner.topLeft), isTrue, reason: reason);
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + 0.5), reason: reason);
  expect(inner.right, lessThanOrEqualTo(outer.right + 0.5), reason: reason);
}

void main() {
  testWidgets('a project Board with items shows its columns and cards', (
    t,
  ) async {
    final s = await pumpHomeApp(
      t,
      notes: [
        Note(
          uid: 'n1',
          summary: 'Write the brief',
          description: 'status: doing',
        ),
      ],
      tasks: [mkTask('t1', summary: 'Ship the build')],
      size: _desktop,
    );
    expect(s.projectTab(testProjectUid), ProjectTab.board);
    expect(_k('proj-board-tab'), findsOneWidget);
    // One column per status in use, each with its cards inside it.
    final todo = _k('board-drop-todo');
    final doing = _k('board-drop-doing');
    expect(todo, findsOneWidget);
    expect(doing, findsOneWidget);
    expect(
      find.descendant(of: todo, matching: find.text('Ship the build')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: doing, matching: find.text('Write the brief')),
      findsOneWidget,
    );
    expect(_k('board-empty'), findsNothing);
  });

  testWidgets('a project with no work items says so instead of blank', (
    t,
  ) async {
    await pumpHomeApp(t, notes: [], size: _desktop);
    expect(_k('board-empty'), findsOneWidget);
    expect(find.text('No notes'), findsOneWidget);
    expect(_k('board-drop-todo'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'the live path draws the Board: panel, header pill (${brightness.name})',
      (t) async {
        t.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
        await _openBoard(t, _project);
        expect(_k('proj-board-tab'), findsOneWidget);
        final page = t.getRect(_k('proj-page'));
        // The columns are on the page and the task's card is inside its
        // column, not squeezed above or below it.
        expect(_k('board-drop-todo'), findsOneWidget);
        expect(_k('board-drop-doing'), findsOneWidget);
        final card = t.getRect(_k('task-card-t1'));
        _fits(card, t.getRect(_k('board-drop-todo')), reason: 'task card');
        _fits(card, page, reason: 'task card on the page');
        expect(find.text('Ship the build'), findsOneWidget);
        final noteCard = t.getRect(_k('card-snippet-n1'));
        _fits(noteCard, t.getRect(_k('board-drop-doing')), reason: 'note');
        expect(_k('board-empty'), findsNothing);
      },
    );

    testWidgets(
      'the live path says an empty project is empty (${brightness.name})',
      (t) async {
        t.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
        await _openBoard(t, _emptyProject);
        expect(_k('proj-board-tab'), findsOneWidget);
        final line = t.getRect(
          find.descendant(of: _k('board-empty'), matching: find.byType(Text)),
        );
        _fits(line, t.getRect(_k('proj-page')), reason: 'empty state');
        expect(find.textContaining('No work items yet'), findsOneWidget);
        expect(_k('board-drop-todo'), findsNothing);
      },
    );
  }

  testWidgets('a project Board still loading says so instead of blank', (
    t,
  ) async {
    // A project page restored with its Board tab before the Space has
    // loaded: no columns yet, and the area used to be an empty white box.
    final s = await pumpHomeApp(t, notes: [], size: _desktop);
    s.loading = true;
    s.setProjectTab(testProjectUid, ProjectTab.overview);
    s.setProjectTab(testProjectUid, ProjectTab.board);
    await t.pump();
    expect(_k('proj-board-tab'), findsOneWidget);
    expect(_k('board-empty'), findsOneWidget);
    expect(find.text('Loading…'), findsOneWidget);
  });
}
