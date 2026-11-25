import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

const _phone = Size(360, 640);

Finder _k(String k) => find.byKey(Key(k));

Note _note(String uid, String title) => Note(
  uid: uid,
  summary: title,
  description: 'Body of $title',
  lastModified: DateTime.now().toUtc(),
);

void _noError(WidgetTester t) {
  final ex = t.takeException();
  expect(ex, isNull, reason: ex is FlutterError ? ex.toStringDeep() : '$ex');
}

Future<AppState> _openNote(WidgetTester t) async {
  final s = await pumpTasksApp(t, notes: [_note('n1', 'Alpha')], size: _phone);
  await s.openNote('n1');
  await t.pumpAndSettle();
  return s;
}

String _body(AppState s) => s.tree.find('n1')!.note.description;

Finder _icon(IconData icon) =>
    find.descendant(of: _k('item-mode'), matching: find.byIcon(icon));

void main() {
  group('narrow item header', () {
    testWidgets('no back arrow; toggle and ⋯; top bar and chip stay', (
      t,
    ) async {
      await _openNote(t);
      expect(_k('peek-toolbar'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('peek-toolbar'),
          matching: find.byIcon(FLucideIcons.arrowLeft),
        ),
        findsNothing,
      );
      expect(find.text('Alpha'), findsWidgets);
      expect(_k('item-mode'), findsOneWidget);
      expect(_k('item-more'), findsOneWidget);
      // The desktop icons are gone.
      for (final k in ['edit-note', 'delete-note', 'move-note']) {
        expect(_k(k), findsNothing, reason: k);
      }
      // The top bar, Space chip and sync stay on an open item.
      expect(_k('top-bar'), findsOneWidget);
      expect(_k('space-chip'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.refreshCw), findsOneWidget);
      _noError(t);
    });

    testWidgets('the toggle icon shows the mode; no strip, tick or cross', (
      t,
    ) async {
      final s = await _openNote(t);
      // Previewing: the button offers Edit, a pencil.
      expect(_icon(FLucideIcons.pencil), findsOneWidget);
      expect(_icon(FLucideIcons.bookOpen), findsNothing);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      expect(s.isEditing('n1'), isTrue);
      // Editing: the button offers the preview, an open book.
      expect(_icon(FLucideIcons.bookOpen), findsOneWidget);
      expect(_icon(FLucideIcons.pencil), findsNothing);
      for (final k in [
        'edit-save',
        'edit-discard',
        'edit-save-action',
        'edit-cancel-action',
        'dirty-indicator',
      ]) {
        expect(_k(k), findsNothing, reason: k);
      }
      expect(find.text('Editing'), findsNothing);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      expect(s.isEditing('n1'), isFalse);
      expect(_icon(FLucideIcons.pencil), findsOneWidget);
      _noError(t);
    });

    testWidgets('the title looks the same in edit and preview', (t) async {
      final s = await _openNote(t);
      final title = find.descendant(
        of: _k('peek-toolbar'),
        matching: find.text('Alpha'),
      );
      final before = t.getRect(title);
      // The style the preview Text really shows (with the inherited one).
      final style = DefaultTextStyle.of(t.element(title)).style
          .merge(t.widget<Text>(title).style);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      expect(s.isEditing('n1'), isTrue);
      final field = find.descendant(
        of: _k('edit-title'),
        matching: find.byType(EditableText),
      );
      final editable = t.widget<EditableText>(field);
      // Same type, no box: no decoration around the field, same place.
      expect(editable.style.fontSize, style.fontSize);
      expect(editable.style.fontWeight, style.fontWeight);
      expect(editable.style.color, style.color);
      expect(editable.style.letterSpacing, style.letterSpacing);
      expect(editable.style.wordSpacing, style.wordSpacing);
      expect(editable.style.height, style.height);
      expect(editable.style.fontFamily, style.fontFamily);
      expect(editable.style.fontFeatures, style.fontFeatures);
      expect(
        find.descendant(
          of: _k('peek-toolbar'),
          matching: find.byType(FTextField),
        ),
        findsNothing,
      );
      expect(t.getRect(field).left, closeTo(before.left, 0.5));
      expect(t.getRect(field).center.dy, closeTo(before.center.dy, 0.5));
      expect(t.getRect(_k('peek-toolbar')).height, 44);
      // Still editable in place.
      await t.enterText(_k('edit-title'), 'Beta');
      expect(s.draftFor('n1')!.titleController.text, 'Beta');
      // Let the autosave run.
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(s.tree.find('n1')!.note.summary, 'Beta');
      _noError(t);
    });

    testWidgets('⋯ opens a sheet from the top with Move and Delete', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-more'));
      await t.pumpAndSettle();
      expect(_k('menu-sheet'), findsOneWidget);
      expect(t.getRect(_k('menu-sheet')).top, lessThan(_phone.height / 4));
      expect(_k('menu-delete'), findsOneWidget);
      expect(_k('menu-move-folder'), findsOneWidget);
      expect(_k('menu-copy-id'), findsOneWidget);
      // Not the tab and edit rows of the context menu.
      for (final k in ['menu-open-main', 'menu-edit', 'menu-close']) {
        expect(_k(k), findsNothing, reason: k);
      }
      // The sheet now lists flattened submenu rows, so Delete can sit below
      // the fold of the scrollable sheet.
      await t.ensureVisible(_k('menu-delete'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-delete'));
      await t.pumpAndSettle();
      await t.tap(_k('delete-confirm'));
      await t.pumpAndSettle();
      expect(s.tree.find('n1'), isNull);
      _noError(t);
    });
  });

  group('autosave', () {
    testWidgets('typing saves after the pause, not before', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-body'), 'Fresh words');
      await t.pump(const Duration(milliseconds: 1000));
      expect(_body(s), 'Body of Alpha');
      expect(_k('autosave-saving'), findsOneWidget);
      // A dot on the toggle's corner, no text beside it.
      final dot = find.descendant(
        of: _k('autosave-saving'),
        matching: find.byType(Container),
      );
      expect(dot, findsOneWidget);
      final toggle = t.getRect(_k('item-mode'));
      expect(toggle.contains(t.getRect(dot).center), isTrue);
      expect(find.text('Saving…'), findsNothing);
      expect(find.text('Saved'), findsNothing);
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      expect(_body(s), contains('Fresh words'));
      expect(s.dirtyFor('n1'), isFalse);
      // Still editing, nothing to confirm; the indicator says Saved.
      expect(s.isEditing('n1'), isTrue);
      expect(_k('autosave-saved'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('autosave-saved'),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
      _noError(t);
    });

    testWidgets('typing again restarts the pause', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-body'), 'one');
      await t.pump(const Duration(milliseconds: 1200));
      await t.enterText(_k('edit-body'), 'one two');
      await t.pump(const Duration(milliseconds: 1200));
      expect(_body(s), 'Body of Alpha');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(_body(s), contains('one two'));
    });

    testWidgets('toggling to preview flushes at once', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-body'), 'Quick');
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      expect(_body(s), contains('Quick'));
      expect(s.isEditing('n1'), isFalse);
      expect(find.textContaining('Quick'), findsWidgets);
    });

    testWidgets('Back flushes the edit without asking', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-body'), 'Before back');
      await t.tap(_k('bar-back'));
      await t.pumpAndSettle();
      expect(s.activeTab, isNull);
      expect(_body(s), contains('Before back'));
      expect(_k('leave-save'), findsNothing);
      _noError(t);
    });

    testWidgets('closing the item from the grid flushes it', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-body'), 'Closing');
      await t.tap(_k('bar-count'));
      await t.pumpAndSettle();
      await t.tap(_k('grid-close-${s.tabs.single.code}'));
      await t.pumpAndSettle();
      expect(_body(s), contains('Closing'));
      expect(_k('leave-save'), findsNothing);
      _noError(t);
    });

    testWidgets('the app pausing flushes', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-body'), 'Paused');
      expect(_body(s), 'Body of Alpha');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pumpAndSettle();
      expect(_body(s), contains('Paused'));
    });

    testWidgets('a selector change saves at once', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      s.draftFor('n1')!.setStatus('doing');
      await t.pumpAndSettle();
      expect(s.dirtyFor('n1'), isFalse);
      expect(PlanItem.fromNote(s.tree.find('n1')!.note).status, 'doing');
    });

    testWidgets('an empty title is not saved and says so', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), '');
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(s.tree.find('n1')!.note.summary, 'Alpha');
      expect(_k('autosave-failed'), findsOneWidget);
      // Back keeps the edit (nothing saved, nothing lost) and asks.
      expect(s.dirtyFor('n1'), isTrue);
    });

    testWidgets('saves run one at a time, the newest text wins', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      final d = s.draftFor('n1')!;
      d.bodyController.text = 'first';
      final a = s.flushEdit('n1');
      d.bodyController.text = 'second';
      final b = s.flushEdit('n1');
      await t.runAsync(() => Future.wait([a, b]));
      await t.pumpAndSettle();
      expect(_body(s), contains('second'));
      expect(s.dirtyFor('n1'), isFalse);
    });

    testWidgets('the preview toggle waits for a save in flight', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      final d = s.draftFor('n1')!;
      d.bodyController.text = 'first';
      // An autosave is running when the toggle is pressed with newer text.
      final running = s.flushEdit('n1');
      d.bodyController.text = 'second';
      await t.tap(_k('item-mode'));
      await t.runAsync(() => running);
      await t.pumpAndSettle();
      expect(_body(s), contains('second'));
      expect(s.isEditing('n1'), isFalse);
      expect(s.autosavePending('n1'), isFalse);
      _noError(t);
    });

    testWidgets('leaving with an empty title says it was not saved', (t) async {
      final s = await _openNote(t);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), '');
      await t.tap(_k('bar-back'));
      await t.pumpAndSettle();
      expect(s.activeTab, isNull);
      expect(find.textContaining('Not saved: a title is required'), findsOne);
      // Nothing is lost: the edit is still open in memory.
      expect(s.dirtyFor('n1'), isTrue);
      expect(s.tree.find('n1')!.note.summary, 'Alpha');
      _noError(t);
    });

    testWidgets('wide keeps explicit Save: no autosave', (t) async {
      final s = await pumpTasksApp(t, notes: [_note('n1', 'Alpha')]);
      await s.openNote('n1');
      await t.pumpAndSettle();
      s.startEdit('n1');
      await t.pumpAndSettle();
      await t.enterText(_k('edit-body'), 'Typed');
      await t.pump(const Duration(seconds: 3));
      expect(_body(s), 'Body of Alpha');
      expect(_k('edit-save-action'), findsOneWidget);
      expect(_k('item-mode'), findsNothing);
    });
  });

  group('tasks and events', () {
    testWidgets('a task: toggle, ⋯, autosave of text and a selector', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        tasks: [mkTask('k1', summary: 'Pay rent')],
        size: _phone,
      );
      await s.openNote('k1');
      await t.pumpAndSettle();
      expect(_k('item-more'), findsOneWidget);
      expect(_icon(FLucideIcons.pencil), findsOneWidget);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      expect(_icon(FLucideIcons.bookOpen), findsOneWidget);
      expect(_k('edit-save-action'), findsNothing);
      await t.enterText(_k('edit-body'), 'Details');
      await t.pump(const Duration(milliseconds: 1600));
      await t.pumpAndSettle();
      expect(s.taskById('k1')!.description, contains('Details'));
      s.taskDraftFor('k1')!.setPriority(1);
      await t.pumpAndSettle();
      expect(s.taskById('k1')!.priority, 1);
      expect(s.dirtyTaskFor('k1'), isFalse);
      await t.tap(_k('item-more'));
      await t.pumpAndSettle();
      expect(_k('menu-delete'), findsOneWidget);
      expect(_k('menu-copy-id'), findsOneWidget);
      _noError(t);
    });

    testWidgets('an event: toggle, ⋯, autosave of text', (t) async {
      final s = await pumpTasksApp(
        t,
        events: [mkEvent('e1', summary: 'Standup')],
        size: _phone,
      );
      await s.openNote('e1');
      await t.pumpAndSettle();
      expect(_icon(FLucideIcons.pencil), findsOneWidget);
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      expect(_icon(FLucideIcons.bookOpen), findsOneWidget);
      expect(_k('edit-save-action'), findsNothing);
      await t.enterText(_k('edit-body'), 'Agenda');
      await t.pump(const Duration(milliseconds: 1600));
      await t.pumpAndSettle();
      expect(s.eventById('e1')!.description, contains('Agenda'));
      await t.tap(_k('item-more'));
      await t.pumpAndSettle();
      expect(_k('menu-delete'), findsOneWidget);
      _noError(t);
    });
  });
}
