import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/parts.dart';
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
      s.openNoteTab('a');
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
    testWidgets('sits above the pane: closable tab, then Maximise', (t) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      final header = t.getRect(_k('detail-header'));
      final pane = t.getRect(_k('detail-pane'));
      final panel = t.getRect(_k('shell-panel'));
      expect(header.left, pane.left);
      expect(header.width, pane.width);
      expect(t.getRect(_in('detail-tab', 'joined-tab')).bottom, panel.top);
      // Close lives in the tab itself, like a strip tab's.
      expect(_in('detail-tab', 'tab-close'), findsOneWidget);
      expect(_k('detail-close'), findsNothing);
      expect(
        t.getRect(_in('detail-tab', 'tab-close')).right,
        lessThanOrEqualTo(t.getRect(_k('pane-size')).left),
      );
      expect(t.getRect(_k('pane-size')).right, header.right);
      expect(
        find.descendant(of: _k('detail-tab'), matching: find.text('Alpha')),
        findsOneWidget,
      );
      expect(_in('detail-pane', 'pane-size'), findsNothing);
      await t.tap(_in('detail-tab', 'tab-close'));
      await t.pumpAndSettle();
      expect(s.selected, isNull);
      expect(_k('detail-header'), findsNothing);
    });

    testWidgets('the tab close matches a strip tab close in size', (t) async {
      final s = await _pump(t);
      s.openNoteTab('a');
      await t.pumpAndSettle();
      expect(
        t.getSize(_in('detail-tab', 'tab-close')),
        t.getSize(_in('tab-n:a', 'tab-close')),
      );
    });

    testWidgets('closing a dirty note asks first; the tab shows the dot', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), 'Changed');
      await t.pump();
      expect(_in('detail-tab', 'tab-dirty'), findsOneWidget);
      await t.tap(_in('detail-tab', 'tab-close'));
      await t.pumpAndSettle();
      expect(_k('leave-discard'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(s.selectedUid, 'a');
      await t.tap(_in('detail-tab', 'tab-close'));
      await t.pumpAndSettle();
      await t.tap(_k('leave-discard'));
      await t.pumpAndSettle();
      expect(s.selected, isNull);
    });

    testWidgets('Maximise hides strip, list and top bar; only the tab shows', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      final before = t.getRect(_k('detail-header'));
      await t.tap(_k('pane-size'));
      await t.pumpAndSettle();
      expect(s.maximised, isTrue);
      expect(_k('tab-strip'), findsNothing);
      expect(_k('tab-home'), findsNothing);
      expect(_k('detail-pane'), findsNothing);
      expect(find.text('Board'), findsNothing);
      expect(_k('full-page'), findsOneWidget);
      expect(_k('back'), findsNothing);
      expect(_k('breadcrumb'), findsNothing);
      final dock = t.getRect(find.byType(DockedSidebar));
      final header = t.getRect(_k('detail-header'));
      expect(header.left, dock.right);
      expect(header.right, before.right);
      expect(header.width, greaterThan(before.width));
      expect(_in('detail-header', 'detail-tab'), findsOneWidget);
      // The side panel stays.
      expect(find.byType(DockedSidebar), findsOneWidget);
      expect(s.tabs, isEmpty);
    });

    for (final side in [LayoutSide.start, LayoutSide.end]) {
      testWidgets('Minimise sits where Maximise was ($side)', (t) async {
        final s = await _pump(t, side: side);
        s.select('a');
        await t.pumpAndSettle();
        final max = t.getRect(_k('pane-size'));
        await t.tap(_k('pane-size'));
        await t.pumpAndSettle();
        expect(s.maximised, isTrue);
        expect(t.getRect(_k('pane-size')), max);
        expect(t.takeException(), isNull);
        await t.tap(_k('pane-size'));
        await t.pumpAndSettle();
        expect(s.maximised, isFalse);
        expect(s.selectedUid, 'a');
        expect(t.getRect(_k('pane-size')), max);
        expect(_k('tab-strip'), findsOneWidget);
        expect(_k('detail-pane'), findsOneWidget);
      });
    }

    testWidgets('tooltips read Maximise then Minimise', (t) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      String tip() => t.widget<IconAction>(_k('pane-size')).tooltip;

      expect(tip(), 'Maximise');
      s.maximise();
      await t.pumpAndSettle();
      expect(tip(), 'Minimise');
    });

    testWidgets('Minimise keeps the dirty guard', (t) async {
      final s = await _pump(t);
      s.select('a');
      s.maximise();
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), 'Changed');
      await t.pump();
      await t.tap(_k('pane-size'));
      await t.pumpAndSettle();
      expect(_k('leave-save'), findsOneWidget);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      expect(s.maximised, isTrue);
      await t.tap(_k('pane-size'));
      await t.pumpAndSettle();
      await t.tap(_k('leave-discard'));
      await t.pumpAndSettle();
      expect(s.maximised, isFalse);
    });

    testWidgets('mirrored: the header is on the left, Maximise at its end', (
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
      expect(t.getRect(_k('pane-size')).left, header.left);
      expect(
        t.getRect(_k('pane-size')).left,
        lessThan(t.getRect(_k('detail-tab')).left),
      );
      expect(t.getRect(_in('detail-tab', 'joined-tab')).bottom, panel.top);
      expect(t.takeException(), isNull);
    });
  });

  group('between 880 and 1280', () {
    testWidgets('compact tab with Maximise at the end; Minimise in place', (
      t,
    ) async {
      final s = await _pump(t, size: const Size(1000, 800));
      expect(_k('tab-strip'), findsOneWidget);
      s.select('a');
      await t.pumpAndSettle();
      // The note replaces the list, as before.
      expect(_k('detail-pane'), findsNothing);
      expect(_k('detail-header'), findsOneWidget);
      expect(
        t.getSize(_k('detail-header')).width,
        Tokens.light.sizes.detailTab,
      );
      expect(t.getSize(_k('tab-strip')).width, greaterThan(300));
      final max = t.getRect(_k('pane-size'));
      await t.tap(_k('pane-size'));
      await t.pumpAndSettle();
      expect(s.maximised, isTrue);
      expect(_k('full-page'), findsOneWidget);
      expect(_k('tab-strip'), findsNothing);
      expect(t.getRect(_k('pane-size')), max);
      await t.tap(_k('pane-size'));
      await t.pumpAndSettle();
      expect(s.maximised, isFalse);
      expect(_k('tab-strip'), findsOneWidget);
      await t.tap(_in('detail-tab', 'tab-close'));
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
    expect(_k('pane-size'), findsNothing);
  });
}
