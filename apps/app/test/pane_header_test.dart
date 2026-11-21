import 'dart:ui';

import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/overflow_tip.dart';
import 'package:davdart_app/ui/sidebar.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

final _long =
    'A very long note title that cannot possibly fit in a narrow header row '
    'of any pane, so it has to be cut with an ellipsis at the end of the line';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha', description: 'Alpha body'),
    Note(uid: 'b', summary: 'Beta', description: 'Beta body'),
    Note(uid: 'l', summary: _long, description: 'Long body'),
  ];
}

Future<AppState> _pump(
  WidgetTester t, {
  Size size = const Size(1500, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s = AppState(
    SpaceNoteSource(space, seed: _Seed()),
    prefs: MemoryStorage(),
  );
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

Finder _k(String k) => find.byKey(Key(k));
Finder _in(String parent, Finder f) =>
    find.descendant(of: _k(parent), matching: f);

Future<void> _hover(WidgetTester t, Finder f) async {
  final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(t.getCenter(f));
  await t.pump(const Duration(seconds: 1));
  await t.pumpAndSettle();
}

void main() {
  final z = Tokens.light.sizes;

  group('item header', () {
    testWidgets('peek: the title is in the header row, none below it', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      expect(_in('peek-toolbar', find.text('Alpha')), findsOneWidget);
      expect(_in('peek-view', find.text('Alpha')), findsOneWidget);
      // The title sits left of the action icons, inside the fixed-height row.
      final row = t.getRect(_in('peek-view', _k('peek-toolbar')));
      final title = t.getRect(_k('pane-title'));
      final edit = t.getRect(_k('edit-note'));
      expect(row.height, z.paneHeader + Tokens.light.borders.hairline * 0);
      expect(title.right, lessThanOrEqualTo(edit.left));
      expect(title.center.dy, closeTo(row.center.dy, 1.5));
    });

    testWidgets('main tab: the title is in the header row', (t) async {
      final s = await _pump(t);
      s.openNoteTab('b');
      await t.pumpAndSettle();
      expect(_in('main-note', _k('peek-toolbar')), findsOneWidget);
      expect(_in('peek-toolbar', find.text('Beta')), findsOneWidget);
      expect(find.text('Beta'), findsWidgets);
      // Body starts right under the header: status row, not a title.
      expect(_in('main-note', find.text('Status')), findsOneWidget);
    });

    testWidgets('a long title ellipsizes on a phone without overflow', (
      t,
    ) async {
      final s = await _pump(t, size: const Size(320, 640));
      s.select('l');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final text = t.widget<Text>(_k('pane-title'));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, 1);
      expect(t.getSize(_k('pane-title')).height, lessThan(z.paneHeader));
      // Cut, so the full title is offered as a tooltip.
      expect(_in('peek-toolbar', find.byType(FTooltip)), findsWidgets);
    });

    testWidgets('edit mode: the field takes the title spot, no jump', (
      t,
    ) async {
      final s = await _pump(t);
      s.select('a');
      await t.pumpAndSettle();
      final before = t.getRect(_in('peek-view', _k('peek-toolbar')));
      final titleLeft = t.getRect(_k('pane-title')).left;
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      expect(_k('pane-title'), findsNothing);
      expect(_in('peek-toolbar', _k('edit-title')), findsOneWidget);
      final after = t.getRect(_in('peek-view', _k('peek-toolbar')));
      expect(after, before);
      final field = t.getRect(_k('edit-title'));
      expect(field.left, closeTo(titleLeft, 1.5));
      expect(field.top, greaterThanOrEqualTo(after.top));
      expect(field.bottom, lessThanOrEqualTo(after.bottom));
      await t.enterText(_k('edit-title'), '');
      await t.pumpAndSettle();
      expect(find.text('A title is required'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('edit mode on a touch phone fits the row, no overflow', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final s = await _pump(t, size: const Size(360, 700));
      s.select('l');
      await t.pumpAndSettle();
      // Narrow: the header's edit/preview toggle.
      await t.tap(_k('item-mode'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // Narrow has no peek: the item opens full screen.
      final row = t.getRect(_in('main-note', _k('peek-toolbar')));
      final field = t.getRect(_k('edit-title'));
      expect(field.top, greaterThanOrEqualTo(row.top));
      expect(field.bottom, lessThanOrEqualTo(row.bottom));
    });

    testWidgets('left panel, main and peek share header height and baseline', (
      t,
    ) async {
      final s = await _pump(t);
      s.openNoteTab('b');
      s.select('a');
      await t.pumpAndSettle();
      final side = t.getRect(_k('side-header'));
      final main = t.getRect(_in('main-note', _k('peek-toolbar')));
      final peek = t.getRect(_in('peek-view', _k('peek-toolbar')));
      expect(side.height, main.height);
      expect(peek.height, main.height);
      expect(side.top, closeTo(main.top, .5));
      expect(peek.top, closeTo(main.top, .5));
      // Same text style, so the titles share a baseline.
      final notes = t.getRect(_in('side-header', find.text('Notes')));
      final mainTitle = t.getRect(_in('main-note', _k('pane-title')));
      final peekTitle = t.getRect(_in('peek-view', _k('pane-title')));
      expect(mainTitle.center.dy, closeTo(notes.center.dy, .5));
      expect(peekTitle.center.dy, closeTo(notes.center.dy, .5));
      expect(mainTitle.height, closeTo(notes.height, .5));
      final a = t.widget<Text>(_in('side-header', find.text('Notes'))).style!;
      final b = t.widget<Text>(_in('main-note', _k('pane-title'))).style!;
      expect(a.fontSize, b.fontSize);
      expect(a.fontWeight, b.fontWeight);
      expect(a.color, b.color);
    });

    testWidgets('Home breadcrumb uses the shared title style', (t) async {
      await _pump(t);
      final crumb = t.widget<Text>(_k('crumb-space')).style!;
      final tk = Tokens.light;
      expect(crumb.fontSize, tk.type.paneTitle);
      expect(crumb.fontWeight, tk.type.paneTitleWeight);
    });
  });

  group('OverflowTip', () {
    Future<void> pumpTip(WidgetTester t, double width, String text) async {
      await t.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          localizationsDelegates: FLocalizations.localizationsDelegates,
          supportedLocales: FLocalizations.supportedLocales,
          pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
            settings: settings,
            pageBuilder: (context, _, _) => builder(context),
          ),
          builder: (context, child) => FTheme(
            data: buildTheme(Brightness.light, touch: false),
            child: FTooltipGroup(child: child!),
          ),
          home: Center(
            child: SizedBox(
              width: width,
              child: OverflowTip(text, textKey: const Key('t')),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('no tooltip when the text fits', (t) async {
      await pumpTip(t, 300, 'Short');
      expect(find.byType(FTooltip), findsNothing);
      await _hover(t, _k('t'));
      expect(find.text('Short'), findsOneWidget);
    });

    testWidgets('hover shows the full text when it is cut', (t) async {
      await pumpTip(t, 80, 'A text that is much too long for this box');
      expect(find.byType(FTooltip), findsOneWidget);
      expect(
        find.text('A text that is much too long for this box'),
        findsOneWidget,
      );
      await _hover(t, _k('t'));
      expect(
        find.text('A text that is much too long for this box'),
        findsNWidgets(2),
      );
    });

    testWidgets('long press shows it on touch', (t) async {
      await pumpTip(t, 80, 'A text that is much too long for this box');
      await t.longPress(_k('t'));
      await t.pump(const Duration(milliseconds: 600));
      expect(
        find.text('A text that is much too long for this box'),
        findsNWidgets(2),
      );
      await t.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('the tooltip comes and goes as the width changes', (t) async {
      await pumpTip(t, 80, 'A text that is much too long for this box');
      expect(find.byType(FTooltip), findsOneWidget);
      await pumpTip(t, 600, 'A text that is much too long for this box');
      expect(find.byType(FTooltip), findsNothing);
    });
  });

  group('truncation tips in the app', () {
    testWidgets('a cut tree row offers its full title', (t) async {
      await _pump(t);
      Finder tip(String text) => find.descendant(
        of: find.byType(DockedSidebar),
        matching: find.byWidgetPredicate(
          (w) => w is OverflowTip && w.text == text,
        ),
      );
      Finder tooltipOf(String text) =>
          find.descendant(of: tip(text), matching: find.byType(FTooltip));
      expect(tip(_long), findsOneWidget);
      expect(tooltipOf(_long), findsOneWidget);
      // A short row has no tooltip.
      expect(tip('Alpha'), findsOneWidget);
      expect(tooltipOf('Alpha'), findsNothing);
      await _hover(t, tip(_long));
      expect(find.text(_long), findsNWidgets(2));
    });

    testWidgets('a cut tab offers its full title', (t) async {
      final s = await _pump(t);
      s.openNoteTab('l');
      s.openNoteTab('a');
      await t.pumpAndSettle();
      expect(_in('tab-n:l', find.byType(FTooltip)), findsOneWidget);
      expect(_in('tab-n:a', find.byType(FTooltip)), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}
