import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../state/task_rules.dart';
import '../theme/tokens.dart';
import 'events_panel.dart';
import 'home_board.dart';
import 'overflow_tip.dart';
import 'placeholder_card.dart';
import 'section_registry.dart' show projectViews;
import 'sections.dart' show NotesSection;
import 'segmented.dart';
import 'empty_state.dart';
import 'card_box.dart';
import 'section_card.dart';
import 'count_badge.dart';
import 'theme.dart';

/// A project's page in the main area: a switcher across its views (Overview,
/// Board, Notes, Calendar) and, on Overview, a summary built from what
/// already exists (progress, coming up, recent). Everything new is a marked
/// placeholder: About, the details and milestones.
///
/// The page needs a real project in scope; [AppState.section] is
/// [Section.overview] for every tab, so the switcher never changes the side
/// panel. Board is the unified board (already scoped by [AppState.scopeUid]);
/// Notes and Calendar reuse the panels' scoped lists.
class ProjectOverviewPage extends StatelessWidget {
  const ProjectOverviewPage({super.key, required this.state, this.now});
  final AppState state;

  /// Clock override for tests.
  final DateTime? now;

  static ProjectTab tabOf(String viewId) => switch (viewId) {
    'board' => ProjectTab.board,
    'notes' => ProjectTab.notes,
    'events' => ProjectTab.calendar,
    _ => ProjectTab.overview,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final t = tokensOf(context);
    final clock = now ?? DateTime.now();
    final ix = state.projectIndex;
    final scopeUid = state.scopeUid;
    final projectUid = scopeUid == null
        ? null
        : ix.projectOf(scopeUid)?.uid ?? scopeUid;
    final tab = projectUid == null
        ? ProjectTab.overview
        : state.projectTab(projectUid);
    final counts = projectUid == null
        ? null
        : state.projectTaskCounts(projectUid, clock);

    Widget tabBody() => switch (tab) {
      ProjectTab.overview => _OverviewTab(
        state: state,
        clock: clock,
        counts: counts,
      ),
      // The tab bodies keep local state (scroll, filters): the outer key
      // changes with the project so nothing leaks from one project to the
      // next. The inner keys stay stable for tests and callers.
      ProjectTab.board => KeyedSubtree(
        key: ValueKey('proj-board-$projectUid'),
        child: KeyedSubtree(
          key: const Key('proj-board-tab'),
          child: _BoardTab(state: state),
        ),
      ),
      ProjectTab.notes => KeyedSubtree(
        key: ValueKey('proj-notes-$projectUid'),
        child: KeyedSubtree(
          key: const Key('proj-notes-tab'),
          child: NotesSection(state: state, onPick: () {}, scoped: true),
        ),
      ),
      ProjectTab.calendar => KeyedSubtree(
        key: ValueKey('proj-calendar-$projectUid'),
        child: KeyedSubtree(
          key: const Key('proj-calendar-tab'),
          child: EventsPanel(state: state, scoped: true),
        ),
      ),
    };

    return Column(
      key: const Key('proj-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.xl, t.space.lg, t.space.xl, 0),
          child: Segmented<ProjectTab>(
            key: const Key('proj-tabs'),
            value: tab,
            fullWidth: narrowLayout(context),
            onChanged: (v) {
              if (projectUid != null) state.setProjectTab(projectUid, v);
            },
            segments: [
              for (final v in projectViews)
                Segment<ProjectTab>(
                  tabOf(v.id),
                  v.label,
                  'proj-tab-${v.id}',
                  icon: v.icon,
                ),
            ],
          ),
        ),
        SizedBox(height: t.space.sm),
        Expanded(child: tabBody()),
      ],
    );
  }
}

/// The Overview tab: About, Progress, Coming up, Details, Milestones, Recent.
/// Wide: two columns (the summary and what is coming up left, the details
/// right); narrow: one column in that order.
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.state,
    required this.clock,
    required this.counts,
  });
  final AppState state;
  final DateTime clock;
  final ({
    int total,
    int done,
    int open,
    int overdue,
    Map<String, int> byStatus,
  })?
  counts;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final open = state.openTasks(clock);
    final notes = state.notesInScope;
    final allTasks = state.scopedTasks;
    final events = state.scopedEvents;
    final about = const PlaceholderCard(
      name: 'project-about',
      title: 'About',
      willBe: 'Description, edited in place.',
    );
    final progress = _Progress(counts: counts);
    final comingUp = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: t.space.lg,
      children: [
        _Tasks(state: state, tasks: open, now: clock),
        _Upcoming(state: state, tasks: open, events: events, now: clock),
      ],
    );
    final details = _Details(counts: counts);
    const milestones = PlaceholderCard(
      name: 'project-milestones',
      title: 'Milestones',
      willBe: 'Milestones are not built yet.',
    );
    final recent = _Recent(
      state: state,
      notes: notes,
      tasks: allTasks,
      events: events,
      now: clock,
    );
    return SingleChildScrollView(
      key: const Key('overview-page'),
      padding: EdgeInsets.fromLTRB(
        t.space.xl,
        t.space.md,
        t.space.xl,
        fabInset(context) + t.space.xl,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final twoUp = c.maxWidth >= Tokens.stackBreakpoint;
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: t.space.lg,
            children: [about, progress, comingUp],
          );
          final right = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: t.space.lg,
            children: [details, milestones, recent],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: t.space.lg,
            children: [
              if (twoUp)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: t.space.lg,
                  children: [
                    Expanded(child: summary),
                    Expanded(child: right),
                  ],
                )
              else ...[
                about,
                progress,
                details,
                milestones,
                comingUp,
                recent,
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Progress is real and derived: percent, done over total tasks, overdue, and
/// a bar by the fixed status set. The due-date line is the one placeholder.
class _Progress extends StatelessWidget {
  const _Progress({required this.counts});
  final ({
    int total,
    int done,
    int open,
    int overdue,
    Map<String, int> byStatus,
  })?
  counts;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final c = counts;
    final total = c?.total ?? 0;
    final done = c?.done ?? 0;
    final overdue = c?.overdue ?? 0;
    final percent = total == 0 ? 0 : (done * 100 / total).round();
    final by = c?.byStatus ?? const <String, int>{};
    const known = {'backlog', 'todo', 'doing', 'blocked', 'review', 'done'};
    final other = by.entries
        .where((e) => !known.contains(e.key))
        .fold(0, (a, e) => a + e.value);
    final segments = <(String, String, Color, int)>[
      ('backlog', 'Backlog', t.muted, by['backlog'] ?? 0),
      ('todo', 'To Do', t.statusTodo, (by['todo'] ?? 0) + other),
      (
        'doing',
        'In Progress',
        t.statusDoing,
        (by['doing'] ?? 0) + (by['blocked'] ?? 0),
      ),
      ('review', 'Review', t.muted, by['review'] ?? 0),
      ('done', 'Done', t.statusDone, by['done'] ?? 0),
    ];
    final muted = t.type.captionStyle.copyWith(color: t.muted);
    return SectionCard(
      key: const Key('proj-progress'),
      title: 'Progress',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$percent%',
              key: const Key('proj-percent'),
              style: t.type.titleStyle,
            ),
            SizedBox(width: t.space.md),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: t.space.xxs),
                child: Text(
                  '$done of $total tasks done',
                  key: const Key('proj-done-line'),
                  style: muted,
                ),
              ),
            ),
          ],
        ),
        if (overdue > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: CountBadge(
              overdue,
              key: const Key('proj-overdue-badge'),
              tone: BadgeTone.danger,
              text: '$overdue overdue',
            ),
          ),
        SizedBox(height: t.space.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(t.radii.small),
          child: Row(
            children: [
              for (final s in segments)
                if (s.$4 > 0)
                  Expanded(
                    flex: s.$4,
                    child: Container(
                      key: Key('proj-bar-${s.$1}'),
                      height: t.sizes.progressBar,
                      color: s.$3,
                    ),
                  ),
            ],
          ),
        ),
        SizedBox(height: t.space.xs),
        Wrap(
          spacing: t.space.md,
          runSpacing: t.space.xxs,
          children: [
            for (final s in segments)
              if (s.$4 > 0)
                Text(
                  '${s.$2} ${s.$4}',
                  key: Key('proj-count-${s.$1}'),
                  style: muted,
                ),
          ],
        ),
        SizedBox(height: t.space.xs),
        Text(
          'Days until due needs a project due date.',
          key: const Key('proj-placeholder-due'),
          style: muted,
        ),
      ],
    );
  }
}

/// The project fields that come later: Status shows a derived word, the rest
/// are marked placeholders.
class _Details extends StatelessWidget {
  const _Details({required this.counts});
  final ({
    int total,
    int done,
    int open,
    int overdue,
    Map<String, int> byStatus,
  })?
  counts;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final total = counts?.total ?? 0;
    final done = counts?.done ?? 0;
    final status = total == 0
        ? 'No tasks yet'
        : done == total
        ? 'Done'
        : done == 0
        ? 'Not started'
        : 'In progress';
    final muted = t.type.captionStyle.copyWith(color: t.muted);
    Widget row(String id, String label, String value, {bool derived = false}) =>
        Padding(
          padding: EdgeInsets.symmetric(vertical: t.space.xxs),
          child: Row(
            children: [
              SizedBox(
                width: t.sizes.statLabel,
                child: Text(label, style: muted),
              ),
              Expanded(
                child: Text(
                  value,
                  key: Key('proj-detail-$id'),
                  style: derived
                      ? t.type.bodyStyle
                      : t.type.captionStyle.copyWith(color: t.muted),
                ),
              ),
            ],
          ),
        );
    return SectionCard(
      key: const Key('proj-details'),
      title: 'Details',
      children: [
        row('status', 'Status', status, derived: true),
        row('lead', 'Lead', 'Placeholder'),
        row('team', 'Team', 'Placeholder'),
        row('start', 'Start', 'Placeholder'),
        row('due', 'Due', 'Placeholder'),
        row('members', 'Members', 'Placeholder'),
      ],
    );
  }
}

/// The project Board tab: the unified board, with its keyboard rows
/// published like Home's board used to.
class _BoardTab extends StatelessWidget {
  const _BoardTab({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      publishBoardNav(state);
      state.nav.homeStacked = false;
      return HomeBoard(state: state);
    },
  );
}

/// One number for [StatTiles]: [id] is used in its keys.
class StatTileData {
  const StatTileData(this.id, this.label, this.value);
  final String id, label;
  final int value;
}

/// The metric tiles shared by the project Overview and Home: a row on a wide
/// card, wrapped on a phone. [keyPrefix] keeps each page's keys distinct
/// (`overview-tile-<id>`, `home-tile-<id>`).
class StatTiles extends StatelessWidget {
  const StatTiles({
    super.key,
    required this.stats,
    this.keyPrefix = 'overview-tile',
    this.tilesKey,
  });
  final List<StatTileData> stats;
  final String keyPrefix;
  final Key? tilesKey;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Wrap(
      key: tilesKey,
      spacing: t.space.sm,
      runSpacing: t.space.sm,
      children: [
        for (final s in stats) _Tile(keyPrefix, s.id, s.label, s.value),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.keyPrefix, this.id, this.label, this.value);
  final String keyPrefix, id, label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return CardBox(
      key: Key('$keyPrefix-$id'),
      variant: CardVariant.tile,
      constraints: BoxConstraints(minWidth: t.sizes.tileMin),
      padding: EdgeInsets.symmetric(
        horizontal: t.space.md,
        vertical: t.space.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            key: Key('$keyPrefix-$id-value'),
            style: t.type.titleStyle,
          ),
          Text(label, style: t.type.captionStyle.copyWith(color: t.muted)),
        ],
      ),
    );
  }
}

/// One block: a small capitalised heading, then a body (or its empty state).
class _Block extends StatelessWidget {
  const _Block({
    required this.id,
    required this.title,
    required this.empty,
    required this.children,
    this.emptyKey,
  });
  final String id, title;

  /// The line shown when [children] is empty.
  final String empty;
  final String? emptyKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Column(
      key: Key('overview-$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: t.space.xs),
          child: Text(
            title.toUpperCase(),
            style: t.type.labelStyle.copyWith(color: t.muted),
          ),
        ),
        if (children.isEmpty)
          EmptyState(empty, key: emptyKey == null ? null : Key(emptyKey!))
        else
          ...children,
      ],
    );
  }
}

/// A plain row: an icon, the title, a quiet second line; a tap opens it.
class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    this.note,
    required this.onPress,
  });
  final IconData icon;
  final String title;
  final String? note;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return FTappable(
      onPress: onPress,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: t.space.xs,
          vertical: t.space.sm,
        ),
        child: Row(
          children: [
            Icon(icon, size: t.icons.md, color: t.muted),
            SizedBox(width: t.space.sm),
            Expanded(
              child: OverflowTip(
                title.isEmpty ? 'Untitled' : title,
                style: t.type.bodyStyle,
              ),
            ),
            if (note != null) ...[
              SizedBox(width: t.space.sm),
              Text(note!, style: t.type.captionStyle.copyWith(color: t.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The project's open tasks, soonest due first (the order [AppState.openTasks]
/// keeps); the first few here, the rest through the Tasks section.
class _Tasks extends StatelessWidget {
  const _Tasks({required this.state, required this.tasks, required this.now});
  final AppState state;
  final List<Task> tasks;
  final DateTime now;

  static const limit = 8;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final today = wallDay(wallNow(now));
    String when(Task k) {
      final day = taskDueDay(k);
      if (day == null) return '';
      final d = day.difference(today).inDays;
      if (isTaskOverdue(k, now)) return 'Overdue';
      return d == 0
          ? 'Today'
          : d == 1
          ? 'Tomorrow'
          : dayLabel(day);
    }

    return _Block(
      id: 'tasks',
      title: 'Tasks',
      empty: 'No open tasks',
      emptyKey: 'overview-tasks-empty',
      children: [
        for (final k in tasks.take(limit))
          _Row(
            key: Key('overview-task-${k.uid}'),
            icon: FLucideIcons.listChecks,
            title: k.summary,
            note: when(k),
            onPress: () => state.clickTask(k.uid),
          ),
        if (tasks.length > limit)
          Padding(
            padding: EdgeInsets.only(top: t.space.xs),
            child: FTappable(
              key: const Key('overview-tasks-more'),
              onPress: () {
                final p = state.mainProjectUid;
                if (p != null) state.setProjectTab(p, ProjectTab.board);
              },
              builder: (_, _, _) => Text(
                '+${tasks.length - limit} more on the Board',
                style: t.type.captionStyle.copyWith(color: t.muted),
              ),
            ),
          ),
      ],
    );
  }
}

/// Today, Tomorrow and This week: the agenda's own rows for the project's
/// events and for its tasks with a due date, grouped with [upcomingGroups].
/// The Calendar's tag filters do not narrow the Overview.
class _Upcoming extends StatelessWidget {
  const _Upcoming({
    required this.state,
    required this.tasks,
    required this.events,
    required this.now,
  });
  final AppState state;

  /// The project's open tasks and events; the Calendar's tag filter is not
  /// the Overview's business.
  final List<Task> tasks;
  final List<Event> events;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final groups = upcomingGroups(events, now, 7);
    final today0 = wallDay(wallNow(now));
    final tasks = <String, List<Task>>{'today': [], 'tomorrow': [], 'week': []};
    for (final k in this.tasks) {
      final day = taskDueDay(k);
      if (day == null) continue;
      final d = day.difference(today0).inDays;
      if (d < 0) continue;
      final id = d == 0
          ? 'today'
          : d == 1
          ? 'tomorrow'
          : d < 7
          ? 'week'
          : null;
      if (id != null) tasks[id]!.add(k);
    }
    final children = <Widget>[];
    for (final g in groups) {
      final rows = <Widget>[];
      for (final o in g.items) {
        rows.add(EventRow(state: state, occurrence: o, showDay: true));
      }
      for (final k in tasks[g.id] ?? const <Task>[]) {
        rows.add(TaskDueRow(state: state, task: k, showDay: true));
      }
      if (rows.isEmpty) continue;
      children.add(
        Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : t.space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                g.label,
                style: t.type.captionStyle.copyWith(color: t.muted),
              ),
              ...rows,
            ],
          ),
        ),
      );
    }
    return _Block(
      id: 'upcoming',
      title: 'Upcoming',
      empty: 'Nothing coming up',
      emptyKey: 'overview-upcoming-empty',
      children: children,
    );
  }
}

/// The most recently changed notes, tasks and events of the project, newest
/// first; who changed them is not kept.
class _Recent extends StatelessWidget {
  const _Recent({
    required this.state,
    required this.notes,
    required this.tasks,
    required this.events,
    required this.now,
  });
  final AppState state;
  final List<Note> notes;
  final List<Task> tasks;
  final List<Event> events;
  final DateTime now;

  static const limit = 6;

  @override
  Widget build(BuildContext context) {
    final items = <({String uid, String title, IconData icon, DateTime at})>[
      for (final n in notes)
        (
          uid: n.uid,
          title: n.summary,
          icon: FLucideIcons.fileText,
          at: n.lastModified ?? n.dtstamp,
        ),
      for (final k in tasks)
        (
          uid: k.uid,
          title: k.summary,
          icon: FLucideIcons.listChecks,
          at: k.lastModified ?? k.dtstamp,
        ),
      for (final e in events)
        (
          uid: e.uid,
          title: e.summary,
          icon: FLucideIcons.calendar,
          at: e.lastModified ?? e.dtstamp,
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    final today = wallDay(wallNow(now));
    return _Block(
      id: 'recent',
      title: 'Recent activity',
      empty: 'Nothing changed yet',
      emptyKey: 'overview-recent-empty',
      children: [
        for (final i in items.take(limit))
          _Row(
            key: Key('overview-recent-${i.uid}'),
            icon: i.icon,
            title: i.title,
            note: dayLabel(wallDay(wallNow(i.at)), today),
            onPress: () => state.clickNote(i.uid),
          ),
      ],
    );
  }
}
