import 'package:davdart_app/ui/calendar_lanes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Week rows start on Monday: 16..22 November 2026.
DateTime _d(int day, [int month = 11]) => DateTime.utc(2026, month, day);

CalendarSpan _span(int from, int to, String title, [int month = 11]) =>
    CalendarSpan(
      start: _d(from, month),
      end: _d(to, month),
      title: title,
      sortKey: title,
    );

/// `lane:first-last:start/end` per segment, for readable expectations.
List<String> _shape(WeekLanes w) => [
  for (final s in w.segments)
    '${s.lane}:${s.firstCol}-${s.lastCol}'
        '${s.startsSpan ? ':start' : ''}${s.endsSpan ? ':end' : ''}',
];

void main() {
  test('a span inside one week is one segment, open at neither end', () {
    final w = layOutWeek([_span(18, 20, 'Visit')], _d(16), maxLanes: 3);
    expect(_shape(w), ['0:2-4:start:end']);
    expect(w.lanes, 1);
    expect(w.hidden, 0);
  });

  test('a span crossing a row keeps a flat edge in the next row', () {
    // Friday 20 to Tuesday 24: two rows, split between the 22nd and the 23rd.
    final spans = [_span(20, 24, 'Visit')];
    final first = layOutWeek(spans, _d(16), maxLanes: 3);
    final second = layOutWeek(spans, _d(23), maxLanes: 3);
    expect(_shape(first), ['0:4-6:start']);
    expect(_shape(second), ['0:0-1:end']);
  });

  test('the span clipped to the row still knows its real ends', () {
    // Starts before the row shown: flat on the left, open on the right too.
    final w = layOutWeek([_span(10, 25, 'Long')], _d(16), maxLanes: 3);
    expect(_shape(w), ['0:0-6']);
  });

  test('overlapping visits stack; gaps reuse the same lane', () {
    final w = layOutWeek(
      [_span(16, 18, 'A'), _span(18, 20, 'B'), _span(21, 22, 'C')],
      _d(16),
      maxLanes: 3,
    );
    expect(_shape(w), [
      '0:0-2:start:end',
      '1:2-4:start:end',
      '0:5-6:start:end',
    ]);
    expect(w.lanes, 2);
  });

  test('order: earliest first, then the longer, then the title', () {
    final w = layOutWeek(
      [
        _span(16, 17, 'Short'),
        _span(16, 19, 'Long'),
        _span(16, 17, 'Also short'),
      ],
      _d(16),
      maxLanes: 3,
    );
    expect(
      [for (final s in w.segments) s.span.title],
      ['Long', 'Also short', 'Short'],
    );
    expect([for (final s in w.segments) s.lane], [0, 1, 2]);
  });

  test('lanes are capped and the rest are counted as hidden', () {
    final w = layOutWeek(
      [_span(16, 20, 'A'), _span(17, 21, 'B'), _span(18, 22, 'C')],
      _d(16),
      maxLanes: 2,
    );
    expect(w.segments.length, 2);
    expect(w.lanes, 2);
    expect(w.hidden, 1);
  });

  test('spans outside the row are dropped', () {
    final w = layOutWeek([_span(23, 24, 'Next week')], _d(16), maxLanes: 3);
    expect(w.segments, isEmpty);
    expect(w.lanes, 0);
  });

  test('geometry: only the real ends are inset; lanes and rows map to px', () {
    const g = LaneGeometry(
      cellWidth: 100,
      laneTop: 24,
      pitch: 18,
      barHeight: 16,
      inset: 2,
    );
    final span = _span(18, 20, 'Visit');
    final week = layOutWeek([span], _d(16), maxLanes: 3);
    final r = g.rectOf(week.segments.single);
    expect(r.left, 202); // column 2, inset
    expect(r.width, 296); // three columns less both insets
    expect(r.top, 24);
    // A continuation is flush with the cell edges and sits on its lane.
    final next = layOutWeek([_span(20, 24, 'Visit')], _d(23), maxLanes: 3);
    final c = g.rectOf(next.segments.single);
    expect(c.left, 0);
    expect(c.width, 198);
    expect(g.reserved(2), 36);
    expect(g.reserved(2, more: true), 54);
    expect(g.moreTop(2), 60);
  });
}
