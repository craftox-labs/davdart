import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
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

Future<AppState> _pump(WidgetTester t, {LayoutSide? side}) async {
  t.view.physicalSize = const Size(1500, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s = AppState(
    SpaceNoteSource(space, seed: _Seed()),
    prefs: MemoryStorage(),
  );
  if (side != null) s.setLayoutSide(side);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

Finder _k(String k) => find.byKey(Key(k));
final _slide = Tokens.light.motion.slide;
final _z = Tokens.light.sizes;
Duration get _half => Duration(microseconds: _slide.inMicroseconds ~/ 2);

void main() {
  group('top bar belongs to the main section', () {
    testWidgets('with a peek open the bar ends before the peek', (t) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      final bar = t.getRect(find.byType(TopBar));
      final pane = t.getRect(_k('detail-pane'));
      expect(bar.right, lessThanOrEqualTo(pane.left));
      // The peek runs the full height of the content, beside the bar.
      expect(pane.top, bar.top);
    });

    testWidgets('collapsed or closed, the bar spans the content', (t) async {
      final s = await _pump(t);
      final panel = t.getRect(_k('shell-panel'));
      final dock = t.getRect(_k('dock-pane'));
      s.select('a');
      await t.pumpAndSettle();
      s.setPeekCollapsed(true);
      await t.pumpAndSettle();
      expect(t.getRect(find.byType(TopBar)).right, panel.right - 1);
      expect(t.getRect(find.byType(TopBar)).left, dock.right);
      s.setPeekCollapsed(false);
      s.select(null);
      await t.pumpAndSettle();
      expect(t.getRect(find.byType(TopBar)).right, panel.right - 1);
    });
  });

  group('slide', () {
    for (final side in [LayoutSide.start, LayoutSide.end]) {
      testWidgets('peek slides shut and open ($side)', (t) async {
        final s = await _pump(t, side: side);
        s.select('a');
        await t.pumpAndSettle();
        final full = t.getSize(_k('detail-pane')).width;
        s.setPeekCollapsed(true);
        await t.pump();
        await t.pump(_half);
        final mid = t.getSize(_k('detail-pane')).width;
        expect(mid, greaterThan(0));
        expect(mid, lessThan(full));
        // The content keeps its full width and stays mounted.
        expect(t.getSize(_k('peek-view')).width, full);
        expect(t.getSize(_k('detail-header')).width, full);
        await t.pumpAndSettle();
        expect(_k('detail-pane'), findsNothing);
        s.setPeekCollapsed(false);
        await t.pump();
        await t.pump(_half);
        final up = t.getSize(_k('detail-pane')).width;
        expect(up, greaterThan(0));
        expect(up, lessThan(full));
        await t.pumpAndSettle();
        expect(t.getSize(_k('detail-pane')).width, full);
      });
    }

    testWidgets('closing the peek keeps its note while sliding', (t) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      s.select(null);
      await t.pump();
      await t.pump(_half);
      expect(_k('peek-view'), findsOneWidget);
      expect(find.text('Alpha body'), findsWidgets);
      await t.pumpAndSettle();
      expect(_k('detail-pane'), findsNothing);
    });

    for (final side in [LayoutSide.start, LayoutSide.end]) {
      testWidgets('dock slides shut and open ($side)', (t) async {
        final s = await _pump(t, side: side);
        final full = t.getSize(_k('dock-pane')).width;
        s.setSidebarCollapsed(true);
        await t.pump();
        await t.pump(_half);
        final mid = t.getSize(_k('dock-pane')).width;
        expect(mid, greaterThan(0));
        expect(mid, lessThan(full));
        await t.pumpAndSettle();
        expect(_k('dock-pane'), findsNothing);
        s.setSidebarCollapsed(false);
        await t.pump();
        await t.pump(_half);
        final up = t.getSize(_k('dock-pane')).width;
        expect(up, greaterThan(0));
        expect(up, lessThan(full));
        await t.pumpAndSettle();
        expect(t.getSize(_k('dock-pane')).width, full);
      });
    }

    testWidgets('dragging a handle resizes at once, without sliding', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      await t.drag(_k('detail-handle'), const Offset(-40, 0));
      await t.pump();
      expect(t.getSize(_k('detail-pane')).width, _z.detail + 40);
      await t.drag(_k('sidebar-handle'), const Offset(30, 0));
      await t.pump();
      expect(t.getSize(_k('dock-pane')).width, _z.sidebar + 30);
      await t.pumpAndSettle();
    });
  });
}
