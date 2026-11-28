import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/markdown_lite.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

/// A task store that stops writing while [broken] is set, so a pick can fail
/// the way a store error does.
class _BrokenStore extends MemoryTaskStore {
  var broken = false;

  @override
  Future<void> put(String uid, StoredTask s) async {
    if (broken) throw StateError('store is broken');
    return super.put(uid, s);
  }
}

class _App {
  _App(this.state, this.store);
  final AppState state;
  final _BrokenStore store;
}

/// Pumps the app on one task, whose store can be made to fail.
Future<_App> _pump(
  WidgetTester t, {
  Task? task,
  List<Note> notes = const [],
  Size size = const Size(1280, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final store = _BrokenStore();
  final src = SpaceNoteSource(
    Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore()),
    seed: SeedNotes(notes),
    taskStore: store,
  );
  final k = task ?? mkTask('k', summary: 'Pay rent');
  await t.runAsync(() => src.saveTask(k));
  final s = FlagState(src, prefs: MemoryStorage());
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  s.select(k.uid);
  await t.pumpAndSettle();
  return _App(s, store);
}

/// A projects container, a project in it, and a plain note in the project.
final _projectNotes = [
  Note(
    uid: 'container',
    summary: 'Projects',
    categories: [folderTag, projectsTag],
  ),
  Note(
    uid: 'proj',
    summary: 'Alpha',
    parentUid: 'container',
    categories: [folderTag],
  ),
  Note(uid: 'notes', summary: 'Notes', parentUid: 'proj'),
];

void main() {
  group('a task page', () {
    testWidgets('no pencil and no Save or Cancel: the rows are the fields', (
      t,
    ) async {
      final app = await _pump(t);
      for (final k in ['edit-note', 'edit-save-action', 'edit-cancel-action']) {
        expect(_k(k), findsNothing, reason: k);
      }
      // The property rows, in order.
      for (final id in ['status', 'priority', 'due', 'start', 'tags']) {
        expect(_k('property-$id'), findsOneWidget, reason: id);
      }
      expect(_k('property-parent'), findsOneWidget);
      expect(find.text('status'), findsOneWidget);
      expect(find.text('needs-action'), findsOneWidget);
      expect(app.state.taskById('k')!.summary, 'Pay rent');
    });

    testWidgets('the title saves on the pause, and on a blur', (t) async {
      final app = await _pump(t);
      await t.tap(_k('pane-title'));
      await t.pumpAndSettle();
      expect(_k('inline-text-editing'), findsOneWidget);
      await t.enterText(_k('edit-title'), 'Pay the rent');
      await t.pump(const Duration(milliseconds: 900));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.summary, 'Pay the rent');
      // A second edit saves as soon as the field loses the focus.
      await t.enterText(_k('edit-title'), 'Pay the rent twice');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.summary, 'Pay the rent twice');
      expect(_k('inline-text-editing'), findsNothing);
    });

    testWidgets('Esc puts the typed title back and closes the field', (
      t,
    ) async {
      final app = await _pump(t);
      await t.tap(_k('pane-title'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), 'Half typed');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.summary, 'Pay rent');
      expect(app.state.taskDraftFor('k')!.titleController.text, 'Pay rent');
      expect(_k('inline-text-editing'), findsNothing);
    });

    testWidgets('a status pick saves at once and leaves an Undo', (t) async {
      final app = await _pump(t);
      await t.tap(_k('property-status'));
      await t.pumpAndSettle();
      await t.tap(_k('property-option-status-doing'));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.boardStatus, 'doing');
      expect(find.text('Moved "Pay rent" to doing'), findsOneWidget);
      await t.tap(_k('board-undo'));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.boardStatus, 'todo');
    });

    testWidgets('the due and start rows pick a day at once', (t) async {
      final app = await _pump(t, task: mkTask('k', summary: 'Pay rent'));
      await t.tap(_k('property-due'));
      await t.pumpAndSettle();
      t.takeException(); // the test font overflows the calendar header
      await t.tap(_k('property-date-due-tomorrow'));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.due, dueIn(1));
      await t.tap(_k('property-start'));
      await t.pumpAndSettle();
      t.takeException();
      await t.tap(_k('property-date-start-today'));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.dtstart, dueIn(0));
    });

    testWidgets('a label toggles from the tags picker, at once', (t) async {
      final app = await _pump(
        t,
        task: mkTask('k', summary: 'Pay rent', tags: ['home']),
      );
      await t.tap(_k('property-tags'));
      await t.pumpAndSettle();
      await t.tap(_k('property-tag-tags-home'));
      await t.pumpAndSettle();
      expect(app.state.taskTagsOf(app.state.taskById('k')!), isEmpty);
      await t.enterText(_k('property-tag-tags-field'), 'bills');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(app.state.taskTagsOf(app.state.taskById('k')!), ['bills']);
    });

    testWidgets('a label pick and an Undo are not undone by a text save', (
      t,
    ) async {
      final app = await _pump(
        t,
        task: mkTask('k', summary: 'Pay rent', tags: ['home']),
      );
      await t.tap(_k('pane-title'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), 'Pay rent now');
      // A pick lands, then its Undo, while the title is still typing.
      await t.runAsync(() async {
        await app.state.setTaskTags('k', ['home', 'bills']);
        await app.state.undoBoard(app.state.pendingUndo!);
      });
      await t.pump(const Duration(milliseconds: 900));
      await t.pumpAndSettle();
      final task = app.state.taskById('k')!;
      expect(task.summary, 'Pay rent now');
      // The labels are back to what the Undo put there.
      expect(app.state.taskTagsOf(task), ['home']);
    });

    testWidgets('a sub-task shows a crumb to its parent, which opens it', (
      t,
    ) async {
      final app = await _pump(
        t,
        task: mkTask('k', summary: 'Pay rent', parent: 'plans'),
        notes: [Note(uid: 'plans', summary: 'Plans')],
      );
      expect(_k('parent-crumb'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('parent-crumb'),
          matching: find.byKey(const Key('parent-crumb-label')),
        ),
        findsOneWidget,
      );
      expect(t.widget<Text>(_k('parent-crumb-label')).data, 'Plans');
      // The crumb sits above the title row.
      expect(
        t.getRect(_k('parent-crumb')).bottom,
        lessThanOrEqualTo(t.getRect(_k('peek-toolbar')).top),
      );
      await t.tap(_k('parent-crumb-label'));
      await t.pumpAndSettle();
      // The peek's parent takes the peek.
      expect(app.state.peekUid, 'plans');
      expect(_k('parent-crumb'), findsNothing);
    });

    testWidgets('a sub-task shows its parent task in the crumb and opens it', (
      t,
    ) async {
      final app = await _pump(
        t,
        task: mkTask('k', summary: 'Pay rent', parent: 'p'),
        notes: [
          ..._projectNotes,
          Note(uid: 'other', summary: 'Parent task', parentUid: 'proj'),
        ],
      );
      await t.runAsync(
        () => app.state.addTask('Parent task', parentUid: 'proj'),
      );
      await t.pumpAndSettle();
      final parent = app.state.tasks.firstWhere(
        (x) => x.summary == 'Parent task',
      );
      // No Undo toast in the way of the crumb: the move writes directly.
      await t.runAsync(
        () => app.state.updateTask('k', setParent: true, parentUid: parent.uid),
      );
      await t.pumpAndSettle();
      // The crumb names the parent task, and the row says what it sits in.
      expect(_k('parent-crumb'), findsOneWidget);
      expect(t.widget<Text>(_k('parent-crumb-label')).data, 'Parent task');
      expect(find.text('Parent task'), findsWidgets);
      // Tapping the crumb opens the parent task in the peek, which then
      // shows the project it sits in.
      await t.tap(_k('parent-crumb-label'));
      await t.pumpAndSettle();
      expect(app.state.peekUid, parent.uid);
      expect(t.widget<Text>(_k('parent-crumb-label')).data, 'Alpha');
    });

    testWidgets('a top-level task has no crumb', (t) async {
      await _pump(t, task: mkTask('k', summary: 'Pay rent'));
      expect(_k('parent-crumb'), findsNothing);
    });

    testWidgets('the project row moves the task at once', (t) async {
      final app = await _pump(
        t,
        task: mkTask('k', summary: 'Pay rent'),
        notes: _projectNotes,
      );
      // The row reads Personal until the task is put in a project.
      expect(find.text('Personal'), findsOneWidget);
      await t.tap(_k('property-parent'));
      await t.pumpAndSettle();
      await t.tap(_k('property-parent-parent-proj'));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.parentUid, 'proj');
      // Back to Personal.
      await t.tap(_k('property-parent'));
      await t.pumpAndSettle();
      await t.tap(_k('property-parent-parent-top'));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.parentUid, isNull);
    });

    testWidgets('the project picker searches folders and sub-tasks', (t) async {
      final app = await _pump(
        t,
        task: mkTask('k', summary: 'Pay rent'),
        notes: _projectNotes,
      );
      await t.tap(_k('property-parent'));
      await t.pumpAndSettle();
      // Only projects (and Personal) until a term is typed.
      expect(_k('property-parent-parent-notes'), findsNothing);
      await t.enterText(_k('property-parent-parent-search'), 'notes');
      await t.pumpAndSettle();
      await t.tap(_k('property-parent-parent-notes'));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.parentUid, 'notes');
    });

    testWidgets('the description opens in place, markdown when closed', (
      t,
    ) async {
      final app = await _pump(
        t,
        task: mkTask('k', summary: 'Pay rent', description: 'Some *text*'),
      );
      // Closed: the markdown preview, not the raw text.
      expect(_k('task-description-tap'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('task-description-tap'),
          matching: find.byType(MarkdownLite),
        ),
        findsOneWidget,
      );
      await t.tap(_k('task-description-tap'));
      await t.pumpAndSettle();
      expect(_k('inline-text-editing'), findsOneWidget);
      await t.enterText(_k('edit-body'), 'More text');
      await t.pump(const Duration(milliseconds: 900));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.description, 'More text');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      // Closed again: the field is off and the preview is what shows.
      expect(_k('inline-text-editing'), findsNothing);
      expect(
        find.descendant(
          of: _k('edit-body'),
          matching: find.byType(MarkdownLite),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a picker opening commits the text that was still typing', (
      t,
    ) async {
      final app = await _pump(t);
      await t.tap(_k('pane-title'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), 'Typed fast');
      // No pause: the picker's press blurs the field and commits it.
      await t.tap(_k('property-priority'));
      await t.pumpAndSettle();
      await t.tap(_k('property-option-priority-1'));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.summary, 'Typed fast');
      expect(app.state.taskById('k')!.priority, 1);
    });

    testWidgets('a pick that cannot be saved goes back and says why', (
      t,
    ) async {
      final app = await _pump(
        t,
        task: mkTask('k', summary: 'Pay rent', days: 3),
      );
      await t.tap(_k('property-due'));
      await t.pumpAndSettle();
      t.takeException(); // the test font overflows the calendar header
      app.store.broken = true;
      await t.tap(_k('property-date-due-tomorrow'));
      await t.pumpAndSettle();
      // The value is what the task still holds, and the reason is a toast.
      expect(app.state.taskById('k')!.due, dueIn(3));
      expect(find.textContaining('Not saved'), findsOneWidget);
      app.store.broken = false;
    });

    testWidgets('leaving the peek saves the text that was typing', (t) async {
      final app = await _pump(t);
      await t.tap(_k('pane-title'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), 'Left behind');
      await t.runAsync(
        () async => app.state.guarded(() => app.state.select(null)),
      );
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.summary, 'Left behind');
      expect(app.state.taskDraftFor('k'), isNull);
    });

    testWidgets('another write while typing keeps the typed text', (t) async {
      final app = await _pump(t);
      await t.tap(_k('pane-title'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), 'Still typing');
      // A pick elsewhere reloads the tasks; the buffer keeps the text.
      await t.runAsync(() => app.state.setTaskPriority('k', 1));
      await t.pumpAndSettle();
      expect(app.state.taskDraftFor('k')!.titleController.text, 'Still typing');
      await t.pump(const Duration(milliseconds: 900));
      await t.pumpAndSettle();
      expect(app.state.taskById('k')!.summary, 'Still typing');
      expect(app.state.taskById('k')!.priority, 1);
    });
  });
}
