import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

final _notes = [
  Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
  Note(uid: 'a', summary: 'A', description: 'status: todo\n\nx'),
  Note(uid: 'b', summary: 'B', description: 'status: doing\n\nx'),
];

Future<AppState> _app(WidgetTester t, {Size? size}) async {
  AppState.debugDefaultFocus = HomeFocus.board;
  final s = await pumpTasksApp(
    t,
    size: size ?? const Size(1280, 900),
    notes: _notes,
    tasks: [mkTask('t1', days: 0)],
  );
  await s.activateTab(null);
  await t.pumpAndSettle();
  return s;
}

Finder get _refresh => find.byIcon(FLucideIcons.refreshCw);

void main() {
  group('wide header', () {
    testWidgets('menu holds move/edit/delete/close; close acts', (t) async {
      final s = await _app(t);
      s.openFolder('f');
      await t.pumpAndSettle();
      expect(_k('scope-edit'), findsNothing);
      expect(_k('scope-close'), findsNothing);
      await t.tap(_k('scope-more'));
      await t.pumpAndSettle();
      expect(_k('scope-edit'), findsOneWidget);
      expect(_k('scope-delete'), findsOneWidget);
      expect(_k('scope-close'), findsOneWidget);
      expect(find.text('Show the whole space'), findsOneWidget);
      await t.tap(_k('scope-close'));
      await t.pumpAndSettle();
      expect(s.scopeUid, isNull);
    });

    testWidgets('refresh stays visible; menu sits left of Columns and it', (
      t,
    ) async {
      final s = await _app(t);
      s.openFolder('f');
      await t.pumpAndSettle();
      final r = t.getRect(_refresh);
      final m = t.getRect(_k('scope-more'));
      expect(m.right, lessThanOrEqualTo(r.left));
    });

    testWidgets('Columns slot is stable across Board and Tasks', (t) async {
      final s = await _app(t);
      final refresh = t.getRect(_refresh);
      s.setHomeFocus(HomeFocus.board);
      await t.pumpAndSettle();
      final board = t.getRect(_k('home-cols'));
      expect(board.right, lessThanOrEqualTo(refresh.left));
      expect(refresh.left - board.right, lessThan(16));
      s.setHomeFocus(HomeFocus.tasks);
      await t.pumpAndSettle();
      expect(t.getRect(_k('home-cols')), board);
      expect(t.getRect(_refresh), refresh);
    });
  });

  group('phone', () {
    testWidgets('search chip is full width with equal gaps', (t) async {
      final s = await _app(t, size: const Size(390, 800));
      s.setQuery('foo');
      await t.pumpAndSettle();
      final chip = t.getRect(_k('filter-chip-search'));
      final sw = t.getRect(_k('home-focus'));
      expect(chip.left, closeTo(sw.left, 1));
      expect(chip.right, closeTo(sw.right, 1));
      final bar = t.getRect(_k('top-bar'));
      expect(chip.top - bar.bottom, closeTo(sw.top - chip.bottom, 1));
      final x = t.getRect(_k('clear-filter-search'));
      expect(x.right, lessThanOrEqualTo(chip.right));
      expect(chip.right - x.right, lessThan(20));
    });
  });

  group('refresh spin', () {
    for (final size in [const Size(1280, 900), const Size(390, 800)]) {
      testWidgets('spins only while syncing at ${size.width}', (t) async {
        final s = await _app(t, size: size);
        s.syncing = true;
        // ignore: invalid_use_of_protected_member
        s.notifyListeners();
        await t.pump();
        final spin = find.descendant(
          of: _k('top-bar'),
          matching: find.byType(RotationTransition),
        );
        expect(spin, findsOneWidget);
        await t.pump(const Duration(milliseconds: 300));
        s.syncing = false;
        // ignore: invalid_use_of_protected_member
        s.notifyListeners();
        await t.pumpAndSettle();
        expect(
          find.descendant(
            of: _k('top-bar'),
            matching: find.byType(RotationTransition),
          ),
          findsNothing,
        );
      });
    }
  });
}
