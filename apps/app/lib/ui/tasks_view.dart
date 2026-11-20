import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import '../state/task_rules.dart';
import 'collapsible_section.dart';
import 'content_grid.dart';
import 'task_parts.dart';
import 'theme.dart';

/// The Tasks tab: every task of the Space in collapsible groups (Overdue,
/// Today, Upcoming, No date, Completed), with quick add on top and filters
/// for status, tag and parent folder.
class TasksView extends StatelessWidget {
  const TasksView({super.key, required this.state, this.now});
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
        final keep = {for (final k in state.filteredTasks) k.uid};
        List<Task> pick(List<Task> l) => [
          for (final k in l)
            if (keep.contains(k.uid)) k,
        ];
        final open = pick(state.openTasks(clock));
        final today = DateTime.utc(
          clock.toLocal().year,
          clock.toLocal().month,
          clock.toLocal().day,
        );
        final overdue = [
          for (final k in open)
            if (isTaskOverdue(k, clock)) k,
        ];
        final due = [
          for (final k in open)
            if (!isTaskOverdue(k, clock) &&
                taskDueDay(k) != null &&
                taskDueDay(k) == today)
              k,
        ];
        final upcoming = [
          for (final k in open)
            if (!isTaskOverdue(k, clock) &&
                taskDueDay(k) != null &&
                taskDueDay(k) != today)
              k,
        ];
        final undated = [
          for (final k in open)
            if (k.due == null || taskDueDay(k) == null) k,
        ];
        final closed = [
          ...pick(state.completedTasks()),
          for (final k in state.filteredTasks)
            if (k.isCancelled) k,
        ];
        final f = state.taskFilter;
        final groups = <(String, String, List<Task>)>[
          if (f != TaskFilter.completed) ...[
            ('overdue', 'Overdue', overdue),
            ('today', 'Today', due),
            ('upcoming', 'Upcoming', upcoming),
            ('no-date', 'No date', undated),
          ],
          if (f != TaskFilter.open) ('completed', 'Completed', closed),
        ];
        final shown = [for (final g in groups) ...g.$3];
        return ContentCap(
          child: Column(
            key: const Key('tasks-view'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  t.space.lg,
                  t.space.md,
                  t.space.lg,
                  t.space.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: t.space.md,
                  children: [
                    TaskQuickAdd(state: state),
                    _Filters(state: state),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    t.space.lg,
                    0,
                    t.space.lg,
                    t.space.huge,
                  ),
                  children: [
                    if (state.tasks.isEmpty)
                      _Note('No tasks yet', key: const Key('tasks-empty'))
                    else if (shown.isEmpty)
                      _Note('No tasks match', key: const Key('tasks-no-match')),
                    for (final g in groups)
                      if (g.$3.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: t.space.md),
                          child: CollapsibleSection(
                            id: 'tasks-${g.$1}',
                            title: g.$2,
                            upper: false,
                            count: g.$3.length,
                            prefs: state.prefs,
                            prefKey: 'davdart.tasks.${g.$1}.collapsed.v1',
                            headerPadding: EdgeInsets.all(t.space.xs),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final k in g.$3)
                                  TaskRow(
                                    key: Key('task-row-${k.uid}'),
                                    state: state,
                                    task: k,
                                    now: clock,
                                    showTags: true,
                                    source: NoteDragSource.list,
                                  ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      padding: EdgeInsets.all(t.space.md),
      child: Text(text, style: t.type.captionStyle.copyWith(color: t.muted)),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    Widget toggle(String label, TaskFilter v) => FButton(
      key: Key('tasks-filter-${v.name}'),
      variant: state.taskFilter == v
          ? FButtonVariant.secondary
          : FButtonVariant.outline,
      size: FButtonSizeVariant.xs,
      mainAxisSize: MainAxisSize.min,
      selected: state.taskFilter == v,
      onPress: () => state.setTaskFilter(v),
      child: Text(label),
    );
    // Folders (any depth) the scope filter can pick, indented like the tree.
    final folders = <(String, String, int)>[];
    void walk(List<NoteNode> nodes, int depth) {
      for (final n in nodes) {
        if (AppState.isFolder(n.note)) {
          folders.add((n.note.uid, n.note.summary, depth));
        }
        walk(n.children, depth + 1);
      }
    }

    walk(state.tree.roots, 0);
    final tags = state.taskTags;
    final folder = state.taskFolderFilter;
    return Wrap(
      spacing: t.space.md,
      runSpacing: t.space.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        toggle('Open', TaskFilter.open),
        toggle('All', TaskFilter.all),
        toggle('Completed', TaskFilter.completed),
        if (tags.isNotEmpty)
          SizedBox(
            width: t.sizes.statusField,
            child: FSelect<String>.rich(
              key: const Key('tasks-tag-filter'),
              format: (v) => v.isEmpty ? 'All tags' : '#$v',
              control: FSelectControl.lifted(
                value: state.taskTagFilter ?? '',
                onChange: (v) =>
                    state.setTaskTagFilter(v == null || v.isEmpty ? null : v),
              ),
              children: [
                FSelectItem<String>(title: const Text('All tags'), value: ''),
                for (final tag in tags)
                  FSelectItem<String>(title: Text('#$tag'), value: tag),
              ],
            ),
          ),
        if (folders.isNotEmpty)
          SizedBox(
            width: t.sizes.statusField,
            child: FSelect<String>.rich(
              key: const Key('tasks-folder-filter'),
              format: (v) => v.isEmpty
                  ? 'Everywhere'
                  : folders.where((e) => e.$1 == v).firstOrNull?.$2 ?? v,
              control: FSelectControl.lifted(
                value: folder != null && folders.any((e) => e.$1 == folder)
                    ? folder
                    : '',
                onChange: (v) => state.setTaskFolderFilter(
                  v == null || v.isEmpty ? null : v,
                ),
              ),
              children: [
                FSelectItem<String>(title: const Text('Everywhere'), value: ''),
                for (final e in folders)
                  FSelectItem<String>(
                    title: Text(e.$2, overflow: TextOverflow.ellipsis),
                    prefix: SizedBox(width: e.$3 * t.space.lg),
                    value: e.$1,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
