import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/persistent_store.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

const _phones = [Size(320, 568), Size(360, 640)];

void main() {
  for (final size in _phones) {
    testWidgets('scoped folder bar has no overflow at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final s = AppState(
        SpaceNoteSource(
          Space(
            SpaceConfig(id: 's', name: 'A very long space name ' * 4),
            PersistentNoteStore(storage),
          ),
          flags: storage,
        ),
      );
      await s.load();
      await s.addFolder('A very long folder name ' * 4, text: 'Some text');
      s.openFolder(s.scope!.uid);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      final ex = t.takeException();
      expect(
        ex,
        isNull,
        reason: ex is FlutterError ? ex.toStringDeep() : '$ex',
      );
      // Folder actions sit in one overflow button on narrow bars.
      expect(find.byKey(const Key('scope-more')), findsOneWidget);
      expect(find.byKey(const Key('scope-delete')), findsNothing);
      await t.tap(find.byKey(const Key('scope-more')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('scope-delete')), findsOneWidget);
      expect(find.byKey(const Key('scope-close')), findsOneWidget);
    });

    testWidgets('Home with Today has no overflow at $size', (t) async {
      await pumpTasksApp(
        t,
        tasks: [
          for (var i = 0; i < 6; i++)
            mkTask('late$i', summary: 'An overdue task number $i', days: -2),
        ],
        events: [
          for (var i = 0; i < 6; i++)
            mkEvent('e$i', summary: 'An event today $i', rrule: 'FREQ=DAILY'),
        ],
        size: size,
      );
      expect(find.byKey(const Key('home-today')), findsOneWidget);
      // The board still gets room below the Today block (it scrolls).
      expect(
        t.getRect(find.byKey(const Key('home-today'))).bottom,
        lessThan(size.height),
      );
      final ex = t.takeException();
      expect(
        ex,
        isNull,
        reason: ex is FlutterError ? ex.toStringDeep() : '$ex',
      );
    });
  }

  for (final size in _phones) {
    testWidgets('board is a status accordion with title-only cards at $size', (
      t,
    ) async {
      await pumpTasksApp(
        t,
        notes: [
          Note(uid: 'a', summary: 'Alpha', description: 'status: todo\n\nx'),
          Note(
            uid: 'b',
            summary: 'Bravo',
            description: 'id: DD-1\nowner: Sam\nstatus: doing\n\nBody',
          ),
        ],
        size: size,
      );
      expect(find.byKey(const Key('board-accordion')), findsOneWidget);
      // Doing starts open, the rest collapsed.
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('DD-1'), findsNothing);
      expect(find.text('Sam'), findsNothing);
      expect(find.text('Alpha'), findsNothing);
      await t.tap(find.byKey(const Key('board-acc-todo-toggle')));
      await t.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      await t.tap(find.byKey(const Key('board-acc-doing-toggle')));
      await t.pumpAndSettle();
      expect(find.text('Bravo'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('top bar buttons and task rows are touch-sized at $size', (
      t,
    ) async {
      await pumpTasksApp(
        t,
        tasks: [mkTask('a', summary: 'Pay rent', days: 0)],
        size: size,
      );
      final bar = find.byKey(const Key('top-bar'));
      final buttons = find.descendant(of: bar, matching: find.byType(FButton));
      expect(buttons, findsWidgets);
      for (final b in buttons.evaluate()) {
        final r = t.getRect(find.byWidget(b.widget));
        expect(r.width, greaterThanOrEqualTo(44), reason: '$r');
        expect(r.height, greaterThanOrEqualTo(44), reason: '$r');
      }
      final row = t.getRect(find.byKey(const Key('home-today-tasks-a')));
      expect(row.height, greaterThanOrEqualTo(44));
      final box = find.ancestor(
        of: find.byKey(const Key('task-check-a')),
        matching: find.byType(SizedBox),
      );
      final hit = box.evaluate().map((e) => t.getRect(find.byWidget(e.widget)));
      expect(
        hit.any((r) => r.width >= 44 && r.height >= 44),
        isTrue,
        reason: 'checkbox hit area',
      );
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('desktop keeps columns and compact buttons', (t) async {
    await pumpTasksApp(
      t,
      notes: [
        Note(uid: 'b', summary: 'Bravo', description: 'status: doing\n\nx'),
      ],
      size: const Size(1280, 900),
    );
    expect(find.byKey(const Key('board-accordion')), findsNothing);
    final r = t.getRect(find.byKey(const Key('home-today-tasks-add')));
    expect(r.height, lessThan(44));
  });
}
