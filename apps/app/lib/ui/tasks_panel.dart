import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import '../state/note_drag.dart';
import '../state/task_rules.dart';
import 'collapsible_section.dart';
import 'key_nav_ui.dart';
import 'panel_tags_drawer.dart';
import 'parts.dart';
import 'side_panel.dart';
import 'task_parts.dart';
import 'theme.dart';

/// The Tasks side panel section: every task of the Space in collapsible
/// groups (Overdue, Today, Upcoming, No date, Completed), with quick add on
/// top and filters for status, tag and parent folder. A row opens the task
/// like a note (peek or main, per the open setting). [onPick] runs after an
/// open, to close the narrow sheet.
class TasksPanel extends StatelessWidget {
  const TasksPanel({super.key, required this.state, this.onPick, this.now});
  final AppState state;
  final VoidCallback? onPick;

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
        state.nav.publish('tasks', [
          for (final g in groups)
            for (final k in g.$3)
              NavEntry(
                k.uid,
                uid: k.uid,
                hidden: () =>
                    state.prefs?.read('davdart.tasks.${g.$1}.collapsed.v1') ==
                    'true',
                open: (mode) async {
                  await state.openNote(k.uid, mode: mode);
                  onPick?.call();
                },
              ),
        ]);
        return SidePanelFrame(
          title: const SidePanelTitle('Tasks'),
          actions: state.tasksEditable
              ? IconAction(
                  compact: true,
                  key: const Key('new-task'),
                  tooltip: 'New task',
                  icon: FLucideIcons.plus,
                  onPress: () async {
                    final uid = await state.addTask('New task');
                    if (uid == null) return;
                    await state.clickTask(uid);
                    onPick?.call();
                  },
                )
              : null,
          body: PanelTagsDrawer(
            keyPrefix: 'tasks-tags',
            tags: state.taskTags,
            selected: state.taskTagFilter,
            onSelect: state.setTaskTagFilter,
            expanded: state.taskTagsExpanded,
            onExpandedChange: state.setTaskTagsOpen,
            body: Column(
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
                    scrollCacheExtent: navCacheExtent,
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
                        _Note(
                          'No tasks match',
                          key: const Key('tasks-no-match'),
                        ),
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
                                    NavRow(
                                      key: ValueKey('nav-tasks-${k.uid}'),
                                      nav: state.nav,
                                      list: 'tasks',
                                      id: k.uid,
                                      child: TaskRow(
                                        key: Key('task-row-${k.uid}'),
                                        state: state,
                                        task: k,
                                        now: clock,
                                        showTags: true,
                                        source: NoteDragSource.list,
                                        onOpen: onPick,
                                      ),
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
    final folder = state.taskFolderFilter;
    return Wrap(
      spacing: t.space.md,
      runSpacing: t.space.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        toggle('Open', TaskFilter.open),
        toggle('All', TaskFilter.all),
        toggle('Completed', TaskFilter.completed),
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
