import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../state/key_nav.dart';
import '../state/task_rules.dart';
import 'calendar_view.dart';
import 'events_panel.dart';
import 'key_nav_ui.dart';
import 'overflow_tip.dart';
import 'project_overview.dart';
import 'placeholder_card.dart';
import 'projects_panel.dart' show ProjectProgressBar, projectCounts;
import 'empty_state.dart';
import 'section_card.dart';
import 'segmented.dart';
import 'theme.dart';

/// Home: the individual's page, scoped to the open Space and ignoring the
/// project scope. It summarises what concerns the user (the Space's numbers,
/// its projects, their own loose tasks, calendar and recent items); project
/// content stays in the project's own views.
///
/// Everything here is derived from what already exists. The personal lists
/// pass through [AppState.isMine], the single future multi-user seam, and
/// leave out anything inside the Projects container (see
/// [AppState.inProjectsLayer]).
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state, this.now});
  final AppState state;

  /// Clock override for tests.
  final DateTime? now;

  /// How many rows a preview shows before 'See all'.
  static const preview = 5;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final t = tokensOf(context);
    final clock = now ?? DateTime.now();
    final ix = state.projectIndex;
    final navRows = <NavEntry>[];

    /// A row that is also one row of Home's keyboard grid.
    Widget row(
      String id,
      String? uid,
      String block,
      Future<void> Function(OpenMode? mode)? open,
      Widget child,
    ) {
      navRows.add(NavEntry(id, uid: uid, block: block, open: open));
      return NavRow(
        key: Key(id),
        nav: state.nav,
        list: KeyNav.homeList,
        id: id,
        child: child,
      );
    }

    // --- Space metrics (the whole Space, whatever the project scope) ---
    final open = state.openTasksIn(null, clock);
    final tiles = StatTiles(
      keyPrefix: 'home-tile',
      tilesKey: const Key('home-tiles'),
      stats: [
        StatTileData('projects', 'Projects', ix.projects().length),
        StatTileData('open', 'Open tasks', open.length),
        StatTileData('overdue', 'Overdue', state.overdueIn(null, clock).length),
        StatTileData(
          'done',
          'Done this week',
          state.doneThisWeekIn(null, clock).length,
        ),
      ],
    );

    // --- Projects, most recently changed first ---
    // The index holds the last-changed map and the order; every
    // notification drops it, so it is rebuilt at most once per change and
    // shared by everything in the same frame.
    final projects = ix.projectsByLastChanged();

    Future<void> openProject(String uid) =>
        state.guarded(() => state.openProjectTab(uid));

    Widget projectRow(Note p) {
      final s = ix.statsOf(p.uid);
      final at = ix.lastChangedOf(p.uid);
      final name = p.summary.isEmpty ? 'Untitled' : p.summary;
      final last = at == null
          ? 'No changes yet'
          : dayLabel(wallDay(wallNow(at)));
      return row(
        'home-project-${p.uid}',
        p.uid,
        'projects',
        (_) => openProject(p.uid),
        FTappable(
          onPress: () => openProject(p.uid),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: t.space.xs,
              vertical: t.space.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  FLucideIcons.folderKanban,
                  size: t.icons.md,
                  color: t.muted,
                ),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: t.space.xs,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OverflowTip(name, style: t.type.bodyStyle),
                          ),
                          SizedBox(width: t.space.sm),
                          Text(
                            last,
                            key: Key('home-project-${p.uid}-changed'),
                            style: t.type.captionStyle.copyWith(color: t.muted),
                          ),
                        ],
                      ),
                      Text(
                        projectCounts(s),
                        key: Key('home-project-${p.uid}-counts'),
                        style: t.type.captionStyle.copyWith(color: t.muted),
                      ),
                      KeyedSubtree(
                        key: Key('home-project-${p.uid}-progress'),
                        child: ProjectProgressBar(s.progress),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final projectsCard = projects.isEmpty
        ? null
        : SectionCard(
            key: const Key('home-projects'),
            title: 'Projects',
            children: [
              ...projects.map(projectRow),
              // One visible placeholder line: project data that comes later.
              Padding(
                padding: EdgeInsets.only(left: t.space.xs, top: t.space.sm),
                child: Text(
                  'Placeholder — Status, due date and members come with the '
                  'project Overview.',
                  key: const Key('placeholder-project-fields'),
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              ),
            ],
          );

    // --- Personal lists: loose items only, through the "is this mine" seam ---
    bool loose(String uid) => !state.inProjectsLayer(uid);
    final personal = state.personalContainer?.uid;
    final looseTasks = [
      for (final k in open)
        if (loose(k.uid) && state.isMine(k)) k,
    ];
    final looseNotes = [
      for (final n in state.notes)
        if (!AppState.isFolder(n) &&
            n.uid != personal &&
            loose(n.uid) &&
            state.isMine(n))
          n,
    ];
    final looseEvents = [
      for (final e in state.events)
        if (loose(e.uid) && state.isMine(e)) e,
    ];

    // Home is personal: "See all" drops any leftover project scope first, so
    // the list matches the heading.
    void seeAll(Section section) => state.guarded(() {
      state.openFolder(null);
      state.setSection(section);
    });

    Widget taskRow(Task k) {
      final day = taskDueDay(k);
      final overdue = isTaskOverdue(k, clock);
      final when = day == null
          ? ''
          : overdue
          ? 'Overdue'
          : dayLabel(day);
      return row(
        'home-task-${k.uid}',
        k.uid,
        'tasks',
        (mode) => state.openNote(k.uid, mode: mode),
        FTappable(
          onPress: () => state.clickTask(k.uid),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: t.space.xs,
              vertical: t.space.sm,
            ),
            child: Row(
              children: [
                Icon(FLucideIcons.listChecks, size: t.icons.md, color: t.muted),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: OverflowTip(
                    k.summary.isEmpty ? 'Untitled' : k.summary,
                    style: t.type.bodyStyle,
                  ),
                ),
                if (when.isNotEmpty) ...[
                  SizedBox(width: t.space.sm),
                  Text(
                    when,
                    style: t.type.captionStyle.copyWith(
                      color: overdue ? t.statusBlocked : t.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final tasksCard = SectionCard(
      key: const Key('home-personal-tasks'),
      title: 'Personal tasks',
      action: _SeeAll(
        key: const Key('home-tasks-all'),
        label: 'See all',
        onPress: () => seeAll(Section.tasks),
      ),
      children: [
        if (looseTasks.isEmpty)
          EmptyState('Nothing loose to do', key: const Key('home-tasks-empty'))
        else
          ...looseTasks.take(preview).map(taskRow),
      ],
    );

    // --- Personal calendar: loose events and loose dated tasks, soonest first ---
    final today0 = wallDay(wallNow(clock));
    final calendarRows =
        <({DateTime at, String id, String uid, Widget child})>[];
    for (final g in upcomingGroups(looseEvents, clock, 7)) {
      for (final o in g.items) {
        calendarRows.add((
          at: o.start,
          id: 'home-cal-${eventRowId(o)}',
          uid: o.event.uid,
          child: EventRow(state: state, occurrence: o, showDay: true),
        ));
      }
    }
    for (final k in looseTasks) {
      final day = taskDueDay(k);
      if (day == null || day.isBefore(today0)) continue;
      calendarRows.add((
        at: day,
        id: 'home-cal-task-${k.uid}',
        uid: k.uid,
        child: TaskDueRow(state: state, task: k, showDay: true),
      ));
    }
    calendarRows.sort((a, b) => a.at.compareTo(b.at));

    final calendarCard = SectionCard(
      key: const Key('home-personal-calendar'),
      title: 'Personal calendar',
      action: _SeeAll(
        key: const Key('home-calendar-all'),
        label: 'See all',
        onPress: () => seeAll(Section.events),
      ),
      children: [
        if (calendarRows.isEmpty)
          EmptyState('Nothing coming up', key: const Key('home-calendar-empty'))
        else
          for (final c in calendarRows.take(preview))
            row(
              c.id,
              c.uid,
              'calendar',
              (mode) => state.openNote(c.uid, mode: mode),
              c.child,
            ),
      ],
    );

    // --- Recently modified: loose notes and tasks ---
    final recent = <({DateTime at, String uid, String title, IconData icon})>[
      for (final n in looseNotes)
        (
          at: n.lastModified ?? n.dtstamp,
          uid: n.uid,
          title: n.summary,
          icon: FLucideIcons.fileText,
        ),
      for (final k in state.tasks)
        if (loose(k.uid) && state.isMine(k))
          (
            at: k.lastModified ?? k.dtstamp,
            uid: k.uid,
            title: k.summary,
            icon: FLucideIcons.listChecks,
          ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    final recentCard = SectionCard(
      key: const Key('home-recent'),
      title: 'Recently modified',
      children: [
        if (recent.isEmpty)
          EmptyState('Nothing changed yet', key: const Key('home-recent-empty'))
        else
          for (final i in recent.take(preview))
            row(
              'home-recent-${i.uid}',
              i.uid,
              'recent',
              (mode) => state.openNote(i.uid, mode: mode),
              FTappable(
                onPress: () => state.clickNote(i.uid),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: t.space.xs,
                    vertical: t.space.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(i.icon, size: t.icons.md, color: t.muted),
                      SizedBox(width: t.space.sm),
                      Expanded(
                        child: OverflowTip(
                          i.title.isEmpty ? 'Untitled' : i.title,
                          style: t.type.bodyStyle,
                        ),
                      ),
                      SizedBox(width: t.space.sm),
                      Text(
                        dayLabel(wallDay(wallNow(i.at))),
                        style: t.type.captionStyle.copyWith(color: t.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );

    state.nav.homeStacked = true;
    // Only the visible view publishes rows: the calendar grid has no keyboard
    // cursor of its own yet.
    state.nav.publish(
      KeyNav.homeList,
      state.homeView == HomeView.calendar ? const [] : navRows,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.xl, t.space.lg, t.space.xl, 0),
          child: Segmented<HomeView>(
            key: const Key('home-tabs'),
            value: state.homeView,
            fullWidth: narrowLayout(context),
            onChanged: state.setHomeView,
            segments: const [
              Segment(
                HomeView.overview,
                'Overview',
                'home-tab-overview',
                icon: FLucideIcons.layoutDashboard,
              ),
              Segment(
                HomeView.calendar,
                'Calendar',
                'home-tab-calendar',
                icon: FLucideIcons.calendar,
              ),
            ],
          ),
        ),
        SizedBox(height: t.space.sm),
        Expanded(
          child: state.homeView == HomeView.calendar
              ? CalendarView(state: state, now: now)
              : SingleChildScrollView(
                  key: const Key('home-page'),
                  padding: EdgeInsets.fromLTRB(
                    t.space.xl,
                    t.space.lg,
                    t.space.xl,
                    fabInset(context) + t.space.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: t.space.lg,
                    children: [
                      tiles,
                      PlaceholderCard(
                        name: 'inbox',
                        title: 'Inbox',
                        willBe:
                            'Unfiled captures you assign onwards (to a project, a '
                            'task, or a note). Capture box now, share-to-app later.',
                      ),
                      ?projectsCard,
                      tasksCard,
                      calendarCard,
                      recentCard,
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({super.key, required this.label, required this.onPress});
  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return FTappable(
      behavior: HitTestBehavior.opaque,
      onPress: onPress,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: narrowLayout(context) ? t.sizes.touchTarget : 0,
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: t.type.captionStyle.copyWith(color: t.accent),
          ),
        ),
      ),
    );
  }
}
