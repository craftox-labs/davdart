import 'dart:ui' show PlatformDispatcher;

import 'package:davdart/davdart.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton, kTouchSlop;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../theme/tokens.dart';
import 'calendar_lanes.dart';
import 'card_box.dart';
import 'chips.dart';
import 'empty_state.dart';
import 'property/option_picker.dart';
import 'property/property_trigger.dart';
import 'event_menu.dart';
import 'events_panel.dart';
import 'parts.dart';
import 'section_label.dart';
import 'task_menu.dart';
import 'task_parts.dart';
import 'theme.dart';

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

// Regions whose week starts on Sunday (CLDR firstDay); everywhere else
// Monday.
const _sundayFirst = {
  'US',
  'CA',
  'MX',
  'BR',
  'JP',
  'IL',
  'IN',
  'PH',
  'TH',
  'TW',
  'KR',
  'ZA',
  'AR',
  'CO',
  'PE',
  'VE',
  'GT',
  'HN',
  'NI',
  'PA',
  'PR',
  'SV',
  'DO',
  'HK',
  'ID',
  'SA',
};

/// The first weekday of the week (1 = Monday .. 7 = Sunday) from the locale's
/// region (the app's Localizations, else the device's); Monday when unknown.
int firstWeekday(BuildContext context) {
  final locale =
      Localizations.maybeLocaleOf(context) ??
      PlatformDispatcher.instance.locale;
  return _sundayFirst.contains(locale.countryCode)
      ? DateTime.sunday
      : DateTime.monday;
}

/// One item of a wide day cell's chip list: what to show, its kind and when
/// it starts, so all-day items lead and the rest follow in start order.
typedef _CellItem = ({
  String title,
  bool event,
  DateTime start,
  bool allDay,
  String uid,
});

/// `y-m-d`, the id a day's widget keys end with.
String _id(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// The first day [o] covers, and the last one it covers, as UTC midnights:
/// an all-day event's end is exclusive, so its last day is the end minus a
/// second (as bucketByDay counts it).
DateTime _firstDay(EventOccurrence o) =>
    DateTime.utc(o.start.year, o.start.month, o.start.day);

DateTime _lastDay(EventOccurrence o) {
  final end = o.end.isAfter(o.start)
      ? o.end.subtract(const Duration(seconds: 1))
      : o.start;
  return DateTime.utc(end.year, end.month, end.day);
}

/// True when [o] covers more than one day, so it is drawn as a bar across the
/// cells rather than as a chip on each of them.
bool _multiDay(EventOccurrence o) => _lastDay(o).isAfter(_firstDay(o));

/// Chip order in a day cell: all-day items first, then by start time, an
/// event before a task that starts at the same moment.
int _byWhen(_CellItem a, _CellItem b) {
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;
  if (a.event != b.event) return a.event ? -1 : 1;
  return 0;
}

/// The one calendar: a month grid and the selected day's items, with a way to
/// add an event or a task on that day.
///
/// Wide, Home shows the grid alone and the picked day in the Calendar panel
/// beside it ([AppState.homeDay]): pressing a day or a bar there opens that
/// panel on the day. A project's Calendar keeps its own picked day in a card
/// under the grid, at every width (it has no panel day of its own), so its
/// grid gets the same full width Home's does.
///
/// [scoped] picks the source. A project's page passes true: the open
/// [AppState.scopeUid] narrows the items (the project index, as everywhere
/// else). Home passes false: the individual's loose items only, filtered by
/// [AppState.isMine] and [AppState.inProjectsLayer] exactly as the Personal
/// Tasks and Calendar lists are, so a project's items never appear on Home and
/// items assigned to the user inside a project will join through that seam
/// without a redesign. A Space without events or tasks
/// ([AppState.supportsEvents], [AppState.supportsTasks]) hides that kind.
///
/// Days come from the core model (bucketByDay over the viewer zone); the
/// selected day and the visible month are this view's own state, so Home and
/// each project tab keep theirs, and both start on today.
///
/// Not built yet, deliberately: event status (tentative/confirmed), overlap
/// marking and the week/timeline views. The day list is where a status mark
/// would go.
class CalendarView extends StatefulWidget {
  const CalendarView({
    super.key,
    required this.state,
    this.scoped = false,
    this.now,
  });

  final AppState state;

  /// A project page's Calendar (true) or Home's (false, loose items only).
  final bool scoped;

  /// Clock override for tests.
  final DateTime? now;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  AppState get state => widget.state;

  /// The picked day (a plain UTC-flagged date); null shows today. A project's
  /// Calendar keeps its own here; Home's is [AppState.homeDay], shared with
  /// the Calendar panel that shows the day beside the grid.
  DateTime? _selected;

  /// The first of the shown month; null follows the selection.
  DateTime? _month;

  /// A drag across the wide grid: the day it started on, where it started and
  /// the day it has reached (null until the pointer has moved far enough to
  /// mean a range rather than a press).
  DateTime? _dragFrom, _dragTo;
  Offset? _dragAt;

  /// Home's last seen picked day, to drop the shown month when a Space switch
  /// clears the pick.
  DateTime? _lastHome;

  DateTime _clock() => widget.now ?? DateTime.now();

  static DateTime _monthOf(DateTime d) => DateTime.utc(d.year, d.month);

  /// The events of the view's source (see [CalendarView.scoped]).
  List<Event> _events() {
    if (!state.supportsEvents) return const [];
    if (widget.scoped) return state.scopedEvents;
    return [
      for (final e in state.events)
        if (!state.inProjectsLayer(e.uid) && state.isMine(e)) e,
    ];
  }

  /// The tasks of the view's source (closed ones are dropped by the bucket).
  List<Task> _tasks() {
    if (!state.supportsTasks) return const [];
    if (widget.scoped) return state.scopedTasks;
    return [
      for (final t in state.tasks)
        if (!state.inProjectsLayer(t.uid) && state.isMine(t)) t,
    ];
  }

  /// The multi-day items of the grid window `[from, to)`: every event
  /// occurrence that covers more than one day, clipped to the window and with
  /// the first and last day it covers, for the bar layer.
  List<CalendarSpan> _spans(DateTime from, DateTime to) {
    final last = to.subtract(const Duration(days: 1));
    final out = <CalendarSpan>[];
    for (final e in _events()) {
      for (final o in occurrencesBetween(e, from, to)) {
        if (o.isCancelled) continue;
        final first = _firstDay(o);
        final end = _lastDay(o);
        if (!end.isAfter(first)) continue;
        out.add(
          CalendarSpan(
            start: first.isBefore(from) ? from : first,
            end: end.isAfter(last) ? last : end,
            title: o.summary.isEmpty ? '(no title)' : o.summary,
            uid: e.uid,
            sortKey: '${e.uid}@${_id(first)}',
          ),
        );
      }
    }
    return out;
  }

  /// Picks [day]. A project's Calendar keeps it to itself (the card under its
  /// grid); Home's shares it with the Calendar panel, which a wide press
  /// opens.
  void _select(DateTime day, {bool openPanel = false}) {
    if (widget.scoped) {
      setState(() {
        _selected = day;
        _month = _monthOf(day);
      });
      return;
    }
    if (openPanel) {
      state.selectHomeDay(day);
    } else {
      state.setHomeDay(day);
    }
    setState(() => _month = _monthOf(day));
  }

  /// A press on a multi-day bar: picks [day] (the one under the pointer) and
  /// opens [uid], as pressing a chip's day and its row does.
  void _openBar(DateTime day, String uid) => _openItem(day, uid, event: true);

  /// A press on an item's chip: picks its day and opens that item (an event or
  /// a task), not just the day.
  void _openItem(DateTime day, String uid, {required bool event}) {
    _select(day, openPanel: true);
    if (event) {
      state.clickEvent(uid);
    } else {
      state.clickTask(uid);
    }
  }

  /// Opens the new-task dialog with [day] as the due date, as the day card's
  /// own add-task button does.
  Future<void> _newTask(DateTime day) => showNewTaskDialog(
    context,
    state,
    due: dueOfDay(day),
    personal: !widget.scoped,
  );

  /// Opens the new-event dialog on [day] (an all-day event to [until], when a
  /// drag across the grid picked a range) and opens what it adds.
  Future<void> _newEvent(DateTime day, {DateTime? until}) async {
    final uid = await showNewEventDialog(
      context,
      state,
      day: day,
      until: until,
      personal: !widget.scoped,
    );
    if (uid != null) await state.clickEvent(uid);
  }

  /// The day cell the pointer is over (wide layout): that cell's add button
  /// shows while the pointer is on it.
  DateTime? _hoverDay;

  /// The day whose add popover is open: its button stays put (and stays
  /// mounted) while the pointer is on the popover instead of the cell.
  String? _addOpenDay;

  /// The day under [at], in the grid starting on [start]: a column per
  /// weekday, a row per week.
  DateTime _dayAt(
    Offset at,
    DateTime start,
    int weeks,
    double cellWidth,
    double rowHeight,
  ) {
    final col = cellWidth <= 0 ? 0 : (at.dx / cellWidth).floor().clamp(0, 6);
    final row = rowHeight <= 0
        ? 0
        : (at.dy / rowHeight).floor().clamp(0, weeks - 1);
    return start.add(Duration(days: row * 7 + col));
  }

  /// The range a drag is showing, oldest first, or null when no drag is on.
  (DateTime, DateTime)? get _range {
    final from = _dragFrom, to = _dragTo;
    if (from == null || to == null) return null;
    return to.isBefore(from) ? (to, from) : (from, to);
  }

  /// Extends the range a drag is drawing: it starts once the pointer has moved
  /// horizontally past the slop (a vertical drag is a scroll), and stays on
  /// the row it started in.
  void _dragMove(Offset at, int Function(Offset) colOf) {
    final from = _dragFrom, origin = _dragAt;
    if (from == null || origin == null) return;
    final d = at - origin;
    final on = _dragTo != null;
    if (!on && (d.dx.abs() < kTouchSlop || d.dx.abs() <= d.dy.abs())) return;
    final steps = colOf(at) - colOf(origin);
    final to = steps == 0 ? null : from.add(Duration(days: steps));
    if (to == _dragTo) return;
    setState(() => _dragTo = to);
  }

  /// Ends a drag: a range opens the new-event dialog on it, an all-day event
  /// from its first day to its last. A press (no range) does nothing here;
  /// the day cell's own tap has already picked the day.
  Future<void> _dragUp({bool cancel = false}) async {
    final range = cancel ? null : _range;
    _dragAt = null;
    _dragFrom = null;
    if (_dragTo != null) setState(() => _dragTo = null);
    if (range == null || !mounted) return;
    final (from, to) = range;
    _select(from);
    await _newEvent(from, until: to);
  }

  /// Shows [month] and keeps the selection inside it: today when the month
  /// holds it, else its first day, so the picked day (a project's card, or
  /// the panel's pinned day on Home) always targets a day that is on screen.
  /// The month arrows never open the panel.
  void _showMonth(DateTime month, DateTime today) {
    final day = month.year == today.year && month.month == today.month
        ? today
        : DateTime.utc(month.year, month.month);
    if (widget.scoped) {
      setState(() {
        _month = month;
        _selected = day;
      });
      return;
    }
    setState(() => _month = month);
    state.setHomeDay(day);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final clock = _clock();
        final today = wallDay(wallNow(clock));
        if (!widget.scoped) {
          if (state.homeDay == null && _lastHome != null) _month = null;
          _lastHome = state.homeDay;
        }
        final selected = (widget.scoped ? _selected : state.homeDay) ?? today;
        final month = _month ?? _monthOf(selected);
        final first = firstWeekday(context);
        final lead = (month.weekday - first + 7) % 7;
        final start = DateTime.utc(month.year, month.month, 1 - lead);
        final days = DateTime.utc(month.year, month.month + 1, 0).day;
        final weeks = ((lead + days) / 7).ceil();
        final end = start.add(Duration(days: weeks * 7));
        final buckets = bucketByDay(
          events: _events(),
          tasks: _tasks(),
          from: start,
          to: end,
        );
        final bucket = buckets[selected];
        return LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= Tokens.stackBreakpoint;
            final grid = _grid(
              context,
              t: t,
              month: month,
              start: start,
              weeks: weeks,
              first: first,
              today: today,
              selected: selected,
              buckets: buckets,
              wide: wide,
            );
            final list = _day(
              context,
              t: t,
              clock: clock,
              day: selected,
              bucket: bucket,
            );
            return SingleChildScrollView(
              key: const Key('calendar-view'),
              padding: EdgeInsets.fromLTRB(
                t.space.xl,
                t.space.md,
                t.space.xl,
                fabInset(context) + t.space.xl,
              ),
              // Home and a project's Calendar share the shape: the grid at
              // the width it has, the picked day under it. On Home wide the
              // day is the Calendar panel's (the grid stands alone); a
              // project's Calendar has no panel day of its own, so its card
              // stays under the grid at every width rather than beside it as
              // a second column.
              child: wide && !widget.scoped
                  ? grid
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        grid,
                        SizedBox(height: t.space.lg),
                        list,
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  /// The month grid: a header row (month title, arrows, Today), the weekday
  /// labels, then the days in a hairline-ruled grid with a faint weekend
  /// wash. Wide cells carry up to three item chips (and '+N more') under the
  /// multi-day bars of their row; narrow ones only a dot per kind, as the old
  /// Home calendar did.
  Widget _grid(
    BuildContext context, {
    required Tokens t,
    required DateTime month,
    required DateTime start,
    required int weeks,
    required int first,
    required DateTime today,
    required DateTime selected,
    required Map<DateTime, DayBucket> buckets,
    required bool wide,
  }) {
    final cellHeight = wide ? t.sizes.calendarCellChips : t.sizes.touchTarget;
    final weekday = t.type.sectionLabelStyle.copyWith(color: t.muted);
    final end = start.add(Duration(days: weeks * 7));
    final spans = wide ? _spans(start, end) : const <CalendarSpan>[];
    return CardBox(
      padding: EdgeInsets.all(t.space.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaneHeaderRow(
            startPad: t.space.xs,
            endPad: t.space.xs,
            children: [
              Expanded(
                child: Text(
                  '${_monthNames[month.month - 1]} ${month.year}',
                  key: const Key('calendar-month'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.type.titleStyle.copyWith(color: t.fg),
                ),
              ),
              IconAction(
                compact: true,
                key: const Key('calendar-prev'),
                tooltip: 'Previous month',
                icon: FLucideIcons.chevronLeft,
                onPress: () => _showMonth(
                  DateTime.utc(month.year, month.month - 1),
                  today,
                ),
              ),
              IconAction(
                compact: true,
                key: const Key('calendar-next'),
                tooltip: 'Next month',
                icon: FLucideIcons.chevronRight,
                onPress: () => _showMonth(
                  DateTime.utc(month.year, month.month + 1),
                  today,
                ),
              ),
              SizedBox(width: t.space.xs),
              touchBox(
                context,
                FButton(
                  key: const Key('calendar-today'),
                  variant: FButtonVariant.secondary,
                  size: FButtonSizeVariant.xs,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => _select(today, openPanel: wide),
                  child: const Text('Today'),
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.xs),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      _weekdayNames[(first - 1 + i) % 7].substring(0, 2),
                      style: weekday,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: t.space.xs),
          Container(height: t.borders.hairline, color: t.divider),
          LayoutBuilder(
            builder: (context, c) {
              // The bar layer's pixels: one column per weekday, so a bar can
              // cover consecutive cells.
              final g = LaneGeometry(
                cellWidth: c.maxWidth / 7,
                laneTop: t.sizes.calendarNumberRow,
                pitch: t.sizes.calendarLanePitch,
                barHeight: t.sizes.calendarChip,
                inset: t.space.xxs,
              );
              final rows = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var w = 0; w < weeks; w++)
                    _week(
                      context,
                      t: t,
                      g: g,
                      weekStart: start.add(Duration(days: w * 7)),
                      month: month,
                      today: today,
                      selected: selected,
                      buckets: buckets,
                      spans: spans,
                      height: cellHeight,
                      wide: wide,
                      topRule: w > 0,
                      range: _range,
                    ),
                ],
              );
              // A drag across the wide grid picks a range of days for a new
              // all-day event. A press is untouched (a tap never moves far
              // enough), a vertical drag stays a scroll, and the phone has no
              // gesture: a touch drag there would fight the scroll.
              if (!wide || !state.eventsEditable) return rows;
              DateTime dayAt(Offset p) =>
                  _dayAt(p, start, weeks, g.cellWidth, cellHeight);
              int colAt(Offset p) => g.cellWidth <= 0
                  ? 0
                  : (p.dx / g.cellWidth).floor().clamp(0, 6);
              return Listener(
                onPointerDown: (e) {
                  // Only the primary button, a finger or a pen starts a range:
                  // a right or middle press scrolls or opens a menu instead.
                  if (e.buttons & kPrimaryButton == 0) return;
                  _dragAt = e.localPosition;
                  _dragFrom = dayAt(e.localPosition);
                  _dragTo = null;
                },
                onPointerMove: (e) => _dragMove(e.localPosition, colAt),
                onPointerUp: (_) => _dragUp(),
                onPointerCancel: (_) => _dragUp(cancel: true),
                child: rows,
              );
            },
          ),
        ],
      ),
    );
  }

  /// One week row: the seven day cells and, on wide, the multi-day bars laid
  /// over them on their lanes. Every cell of the row leaves the bars' room
  /// above its chips, so nothing overlaps.
  Widget _week(
    BuildContext context, {
    required Tokens t,
    required LaneGeometry g,
    required DateTime weekStart,
    required DateTime month,
    required DateTime today,
    required DateTime selected,
    required Map<DateTime, DayBucket> buckets,
    required List<CalendarSpan> spans,
    required double height,
    required bool wide,
    required bool topRule,
    required (DateTime, DateTime)? range,
  }) {
    final row = wide
        ? layOutWeek(spans, weekStart, maxLanes: t.sizes.calendarLanes)
        : const WeekLanes(segments: [], lanes: 0, hidden: 0);
    final inset = row.lanes == 0
        ? 0.0
        : g.reserved(row.lanes, more: row.hidden > 0);
    final cells = Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _cell(
              context,
              t: t,
              day: weekStart.add(Duration(days: i)),
              month: month,
              today: today,
              selected: selected,
              bucket: buckets[weekStart.add(Duration(days: i))],
              height: height,
              wide: wide,
              lanesInset: inset,
              topRule: topRule,
              leftRule: i > 0,
              inRange:
                  range != null &&
                  !weekStart.add(Duration(days: i)).isBefore(range.$1) &&
                  !weekStart.add(Duration(days: i)).isAfter(range.$2),
            ),
          ),
      ],
    );
    if (row.segments.isEmpty && row.hidden == 0) return cells;
    final weekId = _id(weekStart);
    return Stack(
      children: [
        cells,
        for (final s in row.segments)
          Positioned(
            left: g.rectOf(s).left,
            top: g.rectOf(s).top,
            width: g.rectOf(s).width,
            height: g.barHeight,
            child: _bar(
              t,
              s,
              key: Key('calendar-bar-${s.span.sortKey}-$weekId'),
              g: g,
              weekStart: weekStart,
            ),
          ),
        if (row.hidden > 0)
          Positioned(
            left: g.inset,
            top: g.moreTop(row.lanes),
            child: Text(
              '+${row.hidden} more',
              key: Key('calendar-lanes-more-$weekId'),
              maxLines: 1,
              style: t.type.microStyle.copyWith(color: t.muted),
            ),
          ),
      ],
    );
  }

  /// One row segment of a multi-day bar: the event tone's tint, the tone bar
  /// at the span's real start and the title at the segment's start, rounded
  /// only at the span's real ends.
  ///
  /// A press opens the event and picks the day under the pointer: the bar
  /// covers several cells, so its own column decides which day that is (the
  /// listener reads the press before the tap fires). A drag that starts on a
  /// bar still drags a range across the grid: it never reaches the tap.
  Widget _bar(
    Tokens t,
    LaneSegment s, {
    required Key key,
    required LaneGeometry g,
    required DateTime weekStart,
  }) {
    var day = weekStart.add(Duration(days: s.firstCol));
    final radius = Radius.circular(t.radii.small);
    return FTappable(
      key: key,
      behavior: HitTestBehavior.opaque,
      semanticsLabel: s.span.title,
      onPress: () => _openBar(day, s.span.uid),
      child: Listener(
        onPointerDown: (e) {
          final x = g.rectOf(s).left + e.localPosition.dx;
          final col = (x / g.cellWidth).floor().clamp(s.firstCol, s.lastCol);
          day = weekStart.add(Duration(days: col));
        },
        child: ClipRRect(
          borderRadius: BorderRadius.horizontal(
            left: s.startsSpan ? radius : Radius.zero,
            right: s.endsSpan ? radius : Radius.zero,
          ),
          child: ColoredBox(
            color: t.eventTint,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.startsSpan)
                  SizedBox(
                    width: t.sizes.calendarChipBar,
                    child: ColoredBox(color: t.accent),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: t.space.xxs),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        s.span.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.type.microStyle.copyWith(color: t.fg),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One day of the grid: the date number in its circle at the top-left of the
  /// cell, the room its week's multi-day bars take and the day's single-day
  /// chips (wide) or a dot per kind (narrow), inside hairline cell rules with
  /// a faint weekend wash.
  ///
  /// The selection is the filled accent circle around the number; today
  /// without the selection is the accent ring around it, so the cell itself
  /// never takes a fill or a heavy border.
  Widget _cell(
    BuildContext context, {
    required Tokens t,
    required DateTime day,
    required DateTime month,
    required DateTime today,
    required DateTime selected,
    required DayBucket? bucket,
    required double height,
    required bool wide,
    required double lanesInset,
    required bool topRule,
    required bool leftRule,
    required bool inRange,
  }) {
    final id = _id(day);
    final inMonth = day.month == month.month;
    final isSelected = day == selected;
    final isToday = day == today;
    final weekend = day.weekday >= DateTime.saturday;
    final number = Container(
      key: Key('calendar-number-$id'),
      width: t.sizes.calendarNumber,
      height: t.sizes.calendarNumber,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? t.accent : null,
        border: isToday && !isSelected
            ? Border.all(color: t.accent, width: t.sizes.ring)
            : null,
      ),
      child: Text(
        '${day.day}',
        style: t.type.captionStrong.copyWith(
          color: isSelected
              ? t.onAccent
              : inMonth
              ? t.fg
              : t.muted,
        ),
      ),
    );
    final items = <_CellItem>[
      // A multi-day event is a bar across its days, not a chip on each.
      for (final o in bucket?.events ?? const <EventOccurrence>[])
        if (!_multiDay(o))
          (
            title: o.summary.isEmpty ? '(no title)' : o.summary,
            event: true,
            start: o.start,
            allDay: o.allDay,
            uid: o.event.uid,
          ),
      for (final k in bucket?.tasks ?? const <TaskOccurrence>[])
        (
          title: k.task.summary.isEmpty ? '(no title)' : k.task.summary,
          event: false,
          start: k.start,
          allDay: k.allDay,
          uid: k.task.uid,
        ),
    ]..sort(_byWhen);
    Widget body;
    if (wide) {
      const cap = 3;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: t.sizes.calendarNumberRow,
            child: Align(alignment: Alignment.centerLeft, child: number),
          ),
          SizedBox(height: lanesInset),
          Expanded(
            // A lane-heavy week leaves little room: the chips scroll out of
            // sight rather than overflowing the cell.
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, item) in items.take(cap).indexed)
                    _chip(
                      t: t,
                      key: Key('calendar-chip-$id-$i'),
                      title: item.title,
                      event: item.event,
                      start: item.start,
                      allDay: item.allDay,
                      muted: !inMonth,
                      day: day,
                      uid: item.uid,
                    ),
                  if (items.length > cap)
                    Padding(
                      padding: EdgeInsets.only(top: t.space.xxs),
                      child: Text(
                        '+${items.length - cap} more',
                        key: Key('calendar-more-$id'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.type.microStyle.copyWith(color: t.muted),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          number,
          SizedBox(
            height: t.sizes.calendarDot,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (bucket != null && bucket.events.isNotEmpty)
                  StatusDot(
                    null,
                    key: Key('calendar-dot-event-$id'),
                    color: t.accent,
                    size: t.sizes.calendarDot,
                  ),
                if (bucket != null &&
                    bucket.events.isNotEmpty &&
                    bucket.tasks.isNotEmpty)
                  SizedBox(width: t.space.xxs),
                if (bucket != null && bucket.tasks.isNotEmpty)
                  StatusDot(
                    null,
                    key: Key('calendar-dot-task-$id'),
                    color: t.statusTodo,
                    size: t.sizes.calendarDot,
                  ),
              ],
            ),
          ),
        ],
      );
    }
    Widget content = Padding(
      padding: wide
          ? EdgeInsets.symmetric(horizontal: t.space.xxs)
          : EdgeInsets.all(t.space.xxs),
      child: body,
    );
    // Wide: a small add button at the cell's top-right, on hover and always
    // for today and the picked day. It opens a new event or task on that day
    // and takes its own press, so it neither picks the day nor opens the
    // panel. Nothing is shown where the Space takes neither.
    final canEvent = state.eventsEditable;
    final canTask = state.tasksEditable;
    if (wide && (canEvent || canTask)) {
      final showAdd =
          _hoverDay == day || isToday || isSelected || _addOpenDay == id;
      content = MouseRegion(
        onEnter: (_) {
          if (_hoverDay != day) setState(() => _hoverDay = day);
        },
        onExit: (_) {
          if (_hoverDay == day) setState(() => _hoverDay = null);
        },
        child: Stack(
          children: [
            Positioned.fill(child: content),
            // Always mounted, only painted while it shows: the popover of a
            // button that unmounted would close with it. While it is not
            // painted it takes no focus and no screen reader: it is not there.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !showAdd,
                child: ExcludeFocus(
                  excluding: !showAdd,
                  child: ExcludeSemantics(
                    excluding: !showAdd,
                    child: Opacity(
                      opacity: showAdd ? 1 : 0,
                      child: LayoutBuilder(
                        builder: (context, box) => Align(
                          alignment: Alignment.topRight,
                          child: _addButton(
                            day,
                            id,
                            canEvent: canEvent,
                            canTask: canTask,
                            // The popover fits the cell it belongs to.
                            popoverWidth: box.maxWidth,
                            onOpenChanged: (open) {
                              if (open) {
                                setState(() => _addOpenDay = id);
                              } else if (_addOpenDay == id) {
                                setState(() => _addOpenDay = null);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return FTappable(
      key: Key('calendar-day-$id'),
      behavior: HitTestBehavior.opaque,
      semanticsLabel: dayLabel(day, _clock()),
      onPress: () => _select(day, openPanel: wide),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: inRange
                ? t.eventTint
                : weekend
                ? t.weekendTint
                : null,
            border: Border(
              top: topRule
                  ? BorderSide(color: t.divider, width: t.borders.hairline)
                  : BorderSide.none,
              left: leftRule
                  ? BorderSide(color: t.divider, width: t.borders.hairline)
                  : BorderSide.none,
            ),
          ),
          child: content,
        ),
      ),
    );
  }

  /// One item in a wide day cell: a small rounded chip whose left bar carries
  /// the tone (an event's accent, a task's todo tone, with a hollow dot for a
  /// task), a timed item's start time in muted text, then the truncated
  /// title. A press opens that item and picks its day, so the chip takes its
  /// own taps instead of the cell's (a press on the cell's empty space still
  /// picks the day, and a drag across the grid still makes a range).
  Widget _chip({
    required Tokens t,
    required Key key,
    required String title,
    required bool event,
    required DateTime start,
    required bool allDay,
    required bool muted,
    required DateTime day,
    required String uid,
  }) {
    final tone = event ? t.accent : t.statusTodo;
    final small = t.type.microStyle.copyWith;
    return FTappable(
      key: key,
      behavior: HitTestBehavior.opaque,
      semanticsLabel: title,
      onPress: () => _openItem(day, uid, event: event),
      child: Padding(
        padding: EdgeInsets.only(top: t.space.xxs),
        child: SizedBox(
          height: t.sizes.calendarChip,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(t.radii.small),
            child: ColoredBox(
              color: event ? t.eventTint : t.taskTint,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: t.sizes.calendarChipBar,
                    child: ColoredBox(color: tone),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: t.space.xxs),
                      child: Row(
                        children: [
                          if (!event) ...[
                            StatusDot(
                              null,
                              color: tone,
                              size: t.sizes.calendarDot,
                              hollow: true,
                            ),
                            SizedBox(width: t.space.xxs),
                          ],
                          if (!allDay) ...[
                            Text(
                              timeLabel(start),
                              style: small(color: t.muted),
                            ),
                            SizedBox(width: t.space.xxs),
                          ],
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: small(color: muted ? t.muted : t.fg),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The day cell's add button: an event and/or a task on that day. With both
  /// kinds it opens a small tracked popover of the two; with one it goes
  /// straight there.
  Widget _addButton(
    DateTime day,
    String id, {
    required bool canEvent,
    required bool canTask,
    required double popoverWidth,
    required ValueChanged<bool> onOpenChanged,
  }) {
    Widget button(VoidCallback onPress, IconData icon, String tip) =>
        IconAction(
          compact: true,
          key: Key('calendar-add-$id'),
          tooltip: tip,
          icon: icon,
          onPress: onPress,
        );
    if (!(canEvent && canTask)) {
      return canEvent
          ? button(() => _newEvent(day), FLucideIcons.plus, 'New event')
          : button(() => _newTask(day), FLucideIcons.plus, 'New task');
    }
    return PropertyTrigger(
      sheetKey: Key('calendar-add-sheet-$id'),
      onOpenChanged: onOpenChanged,
      popoverWidth: popoverWidth,
      picker: (context, control) => OptionPicker<String>(
        id: 'calendar-add',
        onPick: (v) {
          control.hide();
          if (v == 'event') {
            unawaited(_newEvent(day));
          } else if (v == 'task') {
            unawaited(_newTask(day));
          }
        },
        options: const [
          PickerOption('event', 'New event', icon: FLucideIcons.calendarPlus),
          PickerOption('task', 'New task', icon: FLucideIcons.listPlus),
        ],
      ),
      // The trigger's own tap target takes the press; the button is what it
      // looks like (a disabled button would swallow the press instead).
      child: IgnorePointer(
        child: button(() {}, FLucideIcons.plus, 'New event or task'),
      ),
    );
  }

  /// The selected day: its items and the add buttons for that date.
  Widget _day(
    BuildContext context, {
    required Tokens t,
    required DateTime clock,
    required DateTime day,
    required DayBucket? bucket,
  }) {
    final adds = <Widget>[
      if (state.eventsEditable)
        IconAction(
          compact: true,
          key: const Key('calendar-add-event'),
          tooltip: 'New event',
          icon: FLucideIcons.calendarPlus,
          onPress: () => _newEvent(day),
        ),
      if (state.tasksEditable)
        IconAction(
          compact: true,
          key: const Key('calendar-add-task'),
          tooltip: 'New task',
          icon: FLucideIcons.listPlus,
          onPress: () => showNewTaskDialog(
            context,
            state,
            due: dueOfDay(day),
            personal: !widget.scoped,
          ),
        ),
    ];
    final empty = bucket == null || bucket.isEmpty;
    return CardBox(
      key: const Key('calendar-day-card'),
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            dayLabel(day, clock),
            upper: false,
            action: adds.isEmpty
                ? null
                : Row(mainAxisSize: MainAxisSize.min, children: adds),
          ),
          SizedBox(height: t.space.xs),
          if (empty)
            EmptyState('Nothing on this day', key: const Key('calendar-empty'))
          else ...[
            for (final o in bucket.events)
              EventRow(
                key: Key('calendar-event-${o.event.uid}'),
                state: state,
                occurrence: o,
              ),
            for (final k in bucket.tasks)
              TaskDueRow(
                key: Key('calendar-task-${k.task.uid}'),
                state: state,
                task: k.task,
              ),
          ],
        ],
      ),
    );
  }
}
