import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/persistent_store.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
