import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../state/key_nav.dart';
import '../state/task_rules.dart';
import 'events_panel.dart';
import 'key_nav_ui.dart';
import 'overflow_tip.dart';
import 'project_overview.dart';
import 'placeholder_card.dart';
import 'projects_panel.dart' show ProjectProgressBar, projectCounts;
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
    final changed = <String, DateTime>{};
    void touch(String uid, DateTime? at) {
      if (at == null) return;
      final p = ix.projectOf(uid);
      if (p == null) return;
      final cur = changed[p.uid];
      if (cur == null || at.isAfter(cur)) changed[p.uid] = at;
    }

    for (final n in state.notes) {
      touch(n.uid, n.lastModified ?? n.dtstamp);
    }
    for (final k in state.tasks) {
      touch(k.uid, k.lastModified ?? k.dtstamp);
    }
    for (final e in state.events) {
      touch(e.uid, e.lastModified ?? e.dtstamp);
    }
    final projects = [...ix.projects()]
      ..sort((a, b) {
        final x = changed[a.uid], y = changed[b.uid];
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return y.compareTo(x);
      });

    Future<void> openProject(String uid) =>
        state.guarded(() => state.openProjectTab(uid));

    Widget projectRow(Note p) {
      final s = ix.statsOf(p.uid);
      final at = changed[p.uid];
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
        : _Card(
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

    // Personal Tasks and Calendar hold loose items, but switching there
    // keeps the open project scope (the panel's own scope); a loose-only
    // list would need a Tasks/Calendar mode of its own.
    void seeAll(Section section) =>
        state.guarded(() => state.setSection(section));

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
                    k.summary.isEmpty ? '(untitled)' : k.summary,
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

    final tasksCard = _Card(
      key: const Key('home-personal-tasks'),
      title: 'Personal tasks',
      action: _SeeAll(
        key: const Key('home-tasks-all'),
        label: 'See all',
        onPress: () => seeAll(Section.tasks),
      ),
      children: [
        if (looseTasks.isEmpty)
          _Empty('Nothing loose to do', key: const Key('home-tasks-empty'))
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

    final calendarCard = _Card(
      key: const Key('home-personal-calendar'),
      title: 'Personal calendar',
      action: _SeeAll(
        key: const Key('home-calendar-all'),
        label: 'See all',
        onPress: () => seeAll(Section.events),
      ),
      children: [
        if (calendarRows.isEmpty)
          _Empty('Nothing coming up', key: const Key('home-calendar-empty'))
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

    final recentCard = _Card(
      key: const Key('home-recent'),
      title: 'Recently modified',
      children: [
        if (recent.isEmpty)
          _Empty('Nothing changed yet', key: const Key('home-recent-empty'))
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
                          i.title.isEmpty ? '(untitled)' : i.title,
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
    state.nav.publish(KeyNav.homeList, navRows);

    return SingleChildScrollView(
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
                'Unfiled captures you assign onwards (to a project, a task, '
                'or a note). Capture box now, share-to-app later.',
          ),
          ?projectsCard,
          tasksCard,
          calendarCard,
          recentCard,
        ],
      ),
    );
  }
}

/// A bordered block of Home with a small capitalised heading and an optional
/// right-hand action.
class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.title,
    required this.children,
    this.action,
  });
  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.radii.card),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: t.space.xs,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: t.type.labelStyle.copyWith(color: t.muted),
                ),
              ),
              ?action,
            ],
          ),
          ...children,
        ],
      ),
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

class _Empty extends StatelessWidget {
  const _Empty(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: Text(text, style: t.type.captionStyle.copyWith(color: t.muted)),
    );
  }
}
