import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _note(
  String uid,
  String title, {
  String? parent,
  String description = 'Body',
}) => Note(
  uid: uid,
  summary: title,
  parentUid: parent,
  description: description,
  lastModified: DateTime.now().toUtc(),
);

Future<AppState> _pump(WidgetTester t, {List<Note>? notes}) async {
  final s = await pumpTasksApp(t, notes: notes ?? [_note('n1', 'Alpha')]);
  s.select('n1');
  await t.pumpAndSettle();
  return s;
}

String _body(AppState s, [String uid = 'n1']) =>
    PlanItem.fromNote(s.tree.find(uid)!.note).text;

/// A projects container, a project and a note inside it.
final _projectNotes = [
  Note(
    uid: 'container',
    summary: 'Projects',
    categories: [folderTag, projectsTag],
  ),
  Note(
    uid: 'proj',
    summary: 'Alpha project',
    parentUid: 'container',
    categories: [folderTag],
  ),
  _note('n1', 'In project', parent: 'proj'),
];

void main() {
  group('a note page', () {
    testWidgets('the rows are the properties; the editor is the body alone', (
      t,
    ) async {
      await _pump(t);
      // Before the edit: the same rows a task has.
      for (final id in ['status', 'priority', 'tags', 'parent']) {
        expect(_k('property-$id'), findsOneWidget, reason: id);
      }
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      for (final id in ['status', 'priority', 'tags', 'parent']) {
        expect(_k('property-$id'), findsOneWidget, reason: id);
      }
      expect(_k('edit-body'), findsOneWidget);
      // The selectors the old editor carried are gone from the draft.
      expect(_k('edit-status'), findsNothing);
      expect(_k('edit-note-priority'), findsNothing);
      expect(_k('edit-tags'), findsNothing);
    });

    testWidgets('a status pick saves at once and leaves an Undo', (t) async {
      final s = await _pump(
        t,
        notes: [
          _note('n1', 'Alpha', description: 'status: todo\n\nBody of Alpha'),
        ],
      );
      expect(PlanItem.fromNote(s.tree.find('n1')!.note).status, 'todo');
      await t.tap(_k('property-status'));
      await t.pumpAndSettle();
      await t.tap(_k('property-option-status-doing'));
      await t.pumpAndSettle();
      expect(PlanItem.fromNote(s.tree.find('n1')!.note).status, 'doing');
      expect(find.text('Moved "Alpha" to doing'), findsOneWidget);
      await t.tap(_k('board-undo'));
      await t.pumpAndSettle();
      expect(PlanItem.fromNote(s.tree.find('n1')!.note).status, 'todo');
      expect(_body(s), 'Body of Alpha');
    });

    testWidgets('the title edits in place and saves on the pause', (t) async {
      final s = await _pump(t);
      await t.tap(_k('pane-title'));
      await t.pumpAndSettle();
      expect(_k('inline-text-editing'), findsOneWidget);
      expect(s.draftFor('n1'), isNotNull);
      await t.enterText(_k('edit-title'), 'Alpha two');
      await t.pump(const Duration(milliseconds: 900));
      await t.pumpAndSettle();
      expect(s.tree.find('n1')!.note.summary, 'Alpha two');
      expect(s.draftFor('n1')!.titleController.text, 'Alpha two');
      // The body is still the note's, untouched by the title's save.
      expect(_body(s), 'Body');
    });

    testWidgets('a pick then a body edit and save keep both', (t) async {
      final s = await _pump(t);
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-body'), 'New body');
      await t.pump();
      // Opening the labels row flushes the body first, so the pick and the
      // text land as one coherent item.
      await t.tap(_k('property-tags'));
      await t.pumpAndSettle();
      await t.enterText(_k('property-tag-tags-field'), 'home');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      // Let the label's Undo toast go, so it does not sit over the header.
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      await t.tap(_k('edit-save-action'));
      await t.pumpAndSettle();
      expect(s.isEditing('n1'), isFalse);
      final n = s.tree.find('n1')!.note;
      expect(PlanItem.fromNote(n).text, 'New body');
      expect(s.noteTagsOf(n), ['home']);
    });

    testWidgets('a belongs-to pick moves the note, and Undo moves it back', (
      t,
    ) async {
      final s = await _pump(t, notes: _projectNotes);
      expect(s.tree.find('n1')!.note.parentUid, 'proj');
      await t.tap(_k('property-parent'));
      await t.pumpAndSettle();
      await t.tap(_k('property-parent-parent-top'));
      await t.pumpAndSettle();
      expect(s.tree.find('n1')!.note.parentUid, isNull);
      expect(find.textContaining('Moved "In project"'), findsOneWidget);
      await t.tap(_k('board-undo'));
      await t.pumpAndSettle();
      expect(s.tree.find('n1')!.note.parentUid, 'proj');
    });
  });
}
