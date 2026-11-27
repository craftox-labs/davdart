import 'package:davdart/davdart.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/page_header.dart';
import 'package:davdart_app/ui/top_tab.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Future<void> _pumpWidget(
  WidgetTester t,
  Widget child, {
  double width = 400,
  double? height,
}) async {
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
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  const tokens = Tokens.light;

  group('TopTabPill alone', () {
    testWidgets('is as tall as the pane header and shows icon and label', (
      t,
    ) async {
      await _pumpWidget(
        t,
        TopTabPill(icon: FLucideIcons.house, label: 'Short', onPress: () {}),
        height: tokens.sizes.paneHeader,
      );
      expect(t.getSize(_k('space-chip')).height, tokens.sizes.paneHeader);
      expect(find.text('Short'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.house), findsOneWidget);
      expect(_k('top-title'), findsOneWidget);
    });

    testWidgets('a long label ellipsizes inside the width', (t) async {
      await _pumpWidget(
        t,
        TopTabPill(
          icon: FLucideIcons.house,
          label: 'A very long label that cannot possibly fit in this pill ' * 3,
          onPress: () {},
        ),
        width: 260,
        height: tokens.sizes.paneHeader,
      );
      final text = t.widget<Text>(_k('top-title'));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 1);
      expect(t.getSize(_k('space-chip')).width, lessThanOrEqualTo(260));
      expect(t.takeException(), isNull);
    });

    testWidgets('labelKey replaces the default key; a tap calls onPress', (
      t,
    ) async {
      var taps = 0;
      await _pumpWidget(
        t,
        TopTabPill(
          icon: FLucideIcons.house,
          label: 'Named',
          labelKey: const Key('custom-label'),
          onPress: () => taps++,
        ),
        height: tokens.sizes.paneHeader,
      );
      expect(_k('custom-label'), findsOneWidget);
      expect(_k('top-title'), findsNothing);
      await t.tap(_k('space-chip'));
      await t.pump(const Duration(milliseconds: 200));
      expect(taps, 1);
    });
  });

  group('PageHeaderRow alone', () {
    testWidgets('is pane-header tall, with title, switcher and actions', (
      t,
    ) async {
      await _pumpWidget(
        t,
        PageHeaderRow(
          title: 'Page',
          textKey: const Key('t'),
          switcher: const SizedBox(key: Key('sw'), width: 40, height: 20),
          actions: const [
            SizedBox(key: Key('a1'), width: 30, height: 20),
            SizedBox(key: Key('a2'), width: 30, height: 20),
          ],
        ),
        width: 800,
      );
      expect(t.getSize(_k('page-header')).height, tokens.sizes.paneHeader);
      expect(t.getSize(_k('page-header')).width, 800);
      final title = t.getRect(_k('t'));
      final sw = t.getRect(_k('sw'));
      final a1 = t.getRect(_k('a1'));
      final a2 = t.getRect(_k('a2'));
      expect(title.right, lessThanOrEqualTo(sw.left));
      expect(sw.right, lessThanOrEqualTo(a1.left));
      expect(a1.right, lessThanOrEqualTo(a2.left));
      // Actions sit at the right edge, inside the horizontal padding.
      expect(a2.right, 800 - tokens.space.md);
    });

    testWidgets('a long title does not push the actions out', (t) async {
      await _pumpWidget(
        t,
        PageHeaderRow(
          title: 'Long title ' * 30,
          textKey: const Key('t'),
          actions: const [SizedBox(key: Key('a1'), width: 30, height: 20)],
        ),
        width: 300,
      );
      expect(t.getRect(_k('a1')).right, 300 - tokens.space.md);
      expect(
        t.getRect(_k('t')).right,
        lessThanOrEqualTo(t.getRect(_k('a1')).left),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('call sites use the shared widgets', () {
    testWidgets('phone Home: one TopTabPill, no PageHeaderRow', (t) async {
      final s = await pumpTasksApp(t, size: const Size(390, 800));
      expect(s.activeTab, isNull);
      expect(find.byType(TopTabPill), findsOneWidget);
      expect(find.byType(PageHeaderRow), findsNothing);
      expect(
        find.descendant(of: find.byType(TopTabPill), matching: _k('top-title')),
        findsOneWidget,
      );
      expect(t.getSize(_k('space-chip')).height, tokens.sizes.paneHeader);
    });

    testWidgets('phone project page: the same TopTabPill', (t) async {
      final s = await pumpHomeApp(t, size: const Size(390, 800));
      expect(s.mainProjectUid, testProjectUid);
      expect(find.byType(TopTabPill), findsOneWidget);
      expect(find.byType(PageHeaderRow), findsNothing);
      expect(
        t.widget<TopTabPill>(find.byType(TopTabPill)).label,
        s.mainPageTitle,
      );
      expect(t.getSize(_k('space-chip')).height, tokens.sizes.paneHeader);
    });

    testWidgets('phone item page: the same TopTabPill', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n1', summary: 'Item one')],
        size: const Size(390, 800),
      );
      s.openNoteTab('n1');
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(TopTabPill), findsOneWidget);
      expect(find.byType(PageHeaderRow), findsNothing);
      expect(t.widget<TopTabPill>(find.byType(TopTabPill)).label, 'Item one');
    });

    testWidgets('desktop Home: one PageHeaderRow naming the Space', (t) async {
      final s = await pumpTasksApp(t);
      expect(find.byType(PageHeaderRow), findsOneWidget);
      expect(find.byType(TopTabPill), findsNothing);
      expect(
        t.widget<PageHeaderRow>(find.byType(PageHeaderRow)).title,
        s.currentSpaceName ?? 'This Space',
      );
      expect(t.getSize(_k('page-header')).height, tokens.sizes.paneHeader);
    });

    testWidgets('desktop project page: one PageHeaderRow, project title', (
      t,
    ) async {
      final s = await pumpHomeApp(t);
      expect(find.byType(PageHeaderRow), findsOneWidget);
      expect(find.byType(TopTabPill), findsNothing);
      expect(
        t.widget<PageHeaderRow>(find.byType(PageHeaderRow)).title,
        s.mainPageTitle,
      );
      expect(_k('page-title'), findsOneWidget);
    });

    testWidgets('desktop header actions go in the actions slot', (t) async {
      await pumpHomeApp(t);
      final row = t.widget<PageHeaderRow>(find.byType(PageHeaderRow));
      expect(row.actions, isNotEmpty);
      expect(row.switcher, isNull);
    });
  });
}
