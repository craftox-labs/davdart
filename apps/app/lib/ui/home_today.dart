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

// Home ignores the panel filters (Tasks and Events tags, the Tasks folder
// filter, the Board folder scope): it shows literally today's items.

class HomeToday extends StatefulWidget {
  const HomeToday({
    super.key,
    required this.state,
    this.now,
    this.capStacked = false,
  });
  final AppState state;

  /// The split Home (600 to 880): stacked cards are capped to 40% of the
  /// screen height and scroll inside, so the board below keeps room. Off on
  /// the phone Home, where everything scrolls as one.
  final bool capStacked;

  /// Clock override for tests (a function so the time can advance).
  final DateTime Function()? now;

  @override
  State<HomeToday> createState() => _HomeTodayState();
}

class _HomeTodayState extends State<HomeToday> {
  Timer? _timer;

  AppState get state => widget.state;
  final _rows = <NavEntry>[];
  static const _prefKey = 'davdart.home.today.collapsed.v1';
  // The one source of truth for the collapsed state; the section is
  // controlled by it.
  late bool _collapsed = state.prefs?.read(_prefKey) == 'true';

  void _setCollapsed(bool c) {
    setState(() => _collapsed = c);
    if (c) {
      state.prefs?.write(_prefKey, 'true');
    } else {
      state.prefs?.remove(_prefKey);
    }
  }

  NavEntry _entry(String id, String uid, String block) => NavEntry(
    id,
    uid: uid,
    block: block,
    hidden: () => _collapsed,
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
      setState(() {});
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final clock = _now();
        // The keyboard list of the rows below, filled by the cards.
        _rows.clear();
        // The seam: add further cards (a calendar) to this list.
        final cards = <Widget>[
          _tasksCard(context, clock),
          _eventsCard(context, clock),
        ];
        state.nav.publishHome('today', List.of(_rows));
        return ContentCap(
          child: LayoutBuilder(
            builder: (context, outer) {
              // Known even while the section is collapsed.
              final stacked =
                  outer.maxWidth - 2 * t.space.lg < Tokens.stackBreakpoint;
              state.nav.homeStacked = stacked;
              final gap = t.space.lg;
              Widget body;
              if (stacked) {
                // Stacked cards; on a phone Home they scroll with the
                // board in one scroll view (see app.dart).
                body = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) SizedBox(height: gap),
                      cards[i],
                    ],
                  ],
                );
                if (widget.capStacked) {
                  body = ConstrainedBox(
                    key: const Key('home-today-cap'),
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                    ),
                    child: SingleChildScrollView(child: body),
                  );
                }
              } else {
                body = IntrinsicHeight(
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
              }
              return CollapsibleSection(
                id: 'today-section',
                title: 'Today',
                collapsed: _collapsed,
                onChanged: _setCollapsed,
                headerPadding: EdgeInsets.fromLTRB(
                  t.space.lg,
                  t.space.md,
                  t.space.lg,
                  0,
                ),
                child: Padding(
                  key: const Key('home-today'),
                  padding: EdgeInsets.fromLTRB(
                    t.space.lg,
                    t.space.sm,
                    t.space.lg,
                    0,
                  ),
                  child: body,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _tasksCard(BuildContext context, DateTime clock) {
    // Overdue first, then due today; each already in compareTasks order.
    final due = [...state.overdueTasks(clock), ...state.dueTodayTasks(clock)];
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
          _navRow(
            'tasks',
            'task-${k.uid}',
            k.uid,
            TaskRow(
              key: Key('home-today-tasks-${k.uid}'),
              state: state,
              task: k,
              now: clock,
            ),
          ),
      ],
    );
  }

  Widget _eventsCard(BuildContext context, DateTime clock) {
    final today = <EventOccurrence>[
      for (final g in upcomingGroups(state.events, clock, 1))
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
                  // Title and count take the free width, so the link and
                  // the add button end at the card's right edge.
                  Expanded(
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
                      ],
                    ),
                  ),
                  if (link != null)
                    FTappable(
                      key: Key('home-today-$slug-all'),
                      behavior: HitTestBehavior.opaque,
                      onPress: onLink,
                      // A touch-sized target on the narrow layout.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: narrowLayout(context)
                              ? t.sizes.touchTarget
                              : 0,
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
