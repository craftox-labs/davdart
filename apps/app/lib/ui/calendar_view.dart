import 'dart:ui' show PlatformDispatcher;

import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../theme/tokens.dart';
import 'calendar_lanes.dart';
import 'card_box.dart';
import 'chips.dart';
import 'empty_state.dart';
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
typedef _CellItem = ({String title, bool event, DateTime start, bool allDay});

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
/// panel on the day. A project's Calendar keeps its own day column, and the
/// narrow layout keeps the day list under the grid on both.
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
/// Not built yet, deliberately: event status (tentative/confirmed), multi-day
/// span bars, overlap marking and the week/timeline views. The chip row of a
/// day cell is where a span bar would sit, and the day list is where a status
/// mark would go.
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
            sortKey: '${e.uid}@${_id(first)}',
          ),
        );
      }
    }
    return out;
  }

  /// Picks [day]. A project's Calendar keeps it in its own day column; Home's
  /// shares it with the Calendar panel, which the wide grid opens (there is no
  /// room for a column beside the full-width grid).
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

  /// Shows [month] and keeps the selection inside it: today when the month
  /// holds it, else its first day, so the day column (a project's) and the
  /// panel's pinned day (Home's) always target a day that is on screen. The
  /// month arrows never open the panel.
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
              // Home's wide Calendar is the grid alone: the picked day shows
              // in the Calendar panel beside it. A project's wide Calendar
              // keeps its day column, and the narrow layout keeps the day list
              // under the grid on both.
              child: wide && !widget.scoped
                  ? grid
                  : wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: grid),
                        SizedBox(width: t.space.lg),
                        Expanded(flex: 2, child: list),
                      ],
                    )
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
              return Column(
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
                    ),
                ],
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
  /// only at the span's real ends. It takes no taps itself, so a press lands
  /// on the day under it and selects it, as pressing a chip does.
  Widget _bar(Tokens t, LaneSegment s, {required Key key}) {
    final radius = Radius.circular(t.radii.small);
    return IgnorePointer(
      key: key,
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
          ),
      for (final k in bucket?.tasks ?? const <TaskOccurrence>[])
        (
          title: k.task.summary.isEmpty ? '(no title)' : k.task.summary,
          event: false,
          start: k.start,
          allDay: k.allDay,
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
    return FTappable(
      key: Key('calendar-day-$id'),
      behavior: HitTestBehavior.opaque,
      semanticsLabel: dayLabel(day, _clock()),
      onPress: () => _select(day, openPanel: wide),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: weekend ? t.weekendTint : null,
            border: Border(
              top: topRule
                  ? BorderSide(color: t.divider, width: t.borders.hairline)
                  : BorderSide.none,
              left: leftRule
                  ? BorderSide(color: t.divider, width: t.borders.hairline)
                  : BorderSide.none,
            ),
          ),
          child: Padding(
            padding: wide
                ? EdgeInsets.symmetric(horizontal: t.space.xxs)
                : EdgeInsets.all(t.space.xxs),
            child: body,
          ),
        ),
      ),
    );
  }

  /// One item in a wide day cell: a small rounded chip whose left bar carries
  /// the tone (an event's accent, a task's todo tone, with a hollow dot for a
  /// task), a timed item's start time in muted text, then the truncated
  /// title.
  Widget _chip({
    required Tokens t,
    required Key key,
    required String title,
    required bool event,
    required DateTime start,
    required bool allDay,
    required bool muted,
  }) {
    final tone = event ? t.accent : t.statusTodo;
    final small = t.type.microStyle.copyWith;
    return Padding(
      key: key,
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
                          Text(timeLabel(start), style: small(color: t.muted)),
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
          onPress: () async {
            final uid = await showNewEventDialog(
              context,
              state,
              day: day,
              personal: !widget.scoped,
            );
            if (uid != null) await state.clickEvent(uid);
          },
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
