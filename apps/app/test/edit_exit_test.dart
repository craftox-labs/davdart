import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/key_nav.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Future<void> _esc(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.escape);
  await t.pumpAndSettle();
}

Future<void> _ctrlEnter(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

/// The three editors: how to open one in edit mode in the peek and how to
/// make its draft dirty.
class _Kind {
  _Kind(this.name, this.uid, this.start, this.dirty);
  final String name;
  final String uid;
  final void Function(AppState s) start;
  final void Function(AppState s) dirty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final kinds = [
    _Kind(
      'note',
      'n1',
      (s) => s.startEdit('n1'),
      (s) => s.draftFor('n1')!.titleController.text = 'Changed',
    ),
  ];

  Future<AppState> open(WidgetTester t, _Kind k, {bool main = false}) async {
    final s = await pumpTasksApp(
      t,
      notes: [Note(uid: 'n1', summary: 'Note one', description: 'body')],
      tasks: [mkTask('k1', days: 0)],
      events: [mkEvent('e1', days: 0, hour: 9)],
    );
    if (main) {
      await s.openNote(k.uid, mode: OpenMode.main);
    } else {
      s.select(k.uid);
    }
    await t.pumpAndSettle();
    k.start(s);
    await t.pumpAndSettle();
    expect(s.isEditing(k.uid), isTrue);
    return s;
  }

  for (final k in kinds) {
    group('edit exit: ${k.name}', () {
      testWidgets('header has Cancel and Save icons with shortcut tooltips', (
        t,
      ) async {
        await open(t, k);
        expect(_k('edit-cancel-action'), findsOneWidget);
        expect(_k('edit-save-action'), findsOneWidget);
        final tips = t
            .widgetList<FButton>(find.byType(FButton))
            .map((b) => b.semanticsLabel)
            .toList();
        expect(tips, contains('Cancel (Esc)'));
        expect(tips, contains('Save and close (Ctrl+Enter)'));
      });

      for (final main in [false, true]) {
        final where = main ? 'main tab' : 'peek';
        testWidgets('Esc on a clean edit leaves edit mode ($where)', (t) async {
          final s = await open(t, k, main: main);
          await _esc(t);
          expect(s.isEditing(k.uid), isFalse);
          expect(_k('edit-note'), findsOneWidget);
        });

        testWidgets('Esc on a dirty edit asks; Keep editing stays ($where)', (
          t,
        ) async {
          final s = await open(t, k, main: main);
          k.dirty(s);
          await t.pumpAndSettle();
          await _esc(t);
          expect(find.text('Unsaved changes'), findsWidgets);
          await t.tap(find.text('Keep editing'));
          await t.pumpAndSettle();
          expect(s.isEditing(k.uid), isTrue);
          // Esc then Discard leaves.
          await _esc(t);
          await t.tap(_k('leave-discard'));
          await t.pumpAndSettle();
          expect(s.isEditing(k.uid), isFalse);
        });
      }

      testWidgets('Ctrl+Enter saves and leaves edit mode', (t) async {
        final s = await open(t, k);
        k.dirty(s);
        await t.pumpAndSettle();
        await _ctrlEnter(t);
        expect(s.isEditing(k.uid), isFalse);
        final title = switch (k.name) {
          'note' => s.tree.find('n1')!.note.summary,
          'task' => s.taskById('k1')!.summary,
          _ => s.eventById('e1')!.summary,
        };
        expect(title, 'Changed');
      });

      testWidgets('the Cancel icon leaves like Esc; Save icon saves', (
        t,
      ) async {
        final s = await open(t, k);
        await t.tap(_k('edit-cancel-action'));
        await t.pumpAndSettle();
        expect(s.isEditing(k.uid), isFalse);
        k.start(s);
        await t.pumpAndSettle();
        k.dirty(s);
        await t.pumpAndSettle();
        await t.tap(_k('edit-save-action'));
        await t.pumpAndSettle();
        expect(s.isEditing(k.uid), isFalse);
      });
    });
  }

  testWidgets('Esc and Ctrl+Enter act on the focused area, not the other', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      notes: [
        Note(uid: 'n1', summary: 'Note one', description: 'body'),
        Note(uid: 'n2', summary: 'Peek note', description: 'body'),
      ],
      tasks: [mkTask('k1', days: 0)],
    );
    await s.openNote('k1', mode: OpenMode.main);
    await t.pumpAndSettle();
    // A text buffer in the main page, then an edit whose title field takes
    // the focus in the peek.
    s.startTaskEdit('k1');
    await t.pumpAndSettle();
    s.select('n2');
    await t.pumpAndSettle();
    s.startEdit('n2');
    await t.pumpAndSettle();
    expect(s.isEditing('k1'), isTrue);
    expect(s.isEditing('n2'), isTrue);
    // The peek is the area with the keys: Esc ends its edit only.
    FocusManager.instance.primaryFocus?.unfocus();
    s.nav.focusArea(NavArea.peek);
    await t.pump();
    await _esc(t);
    expect(s.isEditing('n2'), isFalse);
    expect(s.isEditing('k1'), isTrue);
    await _ctrlEnter(t);
    expect(s.isEditing('k1'), isTrue);
    // With the main page focused, Esc closes the task's text buffer.
    s.nav.focusArea(NavArea.main);
    s.nav.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump();
    await _esc(t);
    expect(s.isEditing('k1'), isFalse);
  });

  group('edit exit: event (inline text)', () {
    Future<AppState> openEvent(WidgetTester t) async {
      final s = await pumpTasksApp(
        t,
        events: [mkEvent('e1', summary: 'Event one', days: 0, hour: 9)],
      );
      s.select('e1');
      await t.pumpAndSettle();
      s.startEventEdit('e1');
      await t.pumpAndSettle();
      expect(s.isEditing('e1'), isTrue);
      return s;
    }

    testWidgets('an event header has no Cancel or Save icon', (t) async {
      await openEvent(t);
      expect(_k('edit-cancel-action'), findsNothing);
      expect(_k('edit-save-action'), findsNothing);
      expect(_k('edit-note'), findsNothing);
      expect(_k('inline-text-editing'), findsOneWidget);
    });

    testWidgets('Esc reverts the field; the next Esc leaves the buffer', (
      t,
    ) async {
      final s = await openEvent(t);
      await t.enterText(_k('edit-title'), 'Half typed');
      await _esc(t);
      expect(s.eventDraftFor('e1')!.titleController.text, 'Event one');
      expect(s.eventById('e1')!.summary, 'Event one');
      expect(_k('inline-text-editing'), findsNothing);
      expect(s.isEditing('e1'), isTrue);
      await _esc(t);
      expect(s.isEditing('e1'), isFalse);
    });

    testWidgets('Ctrl+Enter saves the text and closes the buffer', (t) async {
      final s = await openEvent(t);
      await t.enterText(_k('edit-title'), 'Saved by keys');
      await _ctrlEnter(t);
      expect(s.eventById('e1')!.summary, 'Saved by keys');
      expect(s.isEditing('e1'), isFalse);
    });

    testWidgets('the text fields are the title, where and description', (
      t,
    ) async {
      final s = await openEvent(t);
      // A buffer holds three fields; each is its own row or header field.
      expect(_k('edit-title'), findsOneWidget);
      expect(_k('edit-location'), findsOneWidget);
      expect(_k('edit-body'), findsOneWidget);
      expect(s.eventDraftFor('e1')!.titleController.text, 'Event one');
    });
  });

  group('edit exit: task (inline text)', () {
    Future<AppState> openTask(WidgetTester t) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('k1', summary: 'Task one', days: 0)],
      );
      s.select('k1');
      await t.pumpAndSettle();
      s.startTaskEdit('k1');
      await t.pumpAndSettle();
      expect(s.isEditing('k1'), isTrue);
      return s;
    }

    testWidgets('a task header has no Cancel or Save icon', (t) async {
      await openTask(t);
      expect(_k('edit-cancel-action'), findsNothing);
      expect(_k('edit-save-action'), findsNothing);
      expect(_k('edit-note'), findsNothing);
      // The title is the field.
      expect(_k('inline-text-editing'), findsOneWidget);
    });

    testWidgets('Esc reverts the field; the next Esc leaves the buffer', (
      t,
    ) async {
      final s = await openTask(t);
      await t.enterText(_k('edit-title'), 'Half typed');
      await _esc(t);
      expect(s.taskDraftFor('k1')!.titleController.text, 'Task one');
      expect(s.taskById('k1')!.summary, 'Task one');
      expect(_k('inline-text-editing'), findsNothing);
      expect(s.isEditing('k1'), isTrue);
      // Nothing in the page holds the field now: Esc leaves the buffer.
      await _esc(t);
      expect(s.isEditing('k1'), isFalse);
    });

    testWidgets('Ctrl+Enter saves the text and closes the buffer', (t) async {
      final s = await openTask(t);
      await t.enterText(_k('edit-title'), 'Saved by keys');
      await _ctrlEnter(t);
      expect(s.taskById('k1')!.summary, 'Saved by keys');
      expect(s.isEditing('k1'), isFalse);
    });
  });

  Future<void> openSelect(WidgetTester t) async {
    final focus = find
        .descendant(of: _k('edit-status'), matching: find.byType(Focus))
        .evaluate()
        .map((e) => (e.widget as Focus).focusNode)
        .firstWhere((n) => n?.debugLabel == 'FSelect')!;
    focus.requestFocus();
    await t.pump();
    await t.tap(_k('edit-status'));
    await t.pumpAndSettle();
  }

  testWidgets('Esc closes a real FSelect first; the second Esc leaves', (
    t,
  ) async {
    final s = await open(t, kinds[0]);
    await openSelect(t);
    expect(find.text('backlog'), findsWidgets);
    await _esc(t);
    expect(find.text('backlog'), findsNothing);
    expect(s.isEditing('n1'), isTrue);
    await _esc(t);
    expect(s.isEditing('n1'), isFalse);
  });

  testWidgets('Esc closes a real date picker first; second leaves', (t) async {
    final s = await pumpTasksApp(
      t,
      tasks: [mkTask('k1', days: 0, summary: 'Task one')],
    );
    s.select('k1');
    await t.pumpAndSettle();
    await t.tap(_k('property-due'));
    await t.pumpAndSettle();
    t.takeException(); // the test font overflows the calendar header
    expect(find.byType(FCalendar), findsWidgets);
    await _esc(t);
    expect(find.byType(FCalendar), findsNothing);
    // The picker was closed, the page is untouched.
    expect(_k('task-detail'), findsOneWidget);
    expect(s.taskById('k1')!.due, dueIn(0));
  });

  testWidgets('a calendar outside any popover does not disable Esc', (t) async {
    final s = await pumpTasksApp(
      t,
      notes: [Note(uid: 'n1', summary: 'Note one', description: 'body')],
    );
    s.select('n1');
    await t.pumpAndSettle();
    s.startEdit('n1');
    await t.pumpAndSettle();
    // A permanent calendar added to the overlay, never in a popover.
    final overlay = t.state<OverlayState>(find.byType(Overlay).first);
    overlay.insert(
      OverlayEntry(
        builder: (_) => Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(
            width: 300,
            child: FCalendar.grid(
              selectionControl: FDateSelectionControl.managedSingle(),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    t.takeException(); // the test font overflows the calendar header
    expect(find.byType(FCalendar), findsOneWidget);
    await _esc(t);
    expect(s.isEditing('n1'), isFalse);
  });
}
