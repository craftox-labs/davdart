import 'dart:ui' show PlatformDispatcher;

import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../theme/tokens.dart';
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

/// The one calendar: a month grid and the selected day's items, with a way to
/// add an event or a task on that day.
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

  /// The picked day (a plain UTC-flagged date); null shows today.
  DateTime? _selected;

  /// The first of the shown month; null follows the selection.
  DateTime? _month;

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

  void _select(DateTime day) => setState(() {
    _selected = day;
    _month = _monthOf(day);
  });

  /// Shows [month] and keeps the selection inside it: today when the month
  /// holds it, else its first day. The day card and the add buttons always
  /// target a day that is on screen.
  void _showMonth(DateTime month, DateTime today) => setState(() {
    _month = month;
    _selected = month.year == today.year && month.month == today.month
        ? today
        : DateTime.utc(month.year, month.month);
  });

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final clock = _clock();
        final today = wallDay(wallNow(clock));
        final selected = _selected ?? today;
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
              child: wide
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

  /// The month grid: arrows, month name, Today, weekdays, then the days.
  /// Wide cells carry up to three item chips (and '+N more'); narrow ones
  /// only a dot per kind, as the old Home calendar did.
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
    final muted = t.type.captionStyle.copyWith(color: t.muted);
    return CardBox(
      padding: EdgeInsets.all(t.space.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
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
              Expanded(
                child: Text(
                  '${_monthNames[month.month - 1]} ${month.year}',
                  key: const Key('calendar-month'),
                  textAlign: TextAlign.center,
                  style: t.type.labelStyle.copyWith(color: t.fg),
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
                  variant: FButtonVariant.outline,
                  size: FButtonSizeVariant.xs,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => _select(today),
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
                      style: muted,
                    ),
                  ),
                ),
            ],
          ),
          for (var w = 0; w < weeks; w++)
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _cell(
                      context,
                      t: t,
                      day: start.add(Duration(days: w * 7 + i)),
                      month: month,
                      today: today,
                      selected: selected,
                      bucket: buckets[start.add(Duration(days: w * 7 + i))],
                      height: cellHeight,
                      wide: wide,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// One day of the grid: the number and its chips (wide) or dots (narrow),
  /// a fill when selected and a ring on today.
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
  }) {
    final id = '${day.year}-${day.month}-${day.day}';
    final inMonth = day.month == month.month;
    final isSelected = day == selected;
    final isToday = day == today;
    final number = t.type.captionStyle.copyWith(
      color: isSelected
          ? t.onAccent
          : inMonth
          ? t.fg
          : t.faint,
    );
    final items = <({String title, bool event})>[
      for (final o in bucket?.events ?? const <EventOccurrence>[])
        (title: o.summary.isEmpty ? '(no title)' : o.summary, event: true),
      for (final k in bucket?.tasks ?? const <TaskOccurrence>[])
        (
          title: k.task.summary.isEmpty ? '(no title)' : k.task.summary,
          event: false,
        ),
    ];
    Widget body;
    if (wide) {
      const cap = 3;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${day.day}', textAlign: TextAlign.center, style: number),
          Expanded(
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, item) in items.take(cap).indexed)
                    _chip(
                      t: t,
                      key: Key('calendar-chip-$id-$i'),
                      title: item.title,
                      event: item.event,
                      onSelected: isSelected,
                    ),
                  if (items.length > cap)
                    Padding(
                      padding: EdgeInsets.only(top: t.space.xxs),
                      child: Text(
                        '+${items.length - cap} more',
                        key: Key('calendar-more-$id'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.type.microStyle.copyWith(
                          color: isSelected ? t.onAccent : t.muted,
                        ),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${day.day}', style: number),
          SizedBox(
            height: t.sizes.calendarDot,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (bucket != null && bucket.events.isNotEmpty)
                  StatusDot(
                    null,
                    key: Key('calendar-dot-event-$id'),
                    color: isSelected ? t.onAccent : t.accent,
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
                    color: isSelected ? t.onAccent : t.statusTodo,
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
      onPress: () => _select(day),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected ? t.accent : null,
            borderRadius: BorderRadius.circular(t.radii.small),
            border: isToday && !isSelected
                ? Border.all(color: t.accent, width: t.sizes.ring)
                : null,
          ),
          child: Padding(padding: EdgeInsets.all(t.space.xxs), child: body),
        ),
      ),
    );
  }

  /// One item in a wide day cell: a kind dot and the title, cut to the cell.
  Widget _chip({
    required Tokens t,
    required Key key,
    required String title,
    required bool event,
    required bool onSelected,
  }) => Padding(
    key: key,
    padding: EdgeInsets.only(top: t.space.xxs),
    child: Row(
      children: [
        StatusDot(
          null,
          color: onSelected
              ? t.onAccent
              : event
              ? t.accent
              : t.statusTodo,
          size: t.sizes.calendarDot,
        ),
        SizedBox(width: t.space.xxs),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.type.microStyle.copyWith(
              color: onSelected ? t.onAccent : t.fg,
            ),
          ),
        ),
      ],
    ),
  );

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
