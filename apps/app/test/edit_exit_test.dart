import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
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
    _Kind(
      'task',
      'k1',
      (s) => s.startTaskEdit('k1'),
      (s) => s.taskDraftFor('k1')!.titleController.text = 'Changed',
    ),
    _Kind(
      'event',
      'e1',
      (s) => s.startEventEdit('e1'),
      (s) => s.eventDraftFor('e1')!.titleController.text = 'Changed',
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
        expect(_k('edit-discard'), findsOneWidget);
        expect(_k('edit-save'), findsOneWidget);
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

  testWidgets('Esc with a dropdown open does not leave edit mode', (t) async {
    final s = await open(t, kinds[0]);
    // A click on the select focuses its field, then opens the menu.
    final focus = find
        .descendant(of: _k('edit-status'), matching: find.byType(Focus))
        .evaluate()
        .map((e) => (e.widget as Focus).focusNode)
        .firstWhere((n) => n?.debugLabel == 'FSelect')!;
    focus.requestFocus();
    await t.pump();
    await t.tap(_k('edit-status'));
    await t.pumpAndSettle();
    expect(find.text('backlog'), findsWidgets);
    // Esc does not leave edit mode while the dropdown is showing.
    await _esc(t);
    expect(s.isEditing('n1'), isTrue);
    // Closing it (a click outside) and pressing Esc again leaves.
    await t.tapAt(const Offset(2, 2));
    await t.pumpAndSettle();
    expect(find.text('backlog'), findsNothing);
    await _esc(t);
    expect(s.isEditing('n1'), isFalse);
  });
}
