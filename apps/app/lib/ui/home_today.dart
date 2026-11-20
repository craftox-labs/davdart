import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'content_grid.dart';
import 'event_menu.dart';
import 'events_panel.dart';
import 'overflow_tip.dart';
import 'parts.dart';
import 'task_menu.dart';
import 'task_parts.dart';
import 'theme.dart';

// The "Today" section on Home: equal-width cards (Tasks, Events) for what
// falls on today. A pure view over AppState. The cards are a plain list in
// [HomeToday]; a later calendar card is one more [TodayCard] in that list. To
// remove: delete this file, its tests and the one `HomeToday(...)` line in
// app.dart.

const _maxRows = 6;

class HomeToday extends StatelessWidget {
  const HomeToday({super.key, required this.state, this.now});
  final AppState state;

  /// Clock override for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final clock = now ?? DateTime.now();
        // The seam: add further cards (a calendar) to this list.
        final cards = <Widget>[
          _tasksCard(context, clock),
          _eventsCard(context, clock),
        ];
        return ContentCap(
          child: Padding(
            key: const Key('home-today'),
            padding: EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, 0),
            child: LayoutBuilder(
              builder: (context, c) {
                final gap = t.space.lg;
                if (c.maxWidth < Tokens.stackBreakpoint) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) SizedBox(height: gap),
                        cards[i],
                      ],
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) SizedBox(width: gap),
                        Expanded(child: cards[i]),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _tasksCard(BuildContext context, DateTime clock) {
    final scope = state.scopeUid;
    bool inScope(Task k) => scope == null || state.taskIsUnder(k, scope);
    // Overdue first, then due today; each already in compareTasks order.
    final due = [
      ...state.overdueTasks(clock).where(inScope),
      ...state.dueTodayTasks(clock).where(inScope),
    ];
    return TodayCard(
      slug: 'tasks',
      title: 'Tasks',
      count: due.length,
      link: 'All tasks',
      onLink: state.openTasksPanel,
      add: state.tasksEditable
          ? IconAction(
              compact: true,
              key: const Key('home-today-tasks-add'),
              tooltip: 'New task',
              icon: FLucideIcons.plus,
              onPress: () => showNewTaskDialog(
                context,
                state,
                due: dueOfDay(dayFromToday(0, clock)),
              ),
            )
          : null,
      emptyText: 'Nothing due today',
      total: due.length,
      onMore: state.openTasksPanel,
      rows: [
        for (final k in due.take(_maxRows))
          TaskRow(
            key: Key('home-today-tasks-${k.uid}'),
            state: state,
            task: k,
            now: clock,
          ),
      ],
    );
  }

  Widget _eventsCard(BuildContext context, DateTime clock) {
    final today = <EventOccurrence>[
      for (final g in state.upcomingOccurrences(clock, 1))
        if (g.id == 'today') ...g.items,
    ];
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
                final uid = await showNewEventDialog(context, state);
                if (uid != null) await state.clickEvent(uid);
              },
            )
          : null,
      emptyText: 'No events today',
      total: sorted.length,
      onMore: state.openEventsPanel,
      rows: [
        for (final o in sorted.take(_maxRows))
          EventRow(key: eventRowKey(o), state: state, occurrence: o),
      ],
    );
  }
}

/// One card of the Today section: header (title, count, optional "All" link
/// and add button), then [rows], or [emptyText] when [total] is 0. Rows past
/// the cap end in "and N more". Cards do not collapse.
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
    this.onMore,
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
  final VoidCallback? onMore;
  final Widget? add;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final muted = t.type.captionStyle.copyWith(color: t.muted);
    final hidden = total - rows.length;
    return DecoratedBox(
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
            Padding(
              padding: EdgeInsets.all(t.space.xs),
              child: Row(
                children: [
                  Flexible(
                    child: OverflowTip(
                      title,
                      style: t.type.labelStyle.copyWith(
                        fontSize: t.type.caption,
                        color: t.muted,
                      ),
                    ),
                  ),
                  SizedBox(width: t.space.sm),
                  Text(
                    '$count',
                    key: Key('home-today-$slug-count'),
                    style: muted,
                  ),
                  const Spacer(),
                  if (link != null)
                    Flexible(
                      child: FTappable(
                        key: Key('home-today-$slug-all'),
                        onPress: onLink,
                        child: OverflowTip(
                          link!,
                          style: muted.copyWith(color: t.accent),
                        ),
                      ),
                    ),
                  if (add != null) ...[SizedBox(width: t.space.sm), add!],
                ],
              ),
            ),
            if (total == 0)
              Padding(
                padding: EdgeInsets.all(t.space.xs),
                child: Text(
                  emptyText,
                  key: Key('home-today-$slug-empty'),
                  style: muted,
                ),
              )
            else
              ...rows,
            if (hidden > 0)
              FTappable(
                key: Key('home-today-$slug-more'),
                onPress: onMore,
                child: Padding(
                  padding: EdgeInsets.all(t.space.xs),
                  child: Text(
                    'and $hidden more',
                    style: muted.copyWith(color: t.accent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
