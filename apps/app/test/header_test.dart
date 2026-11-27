import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/parts.dart';
import 'package:davdart_app/ui/shell_frame.dart';
import 'package:davdart_app/ui/sidebar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
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
      final bar = t.getRect(find.byKey(const Key('top-bar')));
      expect(bar.top, greaterThan(panel.top));
    });

    testWidgets('the page header row names the page and keeps sync right', (
      t,
    ) async {
      await _pump(t);
      final row = t.getRect(_k('top-bar'));
      final title = t.getRect(_k('page-title'));
      final sync = t.getRect(find.byIcon(FLucideIcons.refreshCw));
      // Home's heading is its Space; the tab strip still says Home.
      expect(t.widget<Text>(_k('page-title')).data, 'This Space');
      expect(t.widget<Text>(_k('page-title')).style?.color, Tokens.light.fg);
      expect(title.width, greaterThan(0));
      expect(row.height, _z.paneHeader);
      expect(title.centerLeft.dx, closeTo(row.left + Tokens.light.space.md, 1));
      expect(title.center.dy, closeTo(row.center.dy, 1));
      expect(sync.right, lessThan(row.right));
      expect(sync.left, greaterThan(row.right - _z.touchTarget));
      expect(title.right, lessThan(sync.left));
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

  group('joined tab outline', () {
    Future<ByteData> paint(WidgetTester t, {required bool flush}) async {
      const fill = Color(0xFF112233), line = Color(0xFFAA0000);
      const w = 100.0, h = 34.0;
      final painter = RailTabPainter(
        fill: fill,
        border: line,
        borderWidth: 1,
        radius: 8,
        margin: 0,
        vertical: true,
        squareStart: flush,
      );
      final rec = ui.PictureRecorder();
      // Room around the box for the flare and the base overlap.
      final c = Canvas(rec)..translate(20, 20);
      painter.paint(c, const Size(w, h));
      final img = await t.runAsync(() => rec.endRecording().toImage(160, 80));
      return (await t.runAsync(img!.toByteData))!;
    }

    int px(ByteData d, int x, int y) => d.getUint32((y * 160 + x) * 4);

    testWidgets('strokes the top and both sides, rounded at the top', (
      t,
    ) async {
      final d = await paint(t, flush: false);
      const line = 0xAA0000FF;
      // Top edge and the two sides (tab box at x 20..120, y 20..54).
      expect(px(d, 70, 20), line);
      expect(px(d, 20, 40), line);
      expect(px(d, 119, 40), line);
      // The rounded top corner leaves its very corner unpainted.
      expect(px(d, 20, 20), isNot(line));
      // Inside is the fill.
      expect(px(d, 70, 40), 0x112233FF);
    });

    testWidgets('a flush start keeps the rounded top, drops the flare', (
      t,
    ) async {
      final free = await paint(t, flush: false);
      final flush = await paint(t, flush: true);
      // Left of the box: the flare paints there only when not flush.
      expect(px(free, 17, 54), isNot(0));
      expect(px(flush, 17, 54), 0);
      expect(px(flush, 19, 20), isNot(0xAA0000FF));
      // The edge stroke reaches one border width out, to column 19.
      expect(px(flush, 19, 40), 0xAA0000FF);
      expect(px(flush, 20, 40), 0x112233FF);
      // The fill reaches out as well; the free tab's column 19 is empty.
      expect(px(free, 19, 40), 0);
    });
  });

  group('tab edge meets the vertical line', () {
    Future<ByteData> shot(WidgetTester t) async {
      final boundary = t.renderObject(
        find.byType(RepaintBoundary).first,
      ) as RenderRepaintBoundary;
      final img = await t.runAsync(() => boundary.toImage());
      return (await t.runAsync(img!.toByteData))!;
    }

    int at(ByteData d, int x, int y) => d.getUint32((y * 1500 + x) * 4);

    // The sampled column holds the same colour in the tab (above the panel's
    // top edge) and in the line below it, and that colour is the border's.
    void expectContinues(ByteData d, double col, double panelTop) {
      final x = col.round();
      final tab = at(d, x, panelTop.round() - 12);
      final line = at(d, x, panelTop.round() + 200);
      expect(tab, line);
      expect(tab, isNot(at(d, x + 2, panelTop.round() - 12)));
      expect(tab, isNot(at(d, x - 2, panelTop.round() - 12)));
    }

    testWidgets('the panel border shows all round, inside the margin', (
      t,
    ) async {
      await _pump(t);
      final panel = t.getRect(_k('shell-panel'));
      final d = await shot(t);
      final b = Tokens.light.panelBorder.toARGB32();
      int rgba(int c) => ((c & 0xFFFFFF) << 8) | (c >>> 24);
      final cy = (panel.top + panel.height / 2).round();
      expect(at(d, panel.right.round() - 1, cy), rgba(b));
      expect(at(d, panel.left.round(), cy), rgba(b));
      expect(at(d, panel.center.dx.round(), panel.bottom.round() - 1), rgba(b));
    });

    testWidgets('home tab continues the dock border', (t) async {
      await _pump(t);
      final dock = t.getRect(find.byType(DockedSidebar));
      final tab = t.getRect(_k('tab-home'));
      final panel = t.getRect(_k('shell-panel'));
      // Rect arithmetic: the stroke is one hairline left of the box edge.
      expect(tab.left - _hair, dock.right - _hair);
      expectContinues(await shot(t), dock.right - _hair, panel.top);
    });

    testWidgets('the peek tab continues the peek border', (t) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      final pane = t.getRect(_k('detail-pane'));
      final panel = t.getRect(_k('shell-panel'));
      final tab = t.getRect(_k('detail-tab'));
      expect(tab.left, pane.left);
      expect(t.getRect(_k('detail-header')).width, pane.width);
      s.openNoteTab('b'); // keep the peek tab flush but make home inactive
      await t.pumpAndSettle();
      s.select('a');
      await t.pumpAndSettle();
      expectContinues(await shot(t), pane.left - _hair, panel.top);
    });

    testWidgets('mirrored: peek tab end and home tab start meet the border', (
      t,
    ) async {
      final s = await _pump(t, side: LayoutSide.end);
      s.select('a');
      await t.pumpAndSettle();
      final pane = t.getRect(_k('detail-pane'));
      final panel = t.getRect(_k('shell-panel'));
      final home = t.getRect(_k('tab-home'));
      expect(t.getRect(_k('detail-header')).width, pane.width);
      // The border column is the one right of the pane; the Collapse control
      // and then the home tab follow it.
      expect(
        t.getRect(_k('peek-collapse')).left,
        greaterThanOrEqualTo(pane.right + _hair),
      );
      expect(home.left, greaterThan(t.getRect(_k('peek-collapse')).right));
      var d = await shot(t);
      expectContinues(d, pane.right, panel.top);
      // Home is active: its stroke is at the same column.
      expect(_in('tab-home', 'joined-tab'), findsOneWidget);
      s.openNoteTab('b');
      await t.pumpAndSettle();
      s.select('a');
      await t.pumpAndSettle();
      d = await shot(t);
      expectContinues(d, pane.right, panel.top);
    });
  });

  group('first tab at a divider', () {
    testWidgets('home tab lines up with the side panel, no concave start', (
      t,
    ) async {
      await _pump(t);
      final dock = t.getRect(find.byType(DockedSidebar));
      expect(t.getRect(_k('tab-home')).left, dock.right);
      final p =
          t.widget<CustomPaint>(_in('tab-home', 'joined-tab')).painter!
              as RailTabPainter;
      expect(p.squareStart, isTrue);
      expect(p.squareEnd, isFalse);
    });

    testWidgets('other tabs keep both concave corners', (t) async {
      final s = await _pump(t);
      s.openNoteTab('b');
      await t.pumpAndSettle();
      final p =
          t.widget<CustomPaint>(_in('tab-n:b', 'joined-tab')).painter!
              as RailTabPainter;
      expect(p.squareStart, isFalse);
      expect(p.squareEnd, isFalse);
    });

    testWidgets('the peek tab lines up with its divider', (t) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      expect(
        t.getRect(_k('detail-tab')).left,
        t.getRect(_k('detail-pane')).left,
      );
      final p =
          t.widget<CustomPaint>(_in('detail-tab', 'joined-tab')).painter!
              as RailTabPainter;
      expect(p.squareStart, isTrue);
    });

    testWidgets('mirrored, wide but not split: no spacer, home tab free', (
      t,
    ) async {
      final s = await _pump(
        t,
        size: const Size(1000, 900),
        side: LayoutSide.end,
      );
      s.select('a');
      await t.pumpAndSettle();
      final p =
          t.widget<CustomPaint>(_in('tab-home', 'joined-tab')).painter!
              as RailTabPainter;
      expect(p.squareStart, isFalse);
      expect(
        t.getRect(_k('tab-home')).left,
        greaterThanOrEqualTo(t.getRect(_k('detail-tab')).right),
      );
      expect(
        t.getRect(_k('tab-home')).left - t.getRect(_k('detail-tab')).right,
        lessThan(
          _hair + 0.5 + Tokens.light.radii.panel + Tokens.light.radii.tab,
        ),
      );
    });

    testWidgets('mirrored: the peek tab ends at its divider', (t) async {
      final s = await _pump(t, side: LayoutSide.end);
      s.select('a');
      await t.pumpAndSettle();
      final p =
          t.widget<CustomPaint>(_in('detail-tab', 'joined-tab')).painter!
              as RailTabPainter;
      expect(p.squareEnd, isTrue);
      expect(p.squareStart, isFalse);
    });
  });

  group('detail header', () {
    testWidgets('sits above the pane: closable tab, then Promote', (t) async {
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
        lessThanOrEqualTo(t.getRect(_k('peek-promote')).left),
      );
      // Collapse is outside the pane, left of it.
      expect(
        t.getRect(_k('peek-collapse')).right,
        lessThanOrEqualTo(pane.left),
      );
      expect(
        find.descendant(of: _k('detail-tab'), matching: find.text('Alpha')),
        findsOneWidget,
      );
      await t.tap(_in('detail-tab', 'tab-close'));
      await t.pumpAndSettle();
      expect(s.peek, isNull);
      expect(_k('detail-header'), findsNothing);
    });

    testWidgets('the tab close matches a strip tab close in size', (t) async {
      final s = await _pump(t);
      s.select('a');
      s.openNoteTab('b');
      await t.pumpAndSettle();
      expect(
        t.getSize(_in('detail-tab', 'tab-close')),
        t.getSize(_in('tab-n:b', 'tab-close')),
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
      expect(s.peekUid, 'a');
      await t.tap(_in('detail-tab', 'tab-close'));
      await t.pumpAndSettle();
      await t.tap(_k('leave-discard'));
      await t.pumpAndSettle();
      expect(s.peek, isNull);
    });

    testWidgets('Collapse outside the pane start, Promote at its end', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      final header = t.getRect(_k('detail-header'));
      final promote = t.getRect(_k('peek-promote'));
      final collapse = t.getRect(_k('peek-collapse'));
      expect(collapse.right, lessThanOrEqualTo(header.left));
      expect(promote.right, lessThanOrEqualTo(header.right));
      expect(
        t.widget<IconAction>(_k('peek-promote')).tooltip,
        'Open in main area',
      );
      expect(t.widget<IconAction>(_k('peek-collapse')).tooltip, 'Collapse');
    });

    testWidgets('Promote keeps an open draft without prompting', (t) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), 'Changed');
      await t.pump();
      await t.tap(_k('peek-promote'));
      await t.pumpAndSettle();
      expect(_k('leave-save'), findsNothing);
      expect(s.dirtyFor('a'), isTrue);
      expect(s.activeTab, const DocTab.note('a'));
    });

    testWidgets('peek and main tab keep separate drafts', (t) async {
      final s = await _pump(t);
      s.select('a');
      s.openNoteTab('b');
      await t.pumpAndSettle();
      s.startEdit('a');
      s.startEdit('b');
      s.draftFor('a')!.titleController.text = 'A2';
      s.draftFor('b')!.titleController.text = 'B2';
      await t.pump();
      expect(s.dirtyFor('a'), isTrue);
      expect(s.dirtyFor('b'), isTrue);
      await t.tap(_k('tab-home'));
      await t.pumpAndSettle();
      expect(s.dirtyFor('b'), isTrue);
      expect(s.draftFor('a')!.titleController.text, 'A2');
    });

    testWidgets(
      'mirrored: the header is on the left, Collapse between it and the strip',
      (t) async {
        final s = await _pump(t, side: LayoutSide.end);
        s.select('a');
        await t.pumpAndSettle();
        final header = t.getRect(_k('detail-header'));
        final pane = t.getRect(_k('detail-pane'));
        final panel = t.getRect(_k('shell-panel'));
        final strip = t.getRect(_k('tab-strip'));
        expect(header.left, pane.left);
        final collapse = t.getRect(_k('peek-collapse'));
        expect(collapse.left, greaterThanOrEqualTo(header.right));
        expect(collapse.right, lessThanOrEqualTo(strip.left));
        expect(t.getRect(_k('icon-rail')).left, panel.right);
        expect(
          t.getRect(_k('peek-promote')).left,
          lessThan(t.getRect(_k('detail-tab')).left),
        );
        expect(t.getRect(_in('detail-tab', 'joined-tab')).bottom, panel.top);
        expect(t.takeException(), isNull);
      },
    );
  });

  group('between 880 and 1280', () {
    testWidgets('compact peek tab; Promote opens a main tab', (t) async {
      final s = await _pump(t, size: const Size(1000, 800));
      expect(_k('tab-strip'), findsOneWidget);
      s.select('a');
      await t.pumpAndSettle();
      // The peeked note replaces the list, as before.
      expect(_k('detail-pane'), findsNothing);
      expect(_k('detail-header'), findsOneWidget);
      expect(
        t.getSize(_k('detail-header')).width,
        Tokens.light.sizes.detailTab,
      );
      expect(t.getSize(_k('tab-strip')).width, greaterThan(300));
      await t.tap(_k('peek-promote'));
      await t.pumpAndSettle();
      expect(s.activeTab, const DocTab.note('a'));
      expect(_k('detail-header'), findsNothing);
      expect(_k('main-note'), findsOneWidget);
      expect(_k('tab-strip'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('narrow layout: no header row, no strip, no peek', (t) async {
    final s = await _pump(t, size: const Size(500, 900));
    s.select('a');
    await t.pumpAndSettle();
    expect(_k('tab-strip'), findsNothing);
    expect(_k('detail-header'), findsNothing);
    expect(_k('shell-panel'), findsNothing);
    // Items open full screen on narrow: no peek.
    expect(_k('peek-view'), findsNothing);
    expect(_k('main-note'), findsOneWidget);
  });
}
