import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
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

final _notes = [
  _folder('c', 'Projects', container: true),
  _folder('p', 'Alpha', parent: 'c'),
  Note(uid: 'in-p', summary: 'Project note', parentUid: 'p'),
  _folder('f', 'Plans'),
  Note(uid: 'in-f', summary: 'In plans', parentUid: 'f'),
  Note(uid: 'loose', summary: 'Loose note'),
];

Finder _inPanel(String text) =>
    find.descendant(of: _k('notes-body'), matching: find.text(text));

Future<void> _end(WidgetTester t) => t.pump(const Duration(seconds: 1));

void main() {
  group('notes panel', () {
    testWidgets('the list is the default: the scope notes and folder labels', (
      t,
    ) async {
      final s = await pumpTasksApp(t, notes: _notes);
      expect(s.notesView, NotesView.list);
      // Personal scope: the Space's own notes, the projects layer left out.
      expect(_inPanel('Loose note'), findsOneWidget);
      expect(_inPanel('In plans'), findsOneWidget);
      expect(_inPanel('Project note'), findsNothing);
      // The folder a note sits in is its group label.
      expect(_k('notes-group-in-f'), findsOneWidget);
      expect(_inPanel('Plans'), findsWidgets);
      // A folder itself is not a list row.
      expect(_inPanel('Projects'), findsNothing);
      // The toggle is there because the scope has a folder.
      expect(_k('notes-view-toggle'), findsOneWidget);
      await _end(t);
    });

    testWidgets('the toggle shows the tree, and the choice is saved', (
      t,
    ) async {
      final prefs = MemoryStorage();
      final s = await pumpTasksApp(t, notes: _notes, prefs: prefs);
      await t.tap(_k('notes-view-tree'));
      await t.pumpAndSettle();
      expect(s.notesView, NotesView.tree);
      expect(prefs.read('davdart.notesview.v1'), 'tree');
      // The tree shows the folder rows, still restricted to the scope.
      expect(_inPanel('Plans'), findsWidgets);
      expect(_inPanel('Project note'), findsNothing);
      expect(find.byKey(const ValueKey('nav-notes-f')), findsOneWidget);
      // Saved for the next start.
      expect(
        AppState(SeedNotes(const []), prefs: prefs).notesView,
        NotesView.tree,
      );
      await t.tap(_k('notes-view-list'));
      await t.pumpAndSettle();
      expect(s.notesView, NotesView.list);
      await _end(t);
    });

    testWidgets('the project scope does not narrow the Personal panel', (
      t,
    ) async {
      final s = await pumpTasksApp(t, notes: _notes);
      s.openFolder('p');
      await t.pumpAndSettle();
      // Personal reads its own layer whatever the scope: project notes stay
      // in the project, loose and personal-folder notes stay here.
      expect(_inPanel('Project note'), findsNothing);
      expect(_inPanel('Loose note'), findsOneWidget);
      expect(_inPanel('In plans'), findsOneWidget);
      await _end(t);
    });

    testWidgets('without sub-folders a saved tree still shows the list', (
      t,
    ) async {
      final prefs = MemoryStorage()..write('davdart.notesview.v1', 'tree');
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'a', summary: 'Alone')],
        prefs: prefs,
      );
      expect(s.notesView, NotesView.tree);
      expect(_k('notes-view-toggle'), findsNothing);
      expect(_inPanel('Alone'), findsOneWidget);
      await _end(t);
    });
  });
}
