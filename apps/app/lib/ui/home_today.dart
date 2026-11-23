import 'dart:async';

import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import '../theme/tokens.dart';
import 'collapsible_section.dart';
import 'content_grid.dart';
import 'event_menu.dart';
import '../state/event_rules.dart';
import 'events_panel.dart';
import 'key_nav_ui.dart';
import 'parts.dart';
import 'task_menu.dart';
import 'task_parts.dart';
import 'theme.dart';

// The day section on Home: Events and Tasks sections (accordion header
// outside, one card of rows each) for the selected day
// (`AppState.homeSelectedDay`, today by default), stacked in one column. A
// view over AppState; the calendar that picks the day is in home_day.dart.

// Home ignores the panel filters (Tasks and Events tags, the Tasks folder
// filter, the Board folder scope): it shows literally today's items.

class HomeToday extends StatefulWidget {
  const HomeToday({super.key, required this.state, this.now});
  final AppState state;

  /// Clock override for tests (a function so the time can advance).
  final DateTime Function()? now;

  @override
  State<HomeToday> createState() => _HomeTodayState();
}

class _HomeTodayState extends State<HomeToday> {
  Timer? _timer;

  AppState get state => widget.state;
  final _rows = <NavEntry>[];
  NavEntry _entry(String id, String uid, String block) => NavEntry(
    id,
    uid: uid,
    block: block,
    hidden: () => state.homeCardCollapsed(block),
    open: (mode) async {
      await state.openNote(uid, mode: mode);
    },
  );

  Widget _navRow(String block, String id, String uid, Widget row) {
    _rows.add(_entry(id, uid, block));
    return NavRow(
      key: ValueKey('nav-home-$id'),
      nav: state.nav,
      list: KeyNav.homeList,
      id: id,
      child: row,
    );
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _arm();
  }

  // One-shot timer to the next local midnight, re-armed on each fire. The app
  // has no lifecycle hook to refresh on resume, so a stale day after sleep is
  // corrected when this timer fires.
  void _arm() {
    _timer?.cancel();
    final n = _now();
    final next = DateTime(n.year, n.month, n.day + 1);
    var wait = next.difference(n);
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    _timer = Timer(wait, () {
      if (!mounted) return;
      state.rollHomeDay();
      _arm();
    });
  }

  @override
  void didUpdateWidget(HomeToday old) {
    super.didUpdateWidget(old);
    if (old.now != widget.now) _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Its keyboard rows go with it (the Board focus has none from here).
    state.nav.publishHome('today', const []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final clock = _now();
        final day = state.homeSelectedDay(clock);
        final isToday = day == wallDay(wallNow(clock));
        // The keyboard list of the rows below, filled by the cards.
        _rows.clear();
        // Events above Tasks, in this order for the keyboard too.
        final cards = <Widget>[
          _eventsCard(context, clock, day, isToday),
          _tasksCard(context, clock, day, isToday),
        ];
        state.nav.publishHome('today', List.of(_rows));
        return ContentCap(
          child: LayoutBuilder(
            builder: (context, outer) {
              // The sections are always one stacked column.
              state.nav.homeStacked = true;
              final gap = t.space.lg;
              final body = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) SizedBox(height: gap),
                    cards[i],
                  ],
                ],
              );
              return Padding(
                key: const Key('home-today'),
                padding: EdgeInsets.all(t.space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Wide: a small date label over the cards (on a phone
                    // the calendar card shows the date).
                    if (MediaQuery.sizeOf(context).width >=
                        Tokens.stackBreakpoint)
                      Padding(
                        padding: EdgeInsets.only(bottom: t.space.sm),
                        child: Text(
                          isToday ? 'Today' : dayLabel(day, clock),
                          key: const Key('home-day-label'),
                          style: t.type.labelStyle.copyWith(color: t.muted),
                        ),
                      ),
                    body,
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _tasksCard(
    BuildContext context,
    DateTime clock,
    DateTime day,
    bool isToday,
  ) {
    // Dated tasks only: overdue first (only on today), then due that day (recurring tasks
    // expanded); each in compareTasks order.
    final overdue = isToday ? state.overdueTasks(clock) : <Task>[];
    // A one-off overdue task is listed once; a repeating one also shows its
    // occurrence on this day (second row, `-occ` keys).
    final skip = {
      for (final k in overdue)
        if (!k.isRecurring) k.uid,
    };
    final overdueIds = {for (final k in overdue) k.uid};
    final onDay =
        (bucketByDay(
                  tasks: state.openTasks(clock),
                  from: day,
                  to: day.add(const Duration(days: 1)),
                )[day]?.tasks ??
                const <TaskOccurrence>[])
            .map((o) => o.task)
            .where((k) => !skip.contains(k.uid))
            .toList();
    final due = [...overdue, ...onDay];
    final all = due.length;
    bool occ(int i) => i >= overdue.length && overdueIds.contains(due[i].uid);
    return TodayCard(
      slug: 'tasks',
      title: 'Tasks',
      count: all,
      collapsed: state.homeCardCollapsed('tasks'),
      onToggle: (c) => state.setHomeCardCollapsed('tasks', c),
      link: 'All tasks',
      onLink: state.openTasksPanel,
      add: state.tasksEditable
          ? IconAction(
              compact: true,
              key: const Key('home-today-tasks-add'),
              tooltip: 'New task',
              icon: FLucideIcons.plus,
              onPress: () =>
                  showNewTaskDialog(context, state, due: dueOfDay(day)),
            )
          : null,
      emptyText: isToday ? 'Nothing due today' : 'Nothing due',
      total: all,
      rows: [
        for (var i = 0; i < due.length; i++)
          _navRow(
            'tasks',
            occ(i) ? 'task-${due[i].uid}-occ' : 'task-${due[i].uid}',
            due[i].uid,
            TaskRow(
              key: Key(
                occ(i)
                    ? 'home-today-tasks-${due[i].uid}-occ'
                    : 'home-today-tasks-${due[i].uid}',
              ),
              state: state,
              task: due[i],
              now: clock,
            ),
          ),
      ],
    );
  }

  Widget _eventsCard(
    BuildContext context,
    DateTime clock,
    DateTime day,
    bool isToday,
  ) {
    final today =
        bucketByDay(
          events: state.events,
          from: day,
          to: day.add(const Duration(days: 1)),
          includeCancelled: true,
        )[day]?.events ??
        const <EventOccurrence>[];
    // All-day first, then by start (the sort is stable).
    final sorted = [
      ...today.where((o) => o.allDay),
      ...today.where((o) => !o.allDay),
    ];
    return TodayCard(
      slug: 'events',
      title: 'Events',
      count: sorted.length,
      link: 'All events',
      onLink: state.openEventsPanel,
      add: state.eventsEditable
          ? IconAction(
              compact: true,
              key: const Key('home-today-events-add'),
              tooltip: 'New event',
              icon: FLucideIcons.plus,
              onPress: () async {
                final uid = await showNewEventDialog(context, state, day: day);
                if (uid != null) await state.clickEvent(uid);
              },
            )
          : null,
      emptyText: isToday ? 'No events today' : 'No events',
      total: sorted.length,
      collapsed: state.homeCardCollapsed('events'),
      onToggle: (c) => state.setHomeCardCollapsed('events', c),
      rows: [
        for (final o in sorted)
          _navRow(
            'events',
            eventRowId(o),
            o.event.uid,
            EventRow(key: eventRowKey(o), state: state, occurrence: o),
          ),
      ],
    );
  }
}

/// One section of the day list: a plain accordion header outside any card
/// (chevron, title, count, then the "All" link and add button at the right),
/// and one card below holding the [rows], or [emptyText] when [total] is 0.
class TodayCard extends StatelessWidget {
  const TodayCard({
    super.key,
    required this.slug,
    required this.title,
    required this.count,
    required this.rows,
    required this.total,
    required this.emptyText,
    this.link,
    this.onLink,
    this.collapsed = false,
    this.onToggle,
    this.add,
  });
  final String slug;
  final String title;
  final int count;
  final List<Widget> rows;
  final int total;
  final String emptyText;
  final String? link;
  final VoidCallback? onLink;
  final bool collapsed;
  final ValueChanged<bool>? onToggle;
  final Widget? add;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final muted = t.type.captionStyle.copyWith(color: t.muted);
    return CollapsibleSection(
      id: 'home-today-$slug',
      title: title,
      count: count,
      collapsed: collapsed,
      onChanged: onToggle,
      headerPadding: EdgeInsets.only(bottom: t.space.xs),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (link != null)
            FTappable(
              key: Key('home-today-$slug-all'),
              behavior: HitTestBehavior.opaque,
              onPress: onLink,
              // A touch-sized target on the narrow layout.
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: narrowLayout(context) ? t.sizes.touchTarget : 0,
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    link!,
                    maxLines: 1,
                    style: muted.copyWith(color: t.accent),
                  ),
                ),
              ),
            ),
          if (add != null) ...[SizedBox(width: t.space.sm), add!],
        ],
      ),
      child: DecoratedBox(
        key: Key('home-today-$slug'),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.radii.card),
          border: Border.all(color: t.cardBorder),
        ),
        child: Padding(
          padding: EdgeInsets.all(t.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (total == 0)
                Text(
                  emptyText,
                  key: Key('home-today-$slug-empty'),
                  style: muted,
                )
              else
                ...rows,
            ],
          ),
        ),
      ),
    );
  }
}
