import 'package:davdart_app/ui/calendar_timegrid.dart';
import 'package:flutter_test/flutter_test.dart';

TimedSpan _s(int from, int to, [String id = 'a']) =>
    TimedSpan(startMinute: from, endMinute: to, uid: id, sortKey: id);

/// `uid:start-end:column/columns` per block.
List<String> _shape(List<TimedBlock> b) => [
  for (final x in b)
    '${x.span.uid}:${x.startMinute}-${x.endMinute}:${x.column}/${x.columns}',
];

void main() {
  test('one block alone fills its column', () {
    expect(_shape(layOutDay([_s(540, 600)])), ['a:540-600:0/1']);
  });

  test('no spans, no blocks', () {
    expect(layOutDay(const []), isEmpty);
  });

  test('blocks that only touch are not concurrent', () {
    final b = layOutDay([_s(540, 600, 'a'), _s(600, 660, 'b')]);
    expect(_shape(b), ['a:540-600:0/1', 'b:600-660:0/1']);
  });

  test('overlapping blocks split the width, left to right by start', () {
    final b = layOutDay([_s(540, 660, 'a'), _s(600, 720, 'b')]);
    expect(_shape(b), ['a:540-660:0/2', 'b:600-720:1/2']);
  });

  test('a freed column is reused inside the same cluster', () {
    // a spans the cluster, b and c share the second column in turn.
    final b = layOutDay([
      _s(540, 780, 'a'),
      _s(560, 620, 'b'),
      _s(640, 700, 'c'),
    ]);
    expect(_shape(b), ['a:540-780:0/2', 'b:560-620:1/2', 'c:640-700:1/2']);
  });

  test('separate clusters count their own columns', () {
    final b = layOutDay([
      _s(540, 600, 'a'),
      _s(570, 630, 'b'),
      _s(900, 960, 'c'),
    ]);
    expect(_shape(b), ['a:540-600:0/2', 'b:570-630:1/2', 'c:900-960:0/1']);
  });

  test('equal starts put the longer block first, then sort key', () {
    final b = layOutDay([
      _s(600, 630, 'b'),
      _s(600, 720, 'c'),
      _s(600, 630, 'a'),
    ]);
    expect(_shape(b), ['c:600-720:0/3', 'a:600-630:1/3', 'b:600-630:2/3']);
  });

  test('a short block is floored at the minimum length', () {
    expect(_shape(layOutDay([_s(600, 605)])), ['a:600-630:0/1']);
    expect(_shape(layOutDay([_s(600, 600)], minMinutes: 15)), [
      'a:600-615:0/1',
    ]);
  });

  test('blocks are clamped to the day', () {
    expect(_shape(layOutDay([_s(-60, 120)])), ['a:0-120:0/1']);
    expect(_shape(layOutDay([_s(1380, 1600)])), ['a:1380-1440:0/1']);
  });

  test('a late short block moves up to end at midnight', () {
    expect(_shape(layOutDay([_s(1430, 1440)])), ['a:1410-1440:0/1']);
  });

  test('snapMinutes rounds to the step and stays in the day', () {
    expect(snapMinutes(0), 0);
    expect(snapMinutes(7), 0);
    expect(snapMinutes(8), 15);
    expect(snapMinutes(62.4), 60);
    expect(snapMinutes(-20), 0);
    expect(snapMinutes(1500), 1440);
    expect(snapMinutes(50, step: 30), 60);
  });
}
