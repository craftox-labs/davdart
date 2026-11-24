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
    testWidgets('breadcrumb header does not overflow at $w', (t) async {
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
      final bar = t.getRect(find.byKey(const Key('top-bar')));
      final text = t.getRect(find.byKey(const Key('scope-text')));
      expect(text.top, greaterThanOrEqualTo(bar.bottom));
      expect(text.width, greaterThan(bar.width / 2));
      expect(text.right, lessThanOrEqualTo(bar.right));
      expect(find.byKey(const Key('scope-bar')), findsNothing);
      expect(find.byKey(const Key('crumb-space')), findsOneWidget);
      final top = find.byKey(const Key('top-bar'));
      expect(
        find.descendant(of: top, matching: find.byIcon(FLucideIcons.house)),
        findsOneWidget,
      );
      expect(
        t.getRect(find.byKey(const Key('crumb-space'))).right,
        lessThanOrEqualTo(bar.right),
      );
    });
  }

  for (final w in [320.0, 880.0]) {
    testWidgets('breadcrumb row is vertically centred at $w', (t) async {
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
      // The folder actions are folded into one menu button at every width.
      final keys = ['scope-more'];
      for (final k in keys) {
        final c = t.getRect(find.byKey(Key(k))).center.dy;
        expect((c - crumb).abs(), lessThanOrEqualTo(1), reason: '$k vs crumb');
      }
    });
  }

  testWidgets('root crumb does not move when a folder opens or closes', (
    t,
  ) async {
    t.view.physicalSize = const Size(880, 800);
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
    final uid = s.notes.firstWhere((n) => n.summary == 'Folder').uid;
    s.openFolder(null);
    await t.pumpWidget(DavdartApp(state: s));
    await t.pumpAndSettle();
    final root = t.getRect(find.byKey(const Key('crumb-space')));
    final bar = t.getRect(find.byKey(const Key('top-bar')));
    s.openFolder(uid);
    await t.pumpAndSettle();
    final scoped = t.getRect(find.byKey(const Key('crumb-space')));
    expect(scoped.left, root.left);
    expect(scoped.center.dy, root.center.dy);
    expect(t.getRect(find.byKey(const Key('top-bar'))), bar);
    expect(find.byKey(const Key('scope-more')), findsOneWidget);
    s.openFolder(null);
    await t.pumpAndSettle();
    expect(t.getRect(find.byKey(const Key('crumb-space'))).left, root.left);
  });

  testWidgets(
    'top bar has no Board/List title, only the toggle on a view tab',
    (t) async {
      t.view.physicalSize = const Size(880, 800);
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
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      final top = find.byKey(const Key('top-bar'));
      for (final w in ['Board', 'List']) {
        expect(find.descendant(of: top, matching: find.text(w)), findsNothing);
      }
      await s.saveView('V');
      s.applyView(s.savedViews.single);
      await t.pumpAndSettle();
      for (final w in ['Board', 'List']) {
        expect(
          find.descendant(of: top, matching: find.text(w)),
          findsOneWidget,
        );
      }
      final x = t.getRect(find.byKey(const Key('crumb-space'))).left;
      for (final w in ['Board', 'List']) {
        expect(
          t.getRect(find.descendant(of: top, matching: find.text(w))).left,
          greaterThan(x + 200),
        );
      }
    },
  );
}
