import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha', description: 'Alpha body'),
    Note(uid: 'b', summary: 'Beta', description: 'Beta body'),
  ];
}

AppState _make(MemoryStorage m) => AppState(
  SpaceNoteSource(
    Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore()),
    seed: _Seed(),
  ),
  prefs: m,
);

void main() {
  // A new install: an empty catalog boots to the first-run screen.
  for (final size in const [
    Size(320, 700),
    Size(880, 900),
    Size(1280, 900),
    Size(2560, 1300),
  ]) {
    testWidgets('boots with an empty catalog: $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final m = MemoryStorage();
      final c = SpaceCatalog(m);
      await t.pumpWidget(
        DavdartApp(
          state: AppState(const EmptyNoteSource(), prefs: m, catalog: c),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Create your first Space'), findsOneWidget);
    });
  }

  for (final side in LayoutSide.values) {
    for (final size in const [
      Size(880, 900),
      Size(1280, 900),
      Size(1911, 1000),
      Size(2560, 1300),
    ]) {
      for (final variant in ['fresh', 'tabs', 'peek', 'collapsed']) {
        testWidgets('boots without exceptions: ${side.name} $size $variant', (
          t,
        ) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final store = MemoryStorage();
          final first = _make(store);
          first.setLayoutSide(side);
          await first.load();
          if (variant != 'fresh') first.openNoteTab('b');
          if (variant == 'peek' || variant == 'collapsed') first.select('a');
          if (variant == 'collapsed') first.setPeekCollapsed(true);
          // Boot a second app from the persisted state.
          final s = _make(store);
          await t.pumpWidget(DavdartApp(state: s));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          if (variant == 'peek') {
            s.select('a');
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            s.setPeekCollapsed(true);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            s.setPeekCollapsed(false);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          }
        });
      }
    }
  }
}
