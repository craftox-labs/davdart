import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

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

final _notes = [
  _folder('c', 'Projects', container: true),
  _folder('p', 'Alpha', parent: 'c'),
  Note(uid: 'pn', summary: 'Project note', parentUid: 'p'),
  _folder('f', 'Plans'),
  Note(uid: 'n1', summary: 'In plans', parentUid: 'f'),
];

void main() {
  testWidgets('a booked project scope that was deleted is not restored', (
    t,
  ) async {
    final prefs = MemoryStorage();
    final s = await pumpTasksApp(t, notes: _notes, prefs: prefs);
    s.openProjectTab('p');
    s.openNoteTab('pn');
    s.showHome();
    await t.pumpAndSettle();
    await s.deleteNote('p');
    await t.pumpAndSettle();
    await s.activateTab(const DocTab.note('pn'));
    await t.pumpAndSettle();
    expect(s.scopeUid, isNull);
    expect(prefs.read('davdart.scope.v1') ?? '', isNot(contains('"p"')));
  });

  testWidgets('a booked folder scope that was deleted is not restored', (
    t,
  ) async {
    final s = await pumpTasksApp(t, notes: _notes);
    s.openFolder('f');
    s.openNoteTab('n1');
    s.showHome();
    await t.pumpAndSettle();
    await s.activateTab(const DocTab.note('n1'));
    s.showHome();
    await s.deleteNote('f');
    await t.pumpAndSettle();
    await s.activateTab(const DocTab.note('n1'));
    await t.pumpAndSettle();
    expect(s.scopeUid, isNull);
  });

  testWidgets('pruning the active project tab keeps Home\'s loose scope', (
    t,
  ) async {
    final prefs = MemoryStorage();
    final s = await pumpTasksApp(t, notes: _notes, prefs: prefs);
    s.openFolder('f');
    s.openProjectTab('p');
    await t.pumpAndSettle();
    expect(s.scopeUid, 'p');
    await s.deleteNote('p');
    await t.pumpAndSettle();
    expect(s.activeTab, isNull);
    expect(s.scopeUid, 'f');
    expect(prefs.read('davdart.scope.v1'), contains('"f"'));
    // And it is still Home's own scope after a trip through a note tab.
    s.openNoteTab('n1');
    s.showHome();
    await t.pumpAndSettle();
    expect(s.scopeUid, 'f');
  });
}
