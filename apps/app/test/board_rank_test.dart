import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _note(String uid, {String status = 'todo', double? rank}) => Note(
  uid: uid,
  summary: 'Note $uid',
  description: 'status: $status\n\nbody',
  categories: ['status-$status'],
  created: DateTime.utc(2026, 1, 1, 0, 0, uid.codeUnitAt(0)),
  lastModified: DateTime.now().toUtc(),
)..rank = rank;

List<String> _uids(AppState s, String col) => [
  for (final i in s.homeColumns(all: true).firstWhere((c) => c.$1 == col).$2)
    i.uid,
];

void _desktop() {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

Future<void> _drag(WidgetTester t, Offset from, Offset to) async {
  final g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
  await t.pump();
  await g.moveTo(from + const Offset(0, 12));
  await t.pump();
  await g.moveTo(to);
  await t.pump();
  await g.moveTo(to + const Offset(0, 1));
  await t.pump();
  await g.up();
  await t.pumpAndSettle();
}

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));

  group('rank ordering', () {
    BoardItem n(String u, double? r) => BoardItem.note(_note(u, rank: r));
    List<String> order(List<BoardItem> i) => [
      for (final x in ([...i]..sort(compareBoardItems))) x.uid,
    ];
    test('ranked first ascending, unranked fall back after', () {
      expect(order([n('a', null), n('c', 2), n('b', null), n('d', -1)]), [
        'd',
        'c',
        'a',
        'b',
      ]);
    });
    test('rank beats priority; tasks read their rank too', () {
      final t = Task(uid: 't', summary: 'T', priority: 1)..rank = 5;
      final u = Task(uid: 'u', summary: 'U', priority: 9)..rank = 3;
      expect(order([BoardItem.task(t), BoardItem.task(u)]), ['u', 't']);
      expect(BoardItem.task(t).rank, 5);
    });
  });

  group('placeBoardItem', () {
    testWidgets('within a column writes one rank between the neighbours', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          _note('a', rank: 1),
          _note('b', rank: 2),
          _note('c', rank: 3),
        ],
      );
      expect(_uids(s, 'todo'), ['a', 'b', 'c']);
      await s.placeBoardItem('c', 'todo', index: 1);
      await t.pumpAndSettle();
      expect(_uids(s, 'todo'), ['a', 'c', 'b']);
      expect(s.tree.find('c')!.note.rank, 1.5);
      expect(s.tree.find('a')!.note.rank, 1);
      expect(s.tree.find('b')!.note.rank, 2);
    });

    testWidgets('unranked column: cards above get ranks, tasks work too', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        notes: [_note('a'), _note('b')],
        tasks: [mkTask('k', summary: 'K')],
      );
      final before = _uids(s, 'todo');
      expect(before, hasLength(3));
      final last = before.last;
      await s.placeBoardItem(last, 'todo', index: 1);
      await t.pumpAndSettle();
      expect(_uids(s, 'todo'), [before[0], last, before[1]]);
    });

    testWidgets('another column: status changes and lands at the index', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          _note('a', rank: 1),
          _note('b', rank: 2),
          _note('x', status: 'doing', rank: 9),
        ],
      );
      await s.placeBoardItem('x', 'todo', index: 0);
      await t.pumpAndSettle();
      expect(_uids(s, 'todo'), ['x', 'a', 'b']);
      expect(PlanItem.fromNote(s.tree.find('x')!.note).status, 'todo');
    });

    testWidgets('status-only drop drops the old rank', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [_note('x', status: 'doing', rank: 9)],
      );
      await s.placeBoardItem('x', 'todo');
      await t.pumpAndSettle();
      expect(s.tree.find('x')!.note.rank, isNull);
      expect(_uids(s, 'todo'), ['x']);
    });
  });

  group('drag within a column', () {
    testWidgets('dropping on the lower half of a card places it after', (
      t,
    ) async {
      _desktop();
      final s = await pumpTasksApp(
        t,
        notes: [_note('a', rank: 1), _note('b', rank: 2), _note('c', rank: 3)],
      );
      await t.tap(_k('home-focus-board'));
      await t.pumpAndSettle();
      final a = find.byKey(const ValueKey('nav-card-a'));
      final c = find.byKey(const ValueKey('nav-card-c'));
      final rect = t.getRect(c);
      // Over the card's upper half: the line shows before it.
      final g = await t.startGesture(
        t.getCenter(a),
        kind: PointerDeviceKind.mouse,
      );
      await t.pump();
      await g.moveTo(t.getCenter(a) + const Offset(0, 12));
      await t.pump();
      await g.moveTo(Offset(rect.center.dx, rect.top + 5));
      await t.pump();
      await g.moveTo(Offset(rect.center.dx, rect.top + 6));
      await t.pump();
      expect(_k('drop-line-before'), findsOneWidget);
      await g.moveTo(Offset(rect.center.dx, rect.bottom - 6));
      await t.pump();
      expect(_k('drop-line-after'), findsOneWidget);
      await g.up();
      await t.pumpAndSettle();
      expect(_uids(s, 'todo'), ['b', 'c', 'a']);
      expect(_k('drop-line-after'), findsNothing);
    });

    testWidgets('onto itself changes nothing', (t) async {
      _desktop();
      final s = await pumpTasksApp(
        t,
        notes: [_note('a', rank: 1), _note('b', rank: 2)],
      );
      await t.tap(_k('home-focus-board'));
      await t.pumpAndSettle();
      final a = find.byKey(const ValueKey('nav-card-a'));
      await _drag(t, t.getCenter(a), t.getCenter(a) + const Offset(0, 4));
      expect(s.tree.find('a')!.note.rank, 1);
      expect(_uids(s, 'todo'), ['a', 'b']);
    });
  });
}
