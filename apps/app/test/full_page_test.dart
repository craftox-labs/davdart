import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
    Note(
      uid: 'a',
      summary: 'Alpha',
      parentUid: 'f',
      description: 'status: todo\n\nAlpha body',
      categories: ['status-todo'],
    ),
    Note(uid: 'b', summary: 'Beta', description: 'Beta body'),
  ];
}

late Space space;

Future<AppState> _pump(
  WidgetTester t, {
  Size size = const Size(1500, 900),
  bool select = true,
  LayoutSide? side,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final state = AppState(
    SpaceNoteSource(space, seed: _Seed()),
    prefs: MemoryStorage(),
  );
  if (side != null) state.setLayoutSide(side);
  await t.pumpWidget(DavdartApp(state: state));
  await t.pumpAndSettle();
  if (select) {
    state.select('a');
    await t.pumpAndSettle();
  }
  return state;
}

Finder _k(String k) => find.byKey(Key(k));
Future<void> _settle(WidgetTester t) => t.pumpAndSettle();

Future<void> _type(WidgetTester t, String key, String text) async {
  await t.enterText(_k(key), text);
  await t.pump();
}

Future<List<String>> _titles() async => [
  for (final n in await space.notes()) n.summary,
];

void main() {
  group('full page', () {
    testWidgets('expand opens it, Back returns, selection unchanged', (
      t,
    ) async {
      final s = await _pump(t);
      expect(_k('detail-pane'), findsOneWidget);
      await t.tap(_k('expand-note'));
      await _settle(t);
      expect(s.fullPage, isTrue);
      expect(_k('full-page'), findsOneWidget);
      expect(_k('detail-pane'), findsNothing);
      expect(find.text('TODO'), findsNothing);
      await t.tap(_k('back'));
      await _settle(t);
      expect(s.fullPage, isFalse);
      expect(s.selectedUid, 'a');
      expect(_k('detail-pane'), findsOneWidget);
      expect(find.text('TODO'), findsOneWidget);
    });

    testWidgets('Escape goes back', (t) async {
      final s = await _pump(t);
      s.openFullPage();
      await _settle(t);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(t);
      expect(s.fullPage, isFalse);
      expect(s.selectedUid, 'a');
    });

    testWidgets('breadcrumb shows the folder path and the title', (t) async {
      final s = await _pump(t);
      s.openFullPage();
      await _settle(t);
      expect(t.widget<Text>(_k('breadcrumb')).data, 'Plans > Alpha');
    });

    testWidgets('picking another note switches the page', (t) async {
      final s = await _pump(t);
      s.openFullPage();
      await _settle(t);
      await t.tap(find.text('Beta').first);
      await _settle(t);
      expect(s.fullPage, isTrue);
      expect(s.selectedUid, 'b');
      expect(t.widget<Text>(_k('breadcrumb')).data, 'Beta');
    });

    testWidgets('narrow layout has no Expand and no full page', (t) async {
      final s = await _pump(t, size: const Size(500, 900));
      expect(_k('expand-note'), findsNothing);
      s.openFullPage();
      await _settle(t);
      expect(_k('full-page'), findsNothing);
      expect(find.text('Alpha body'), findsOneWidget);
    });

    testWidgets('mirrored layout keeps the pane and the full page', (t) async {
      final s = await _pump(t, side: LayoutSide.end);
      final pane = t.getTopLeft(_k('detail-pane'));
      expect(pane.dx, lessThan(300));
      s.openFullPage();
      await _settle(t);
      expect(_k('full-page'), findsOneWidget);
      await t.tap(_k('back'));
      await _settle(t);
      expect(t.getTopLeft(_k('detail-pane')), pane);
    });
  });

  testWidgets('section titles stay in the same place across sections', (
    t,
  ) async {
    final s = await _pump(t, select: false);
    final ys = <Section, double>{};
    final xs = <Section, double>{};
    for (final (sec, label) in [
      (Section.notes, 'Files'),
      (Section.views, 'Views'),
      (Section.search, 'Search'),
    ]) {
      s.setSection(sec);
      await _settle(t);
      final o = t.getTopLeft(find.text(label).first);
      ys[sec] = o.dy;
      xs[sec] = o.dx;
    }
    expect(
      ys.values.toSet().length,
      1,
      reason: 'titles at different heights: $ys',
    );
    expect(xs.values.toSet().length, 1, reason: 'titles at different x: $xs');
  });

  group('leaving a Space with unsaved edits', () {
    testWidgets('asks first; keep stays, discard switches', (t) async {
      t.view.physicalSize = const Size(1500, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = SpaceCatalog(storage, planningSeed: _Seed());
      final other = c.add('Other');
      final startId = c.current;
      final s = AppState(c.sourceFor(startId), prefs: storage, catalog: c);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      s.select('a');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Changed');
      expect(s.dirty, isTrue);

      final stay = s.switchSpace(other.id);
      await _settle(t);
      expect(find.text('Unsaved changes'), findsWidgets);
      await t.tap(find.text('Keep editing'));
      await _settle(t);
      expect(await stay, isFalse);
      expect(s.currentSpaceId, startId);
      expect(s.dirty, isTrue);

      final go = s.switchSpace(other.id);
      await _settle(t);
      await t.tap(_k('leave-discard'));
      await _settle(t);
      expect(await go, isTrue);
      expect(s.currentSpaceId, other.id);
      expect(s.dirty, isFalse);
    });
  });

  group('in-place editing', () {
    testWidgets('edit, Save writes title, status, tags and text', (t) async {
      final s = await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      expect(_k('dirty-indicator'), findsNothing);
      await _type(t, 'edit-title', 'Alpha 2');
      await _type(t, 'edit-tags', 'x, y');
      await _type(t, 'edit-body', 'New body');
      expect(_k('dirty-indicator'), findsOneWidget);
      await t.tap(_k('edit-save'));
      await _settle(t);
      expect(s.activeDraft, isNull);
      final n = (await space.notes()).firstWhere((n) => n.uid == 'a');
      expect(n.summary, 'Alpha 2');
      expect(n.categories, containsAll(['x', 'y', 'status-todo']));
      expect(PlanItem.fromNote(n).text, 'New body');
      expect(PlanItem.fromNote(n).status, 'todo');
      expect(find.text('New body'), findsOneWidget);
    });

    testWidgets('Ctrl+S saves', (t) async {
      await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Via keys');
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyS);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _settle(t);
      expect(await _titles(), contains('Via keys'));
    });

    testWidgets('Discard drops the edit', (t) async {
      final s = await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Nope');
      await t.tap(_k('edit-discard'));
      await _settle(t);
      expect(s.activeDraft, isNull);
      expect(await _titles(), isNot(contains('Nope')));
      expect(find.text('Alpha'), findsWidgets);
    });

    testWidgets('empty title cannot be saved', (t) async {
      await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', '  ');
      await _settle(t);
      expect(find.text('A title is required'), findsOneWidget);
      await t.tap(_k('edit-save'));
      await _settle(t);
      expect(await _titles(), contains('Alpha'));
    });

    testWidgets('dirty guard: keep editing, discard, save', (t) async {
      final s = await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Changed');
      await t.tap(find.text('Beta').first);
      await _settle(t);
      expect(find.text('Unsaved changes'), findsWidgets);
      expect(_k('leave-save'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await _settle(t);
      expect(s.selectedUid, 'a');
      expect(s.dirty, isTrue);
      await t.tap(find.text('Beta').first);
      await _settle(t);
      await t.tap(_k('leave-discard'));
      await _settle(t);
      expect(s.selectedUid, 'b');
      expect(await _titles(), isNot(contains('Changed')));
      // Save path, from the full page's Back.
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Beta 2');
      s.openFullPage();
      await _settle(t);
      await t.tap(_k('back'));
      await _settle(t);
      await t.tap(_k('leave-save'));
      await _settle(t);
      expect(s.fullPage, isFalse);
      expect(await _titles(), contains('Beta 2'));
    });

    testWidgets('the draft survives expanding', (t) async {
      final s = await _pump(t);
      await t.tap(_k('edit-note'));
      await _settle(t);
      await _type(t, 'edit-title', 'Kept');
      await t.tap(_k('expand-note'));
      await _settle(t);
      expect(s.dirty, isTrue);
      expect(
        t
            .widget<EditableText>(
              find.descendant(
                of: _k('edit-title'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Kept',
      );
    });
  });
}
