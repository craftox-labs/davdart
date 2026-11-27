import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

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

/// A project with a note, a task and an event under it, a sub-note two
/// levels down, and a loose note that must be left alone.
Future<AppState> _app(WidgetTester t) => pumpTasksApp(
  t,
  notes: [
    _folder('pc', 'Personal', personal: true),
    _folder('c', 'Projects', container: true),
    _folder('p', 'Alpha', parent: 'c'),
    _note('pn', 'Project note', parent: 'p'),
    _note('deep', 'Deep note', parent: 'pn'),
    _note('loose', 'Loose note'),
  ],
  tasks: [mkTask('pt', summary: 'Project task', parent: 'p')],
  events: [mkEvent('pe', summary: 'Project event', parent: 'p')],
);

String? _parent(AppState s, String uid) => s.tree.find(uid)?.note.parentUid;

void main() {
  testWidgets('undo of a deleted project brings its children back under it', (
    t,
  ) async {
    final s = await _app(t);
    await s.deleteProject('p');
    await t.pumpAndSettle();
    final undo = s.pendingUndo!;
    // Deleted: the folder is gone, its children moved to Personal.
    expect(s.tree.find('p'), isNull);
    final home = s.personalContainer!.uid;
    expect(_parent(s, 'pn'), home);
    expect(s.tasks.firstWhere((k) => k.uid == 'pt').parentUid, home);
    expect(s.events.firstWhere((e) => e.uid == 'pe').parentUid, home);

    await s.undoBoard(undo);
    await t.pumpAndSettle();
    // Back: the project note and everything that was under it.
    expect(s.tree.find('p'), isNotNull);
    expect(s.projectIndex.isProject('p'), isTrue);
    expect(_parent(s, 'pn'), 'p');
    expect(_parent(s, 'deep'), 'pn');
    expect(s.tasks.firstWhere((k) => k.uid == 'pt').parentUid, 'p');
    expect(s.events.firstWhere((e) => e.uid == 'pe').parentUid, 'p');
    // Untouched: the loose note stays where it was.
    expect(_parent(s, 'loose'), isNull);
    expect(s.pendingUndo, isNull);
  });

  testWidgets('the deleted project comes back with nothing else changed', (
    t,
  ) async {
    final s = await _app(t);
    final before = s.notes.map((n) => '${n.uid}:${n.parentUid}').toList()
      ..sort();
    await s.deleteProject('p');
    await t.pumpAndSettle();
    await s.undoBoard(s.pendingUndo!);
    await t.pumpAndSettle();
    expect(
      s.notes.map((n) => '${n.uid}:${n.parentUid}').toList()..sort(),
      before,
    );
  });
}
