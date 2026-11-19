import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/shell_frame.dart';
import 'package:davdart_app/ui/sidebar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha', description: 'Alpha body'),
    Note(uid: 'b', summary: 'Beta', description: 'Beta body'),
  ];
}

Future<AppState> _pump(
  WidgetTester t, {
  Size size = const Size(1500, 900),
  LayoutSide? side,
}) async {
  t.view.physicalSize = size;
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
Finder _in(String parent, String child) =>
    find.descendant(of: _k(parent), matching: _k(child));

final _z = Tokens.light.sizes;
final _hair = Tokens.light.borders.hairline;

void main() {
  group('header row and panel', () {
    testWidgets('margin on all four sides, header above the panel', (t) async {
      await _pump(t);
      final panel = t.getRect(_k('shell-panel'));
      final strip = t.getRect(_k('tab-strip'));
      final rail = t.getRect(_k('icon-rail'));
      expect(strip.top, _z.frameInset);
      expect(panel.top, _z.frameInset + _z.tabStrip);
      expect(strip.bottom - _hair, panel.top);
      expect(panel.left, rail.right);
      expect(panel.right, 1500 - _z.frameInset);
      expect(panel.bottom, 900 - _z.frameInset);
      expect(strip.left, greaterThanOrEqualTo(rail.right));
    });

    testWidgets('the side panel sits inside the panel, under the header', (
      t,
    ) async {
      await _pump(t);
      final panel = t.getRect(_k('shell-panel'));
      final dock = t.getRect(find.byType(DockedSidebar));
      final strip = t.getRect(_k('tab-strip'));
      expect(dock.top, greaterThanOrEqualTo(panel.top));
      expect(dock.top, greaterThanOrEqualTo(strip.bottom - _hair));
      // The strip starts over the main content, not over the side panel.
      expect(strip.left, greaterThanOrEqualTo(dock.right));
    });

    testWidgets('the top bar stays in the panel over the main content', (
      t,
    ) async {
      await _pump(t);
      final panel = t.getRect(_k('shell-panel'));
      final bar = t.getRect(find.text('Board').first);
      expect(bar.top, greaterThan(panel.top));
    });

    testWidgets('the active tab is flush on the panel top, others unframed', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      s.openFullPage();
      await t.pumpAndSettle();
      final panel = t.getRect(_k('shell-panel'));
      final active = _in('tab-n:a', 'joined-tab');
      expect(active, findsOneWidget);
      final box = t.getRect(active);
      expect(box.bottom, panel.top);
      final p = t.widget<CustomPaint>(active).painter! as RailTabPainter;
      expect(p.vertical, isTrue);
      expect(p.fill, Tokens.light.panel);
      // It reaches over the panel's border line.
      expect(p.reach, _hair);
      // Home is now inactive: no joined paint.
      expect(_in('tab-home', 'joined-tab'), findsNothing);
    });
  });

  group('detail header', () {
    testWidgets('sits above the pane with Expand and Close at its end', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      final header = t.getRect(_k('detail-header'));
      final pane = t.getRect(_k('detail-pane'));
      final panel = t.getRect(_k('shell-panel'));
      expect(header.left, pane.left);
      expect(header.width, pane.width);
      expect(t.getRect(_k('detail-tab')).bottom, panel.top);
      expect(
        t.getRect(_in('detail-header', 'expand-note')).right,
        lessThanOrEqualTo(t.getRect(_in('detail-header', 'detail-close')).left),
      );
      expect(
        find.descendant(of: _k('detail-tab'), matching: find.text('Alpha')),
        findsOneWidget,
      );
      // Not duplicated in the pane.
      expect(_in('detail-pane', 'expand-note'), findsNothing);
      await t.tap(_k('detail-close'));
      await t.pumpAndSettle();
      expect(s.selected, isNull);
      expect(_k('detail-header'), findsNothing);
    });

    testWidgets('expand opens the full page and the header goes', (t) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      await t.tap(_k('expand-note'));
      await t.pumpAndSettle();
      expect(s.fullPage, isTrue);
      expect(_k('detail-header'), findsNothing);
      expect(_k('tab-n:a'), findsOneWidget);
    });

    testWidgets('mirrored: the header is on the left, actions at its end', (
      t,
    ) async {
      final s = await _pump(t, side: LayoutSide.end);
      s.select('a');
      await t.pumpAndSettle();
      final header = t.getRect(_k('detail-header'));
      final pane = t.getRect(_k('detail-pane'));
      final panel = t.getRect(_k('shell-panel'));
      final strip = t.getRect(_k('tab-strip'));
      expect(header.left, pane.left);
      expect(header.right, lessThanOrEqualTo(strip.left));
      expect(t.getRect(_k('icon-rail')).left, panel.right);
      expect(
        t.getRect(_k('detail-close')).left,
        lessThan(t.getRect(_k('expand-note')).left),
      );
      expect(
        t.getRect(_k('detail-close')).left,
        lessThan(t.getRect(_k('detail-tab')).left),
      );
      expect(t.getRect(_k('detail-tab')).bottom, panel.top);
      expect(t.takeException(), isNull);
    });
  });

  group('between 880 and 1280', () {
    testWidgets('the strip shows and Expand opens the full page', (t) async {
      final s = await _pump(t, size: const Size(1000, 800));
      expect(_k('tab-strip'), findsOneWidget);
      s.select('a');
      await t.pumpAndSettle();
      // The note replaces the list, as before.
      expect(_k('detail-pane'), findsNothing);
      expect(_k('detail-header'), findsOneWidget);
      // Compact tab at the end of the row, not sized for an absent pane.
      expect(
        t.getSize(_k('detail-header')).width,
        Tokens.light.sizes.detailTab,
      );
      expect(t.getSize(_k('tab-strip')).width, greaterThan(300));
      await t.tap(_k('expand-note'));
      await t.pumpAndSettle();
      expect(s.fullPage, isTrue);
      expect(_k('full-page'), findsOneWidget);
      expect(_k('tab-n:a'), findsOneWidget);
      await t.tap(_k('tab-home'));
      await t.pumpAndSettle();
      expect(s.fullPage, isFalse);
      await t.tap(_k('detail-close'));
      await t.pumpAndSettle();
      expect(s.selected, isNull);
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('narrow layout is unchanged: no header row, no strip', (t) async {
    final s = await _pump(t, size: const Size(500, 900));
    s.select('a');
    await t.pumpAndSettle();
    expect(_k('tab-strip'), findsNothing);
    expect(_k('detail-header'), findsNothing);
    expect(_k('shell-panel'), findsNothing);
    expect(_k('expand-note'), findsNothing);
  });
}
