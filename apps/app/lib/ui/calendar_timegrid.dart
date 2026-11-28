/// Geometry of the Week and Day time grid: where a timed block sits in its
/// day column.
///
/// A [TimedSpan] is one timed occurrence on one day, as wall minutes from
/// midnight. [layOutDay] clamps each to the day, floors it at a minimum
/// length and sweeps the day into clusters of overlapping blocks, so
/// concurrent items share the column's width instead of hiding each other.
/// [snapMinutes] rounds a pointer's minute to the drag-to-create grid.
///
/// Pure data and arithmetic, no widgets and no tokens: the view supplies the
/// pixels, and the rules are unit tested without pumping a widget
/// (test/calendar_timegrid_test.dart). Items that cover more than one day are
/// bars in the strip above the grid, never blocks, so a span here is always
/// inside one day.
library;

/// Minutes in a day: the bottom edge of every column.
const minutesPerDay = 24 * 60;

/// One timed item on one day.
class TimedSpan {
  const TimedSpan({
    required this.startMinute,
    required this.endMinute,
    required this.uid,
    required this.sortKey,
  });

  /// Wall minutes from the day's midnight (may lie outside 0..1440 before
  /// clamping).
  final int startMinute, endMinute;

  /// The event the block stands for, so a press on it opens that event.
  final String uid;

  /// Tie-breaker, so equal blocks keep a fixed order between rebuilds.
  final String sortKey;
}

/// One span placed in its day column.
class TimedBlock {
  const TimedBlock({
    required this.span,
    required this.startMinute,
    required this.endMinute,
    required this.column,
    required this.columns,
  });

  final TimedSpan span;

  /// The clamped, floored extent in minutes from midnight.
  final int startMinute, endMinute;

  /// 0-based slot among the [columns] concurrent blocks of its cluster: the
  /// block's left edge is `column / columns` of the day column's width, its
  /// width `1 / columns`.
  final int column, columns;

  int get minutes => endMinute - startMinute;
}

/// Rounds [minute] to the nearest multiple of [step], within the day.
int snapMinutes(num minute, {int step = 15}) {
  final snapped = (minute / step).round() * step;
  return snapped.clamp(0, minutesPerDay);
}

/// Places [spans] in one day column.
///
/// Each span is clamped to 0..1440 and floored at [minMinutes] (a block
/// starting so late that the floor would pass midnight moves up to end at
/// midnight). Blocks sort by start, then longer first, then [TimedSpan
/// .sortKey]. A cluster grows while the next start is before the cluster's
/// latest end; inside it a block takes the first column whose last block has
/// ended, and every block of the cluster reports the cluster's column count.
/// A block that only touches the previous one (start == end) is not
/// concurrent.
List<TimedBlock> layOutDay(List<TimedSpan> spans, {int minMinutes = 30}) {
  final items = <({TimedSpan span, int start, int end})>[];
  for (final s in spans) {
    var start = s.startMinute.clamp(0, minutesPerDay);
    var end = s.endMinute.clamp(0, minutesPerDay);
    if (end < start + minMinutes) end = start + minMinutes;
    if (end > minutesPerDay) {
      end = minutesPerDay;
      start = (end - minMinutes).clamp(0, minutesPerDay);
    }
    items.add((span: s, start: start, end: end));
  }
  items.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    final byLength = (b.end - b.start).compareTo(a.end - a.start);
    if (byLength != 0) return byLength;
    return a.span.sortKey.compareTo(b.span.sortKey);
  });

  final out = <TimedBlock>[];
  var i = 0;
  while (i < items.length) {
    var clusterEnd = items[i].end;
    var j = i + 1;
    while (j < items.length && items[j].start < clusterEnd) {
      if (items[j].end > clusterEnd) clusterEnd = items[j].end;
      j++;
    }
    final lastEnds = <int>[];
    final slots = <int>[];
    for (var k = i; k < j; k++) {
      var col = lastEnds.indexWhere((e) => e <= items[k].start);
      if (col < 0) {
        col = lastEnds.length;
        lastEnds.add(items[k].end);
      } else {
        lastEnds[col] = items[k].end;
      }
      slots.add(col);
    }
    for (var k = i; k < j; k++) {
      out.add(
        TimedBlock(
          span: items[k].span,
          startMinute: items[k].start,
          endMinute: items[k].end,
          column: slots[k - i],
          columns: lastEnds.length,
        ),
      );
    }
    i = j;
  }
  return out;
}
