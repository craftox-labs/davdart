import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));
Finder _card(String uid) => find.byKey(ValueKey('nav-card-$uid'));

Note _note(String uid, String status, {double? rank}) => Note(
  uid: uid,
  summary: 'Note $uid',
  description: 'status: $status\n\nbody',
  categories: ['status-$status'],
  created: DateTime.utc(2026, 1, 1, 0, 0, uid.codeUnitAt(0)),
  lastModified: DateTime.now().toUtc(),
)..rank = rank;

String _status(AppState s, String uid) =>
    PlanItem.fromNote(s.findItem(uid) as Note).status ?? '';

/// A mouse drag with pauses so the drop targets see it.
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
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(seconds: 1));
}

void _desktop() {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));

  testWidgets('desktop: dragging a card onto another column sets its status', (
    t,
  ) async {
    _desktop();
    final s = await pumpHomeApp(
      t,
      notes: [_note('a', 'todo'), _note('x', 'doing')],
    );
    expect(_status(s, 'a'), 'todo');
    await _drag(
      t,
      t.getCenter(_card('a')),
      t.getCenter(_k('board-drop-doing')),
    );
    expect(_status(s, 'a'), 'doing');
  });

  testWidgets('desktop: a drop onto a card of another column lands by half', (
    t,
  ) async {
    _desktop();
    final s = await pumpHomeApp(
      t,
      notes: [
        _note('a', 'todo'),
        _note('x', 'doing', rank: 1),
        _note('y', 'doing', rank: 2),
      ],
    );
    final r = t.getRect(_card('x'));
    await _drag(t, t.getCenter(_card('a')), Offset(r.center.dx, r.top + 3));
    expect(_status(s, 'a'), 'doing');
    final col = s.homeColumns(all: true).firstWhere((c) => c.$1 == 'doing').$2;
    expect([for (final i in col) i.uid], ['a', 'x', 'y']);
  });

  testWidgets('desktop: a drop on the card\'s own column changes nothing', (
    t,
  ) async {
    _desktop();
    final s = await pumpHomeApp(
      t,
      notes: [_note('a', 'todo'), _note('b', 'todo')],
    );
    await _drag(t, t.getCenter(_card('a')), t.getCenter(_k('board-drop-todo')));
    expect(_status(s, 'a'), 'todo');
    expect(s.findItem('a'), isNotNull);
  });

  testWidgets('desktop: a task card drags to another column', (t) async {
    _desktop();
    final s = await pumpHomeApp(
      t,
      notes: [_note('x', 'doing')],
      tasks: [mkTask('tk', summary: 'A task')],
    );
    final before = (s.findItem('tk') as Task).boardStatus;
    expect(find.byKey(const ValueKey('nav-card-tk')), findsOneWidget);
    await _drag(
      t,
      t.getCenter(_card('tk')),
      t.getCenter(_k('board-drop-doing')),
    );
    final after = (s.findItem('tk') as Task).boardStatus;
    expect(after, isNot(before));
    expect(statusColumn(canonicalStatus(after) ?? after), 'doing');
  });

  testWidgets('read-only tasks do not move when dragged', (t) async {
    _desktop();
    final s = await pumpHomeApp(
      t,
      notes: [_note('x', 'doing')],
      tasks: [mkTask('tk', summary: 'A task')],
      readOnly: true,
    );
    final before = (s.findItem('tk') as Task).boardStatus;
    await _drag(
      t,
      t.getCenter(_card('tk')),
      t.getCenter(_k('board-drop-doing')),
    );
    expect((s.findItem('tk') as Task).boardStatus, before);
  });
}
