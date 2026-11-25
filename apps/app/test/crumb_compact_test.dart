import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _f(String uid, String name, [String? parent]) => Note(
  uid: uid,
  summary: name,
  parentUid: parent,
  categories: ['kind-folder'],
);

final _long = 'A very long ancestor folder name ' * 3;

final _notes = [
  Note(
    uid: 'n1',
    summary: 'N1',
    parentUid: 'a',
    description: 'status: todo\n\nx',
  ),
  Note(
    uid: 'n2',
    summary: 'N2',
    parentUid: 'a',
    description: 'status: doing\n\nx',
  ),
  _f('a', 'Alpha'),
  _f('b', 'Beta', 'a'),
  _f('c', 'Gamma', 'b'),
  for (var i = 0; i < 6; i++)
    _f('l$i', '$_long$i', i == 0 ? null : 'l${i - 1}'),
  _f('cur', 'Current folder with a rather long title indeed', 'l5'),
];

Future<AppState> _app(WidgetTester t, Size size) async {
  AppState.debugDefaultFocus = HomeFocus.board;
  final s = await pumpTasksApp(
    t,
    size: size,
    notes: _notes,
    tasks: [mkTask('t1', days: 0)],
  );
  await s.activateTab(null);
  await t.pumpAndSettle();
  return s;
}

Finder get _refresh => find.byIcon(FLucideIcons.refreshCw);

void main() {
  testWidgets('wide: Columns and refresh stay put as a folder opens', (
    t,
  ) async {
    final s = await _app(t, const Size(1280, 900));
    final cols = t.getRect(_k('home-cols'));
    final refresh = t.getRect(_refresh);
    expect(_k('scope-more'), findsNothing);
    s.openFolder('a');
    await t.pumpAndSettle();
    expect(t.getRect(_k('home-cols')), cols);
    expect(t.getRect(_refresh), refresh);
    expect(t.getRect(_k('scope-more')).right, lessThanOrEqualTo(cols.left));
    s.openFolder(null);
    await t.pumpAndSettle();
    expect(t.getRect(_k('home-cols')), cols);
    expect(t.getRect(_refresh), refresh);
  });

  group('narrow crumb', () {
    testWidgets('house, ellipsis, current; sheet lists ancestors', (t) async {
      final s = await _app(t, const Size(390, 800));
      s.openFolder('c');
      await t.pumpAndSettle();
      expect(_k('crumb-space'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('crumb-space'),
          matching: find.byIcon(FLucideIcons.house),
        ),
        findsOneWidget,
      );
      expect(_k('crumb-more'), findsOneWidget);
      expect(
        find
                .descendant(
                  of: _k('crumb-folder'),
                  matching: find.text('Gamma'),
                )
                .evaluate()
                .length +
            find.text('Gamma').evaluate().length,
        greaterThan(0),
      );
      expect(find.text('Alpha'), findsNothing);
      await t.tap(_k('crumb-more'));
      await t.pumpAndSettle();
      final ys = [
        for (final k in ['crumb-anc-root', 'crumb-anc-1', 'crumb-anc-2'])
          t.getRect(_k(k)).top,
      ];
      expect(ys, [...ys]..sort());
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      final x1 = t.getTopLeft(find.text('Alpha')).dx;
      final x2 = t.getTopLeft(find.text('Beta')).dx;
      expect(x2, greaterThan(x1));
      await t.tap(_k('crumb-anc-1'));
      await t.pumpAndSettle();
      expect(s.scopeUid, 'a');
      expect(_k('crumb-more'), findsNothing);
    });

    testWidgets('root entry clears the scope', (t) async {
      final s = await _app(t, const Size(390, 800));
      s.openFolder('c');
      await t.pumpAndSettle();
      await t.tap(_k('crumb-more'));
      await t.pumpAndSettle();
      await t.tap(_k('crumb-anc-root'));
      await t.pumpAndSettle();
      expect(s.scopeUid, isNull);
    });

    testWidgets('one level deep has no ellipsis', (t) async {
      final s = await _app(t, const Size(390, 800));
      s.openFolder('a');
      await t.pumpAndSettle();
      expect(_k('crumb-more'), findsNothing);
      expect(_k('crumb-folder'), findsOneWidget);
    });

    testWidgets('current stays visible at 320dp with a long chain', (t) async {
      final s = await _app(t, const Size(320, 800));
      s.openFolder('cur');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final row = t.getRect(_k('content-crumbs'));
      final cur = t.getRect(_k('crumb-folder'));
      expect(cur.width, greaterThan(70));
      expect(cur.left, greaterThanOrEqualTo(row.left));
      expect(cur.right, lessThanOrEqualTo(row.right));
      expect(cur.top, greaterThanOrEqualTo(row.top));
      expect(cur.bottom, lessThanOrEqualTo(row.bottom));
      final bar = t.getRect(_k('top-bar'));
      expect(t.getRect(_refresh).right, lessThanOrEqualTo(bar.right));
    });
  });
}
