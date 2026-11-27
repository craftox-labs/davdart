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
  Note(uid: 'loose', summary: 'Loose note'),
];

Future<AppState> _app(WidgetTester t, MemoryStorage prefs) =>
    pumpTasksApp(t, notes: _notes, prefs: prefs);

void main() {
  testWidgets('closing the project tab with an unvisited note tab drops '
      'the project scope', (t) async {
    final prefs = MemoryStorage();
    final first = await _app(t, prefs);
    first.openNoteTab('loose');
    first.openProjectTab('p');
    await t.pumpAndSettle();
    expect(first.scopeUid, 'p');
    // Restart: only the active page is booked, the note tab is unvisited.
    final s = await _app(t, prefs);
    await t.pumpAndSettle();
    expect(s.activeTab, const DocTab.project('p'));
    expect(s.scopeUid, 'p');
    await s.closeTab(const DocTab.project('p'));
    await t.pumpAndSettle();
    expect(s.activeTab, const DocTab.note('loose'));
    expect(s.scopeUid, isNull);
    expect(prefs.read('davdart.scope.v1') ?? '', isNot(contains('"p"')));
  });
}
