import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/persistent_store.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final w in [320.0, 480.0, 880.0]) {
    testWidgets('scope bar does not overflow at $w', (t) async {
      t.view.physicalSize = Size(w, 800);
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
      await s.addFolder(
        'A very long folder name ' * 4,
        text: 'A long folder description that should wrap. ' * 8,
      );
      s.openFolder(s.scope!.uid);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      final ex = t.takeException();
      expect(
        ex,
        isNull,
        reason: ex is FlutterError ? ex.toStringDeep() : "$ex",
      );
      final bar = t.getRect(find.byKey(const Key('scope-bar')));
      expect(bar.width, greaterThan(0));
      final text = t.getRect(find.byKey(const Key('scope-text')));
      final icons = t.getRect(find.byKey(const Key('scope-close')));
      expect(text.top, greaterThanOrEqualTo(icons.top));
      expect(text.width, greaterThan(bar.width / 2));
      expect(text.right, lessThanOrEqualTo(bar.right));
      expect(find.byKey(const Key('crumb-space')), findsOneWidget);
      final bar2 = find.byKey(const Key('scope-bar'));
      expect(
        find.descendant(of: bar2, matching: find.text('Home')),
        findsNothing,
      );
      expect(
        find.descendant(of: bar2, matching: find.byIcon(FLucideIcons.house)),
        findsOneWidget,
      );
    });
  }

  for (final w in [320.0, 880.0]) {
    testWidgets('scope bar row is vertically centred at $w', (t) async {
      t.view.physicalSize = Size(w, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final s = AppState(
        SpaceNoteSource(
          Space(
            SpaceConfig(id: 's', name: 'Space'),
            PersistentNoteStore(storage),
          ),
          flags: storage,
        ),
      );
      await s.load();
      await s.addFolder('Folder', text: 'Some description');
      s.openFolder(s.scope!.uid);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      final crumb = t.getRect(find.byKey(const Key('crumb-space'))).center.dy;
      for (final k in ['scope-edit', 'scope-delete', 'scope-close']) {
        final c = t.getRect(find.byKey(Key(k))).center.dy;
        expect((c - crumb).abs(), lessThanOrEqualTo(1), reason: '$k vs crumb');
      }
    });
  }
}
