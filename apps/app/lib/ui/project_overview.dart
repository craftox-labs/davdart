import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../state/task_rules.dart';
import '../theme/tokens.dart';
import 'events_panel.dart';
import 'overflow_tip.dart';
import 'theme.dart';

/// A project's page in the main area: what the project holds, its open tasks,
/// what is coming (tasks with a due date and events, reusing the agenda's
/// rows) and the items changed last. No new data: every number and list is
/// derived from the Space's notes, tasks and events, narrowed to the project
/// in scope.
///
/// Below [Tokens.stackBreakpoint] the blocks stack in one column; a wider
/// window sets the blocks beside each other.
class ProjectOverviewPage extends StatelessWidget {
  const ProjectOverviewPage({super.key, required this.state, this.now});
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
        final scope = state.scope;
        final open = state.openTasks(clock);
        final overdue = state.overdueTasks(clock);
        final notes = state.notesInScope;
        final events = state.scopedEvents;
        final tiles = _Tiles(
          open: open.length,
          overdue: overdue.length,
          done: state.doneThisWeek(clock).length,
          notes: notes.length,
          events: events.length,
        );
        final tasks = _Tasks(state: state, tasks: open);
        final upcoming = _Upcoming(state: state, now: clock);
        final recent = _Recent(state: state, now: clock);
        return SingleChildScrollView(
          key: const Key('overview-page'),
          padding: EdgeInsets.fromLTRB(
            t.space.xl,
            t.space.lg,
            t.space.xl,
            fabInset(context) + t.space.xl,
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final twoUp = c.maxWidth >= Tokens.stackBreakpoint;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: t.space.lg,
                children: [
                  Text(
                    scope == null || scope.summary.isEmpty
                        ? 'Overview'
                        : scope.summary,
                    key: const Key('overview-title'),
                    style: t.type.titleStyle,
                  ),
                  tiles,
                  if (twoUp)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: t.space.lg,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: t.space.lg,
                            children: [tasks, upcoming],
                          ),
                        ),
                        Expanded(child: recent),
                      ],
                    )
                  else ...[
                    tasks,
                    upcoming,
                    recent,
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// The five numbers, in a row on a wide card and wrapped on a phone.
class _Tiles extends StatelessWidget {
  const _Tiles({
    required this.open,
    required this.overdue,
    required this.done,
    required this.notes,
    required this.events,
  });
  final int open, overdue, done, notes, events;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Wrap(
      key: const Key('overview-tiles'),
      spacing: t.space.sm,
      runSpacing: t.space.sm,
      children: [
        _Tile('open', 'Open tasks', open),
        _Tile('overdue', 'Overdue', overdue),
        _Tile('done', 'Done this week', done),
        _Tile('notes', 'Notes', notes),
        _Tile('events', 'Events', events),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.id, this.label, this.value);
  final String id, label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      key: Key('overview-tile-$id'),
      constraints: BoxConstraints(minWidth: t.sizes.touchTarget * 2),
      padding: EdgeInsets.symmetric(
        horizontal: t.space.md,
        vertical: t.space.sm,
      ),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.panelBorder, width: t.borders.hairline),
        borderRadius: BorderRadius.circular(t.radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            key: Key('overview-tile-$id-value'),
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
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.xs),
            child: Text(
              empty,
              key: emptyKey == null ? null : Key(emptyKey!),
              style: t.type.captionStyle.copyWith(color: t.muted),
            ),
          )
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
                title.isEmpty ? '(untitled)' : title,
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
  const _Tasks({required this.state, required this.tasks});
  final AppState state;
  final List<Task> tasks;

  static const limit = 8;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final today = wallDay(wallNow(DateTime.now()));
    String when(Task k) {
      final day = taskDueDay(k);
      if (day == null) return '';
      final d = day.difference(today).inDays;
      if (isTaskOverdue(k, DateTime.now())) return 'Overdue';
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
            child: Text(
              '+${tasks.length - limit} more in Tasks',
              style: t.type.captionStyle.copyWith(color: t.muted),
            ),
          ),
      ],
    );
  }
}

/// Today, Tomorrow and This week: the agenda's own rows for events and for
/// tasks with a due date, taken from the same grouping the Calendar uses.
class _Upcoming extends StatelessWidget {
  const _Upcoming({required this.state, required this.now});
  final AppState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final groups = state.upcomingOccurrences(now, 7);
    final today0 = wallDay(wallNow(now));
    final tasks = <String, List<Task>>{'today': [], 'tomorrow': [], 'week': []};
    for (final k in state.openTasks(now)) {
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
  const _Recent({required this.state, required this.now});
  final AppState state;
  final DateTime now;

  static const limit = 6;

  @override
  Widget build(BuildContext context) {
    final items = <({String uid, String title, IconData icon, DateTime at})>[
      for (final n in state.notesInScope)
        (
          uid: n.uid,
          title: n.summary,
          icon: FLucideIcons.fileText,
          at: n.lastModified ?? n.dtstamp,
        ),
      for (final k in state.scopedTasks)
        (
          uid: k.uid,
          title: k.summary,
          icon: FLucideIcons.listChecks,
          at: k.lastModified ?? k.dtstamp,
        ),
      for (final e in state.scopedEvents)
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
      title: 'Recent',
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
