import 'package:davdart_app/ui/segmented.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Future<void> _pump(WidgetTester t, Widget child, {double width = 1000}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    FTheme(
      data: buildTheme(Brightness.light, touch: false),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: SizedBox(
            width: width,
            height: 800,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [child],
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Segmented<int> _labels() => Segmented<int>(
  key: const Key('labels'),
  value: 0,
  onChanged: (_) {},
  segments: const [Segment(0, 'List', 'l0'), Segment(1, 'Tree', 'l1')],
);

Segmented<int> _fourIcons({bool full = false}) => Segmented<int>(
  key: const Key('four-icons'),
  value: 0,
  fullWidth: full,
  onChanged: (_) {},
  segments: const [
    Segment(0, 'Overview', 'f0', icon: FLucideIcons.layoutGrid),
    Segment(1, 'Board', 'f1', icon: FLucideIcons.squareKanban),
    Segment(2, 'Notes', 'f2', icon: FLucideIcons.fileText),
    Segment(3, 'Calendar', 'f3', icon: FLucideIcons.calendarDays),
  ],
);

Segmented<int> _icons({bool full = false}) => Segmented<int>(
  key: const Key('icons'),
  value: 0,
  fullWidth: full,
  onChanged: (_) {},
  segments: const [
    Segment(0, 'List', 'i0', icon: FLucideIcons.list),
    Segment(1, 'Tree', 'i1', icon: FLucideIcons.listTree),
  ],
);

void main() {
  testWidgets(
    'desktop segments are equal width and one height in any switcher',
    (t) async {
      await _pump(t, Column(children: [_fourIcons(), _labels(), _icons()]));
      double w(String k) => t.getSize(find.byKey(Key(k))).width;
      double h(String k) => t.getSize(find.byKey(Key(k))).height;
      final four = [w('f0'), w('f1'), w('f2'), w('f3')];
      expect(four.every((x) => x == four.first), isTrue, reason: '$four');
      expect(four.first, greaterThanOrEqualTo(Tokens.light.sizes.segmentMin));
      expect(w('l0'), w('l1'));
      expect(w('i0'), w('i1'));
      for (final k in ['f0', 'f3', 'l0', 'i1']) {
        expect(h(k), Tokens.light.sizes.segmentHeight);
      }
    },
  );

  for (final width in [1000.0, 400.0]) {
    testWidgets('icon and label segments share a height at $width', (t) async {
      await _pump(t, Column(children: [_labels(), _icons()]), width: width);
      final a = t.getSize(find.byKey(const Key('l0')));
      final b = t.getSize(find.byKey(const Key('i0')));
      expect(b.height, a.height);
      // Both honour the same minimum width; icon-only (narrow) segments
      // are the same size as label-only ones.
      expect(a.width, greaterThanOrEqualTo(72));
      expect(b.width, greaterThanOrEqualTo(72));
      // Short labels keep their segmentMin width; the padding does not widen
      // them, and the icon+label variant has room for the icon and text.
      expect(a.width, Tokens.light.sizes.segmentMin);
      if (width < 600) expect(b.width, a.width);
    });
  }

  for (final width in [1000.0, 400.0]) {
    testWidgets('every segment keeps the shared side padding at $width', (
      t,
    ) async {
      await _pump(t, Column(children: [_labels(), _icons()]), width: width);
      final pad = Tokens.light.space.lg;
      Rect content(String key) {
        final seg = find.byKey(Key(key));
        final rects = [
          for (final f in [find.byType(Text), find.byType(Icon)])
            for (final e in find.descendant(of: seg, matching: f).evaluate())
              e.renderObject! as RenderBox,
        ].map((b) => b.localToGlobal(Offset.zero) & b.size);
        return rects.reduce((a, b) => a.expandToInclude(b));
      }

      for (final key in ['l0', 'i0']) {
        final box = t.getRect(find.byKey(Key(key)));
        final inside = content(key);
        expect(inside.left - box.left, greaterThanOrEqualTo(pad - 0.1));
        expect(box.right - inside.right, greaterThanOrEqualTo(pad - 0.1));
      }
    });
  }

  testWidgets('four icon-only segments fit a phone row', (t) async {
    await _pump(
      t,
      SizedBox(width: 320, child: _fourIcons(full: true)),
      width: 320,
    );
    for (final key in ['f0', 'f1', 'f2', 'f3']) {
      final box = t.getRect(find.byKey(Key(key)));
      expect(box.width, greaterThan(0));
      expect(box.right, lessThanOrEqualTo(320));
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('a non-full-width switcher sits at the start, not centred', (
    t,
  ) async {
    await _pump(t, _labels());
    expect(t.getTopLeft(find.byKey(const Key('labels'))).dx, 0);
  });

  testWidgets('a full-width switcher spans its parent', (t) async {
    await _pump(t, SizedBox(width: 400, child: _icons(full: true)), width: 500);
    expect(t.getSize(find.byKey(const Key('icons'))).width, 400);
  });
}
