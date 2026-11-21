import 'package:davdart/davdart.dart';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../theme/tokens.dart';
import 'content_grid.dart';
import 'home_today.dart';
import 'theme.dart';

// Home's Day focus: a month calendar that picks a day, and the day section
// (home_today.dart) for it. Wide (>= 600): calendar left, list right. Phone:
// a one-line collapsible calendar, the list below. The selected day is a
// plain date (AppState.homeDay), never an instant.

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

/// The `Day | Board` switch at the top of Home.
class HomeSwitch extends StatelessWidget {
  const HomeSwitch({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => _build(context, t),
    );
  }

  Widget _build(BuildContext context, Tokens t) {
    final focus = state.homeFocus;
    Widget seg(HomeFocus f, String label) {
      final on = focus == f;
      return FTappable(
        key: Key('home-focus-${f.name}'),
        behavior: HitTestBehavior.opaque,
        semanticsLabel: label,
        onPress: () => state.setHomeFocus(f),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: narrowLayout(context)
                ? t.sizes.touchTarget
                : t.sizes.segmentHeight,
            minWidth: t.sizes.segmentMin,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: on ? t.selected : null,
              borderRadius: BorderRadius.circular(t.radii.card),
            ),
            child: Center(
              child: Text(
                label,
                style: t.type.captionStyle.copyWith(
                  color: on ? t.fg : t.muted,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ContentCap(
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: DecoratedBox(
            key: const Key('home-focus'),
            decoration: BoxDecoration(
              border: Border.all(color: t.cardBorder),
              borderRadius: BorderRadius.circular(t.radii.card),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                seg(HomeFocus.day, 'Day'),
                seg(HomeFocus.board, 'Board'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Day focus. [now] overrides the clock (tests).
class HomeDayFocus extends StatefulWidget {
  const HomeDayFocus({super.key, required this.state, this.now});
  final AppState state;
  final DateTime Function()? now;

  @override
  State<HomeDayFocus> createState() => _HomeDayFocusState();
}

class _HomeDayFocusState extends State<HomeDayFocus> {
  AppState get state => widget.state;
  DateTime? _month; // first of the shown month
  DateTime? _lastSelected;

  DateTime _clock() => (widget.now ?? DateTime.now)();

  DateTime _monthOf(DateTime d) => DateTime.utc(d.year, d.month);

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        // The board's keyboard rows are not on screen in this focus.
        state.nav.publishHome('board', const []);
        final clock = _clock();
        final today = wallDay(wallNow(clock));
        final sel = state.homeSelectedDay(clock);
        // The grid follows the selection when it changes from outside.
        if (_lastSelected != sel) {
          _lastSelected = sel;
          _month = _monthOf(sel);
        }
        final month = _month ?? _monthOf(sel);
        final calendar = MonthCalendar(
          state: state,
          month: month,
          selected: sel,
          today: today,
          onMonth: (m) => setState(() => _month = m),
          onSelect: (d) {
            _lastSelected = d;
            _month = _monthOf(d);
            state.selectHomeDay(d);
          },
          clock: clock,
        );
        final list = HomeToday(state: state, now: widget.now);
        return LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= Tokens.stackBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(t.space.lg, t.space.md, 0, 0),
                    child: SizedBox(
                      width: t.sizes.calendarWidth,
                      child: calendar,
                    ),
                  ),
                  Expanded(child: SingleChildScrollView(child: list)),
                ],
              );
            }
            return SingleChildScrollView(
              key: const Key('home-scroll'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      t.space.lg,
                      t.space.md,
                      t.space.lg,
                      0,
                    ),
                    child: CollapsedCalendar(
                      state: state,
                      selected: sel,
                      today: today,
                      clock: clock,
                      grid: calendar,
                    ),
                  ),
                  list,
                  SizedBox(height: fabInset(context)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Phone calendar: one line `< Sat 22 Nov v >` (day-step arrows, tap to open
/// the month grid), expanded state persisted per Space.
class CollapsedCalendar extends StatelessWidget {
  const CollapsedCalendar({
    super.key,
    required this.state,
    required this.selected,
    required this.today,
    required this.clock,
    required this.grid,
  });
  final AppState state;
  final DateTime selected;
  final DateTime today;
  final DateTime clock;
  final Widget grid;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final open = state.homeCalOpen;
    void step(int d) => state.selectHomeDay(selected.add(Duration(days: d)));
    Widget arrow(String key, IconData icon, String label, int d) => SizedBox(
      width: t.sizes.touchTarget,
      height: t.sizes.touchTarget,
      child: FTappable(
        key: Key(key),
        behavior: HitTestBehavior.opaque,
        semanticsLabel: label,
        onPress: () => step(d),
        child: Center(
          child: Icon(icon, size: t.icons.md, color: t.muted),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            arrow(
              'home-cal-prev-day',
              FLucideIcons.chevronLeft,
              'Previous day',
              -1,
            ),
            Expanded(
              child: FTappable(
                key: const Key('home-cal-toggle'),
                behavior: HitTestBehavior.opaque,
                semanticsLabel: open ? 'Collapse calendar' : 'Expand calendar',
                onPress: () => state.setHomeCalOpen(!open),
                child: SizedBox(
                  height: t.sizes.touchTarget,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        dayLabel(selected, clock),
                        key: const Key('home-cal-label'),
                        style: t.type.labelStyle.copyWith(color: t.fg),
                      ),
                      SizedBox(width: t.space.sm),
                      Icon(
                        open
                            ? FLucideIcons.chevronUp
                            : FLucideIcons.chevronDown,
                        size: t.icons.md,
                        color: t.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            arrow(
              'home-cal-next-day',
              FLucideIcons.chevronRight,
              'Next day',
              1,
            ),
          ],
        ),
        if (open) grid,
      ],
    );
  }
}

/// A month grid: a dot per day with events (accent) or tasks (todo tone),
/// a ring on today, a fill on the selected day, month arrows. Weeks start on
/// the locale's first weekday.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.state,
    required this.month,
    required this.selected,
    required this.today,
    required this.onMonth,
    required this.onSelect,
    required this.clock,
  });
  final AppState state;
  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final DateTime clock;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final first = firstWeekday(context);
    final lead = (month.weekday - first + 7) % 7;
    final start = DateTime.utc(month.year, month.month, 1 - lead);
    final days = DateTime.utc(month.year, month.month + 1, 0).day;
    final weeks = ((lead + days) / 7).ceil();
    final end = start.add(Duration(days: weeks * 7));
    final buckets = bucketByDay(
      events: state.events,
      tasks: state.openTasks(clock),
      from: start,
      to: end,
    );
    final cell = narrowLayout(context)
        ? t.sizes.touchTarget
        : t.sizes.calendarCell;
    final muted = t.type.captionStyle.copyWith(color: t.muted);

    Widget nav(String key, IconData icon, String label, int d) => SizedBox(
      width: cell,
      height: cell,
      child: FTappable(
        key: Key(key),
        behavior: HitTestBehavior.opaque,
        semanticsLabel: label,
        onPress: () => onMonth(DateTime.utc(month.year, month.month + d)),
        child: Center(
          child: Icon(icon, size: t.icons.md, color: t.muted),
        ),
      ),
    );

    Widget day(DateTime d) {
      final inMonth = d.month == month.month;
      final b = buckets[d];
      final isSel = d == selected;
      final isToday = d == today;
      return FTappable(
        key: Key('cal-day-${d.year}-${d.month}-${d.day}'),
        behavior: HitTestBehavior.opaque,
        semanticsLabel: dayLabel(d, clock),
        onPress: () => onSelect(d),
        child: SizedBox(
          height: cell,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isSel ? t.accent : null,
                shape: BoxShape.circle,
                border: isToday && !isSel
                    ? Border.all(color: t.accent, width: t.sizes.ring)
                    : null,
              ),
              child: SizedBox(
                width: cell - t.space.sm,
                height: cell - t.space.sm,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${d.day}',
                      style: t.type.captionStyle.copyWith(
                        color: isSel
                            ? t.onAccent
                            : inMonth
                            ? t.fg
                            : t.muted.withValues(alpha: 0.5),
                      ),
                    ),
                    SizedBox(
                      height: t.sizes.calendarDot,
                      child: b == null
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (b.events.isNotEmpty)
                                  _Dot(
                                    key: Key('cal-dot-event-${d.day}'),
                                    color: isSel ? t.onAccent : t.accent,
                                  ),
                                if (b.events.isNotEmpty && b.tasks.isNotEmpty)
                                  SizedBox(width: t.space.xxs),
                                if (b.tasks.isNotEmpty)
                                  _Dot(
                                    key: Key('cal-dot-task-${d.day}'),
                                    color: isSel ? t.onAccent : t.statusTodo,
                                  ),
                              ],
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

    return Container(
      key: const Key('home-calendar'),
      padding: EdgeInsets.all(t.space.sm),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.radii.card),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              nav('cal-prev', FLucideIcons.chevronLeft, 'Previous month', -1),
              Expanded(
                child: Text(
                  '${_monthNames[month.month - 1]} ${month.year}',
                  key: const Key('cal-month'),
                  textAlign: TextAlign.center,
                  style: t.type.labelStyle.copyWith(color: t.fg),
                ),
              ),
              nav('cal-next', FLucideIcons.chevronRight, 'Next month', 1),
            ],
          ),
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
                  Expanded(child: day(start.add(Duration(days: w * 7 + i)))),
              ],
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({super.key, required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    final d = tokensOf(context).sizes.calendarDot;
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: SizedBox(width: d, height: d),
    );
  }
}
