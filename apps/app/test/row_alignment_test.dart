import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha', description: 'Alpha body'),
  ];
}

Future<AppState> _pump(WidgetTester t, double width, LayoutSide side) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s = AppState(
    SpaceNoteSource(space, seed: _Seed()),
    prefs: MemoryStorage(),
  );
  s.setLayoutSide(side);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

Finder _k(String k) => find.byKey(Key(k));

void _same(WidgetTester t, Finder a, Finder b, {bool box = true}) {
  expect(a, findsOneWidget);
  expect(b, findsOneWidget);
  final ra = t.getRect(a), rb = t.getRect(b);
  if (box) {
    expect((ra.top - rb.top).abs(), lessThanOrEqualTo(1));
    expect((ra.height - rb.height).abs(), lessThanOrEqualTo(1));
  }
  expect((ra.center.dy - rb.center.dy).abs(), lessThanOrEqualTo(1));
}

void main() {
  for (final side in LayoutSide.values) {
    for (final width in [880.0, 1280.0]) {
      final tag = '$width ${side.name}';
      testWidgets('side header lines up with top bar, $tag', (t) async {
        await _pump(t, width, side);
        _same(t, _k('side-header'), _k('top-bar'));
        _same(
          t,
          find.descendant(of: _k('side-header'), matching: find.text('Notes')),
          find
              .descendant(
                of: _k('top-bar'),
                matching: find.byKey(const Key('crumb-space')),
              )
              .first,
          box: false,
        );
        final icons = find.descendant(
          of: _k('side-header'),
          matching: find.byType(Icon),
        );
        final bar = find.descendant(
          of: _k('top-bar'),
          matching: find.byType(Icon),
        );
        expect(icons, findsWidgets);
        expect(bar, findsWidgets);
        expect(
          (t.getRect(icons.first).center.dy - t.getRect(bar.first).center.dy)
              .abs(),
          lessThanOrEqualTo(1),
        );
      });

      testWidgets('peek toolbar lines up with side header, $tag', (t) async {
        final s = await _pump(t, width, side);
        s.select('a');
        await t.pumpAndSettle();
        _same(t, _k('peek-toolbar'), _k('side-header'));
        if (width >= 1280) _same(t, _k('peek-toolbar'), _k('top-bar'));
      });
    }
  }

  testWidgets('rail Spaces icon is level with the side panel header', (
    t,
  ) async {
    await _pump(t, 1280, LayoutSide.start);
    expect(
      (t.getRect(_k('rail-spaces')).center.dy -
              t.getRect(_k('side-header')).center.dy)
          .abs(),
      lessThanOrEqualTo(1),
    );
  });

  testWidgets('header controls share one centreline at 1280', (t) async {
    final s = await _pump(t, 1280, LayoutSide.start);
    s.select('a');
    await t.pumpAndSettle();
    final plus = _k('tab-new');
    final line = t.getRect(plus).center.dy;
    for (final k in ['peek-collapse', 'detail-tab', 'tab-home', 'logo-slot']) {
      expect(
        (t.getRect(_k(k)).center.dy - line).abs(),
        lessThanOrEqualTo(1),
        reason: k,
      );
    }
    // The control is outside the pane, left of it.
    expect(
      t.getRect(_k('peek-collapse')).left,
      lessThan(t.getRect(_k('detail-pane')).left),
    );
    expect(
      t.getRect(_k('peek-collapse')).right,
      lessThanOrEqualTo(t.getRect(_k('detail-pane')).left),
    );
    s.setPeekCollapsed(true);
    await t.pumpAndSettle();
    expect(
      (t.getRect(_k('peek-expand')).center.dy - line).abs(),
      lessThanOrEqualTo(1),
    );
    s.setPeekCollapsed(false);
    await t.pumpAndSettle();
    expect(_k('peek-collapse'), findsOneWidget);
  });

  testWidgets('peek label and title share a left edge, content full width', (
    t,
  ) async {
    final s = await _pump(t, 1280, LayoutSide.start);
    await s.addFolder('Decisions');
    await s.addNote('Scope note', parentUid: s.scope!.uid);
    final uid = s.notes.firstWhere((n) => n.summary == 'Scope note').uid;
    s.openFolder(null);
    s.select(uid);
    await t.pumpAndSettle();
    final peek = _k('peek-view');
    final label = t.getRect(_k('breadcrumb')).left;
    final title = t
        .getRect(find.descendant(of: peek, matching: find.text('Scope note')))
        .left;
    expect((label - title).abs(), lessThanOrEqualTo(1));
    // The page has the pane's ordinary padding, no tab-driven inset.
    final tk = tokensOf(t.element(peek));
    final pane = t.getRect(_k('detail-pane'));
    expect(title - pane.left, closeTo(tk.space.xxl, 1.5));
    final scroll = t.getRect(
      find.descendant(of: peek, matching: find.byType(SingleChildScrollView)),
    );
    expect(scroll.width, closeTo(pane.width, 1.5));
  });

  testWidgets('collapsed rail: divider through header, square corner', (
    t,
  ) async {
    final s = await _pump(t, 1280, LayoutSide.start);
    s.setSidebarCollapsed(true);
    await t.pumpAndSettle();
    final tk = tokensOf(t.element(_k('shell-panel')));
    final panel = t.getRect(_k('shell-panel'));
    final divider = t.getRect(_k('rail-divider'));
    expect(divider.left, panel.left);
    expect(divider.top, 0);
    expect(divider.bottom, greaterThanOrEqualTo(panel.top));
    // Flush at the divider's inner edge, as beside an open side panel.
    expect(t.getRect(_k('tab-home')).left, panel.left + tk.borders.hairline);
    final box =
        t.widget<Container>(_k('shell-panel')).decoration! as BoxDecoration;
    final r = box.borderRadius! as BorderRadius;
    expect(r.topLeft, Radius.zero);
    expect(r.topRight, isNot(Radius.zero));
    expect(r.bottomLeft, isNot(Radius.zero));
    // Open again: the rounded corner and the divider-less header return.
    s.setSidebarCollapsed(false);
    await t.pumpAndSettle();
    expect(_k('rail-divider'), findsNothing);
    final open =
        t.widget<Container>(_k('shell-panel')).decoration! as BoxDecoration;
    expect((open.borderRadius! as BorderRadius).topLeft, isNot(Radius.zero));
  });
}
