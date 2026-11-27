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

Note _note(String uid, String summary, {String? parent}) =>
    Note(uid: uid, summary: summary, parentUid: parent);

final _notes = [
  _folder('c', 'Projects', container: true),
  _folder('p', 'Alpha', parent: 'c'),
  _note('pn', 'Project note', parent: 'p'),
  _folder('f', 'Plans'),
  _note('n1', 'In plans', parent: 'f'),
  _note('n2', 'Also in plans', parent: 'f'),
  _note('loose', 'Loose note'),
];

Future<AppState> _app(WidgetTester t, {MemoryStorage? prefs}) => pumpTasksApp(
  t,
  notes: _notes,
  tasks: [mkTask('tt', summary: 'Project task', parent: 'p')],
  events: [mkEvent('ee', summary: 'Project event', parent: 'p')],
  prefs: prefs,
);

String? _savedScope(MemoryStorage prefs) => prefs.read('davdart.scope.v1');

void main() {
  testWidgets('a loose folder scope on Home survives a note tab', (t) async {
    final prefs = MemoryStorage();
    final s = await _app(t, prefs: prefs);
    // Home is at the folder, not at a project.
    s.openFolder('f');
    await t.pumpAndSettle();
    expect(s.scopeUid, 'f');
    s.openNoteTab('n1');
    await t.pumpAndSettle();
    // The note tab is shown at the scope it was opened at.
    expect(s.scopeUid, 'f');
    await s.closeTab(const DocTab.note('n1'));
    await t.pumpAndSettle();
    // Back on Home: the folder scope is still the scope, saved too.
    expect(s.activeTab, isNull);
    expect(s.scopeUid, 'f');
    expect(_savedScope(prefs), contains('"f"'));
  });

  testWidgets('closing an unrelated tab leaves the scope alone', (t) async {
    final prefs = MemoryStorage();
    final s = await _app(t, prefs: prefs);
    s.openNoteTab('n1');
    s.openProjectTab('p');
    await t.pumpAndSettle();
    expect(s.activeTab, const DocTab.project('p'));
    expect(s.scopeUid, 'p');
    // Another tab goes; the open project page and its scope stay.
    await s.closeTab(const DocTab.note('n1'));
    await t.pumpAndSettle();
    expect(s.activeTab, const DocTab.project('p'));
    expect(s.scopeUid, 'p');
    expect(_savedScope(prefs), contains('"p"'));
  });

  testWidgets('a project page owns its project; other pages keep theirs', (
    t,
  ) async {
    final s = await _app(t);
    expect(s.scopeUid, isNull);
    s.openProjectTab('p');
    await t.pumpAndSettle();
    expect(s.scopeUid, 'p');
    // A note tab opened inside the project keeps the project scope.
    s.openNoteTab('pn');
    await t.pumpAndSettle();
    expect(s.scopeUid, 'p');
    // Home is personal: the project's scope is not Home's.
    s.showHome();
    await t.pumpAndSettle();
    expect(s.activeTab, isNull);
    expect(s.scopeUid, isNull);
    // Going back to the note tab brings its scope back.
    await s.activateTab(const DocTab.note('pn'));
    await t.pumpAndSettle();
    expect(s.scopeUid, 'p');
    await s.activateTab(const DocTab.project('p'));
    await t.pumpAndSettle();
    expect(s.scopeUid, 'p');
  });

  testWidgets('task and event tabs own the scope too', (t) async {
    final s = await _app(t);
    s.openProjectTab('p');
    await t.pumpAndSettle();
    s.openTaskTab('tt');
    await t.pumpAndSettle();
    expect(s.scopeUid, 'p');
    s.openEventTab('ee');
    await t.pumpAndSettle();
    expect(s.scopeUid, 'p');
    s.showHome();
    await t.pumpAndSettle();
    expect(s.scopeUid, isNull);
    await s.activateTab(const DocTab.task('tt'));
    await t.pumpAndSettle();
    expect(s.scopeUid, 'p');
    await s.activateTab(const DocTab.event('ee'));
    await t.pumpAndSettle();
    expect(s.scopeUid, 'p');
    await s.activateTab(null);
    await t.pumpAndSettle();
    expect(s.scopeUid, isNull);
  });

  testWidgets('the next tab brings back the scope it was left at', (t) async {
    final s = await _app(t);
    s.openFolder('f');
    s.openNoteTab('loose');
    s.openProjectTab('p');
    await t.pumpAndSettle();
    expect(s.scopeUid, 'p');
    await s.closeTab(const DocTab.project('p'));
    await t.pumpAndSettle();
    // When it was left, the note tab was at the loose folder scope.
    expect(s.activeTab, const DocTab.note('loose'));
    expect(s.scopeUid, 'f');
  });

  testWidgets('a session with a saved loose scope restores it on Home', (
    t,
  ) async {
    final prefs = MemoryStorage()..write('davdart.scope.v1', '{"default":"f"}');
    final s = await _app(t, prefs: prefs);
    expect(s.activeTab, isNull);
    expect(s.scopeUid, 'f');
    // And it survives leaving Home and coming back.
    s.openNoteTab('loose');
    await t.pumpAndSettle();
    expect(s.scopeUid, 'f');
    s.showHome();
    await t.pumpAndSettle();
    expect(s.scopeUid, 'f');
  });
}
