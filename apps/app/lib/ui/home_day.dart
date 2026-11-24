import 'package:davdart/davdart.dart';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../theme/tokens.dart';
import 'content_grid.dart';
import 'home_today.dart';
import 'home_board.dart' show kindIcon;
import 'mobile_nav.dart' show addEntries;
import 'note_menu.dart' show NoteMenuItem, menuRows;
import 'parts.dart';
import 'scope_bar.dart' show FilterChips;
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
    final full = narrowLayout(context);
    // One outlined box, Day (half) | Board (the other half), the kind filter
    // inside the Board half so it reads as the Board's own filter.
    final side = full ? t.sizes.touchTarget : t.sizes.segmentHeight;
    final onDay = state.homeFocus == HomeFocus.day;
    Widget half(Widget child, bool on, {Key? key}) => Expanded(
      child: DecoratedBox(
        key: key,
        decoration: BoxDecoration(
          color: on ? t.selected : null,
          borderRadius: BorderRadius.circular(t.radii.card),
        ),
        child: child,
      ),
    );
    Widget label(String text, bool on, String key, HomeFocus f) => FTappable(
      key: Key(key),
      behavior: HitTestBehavior.opaque,
      semanticsLabel: text,
      onPress: () => state.setHomeFocus(f),
      child: SizedBox(
        height: side,
        child: Center(
          child: Text(
            text,
            style: t.type.captionStyle.copyWith(
              color: on ? t.fg : t.muted,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
    final strip = DecoratedBox(
      key: const Key('home-strip'),
      decoration: BoxDecoration(
        border: Border.all(color: t.cardBorder),
        borderRadius: BorderRadius.circular(t.radii.card),
      ),
      child: Row(
        key: const Key('home-focus'),
        children: [
          half(label('Day', onDay, 'home-focus-day', HomeFocus.day), onDay),
          half(
            Row(
              children: [
                Expanded(
                  child: label(
                    'Board',
                    !onDay,
                    'home-focus-board',
                    HomeFocus.board,
                  ),
                ),
                _KindFilter(state: state, side: side),
              ],
            ),
            !onDay,
          ),
        ],
      ),
    );
    return ContentCap(
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space.lg, t.space.lg, t.space.lg, 0),
        child: full
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.query.trim().isNotEmpty) ...[
                    FilterChips(state: state, fullWidth: true),
                    SizedBox(height: t.space.lg),
                  ],
                  strip,
                ],
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: strip,
                      ),
                    ),
                    SizedBox(width: t.space.md),
                    _HomeAdd(state: state),
                    if (state.query.trim().isNotEmpty) ...[
                      SizedBox(width: t.space.md),
                      Flexible(child: FilterChips(state: state)),
                    ],
                  ],
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
        Widget calendarFor(bool bleed, {double? availHeight}) => MonthCalendar(
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
          bleed: bleed,
          availHeight: availHeight,
          onToday: bleed ? null : state.resetHomeDay,
        );
        final list = HomeToday(state: state, now: widget.now);
        return LayoutBuilder(
          builder: (context, c) {
            final calendar = calendarFor(c.maxWidth < Tokens.stackBreakpoint);
            if (c.maxWidth >= Tokens.stackBreakpoint) {
              // Two columns on one top edge: the calendar card (1/2) and the day list (scrolls on
              // its own). Page margins and the gap are space.lg.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, lc) => Padding(
                        padding: EdgeInsets.all(t.space.lg).copyWith(right: 0),
                        // Fits the window where it can; scrolls when not.
                        child: SingleChildScrollView(
                          key: const Key('home-calendar-scroll'),
                          child: calendarFor(
                            false,
                            availHeight: lc.maxHeight - 2 * t.space.lg,
                          ),
                        ),
                      ),
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
                      t.space.lg,
                      t.space.lg,
                      0,
                    ),
                    child: CollapsedCalendar(
                      state: state,
                      selected: sel,
                      today: today,
                      clock: clock,
                      month: month,
                      onMonth: (m) => setState(() => _month = m),
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

/// The one header row of the calendar card: `< title v >` with the title
/// centred between two arrows. A `Today` button lives in a reserved slot on
/// the right (mirrored by an empty slot on the left), sized to its text, so
/// the title never shifts and never meets the button or the arrows.
class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    super.key,
    required this.title,
    required this.titleKey,
    required this.prevKey,
    required this.nextKey,
    required this.prevLabel,
    required this.nextLabel,
    required this.onPrev,
    required this.onNext,
    required this.showToday,
    required this.onToday,
    this.onToggle,
    this.open,
  });
  final String title;
  final String titleKey, prevKey, nextKey;
  final String prevLabel, nextLabel;
  final VoidCallback onPrev, onNext;
  final bool showToday;
  final VoidCallback? onToday;

  /// Taps on the title (collapse or expand); null on wide.
  final VoidCallback? onToggle;

  /// The chevron: up when open, down when closed; none when null.
  final bool? open;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final box = narrowLayout(context)
        ? t.sizes.touchTarget
        : t.sizes.calendarCell;
    final todayStyle = t.type.captionStyle.copyWith(color: t.accent);
    final tp = TextPainter(
      text: TextSpan(text: 'Today', style: todayStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final slot = tp.width + 2 * t.space.sm;
    Widget arrow(String key, IconData icon, String label, VoidCallback f) =>
        SizedBox(
          width: box,
          height: box,
          child: FTappable(
            key: Key(key),
            behavior: HitTestBehavior.opaque,
            semanticsLabel: label,
            onPress: f,
            child: Center(
              child: Icon(icon, size: t.icons.md, color: t.muted),
            ),
          ),
        );
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            key: Key(titleKey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.type.labelStyle.copyWith(color: t.fg),
          ),
        ),
        if (open != null) ...[
          SizedBox(width: t.space.sm),
          Icon(
            open! ? FLucideIcons.chevronUp : FLucideIcons.chevronDown,
            size: t.icons.md,
            color: t.muted,
          ),
        ],
      ],
    );
    return Row(
      children: [
        arrow(prevKey, FLucideIcons.chevronLeft, prevLabel, onPrev),
        SizedBox(width: slot),
        Expanded(
          child: onToggle == null
              ? Center(child: label)
              : FTappable(
                  key: const Key('home-cal-toggle'),
                  behavior: HitTestBehavior.opaque,
                  semanticsLabel: open == true
                      ? 'Collapse calendar'
                      : 'Expand calendar',
                  onPress: onToggle,
                  child: SizedBox(
                    height: box,
                    child: Center(child: label),
                  ),
                ),
        ),
        SizedBox(
          width: slot,
          child: showToday
              ? FTappable(
                  key: const Key('home-day-reset'),
                  behavior: HitTestBehavior.opaque,
                  onPress: onToday,
                  child: SizedBox(
                    height: box,
                    child: Center(child: Text('Today', style: todayStyle)),
                  ),
                )
              : null,
        ),
        arrow(nextKey, FLucideIcons.chevronRight, nextLabel, onNext),
      ],
    );
  }
}

const _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Phone calendar card: one header row (collapsed `< Sat 22 Nov v >`, day
/// arrows; open `< Nov 2026 ^ >`, month arrows) and, when open, the month
/// grid. Expanded state persisted per Space.
class CollapsedCalendar extends StatelessWidget {
  const CollapsedCalendar({
    super.key,
    required this.state,
    required this.selected,
    required this.today,
    required this.clock,
    required this.month,
    required this.onMonth,
    required this.grid,
  });
  final AppState state;
  final DateTime selected;
  final DateTime today;
  final DateTime clock;
  final DateTime month;
  final ValueChanged<DateTime> onMonth;
  final Widget grid;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final open = state.homeCalOpen;
    void step(int d) => state.selectHomeDay(selected.add(Duration(days: d)));
    void stepMonth(int d) => onMonth(DateTime.utc(month.year, month.month + d));
    return DecoratedBox(
      key: const Key('home-calendar-card'),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.radii.card),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CalendarHeader(
            title: open
                ? '${_shortMonths[month.month - 1]} ${month.year}'
                : dayLabel(selected, clock),
            titleKey: open ? 'cal-month' : 'home-cal-label',
            prevKey: open ? 'cal-prev' : 'home-cal-prev-day',
            nextKey: open ? 'cal-next' : 'home-cal-next-day',
            prevLabel: open ? 'Previous month' : 'Previous day',
            nextLabel: open ? 'Next month' : 'Next day',
            onPrev: () => open ? stepMonth(-1) : step(-1),
            onNext: () => open ? stepMonth(1) : step(1),
            showToday: selected != today,
            onToday: state.resetHomeDay,
            onToggle: () => state.setHomeCalOpen(!open),
            open: open,
          ),
          if (open) grid,
        ],
      ),
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
    this.bleed = false,
    this.onToday,
    this.availHeight,
  });
  final AppState state;

  /// Wide: the height the card may use; the day cell height fits it, between
  /// the phone cell and sizes.calendarCellMax.
  final double? availHeight;

  /// Phone: no side padding or border, so seven cells of 44dp fit 320dp.
  final bool bleed;

  /// Wide: a `Today` button above the grid while another day is selected.
  final VoidCallback? onToday;
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
      events: state.scopedEvents,
      tasks: state.openTasks(clock),
      from: start,
      to: end,
    );
    final cell = narrowLayout(context)
        ? t.sizes.touchTarget
        : t.sizes.calendarCell;
    final muted = t.type.captionStyle.copyWith(color: t.muted);
    var cellHeight = cell;
    if (availHeight != null && !bleed) {
      // Padding, the header row (`cell` tall: 44 on narrow layouts), the
      // weekday row and its gap are fixed; the week rows
      // share what is left.
      final fixed = 2 * t.space.md + cell + t.sizes.calendarCell + t.space.md;
      cellHeight = ((availHeight! - fixed) / weeks).clamp(
        t.sizes.touchTarget,
        t.sizes.calendarCellMax,
      );
    }

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
        child: _Cell(
          height: cellHeight,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isSel ? t.accent : null,
                shape: BoxShape.circle,
                border: isToday && !isSel
                    ? Border.all(color: t.accent, width: t.sizes.ring)
                    : null,
              ),
              child: Builder(
                builder: (context) {
                  // A fixed marker size, whatever the cell grows to.
                  final side = cell - t.space.sm;
                  return SizedBox(
                    width: side,
                    height: side,
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
                                    if (b.events.isNotEmpty &&
                                        b.tasks.isNotEmpty)
                                      SizedBox(width: t.space.xxs),
                                    if (b.tasks.isNotEmpty)
                                      _Dot(
                                        key: Key('cal-dot-task-${d.day}'),
                                        color: isSel
                                            ? t.onAccent
                                            : t.statusTodo,
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const Key('home-calendar'),
      padding: bleed
          ? EdgeInsets.fromLTRB(t.space.md, 0, t.space.md, t.space.md)
          : EdgeInsets.all(t.space.md),
      decoration: bleed
          ? null
          : BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(t.radii.card),
              border: Border.all(color: t.cardBorder),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!bleed)
            CalendarHeader(
              title: '${_monthNames[month.month - 1]} ${month.year}',
              titleKey: 'cal-month',
              prevKey: 'cal-prev',
              nextKey: 'cal-next',
              prevLabel: 'Previous month',
              nextLabel: 'Next month',
              onPrev: () => onMonth(DateTime.utc(month.year, month.month - 1)),
              onNext: () => onMonth(DateTime.utc(month.year, month.month + 1)),
              showToday: selected != today,
              onToday: onToday,
            ),
          if (!bleed) SizedBox(height: t.space.md),
          SizedBox(
            height: t.sizes.calendarCell,
            child: Row(
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

/// A calendar day's hit box of a fixed [height].
class _Cell extends StatelessWidget {
  const _Cell({required this.height, required this.child});
  final double height;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(height: height, child: child);
}

/// The small square at the strip's right end: narrows the Board to notes or
/// tasks. It shows the active kind's glyph (a neutral filter icon for All) so
/// a narrowed board never looks like missing items; dimmed and inactive on
/// Day, where it keeps its place.
class _KindFilter extends StatelessWidget {
  const _KindFilter({required this.state, required this.side});
  final AppState state;
  final double side;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final active = state.homeFocus == HomeFocus.board;
    final kind = state.homeKind;
    IconData iconOf(HomeKind k) => switch (k) {
      HomeKind.all => FLucideIcons.listFilter,
      HomeKind.notes => kindIcon(false),
      HomeKind.tasks => kindIcon(true),
    };
    final choices = [
      (HomeKind.all, 'All'),
      (HomeKind.notes, 'Notes'),
      if (state.supportsTasks) (HomeKind.tasks, 'Tasks'),
    ];
    Widget box(VoidCallback? onPress) => FTappable(
      key: const Key('home-kind'),
      behavior: HitTestBehavior.opaque,
      semanticsLabel: 'Show: ${kind.name}',
      onPress: onPress,
      child: SizedBox(
        width: side * 1.3,
        height: side,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                iconOf(kind),
                key: Key('home-kind-icon-${kind.name}'),
                size: t.icons.md,
                color: kind == HomeKind.all ? t.muted : t.fg,
              ),
              Icon(FLucideIcons.chevronDown, size: t.icons.sm, color: t.muted),
            ],
          ),
        ),
      ),
    );
    if (!active) {
      return Opacity(opacity: 0.4, child: IgnorePointer(child: box(null)));
    }
    return FPopoverMenu(
      menuAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      menuBuilder: (ctx, controller, _) => [
        FItemGroup(
          children: menuRows(ctx, controller, [
            for (final (k, label) in choices)
              NoteMenuItem(
                label,
                iconOf(k),
                () => state.setHomeKind(k),
                key: Key('home-kind-${k.name}'),
                selected: k == kind,
              ),
          ]),
        ),
      ],
      builder: (ctx, controller, _) => box(controller.toggle),
    );
  }
}

/// Wide layouts: a split + beside the Day | Board switch. Clicking +
/// adds the type the current focus leads with (Day: event, Board: note,
/// Board narrowed to Tasks: task); the chevron opens the menu of all three. The
/// phone has the add button; both use [addEntries].
class _HomeAdd extends StatelessWidget {
  const _HomeAdd({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    // The menu follows the order of the Home views: Day, Board, Tasks.
    const order = ['add-event', 'add-note', 'add-task'];
    final entries = [
      for (final k in order) ...addEntries(state).where((e) => e.key == k),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    final t = tokensOf(context);
    final lead = switch (state.homeFocus) {
      HomeFocus.day => 'add-event',
      HomeFocus.board =>
        state.homeKind == HomeKind.tasks ? 'add-task' : 'add-note',
    };
    final primary = entries.where((e) => e.key == lead).firstOrNull;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primary != null)
          IconAction(
            key: const Key('home-add'),
            icon: FLucideIcons.plus,
            tooltip: primary.label.replaceFirst('New ', 'Add '),
            onPress: () => primary.run(context),
          ),
        FPopoverMenu(
          menuAnchor: Alignment.topLeft,
          childAnchor: Alignment.bottomLeft,
          menuBuilder: (ctx, controller, _) => [
            FItemGroup(
              children: [
                for (final e in entries)
                  FItem(
                    key: Key('home-${e.key}'),
                    prefix: Icon(e.icon, size: t.icons.md, color: t.muted),
                    title: Text(e.label),
                    onPress: () {
                      controller.hide();
                      e.run(context);
                    },
                  ),
              ],
            ),
          ],
          builder: (ctx, controller, _) => IconAction(
            key: Key(primary == null ? 'home-add' : 'home-add-more'),
            icon: primary == null
                ? FLucideIcons.plus
                : FLucideIcons.chevronDown,
            tooltip: primary == null ? 'New…' : 'More: note, task or event',
            onPress: controller.toggle,
          ),
        ),
      ],
    );
  }
}
