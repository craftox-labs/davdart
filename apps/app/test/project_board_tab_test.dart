import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

/// A desktop window narrow enough that the main area is the width a 1265-wide
/// window leaves it (the project Board the live check saw blank).
const _desktop = Size(1265, 800);

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
