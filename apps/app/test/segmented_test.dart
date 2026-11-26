import 'package:davdart_app/ui/segmented.dart';
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
      if (width < 600) expect(b.width, a.width);
    });
  }

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
