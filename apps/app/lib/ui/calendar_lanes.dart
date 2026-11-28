/// Lane layout for the month grid's multi-day bars.
///
/// A [CalendarSpan] is one multi-day occurrence: the first and last day it
/// covers (inclusive, UTC-flagged dates) and what its bar shows. [layOutWeek]
/// turns the spans that touch one week row into [LaneSegment]s: the columns
/// each one covers in that row, whether it starts or ends there (a bar that
/// runs into the next row keeps a flat edge), and the lane it sits in, so
/// overlapping visits stack into lanes instead of hiding each other.
///
/// Pure data and arithmetic, no widgets and no tokens: the view supplies the
/// pixels through [LaneGeometry], and the rules are unit tested without
/// pumping a widget (test/calendar_lanes_test.dart).
library;

/// One multi-day item as the bar layer sees it.
class CalendarSpan {
  const CalendarSpan({
    required this.start,
    required this.end,
    required this.title,
    required this.sortKey,
  });

  /// The first day the bar covers, at midnight.
  final DateTime start;

  /// The last day it covers, at midnight (inclusive).
  final DateTime end;

  /// What the bar reads; truncated to the space it has.
  final String title;

  /// Tie-breaker, so two visits with the same days and title keep a fixed
  /// order between rebuilds (the occurrence's uid and day).
  final String sortKey;
}

/// One span's bar within one week row.
class LaneSegment {
  const LaneSegment({
    required this.span,
    required this.lane,
    required this.firstCol,
    required this.lastCol,
    required this.startsSpan,
    required this.endsSpan,
  });

  final CalendarSpan span;

  /// 0-based lane in this row; higher lanes sit lower.
  final int lane;

  /// The columns this row shows the span on (0 = the row's first day).
  final int firstCol, lastCol;

  /// True when this segment holds the span's first (last) day, so that edge is
  /// the real end of the bar: rounded, and the start carries the tone bar.
  final bool startsSpan, endsSpan;
}

/// One week row's bar layer.
class WeekLanes {
  const WeekLanes({
    required this.segments,
    required this.lanes,
    required this.hidden,
  });

  /// The bars of this row, in placement order.
  final List<LaneSegment> segments;

  /// Lanes in use, so the row's cells can leave room above their chips.
  final int lanes;

  /// Spans that found no free lane within the allowed depth.
  final int hidden;
}

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

DateTime _add(DateTime d, int days) =>
    DateTime.utc(d.year, d.month, d.day + days);

/// Whole days from [from] to [to] (both midnights).
int _gap(DateTime from, DateTime to) => _day(to).difference(_day(from)).inDays;

/// Spreads [spans] over the lanes of the week row that starts on [weekStart]
/// (seven days), at most [maxLanes] lanes deep.
///
/// Placement is stable: the earliest start takes the first lane, then the
/// longer span, then the title, then [CalendarSpan.sortKey]. Each span takes
/// the topmost lane that is free across its columns in this row, so spans
/// that do not touch share a lane and overlapping ones stack. A span with no
/// free lane is counted in [WeekLanes.hidden] and drawn nowhere.
WeekLanes layOutWeek(
  List<CalendarSpan> spans,
  DateTime weekStart, {
  required int maxLanes,
}) {
  final first = _day(weekStart);
  final last = _add(first, 6);
  final week =
      [
        for (final s in spans)
          if (!_day(s.start).isAfter(last) && !_day(s.end).isBefore(first)) s,
      ]..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        if (byStart != 0) return byStart;
        final byLength = b.end.compareTo(a.end);
        if (byLength != 0) return byLength;
        final byTitle = a.title.compareTo(b.title);
        if (byTitle != 0) return byTitle;
        return a.sortKey.compareTo(b.sortKey);
      });

  // The last column each lane has taken in this row.
  final laneEnds = <int>[];
  final segments = <LaneSegment>[];
  var hidden = 0;
  for (final s in week) {
    final from = _day(s.start).isBefore(first) ? first : _day(s.start);
    final to = _day(s.end).isAfter(last) ? last : _day(s.end);
    final firstCol = _gap(first, from);
    final lastCol = _gap(first, to);
    var lane = 0;
    while (lane < laneEnds.length && laneEnds[lane] >= firstCol) {
      lane++;
    }
    if (lane >= maxLanes) {
      hidden++;
      continue;
    }
    if (lane == laneEnds.length) {
      laneEnds.add(lastCol);
    } else {
      laneEnds[lane] = lastCol;
    }
    segments.add(
      LaneSegment(
        span: s,
        lane: lane,
        firstCol: firstCol,
        lastCol: lastCol,
        startsSpan: from == _day(s.start),
        endsSpan: to == _day(s.end),
      ),
    );
  }
  return WeekLanes(segments: segments, lanes: laneEnds.length, hidden: hidden);
}

/// The pixels of one week row's bar layer: the layer starts [laneTop] below
/// the row's top (under the date numbers), a day cell is [cellWidth] wide, a
/// bar is [barHeight] tall and lanes are [pitch] apart. A bar insets its real
/// ends by [inset], so a visit that ends where another starts leaves a gap
/// instead of reading as one bar.
class LaneGeometry {
  const LaneGeometry({
    required this.cellWidth,
    required this.laneTop,
    required this.pitch,
    required this.barHeight,
    required this.inset,
  });

  final double cellWidth, laneTop, pitch, barHeight, inset;

  /// Room the bars of [lanes] lanes take above the chips.
  double bars(int lanes) => pitch * lanes;

  /// Room a cell leaves above its chips: the bars, and the "+N more" line
  /// under them when [more] is set.
  double reserved(int lanes, {bool more = false}) =>
      pitch * (lanes + (more ? 1 : 0));

  /// The top of the "+N more" line under [lanes] lanes of bars.
  double moreTop(int lanes) => laneTop + pitch * lanes;

  /// Where [segment]'s bar sits in the row.
  ({double left, double top, double width}) rectOf(LaneSegment s) {
    final left = cellWidth * s.firstCol + (s.startsSpan ? inset : 0);
    final right = cellWidth * (s.lastCol + 1) - (s.endsSpan ? inset : 0);
    return (left: left, top: laneTop + pitch * s.lane, width: right - left);
  }
}
