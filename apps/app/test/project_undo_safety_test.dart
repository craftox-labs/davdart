import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';

import 'catalog_helper.dart';
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

Future<AppState> _app(WidgetTester t) => pumpTasksApp(
  t,
  notes: [
    _folder('pc', 'Personal', personal: true),
    _folder('c', 'Projects', container: true),
    _folder('p', 'Alpha', parent: 'c'),
    _note('a', 'Keep', parent: 'p'),
    _note('b', 'Edited', parent: 'p'),
    _note('d', 'Deleted later', parent: 'p'),
    _note('m', 'Moved later', parent: 'p'),
    _folder('other', 'Elsewhere'),
  ],
  tasks: [mkTask('pt', summary: 'Project task', parent: 'p')],
);

Note _n(AppState s, String uid) => s.notes.firstWhere((n) => n.uid == uid);

void main() {
  testWidgets('undo keeps later edits, deletions and moves', (t) async {
    final s = await _app(t);
    await s.deleteProject('p');
    await t.pumpAndSettle();
    final undo = s.pendingUndo!;
    // Later: an edit, a delete, a move elsewhere.
    await s.updateNote('b', title: 'Edited later');
    await s.deleteNote('d');
    await s.moveNote('m', 'other');
    await s.deleteTask('pt');
    // Later changes may have replaced pendingUndo; run the project's own.
    await undo.undo();
    await t.pumpAndSettle();
    expect(s.tree.find('p'), isNotNull);
    expect(_n(s, 'a').parentUid, 'p');
    expect(_n(s, 'b').parentUid, 'p');
    expect(_n(s, 'b').summary, 'Edited later');
    expect(s.tree.find('d'), isNull);
    expect(_n(s, 'm').parentUid, 'other');
    expect(s.tasks.any((k) => k.uid == 'pt'), isFalse);
  });

  test('a Space switch clears the pending Undo', () async {
    final prefs = MemoryStorage();
    final c = catalogWithPlanning(prefs, planningSeed: _Seed());
    final s = AppState(c.sourceFor(c.current!), prefs: prefs, catalog: c);
    await s.load();
    await s.deleteProject('p');
    expect(s.pendingUndo, isNotNull);
    await s.createSpace('Other');
    expect(s.pendingUndo, isNull);
  });
}

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    _folder('pc', 'Personal', personal: true),
    _folder('c', 'Projects', container: true),
    _folder('p', 'Alpha', parent: 'c'),
    _note('a', 'Keep', parent: 'p'),
  ];
}
