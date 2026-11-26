import 'package:davdart/davdart.dart';
import 'package:davdart_app/ui/move_folder_dialog.dart';
import 'package:davdart_app/ui/new_note_dialog.dart';
import 'package:davdart_app/ui/tab_strip.dart';
import 'package:forui/forui.dart';
import 'package:davdart_app/ui/scope_bar.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

final _notes = [
  Note(uid: 'c', summary: 'Projects', categories: [folderTag, projectsTag]),
  Note(uid: 'a', summary: 'Alpha', parentUid: 'c', categories: [folderTag]),
  Note(uid: 'n1', summary: 'Inside', parentUid: 'a'),
];

void main() {
  _mediumTests();
  _emptyTests();
  testWidgets('back to all projects leaves the project page', (t) async {
    final s = await pumpTasksApp(t, notes: _notes);
    s.openProjectTab('a');
    await t.pumpAndSettle();
    expect(s.mainProjectUid, 'a');
    leaveProject(s);
    await t.pumpAndSettle();
    expect(s.scopeUid, isNull);
    expect(s.mainProjectUid, isNull);
    expect(
      s.activeTab,
      isNull,
      reason: 'Home, not a project tab with no scope',
    );
  });

  testWidgets('global New entries create inside an open project', (t) async {
    final s = await pumpTasksApp(t, notes: _notes);
    expect(createsPersonal(s), isTrue);
    s.openProjectTab('a');
    await t.pumpAndSettle();
    expect(createsPersonal(s), isFalse);
    final id = await t.runAsync(() => s.addTask('In project'));
    expect(s.tasks.firstWhere((k) => k.uid == id).parentUid, 'a');
    s.openFolder('c');
    expect(
      createsPersonal(s),
      isTrue,
      reason: 'the hidden container is no scope',
    );
  });

  testWidgets('the project menu offers project dialogs', (t) async {
    final s = await pumpTasksApp(t, notes: _notes);
    s.openProjectTab('a');
    await t.pumpAndSettle();
    final ctx = t.element(
      find
          .descendant(
            of: find.byType(Navigator).first,
            matching: find.byType(Overlay),
          )
          .first,
    );
    final items = scopeActionItems(
      ctx,
      s,
      s.notes.firstWhere((n) => n.uid == 'a'),
    );
    final edit = items.firstWhere((i) => i.key == const Key('scope-edit'));
    edit.onPress();
    await t.pumpAndSettle();
    expect(find.text('Edit project'), findsOneWidget);
    expect(_k('edit-parent'), findsNothing, reason: 'no Inside picker');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    final del = items.firstWhere((i) => i.key == const Key('scope-delete'));
    del.onPress();
    await t.pumpAndSettle();
    expect(find.text('Delete project?'), findsOneWidget);
    expect(find.textContaining('move to Personal'), findsOneWidget);
    await t.tap(_k('delete-confirm'));
    await t.pumpAndSettle();
    expect(s.notes.any((n) => n.uid == 'a'), isFalse);
    expect(s.mainProjectUid, isNull);
  });
}

void _emptyTests() {
  testWidgets(
    'an editable Space with no project shows the first-project entry',
    (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'x', summary: 'X')],
      );
      s.setSection(Section.projects);
      await t.pumpAndSettle();
      expect(_k('projects-empty-new'), findsOneWidget);
      await t.tap(_k('projects-empty-new'));
      await t.pumpAndSettle();
      expect(_k('new-project-title'), findsOneWidget);
    },
  );
}

void _mediumTests() {
  testWidgets('one icon for an event tab, one list of icons', (t) async {
    final s = await pumpTasksApp(t, notes: _notes);
    expect(tabStripIcon(s, DocTab.event('e')), FLucideIcons.calendar);
  });

  testWidgets('the top bar offers project actions only on a project page', (
    t,
  ) async {
    final s = await pumpTasksApp(t, notes: _notes);
    s.openProjectTab('a');
    await t.pumpAndSettle();
    expect(_k('scope-more'), findsOneWidget);
    s.showHome();
    s.openFolder('a'); // a leftover scope behind Home
    await t.pumpAndSettle();
    expect(s.activeTab, isNull);
    expect(_k('scope-more'), findsNothing);
  });
  testWidgets('"more" on the Overview opens the project Board', (t) async {
    final s = await pumpTasksApp(
      t,
      notes: _notes,
      tasks: [for (var i = 0; i < 10; i++) mkTask('t$i', parent: 'a')],
    );
    s.openProjectTab('a');
    await t.pumpAndSettle();
    await t.ensureVisible(_k('overview-tasks-more'));
    await t.tap(_k('overview-tasks-more'));
    await t.pumpAndSettle();
    expect(s.mainProjectTab, ProjectTab.board);
  });

  testWidgets('a project cannot be moved into Personal', (t) async {
    final s = await pumpTasksApp(t, notes: _notes);
    final ctx = t.element(
      find
          .descendant(
            of: find.byType(Navigator).first,
            matching: find.byType(Overlay),
          )
          .first,
    );
    showMoveFolderDialog(ctx, s, s.notes.firstWhere((n) => n.uid == 'a'));
    await t.pumpAndSettle();
    expect(t.widget<FItem>(_k('move-folder-personal')).enabled, isFalse);
  });
}
