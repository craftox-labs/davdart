import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/drag_drop.dart';
import 'package:davdart_app/ui/list_view.dart';
import 'package:flutter/widgets.dart';
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
  Note(uid: 'in-p', summary: 'Project note', parentUid: 'p'),
  _folder('f', 'Plans'),
  Note(uid: 'in-f', summary: 'In plans', parentUid: 'f'),
  Note(uid: 'loose', summary: 'Loose note'),
];

Finder _k(String k) => find.byKey(Key(k));

Finder _dropTargets(Finder within) => find.descendant(
  of: within,
  matching: find.byWidgetPredicate((w) => w is NoteDropTarget),
);

/// The uids of the draggable rows inside [within].
List<String> _dragged(WidgetTester t, Finder within) => [
  for (final w in t.widgetList<NoteDraggable>(
    find.descendant(of: within, matching: find.byType(NoteDraggable)),
  ))
    w.uid,
];

Future<void> _end(WidgetTester t) => t.pump(const Duration(seconds: 1));

void main() {
  group('folder drag scope', () {
    testWidgets('the list has no drop targets and no folder drags', (t) async {
      final s = await pumpTasksApp(t, notes: _notes);
      expect(s.notesView, NotesView.list);
      // The panel body is there (it takes the right-click menu), but nothing
      // in it takes a drop, and no folder row is a drag.
      expect(_k('notes-body'), findsOneWidget);
      expect(_k('drop-root'), findsNothing);
      expect(_dropTargets(_k('notes-body')), findsNothing);
      expect(
        _dragged(t, _k('notes-body')),
        unorderedMatches(['in-f', 'loose']),
      );
      await _end(t);
    });

    testWidgets('the tree keeps the top-level and folder drop targets', (
      t,
    ) async {
      final s = await pumpTasksApp(t, notes: _notes);
      await t.tap(_k('notes-view-tree'));
      await t.pumpAndSettle();
      expect(s.notesView, NotesView.tree);
      // The top level, then one per folder row in the scope (the top-level
      // target wraps the body, so only the folder row is inside it).
      expect(_k('drop-root'), findsOneWidget);
      expect(_k('drop-f'), findsOneWidget);
      expect(_dropTargets(_k('notes-body')), findsOneWidget);
      expect(
        _dragged(t, _k('notes-body')),
        unorderedMatches(['f', 'in-f', 'loose']),
      );
      await _end(t);
    });

    testWidgets('the main list is no drop target and folders do not drag', (
      t,
    ) async {
      final s = await pumpTasksApp(t, notes: _notes);
      s.setView(ViewMode.list);
      await t.runAsync(() => s.saveView('List'));
      s.applyView(s.savedViews.single);
      await t.pumpAndSettle();
      final list = find.byType(NoteListView);
      expect(list, findsOneWidget);
      // Folders are rows here, but they neither drag nor take a drop: folder
      // moves belong to the Notes tree only.
      expect(
        find.descendant(of: list, matching: find.text('Plans')),
        findsOneWidget,
      );
      final dragged = _dragged(t, list);
      expect(dragged, unorderedMatches(['in-p', 'in-f', 'loose']));
      expect(_dropTargets(list), findsNothing);
      await _end(t);
    });
  });
}
