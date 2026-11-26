import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

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
      find.descendant(of: _k('drop-root'), matching: find.text('Loose note')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _k('drop-root'), matching: find.text('Project note')),
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
    await t.ensureVisible(_k('home-new-note'));
    await t.tap(_k('home-new-note'));
    await t.pumpAndSettle();
    await t.enterText(_k('new-note-title'), 'Personal note');
    await t.tap(_k('new-note-add'));
    await t.pumpAndSettle();
    final container = s.personalContainer;
    expect(container, isNotNull);
    expect(container!.categories, contains(personalTag));
    final note = s.notes.firstWhere((n) => n.summary == 'Personal note');
    expect(note.parentUid, container.uid);
    // A task and an event made from Home too.
    await t.tap(_k('home-new-task'));
    await t.pumpAndSettle();
    await t.enterText(_k('new-task-title'), 'Personal task');
    await t.tap(_k('new-task-add'));
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
}
