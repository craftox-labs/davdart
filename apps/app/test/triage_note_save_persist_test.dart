import 'package:davdart/davdart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';

import 'catalog_helper.dart';
import 'tasks_helper.dart';

// Triage of bug f0887592 (note save does not persist) and 965ea4b6 (search):
// regression guards, both pass on HEAD.
Finder _k(String k) => find.byKey(Key(k));

void main() {
  testWidgets('title, tags and body survive Ctrl+Enter and reopen', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final s = await pumpTasksApp(
      t,
      notes: [Note(uid: 'n1', summary: 'Test note A', description: '')],
    );
    s.openNoteTab('n1');
    await t.pumpAndSettle();
    s.startEdit('n1');
    await t.pumpAndSettle();
    await t.enterText(_k('edit-tags'), 'test,cod');
    // A click puts the body in INSERT; in NORMAL it is readOnly and ignores
    // typed text (vim by design).
    await t.tap(_k('edit-body'));
    await t.pumpAndSettle();
    await t.enterText(_k('edit-body'), 'body line from cod test');
    await t.pump();
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(s.isEditing('n1'), isFalse);
    final n = s.notes.firstWhere((e) => e.uid == 'n1');
    expect(n.description, 'body line from cod test');
    expect(n.categories, containsAll(['test', 'cod']));
    s.startEdit('n1');
    await t.pumpAndSettle();
    expect(s.draftFor('n1')!.tagsController.text, contains('cod'));
    expect(s.draftFor('n1')!.bodyController.text, 'body line from cod test');
  });

  testWidgets('search finds a note by its full title; Enter keeps the query', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final storage = MemoryStorage();
    final c = catalogWithPlanning(
      storage,
      planningSeed: SeedNotes([
        Note(uid: 'n1', summary: 'Test note A', description: ''),
      ]),
    );
    final st = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
    await t.pumpWidget(DavdartApp(state: st));
    await t.pumpAndSettle();
    await t.tap(_k('rail-search'));
    await t.pumpAndSettle();
    await t.enterText(_k('search-all-field'), 'Test note A');
    await t.pumpAndSettle();
    expect(_k('hit-n1'), findsOneWidget);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(_k('hit-n1'), findsOneWidget);
    expect(
      t
          .widget<EditableText>(
            find.descendant(
              of: _k('search-all-field'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'Test note A',
    );
  });
}
