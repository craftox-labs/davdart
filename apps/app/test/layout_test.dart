import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/shell_frame.dart';
import 'package:davdart_app/ui/sidebar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

class _Source implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'One', description: 'status: todo\n\nBody'),
  ];
}

final z = Tokens.light.sizes;

Future<AppState> _pump(
  WidgetTester t, {
  MemoryStorage? storage,
  Size size = const Size(1500, 900),
  bool select = true,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final state = AppState(_Source(), prefs: storage ?? MemoryStorage());
  await t.pumpWidget(DavdartApp(state: state));
  await t.pumpAndSettle();
  if (select) {
    state.select('a');
    await t.pumpAndSettle();
  }
  return state;
}

Finder get _detail => find.byKey(const Key('detail-pane'));
Finder get _handle => find.byKey(const Key('detail-handle'));

Future<void> _doubleTap(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pump(kDoubleTapMinTime);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  group('detail pane resize', () {
    testWidgets('defaults to the token, drags within limits, persists', (
      t,
    ) async {
      final storage = MemoryStorage();
      final state = await _pump(t, storage: storage);
      double width() => t.getSize(_detail).width;
      expect(width(), z.detail);
      // Handle on the pane's left edge: dragging left widens it.
      await t.drag(_handle, const Offset(-100, 0));
      await t.pumpAndSettle();
      expect(width(), z.detail + 100);
      expect(AppState(_Source(), prefs: storage).detailWidth, z.detail + 100);
      expect(state.detailWidth, z.detail + 100);
      await t.drag(_handle, const Offset(900, 0));
      await t.pumpAndSettle();
      expect(width(), z.detailMin);
      await t.drag(_handle, const Offset(-900, 0));
      await t.pumpAndSettle();
      expect(width(), lessThanOrEqualTo(z.detailMax));
      expect(width(), greaterThan(z.detailMin));
    });

    testWidgets('never takes the list below its minimum', (t) async {
      await _pump(t, size: const Size(1290, 900));
      await t.drag(_handle, const Offset(-900, 0));
      await t.pumpAndSettle();
      final body = t.getSize(find.byType(FScaffold)).width;
      expect(body - t.getSize(_detail).width, greaterThanOrEqualTo(z.listMin));
    });

    testWidgets('double-click resets and forgets the saved width', (t) async {
      final storage = MemoryStorage();
      await _pump(t, storage: storage);
      await t.drag(_handle, const Offset(-80, 0));
      await t.pumpAndSettle();
      expect(storage.read('davdart.detail.width.v1'), isNotNull);
      await _doubleTap(t, _handle);
      expect(t.getSize(_detail).width, z.detail);
      expect(storage.read('davdart.detail.width.v1'), isNull);
    });

    test('saved width: non-finite is ignored', () {
      for (final bad in ['NaN', 'Infinity', 'x']) {
        final s = MemoryStorage()..write('davdart.detail.width.v1', bad);
        expect(AppState(_Source(), prefs: s).detailWidth, isNull);
      }
    });

    testWidgets('a saved width outside the limits is clamped', (t) async {
      final s = MemoryStorage()..write('davdart.detail.width.v1', '9999');
      await _pump(t, storage: s);
      expect(t.getSize(_detail).width, z.detailMax);
      final s2 = MemoryStorage()..write('davdart.detail.width.v1', '10');
      await _pump(t, storage: s2);
      expect(t.getSize(_detail).width, z.detailMin);
    });
  });

  group('mirrored shell', () {
    double left(WidgetTester t, Finder f) => t.getTopLeft(f).dx;

    testWidgets('start: rail, panel, content, detail left to right', (t) async {
      await _pump(t);
      expect(left(t, find.byKey(const Key('icon-rail'))), 0);
      expect(
        left(t, find.byType(DockedSidebar)),
        lessThan(left(t, find.byType(FScaffold))),
      );
      expect(left(t, find.byType(FScaffold)), lessThan(left(t, _detail)));
    });

    testWidgets('end: detail, content, panel, rail left to right', (t) async {
      final state = await _pump(t, select: false);
      state.setLayoutSide(LayoutSide.end);
      state.select('a');
      await t.pumpAndSettle();
      final rail = find.byKey(const Key('icon-rail'));
      expect(t.getRect(rail).right, 1500);
      expect(t.getRect(find.byType(DockedSidebar)).right, lessThan(1500));
      // The side panel sits immediately left of the rail, inside the panel.
      final panel = t.getRect(find.byKey(const Key('shell-panel')));
      expect(t.getRect(rail).left, panel.right);
      expect(
        t.getRect(find.byType(DockedSidebar)).right,
        lessThanOrEqualTo(panel.right),
      );
      final sidebar = t.getRect(find.byType(DockedSidebar));
      final scaffold = t.getRect(find.byType(FScaffold));
      final detail = t.getRect(_detail);
      expect(detail.right, lessThanOrEqualTo(scaffold.right));
      expect(detail.left, lessThan(scaffold.left + scaffold.width / 2));
      expect(scaffold.right, sidebar.left);
      expect(panel.left, z.frameInset);
      // Handles sit on the inner edges: detail's right, sidebar's left.
      expect(t.getRect(_handle).right, closeTo(detail.right, 0.01));
      expect(
        t.getRect(find.byKey(const Key('sidebar-handle'))).left,
        closeTo(sidebar.left, 0.01),
      );
    });

    testWidgets('end: handles grow the panes the other way', (t) async {
      final state = await _pump(t, select: false);
      state.setLayoutSide(LayoutSide.end);
      state.select('a');
      await t.pumpAndSettle();
      await t.drag(_handle, const Offset(60, 0));
      await t.pumpAndSettle();
      expect(t.getSize(_detail).width, z.detail + 60);
      final sb = find.byKey(const Key('sidebar-handle'));
      await t.drag(sb, const Offset(-50, 0));
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(DockedSidebar)).width, z.sidebar + 50);
    });

    testWidgets('the setting persists and Settings offers it', (t) async {
      final storage = MemoryStorage();
      final state = await _pump(t, storage: storage, select: false);
      state.setSection(Section.settings);
      await t.pumpAndSettle();
      expect(find.text('Layout side'), findsOneWidget);
      await t.tap(find.byType(FRadio).last);
      await t.pumpAndSettle();
      expect(state.layoutSide, LayoutSide.end);
      expect(AppState(_Source(), prefs: storage).layoutSide, LayoutSide.end);
      await t.tap(find.byType(FRadio).first);
      await t.pumpAndSettle();
      expect(state.layoutSide, LayoutSide.start);
      expect(storage.read('davdart.layout.side.v1'), isNull);
    });

    testWidgets('the tab painter is flipped and opens into the panel', (
      t,
    ) async {
      final state = await _pump(t, select: false);
      state.setLayoutSide(LayoutSide.end);
      await t.pumpAndSettle();
      final tab = find.byKey(const Key('rail-tab'));
      final p = t.widget<CustomPaint>(tab).painter! as RailTabPainter;
      expect(p.flip, isTrue);
      final box = t.getRect(tab);
      final panel = t.getRect(find.byKey(const Key('shell-panel')));
      final body = p.body(box.size).shift(box.topLeft);
      // Its left edge reaches the panel's inner edge over the border.
      expect(
        body.left,
        closeTo(panel.right - Tokens.light.borders.hairline, 0.01),
      );
      expect(body.right, box.right);
    });

    testWidgets('rail tooltips and the Spaces popup open leftwards', (t) async {
      final state = await _pump(t, select: false);
      FTooltip tip() => t.widget<FTooltip>(
        find.descendant(
          of: find.byKey(const Key('rail-notes')),
          matching: find.byType(FTooltip),
        ),
      );
      expect(tip().childAnchor, Alignment.centerRight);
      state.setLayoutSide(LayoutSide.end);
      await t.pumpAndSettle();
      expect(tip().tipAnchor, Alignment.centerRight);
      expect(tip().childAnchor, Alignment.centerLeft);
      final menu = t.widget<FPopoverMenu>(
        find.descendant(
          of: find.byKey(const Key('rail-spaces')),
          matching: find.byType(FPopoverMenu),
        ),
      );
      expect(menu.menuAnchor, Alignment.topRight);
      expect(menu.childAnchor, Alignment.topLeft);
    });

    testWidgets('narrow layout ignores the side', (t) async {
      final storage = MemoryStorage()..write('davdart.layout.side.v1', 'end');
      await _pump(
        t,
        storage: storage,
        size: const Size(420, 800),
        select: false,
      );
      expect(find.byKey(const Key('icon-rail')), findsNothing);
      expect(find.byKey(const Key('shell-panel')), findsNothing);
    });
  });
}
