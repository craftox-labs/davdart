import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/move_folder_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _folder(
  String uid,
  String name, {
  String? parent,
  bool container = false,
  bool personal = false,
}) => Note(
  uid: uid,
  summary: name,
  parentUid: parent,
  categories: [
    folderTag,
    if (container) projectsTag,
    if (personal) personalTag,
  ],
);

Note _note(String uid, String summary, {String? parent}) =>
    Note(uid: uid, summary: summary, parentUid: parent);

Future<AppState> _app(WidgetTester t) => pumpTasksApp(
  t,
  notes: [
    _folder('c', 'Projects', container: true),
    _folder('p', 'Alpha', parent: 'c'),
    _note('pn', 'Project note', parent: 'p'),
    _note('loose', 'Loose note'),
  ],
  tasks: [
    mkTask('pt', summary: 'Project task', parent: 'p'),
    mkTask('lt', summary: 'Loose task'),
  ],
  events: [
    mkEvent('pe', summary: 'Project event', parent: 'p'),
    mkEvent('le', summary: 'Loose event'),
  ],
);

void main() {
  testWidgets('the Personal panels show only the personal layer', (t) async {
    final s = await _app(t);
    // The project scope is open, yet the panels stay personal.
    s.openProjectTab('p');
    await t.pumpAndSettle();
    s.setSection(Section.notes);
    await t.pumpAndSettle();
    expect(
      find.descendant(of: _k('notes-body'), matching: find.text('Loose note')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _k('notes-body'),
        matching: find.text('Project note'),
      ),
      findsNothing,
    );
    s.setSection(Section.tasks);
    await t.pumpAndSettle();
    expect(
      find.descendant(of: _k('tasks-view'), matching: find.text('Loose task')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _k('tasks-view'),
        matching: find.text('Project task'),
      ),
      findsNothing,
    );
    s.setSection(Section.events);
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: _k('events-view'),
        matching: find.text('Loose event'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _k('events-view'),
        matching: find.text('Project event'),
      ),
      findsNothing,
    );
  });

  testWidgets('Home new items go under a Personal container, created lazily', (
    t,
  ) async {
    final s = await _app(t);
    await t.runAsync(() => s.addNote('Personal note', personal: true));
    await t.pumpAndSettle();
    final container = s.personalContainer;
    expect(container, isNotNull);
    expect(container!.categories, contains(personalTag));
    final note = s.notes.firstWhere((n) => n.summary == 'Personal note');
    expect(note.parentUid, container.uid);
    // A task made the same way.
    await t.runAsync(() => s.addTask('Personal task', personal: true));
    await t.pumpAndSettle();
    expect(
      s.tasks.firstWhere((k) => k.summary == 'Personal task').parentUid,
      container.uid,
    );
    // The container is an ordinary folder; only one is made.
    expect(s.notes.where((n) => n.categories.contains(personalTag)).length, 1);
  });

  testWidgets('Home See all opens the personal Tasks list, not the project', (
    t,
  ) async {
    final s = await _app(t);
    s.openProjectTab('p');
    await t.pumpAndSettle();
    // Back Home: scope cleared.
    s.showHome();
    await t.pumpAndSettle();
    await t.ensureVisible(_k('home-tasks-all'));
    await t.tap(_k('home-tasks-all'));
    await t.pumpAndSettle();
    expect(s.section, Section.tasks);
    expect(
      find.descendant(of: _k('tasks-view'), matching: find.text('Loose task')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _k('tasks-view'),
        matching: find.text('Project task'),
      ),
      findsNothing,
    );
  });

  testWidgets('a Personal container is never an item or a tree row', (t) async {
    final s = await pumpTasksApp(
      t,
      notes: [
        _folder('pc', 'Personal', personal: true),
        _note('inside', 'Inside personal', parent: 'pc'),
        _note('loose', 'Loose note'),
      ],
    );
    expect(s.personalNotes.map((n) => n.uid), isNot(contains('pc')));
    expect(s.filteredPersonal.map((n) => n.uid), isNot(contains('pc')));
    // The whole-Space tree hides the container and promotes its children.
    expect(s.spaceTreeRoots.map((n) => n.note.uid), contains('inside'));
    expect(s.spaceTreeRoots.map((n) => n.note.uid), isNot(contains('pc')));
    // Home's loose list never shows it as a recent note either.
    expect(find.text('Personal'), findsNothing);
  });

  testWidgets('a read-only Space makes no container and does not fail', (
    t,
  ) async {
    final s = await pumpTasksApp(t, readOnly: true, notesReadOnly: true);
    expect(await s.ensurePersonalContainer(), isNull);
    expect(s.error, isNull);
    expect(s.personalContainer, isNull);
    // The item falls back to the top level instead of throwing.
    final uid = await s.addTask('Read only task', personal: true);
    expect(s.error, isNull);
    expect(s.personalContainer, isNull);
    if (uid != null) expect(s.taskById(uid)!.parentUid, isNull);
  });

  testWidgets('concurrent personal adds make one container', (t) async {
    final s = await pumpTasksApp(t);
    final ids = await Future.wait([
      s.ensurePersonalContainer(),
      s.ensurePersonalContainer(),
    ]);
    await t.pumpAndSettle();
    expect(ids[0], isNotNull);
    expect(ids[1], ids[0]);
    expect(s.notes.where(isPersonalContainer).length, 1);
  });

  testWidgets('two containers: the oldest is used', (t) async {
    final old = DateTime.utc(2026, 1, 1), young = DateTime.utc(2026, 2, 1);
    final s = await pumpTasksApp(
      t,
      notes: [
        Note(
          uid: 'pc-young',
          summary: 'Personal',
          categories: [folderTag, personalTag],
          created: young,
        ),
        Note(
          uid: 'pc-old',
          summary: 'Personal',
          categories: [folderTag, personalTag],
          created: old,
        ),
      ],
    );
    expect(s.personalContainer!.uid, 'pc-old');
    expect(await s.ensurePersonalContainer(), 'pc-old');
  });

  testWidgets('non-personal move targets hide the Personal container', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      notes: [
        _folder('pc', 'Personal', personal: true),
        _folder('pf', 'A folder', parent: 'pc'),
        _note('loose', 'Loose note'),
      ],
    );
    showMoveFolderDialog(
      t.element(find.byKey(const Key('home-page'))),
      s,
      s.tree.find('loose')!.note,
    );
    await t.pumpAndSettle();
    expect(_k('move-folder-pc'), findsNothing);
    // Its child folder stays reachable.
    expect(_k('move-folder-pf'), findsOneWidget);
  });

  testWidgets('move dialog offers Personal and projects, not the container', (
    t,
  ) async {
    final s = await _app(t);
    showMoveFolderDialog(
      t.element(find.byKey(const Key('home-page'))),
      s,
      s.tree.find('loose')!.note,
    );
    await t.pumpAndSettle();
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Top level'), findsNothing);
    expect(_k('move-folder-c'), findsNothing);
    expect(_k('move-folder-p'), findsOneWidget);
    expect(
      find.descendant(of: _k('move-folder-p'), matching: find.text('Alpha')),
      findsOneWidget,
    );
  });

  testWidgets('moving a top-level note to Personal uses the container', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      notes: [
        _folder('pc', 'Personal', personal: true),
        _note('loose', 'Loose note'),
      ],
    );
    showMoveFolderDialog(
      t.element(find.byKey(const Key('home-page'))),
      s,
      s.tree.find('loose')!.note,
    );
    await t.pumpAndSettle();
    await t.tap(_k('move-folder-personal'));
    await t.pumpAndSettle();
    expect(s.tree.find('loose')!.note.parentUid, 'pc');
  });

  testWidgets('a note already in Personal has the row disabled', (t) async {
    final s = await pumpTasksApp(
      t,
      notes: [
        _folder('pc', 'Personal', personal: true),
        _note('inside', 'Inside', parent: 'pc'),
      ],
    );
    showMoveFolderDialog(
      t.element(find.byKey(const Key('home-page'))),
      s,
      s.tree.find('inside')!.note,
    );
    await t.pumpAndSettle();
    expect(t.widget<FItem>(_k('move-folder-personal')).enabled, isFalse);
  });

  testWidgets('read-only, no container: a top-level note cannot move', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      notesReadOnly: true,
      notes: [_note('loose', 'Loose note')],
    );
    showMoveFolderDialog(
      t.element(find.byKey(const Key('home-page'))),
      s,
      s.tree.find('loose')!.note,
    );
    await t.pumpAndSettle();
    expect(t.widget<FItem>(_k('move-folder-personal')).enabled, isFalse);
  });

  testWidgets('with no container, a move to Personal creates it', (t) async {
    final s = await _app(t);
    expect(s.personalContainer, isNull);
    showMoveFolderDialog(
      t.element(find.byKey(const Key('home-page'))),
      s,
      s.tree.find('loose')!.note,
    );
    await t.pumpAndSettle();
    expect(t.widget<FItem>(_k('move-folder-personal')).enabled, isTrue);
    await t.tap(_k('move-folder-personal'));
    await t.pumpAndSettle();
    final container = s.personalContainer;
    expect(container, isNotNull);
    expect(s.tree.find('loose')!.note.parentUid, container!.uid);
  });
}
