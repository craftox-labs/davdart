import 'package:davdart/davdart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/task_draft.dart';
import '../state/task_rules.dart';
import 'markdown_lite.dart';
import 'parts.dart';
import 'chips.dart';
import 'task_menu.dart';
import 'task_parts.dart';
import 'theme.dart';

const _statusWords = [
  ('todo', 'needs-action'),
  ('doing', 'in-process'),
  ('done', 'completed'),
  ('cancelled', 'cancelled'),
];

/// Priority as the three buckets the editor offers (RFC 5545: 1-4 high,
/// 5 medium, 6-9 low, 0 or none).
String priorityBucket(int? p) => p == null || p <= 0
    ? 'none'
    : p <= 4
    ? 'high'
    : p == 5
    ? 'medium'
    : 'low';

int? priorityOfBucket(String? b) => switch (b) {
  'high' => 1,
  'medium' => 5,
  'low' => 9,
  _ => null,
};

/// The unsaved-edits bar of a task edit.
class TaskEditBar extends StatelessWidget {
  const TaskEditBar({super.key, required this.state, required this.draft});
  final AppState state;
  final TaskDraft draft;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final dirty = draft.dirty;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: t.space.lg,
            vertical: t.space.sm,
          ),
          child: Row(
            children: [
              if (dirty) ...[
                Container(
                  key: const Key('dirty-indicator'),
                  width: t.sizes.statusDot,
                  height: t.sizes.statusDot,
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: t.space.sm),
                Flexible(
                  child: Text(
                    'Unsaved changes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.type.captionStyle.copyWith(color: t.muted),
                  ),
                ),
              ] else
                Text(
                  'Editing',
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              const Spacer(),
              SizedBox(width: t.space.sm),
              FButton(
                key: const Key('edit-discard'),
                variant: FButtonVariant.outline,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: () => state.discardTaskDraft(draft.uid),
                child: Text(dirty ? 'Discard' : 'Done'),
              ),
              SizedBox(width: t.space.sm),
              FButton(
                key: const Key('edit-save'),
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: dirty && !draft.titleEmpty
                    ? () => state.saveTaskDraft(draft.uid)
                    : null,
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The fields of an open task edit: title, due date, priority, tags, parent
/// and description.
class TaskEditor extends StatelessWidget {
  const TaskEditor({
    super.key,
    required this.state,
    required this.draft,
    required this.task,
    required this.full,
  });
  final AppState state;
  final TaskDraft draft;
  final Task task;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    // Where the task can go: top level, any note, or a task that is not it or
    // under it. Notes are indented like the tree.
    final targets = <(String?, String, String, int)>[
      (null, 'Top level', '', 0),
    ];
    void collect(List<NoteNode> nodes, int depth) {
      for (final n in nodes) {
        targets.add((
          n.note.uid,
          n.note.summary,
          AppState.isFolder(n.note) ? '  (folder)' : '',
          depth,
        ));
        collect(n.children, depth + 1);
      }
    }

    collect(state.tree.roots, 0);
    for (final k in state.tasks) {
      if (state.canMoveTask(task.uid, k.uid)) {
        targets.add((k.uid, k.summary, '  (task)', 0));
      }
    }
    final labels = {for (final e in targets) e.$1 ?? '': e.$2};
    final parent = targets.any((e) => e.$1 == draft.parent)
        ? draft.parent
        : null;
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final day = draft.due == null
            ? null
            : taskDueDay(Task(uid: 'x', due: draft.due));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: t.space.lg,
          children: [
            field(
              key: const Key('edit-title'),
              controller: draft.titleController,
              label: 'Title',
              autofocus: true,
              error: draft.titleEmpty ? 'A title is required' : null,
            ),
            FDateField.calendar(
              key: const Key('edit-due'),
              label: const Text('Due'),
              clearable: true,
              hint: 'No due date',
              selectionControl: FDateSelectionControl.liftedSingle(
                value: day,
                onChange: (d) {
                  if (d == null) {
                    draft.setDue(null);
                  } else if (day == null ||
                      DateTime.utc(d.year, d.month, d.day) != day) {
                    draft.setDue(dueOfDay(d));
                  }
                },
              ),
            ),
            FSelect<String>.rich(
              key: const Key('edit-priority'),
              label: const Text('Priority'),
              format: (v) => v,
              control: FSelectControl.lifted(
                value: priorityBucket(draft.priority),
                onChange: (v) {
                  final b = priorityBucket(draft.priority);
                  if (v != null && v != b) {
                    draft.setPriority(priorityOfBucket(v));
                  }
                },
              ),
              children: [
                for (final p in const ['none', 'low', 'medium', 'high'])
                  FSelectItem<String>(title: Text(p), value: p),
              ],
            ),
            field(
              key: const Key('edit-tags'),
              controller: draft.tagsController,
              label: 'Tags (comma separated)',
            ),
            FSelect<String>.rich(
              key: const Key('edit-parent'),
              label: const Text('Inside'),
              format: (v) => labels[v] ?? v,
              control: FSelectControl.lifted(
                value: parent ?? '',
                onChange: (v) =>
                    draft.setParent((v == null || v.isEmpty) ? null : v),
              ),
              children: [
                for (final e in targets)
                  FSelectItem<String>(
                    title: Text(
                      '${e.$2}${e.$3}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    prefix: SizedBox(width: e.$4 * t.space.lg),
                    value: e.$1 ?? '',
                  ),
              ],
            ),
            field(
              key: const Key('edit-body'),
              controller: draft.bodyController,
              minLines: full ? t.sizes.editorLinesFull : t.sizes.editorLines,
              maxLines: null,
              label: 'Description',
            ),
          ],
        );
      },
    );
  }
}

/// The tasks directly under note or task [parentUid]: rows plus a quick add.
/// Shown in a task's page, and in a note's page once it has tasks.
class ChildTasks extends StatelessWidget {
  const ChildTasks({super.key, required this.state, required this.parentUid});
  final AppState state;
  final String parentUid;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final kids = state.tasksByParent(parentUid);
    if (kids.isEmpty && !state.tasksEditable) return const SizedBox.shrink();
    final now = DateTime.now();
    return Column(
      key: Key('child-tasks-$parentUid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: t.space.xs),
          child: Text(
            kids.isEmpty ? 'Tasks' : 'Tasks (${kids.length})',
            style: t.type.labelStyle.copyWith(color: t.muted),
          ),
        ),
        for (final k in kids)
          TaskRow(
            key: Key('child-task-${k.uid}'),
            state: state,
            task: k,
            now: now,
          ),
        SizedBox(height: t.space.sm),
        TaskQuickAdd(
          state: state,
          parentUid: parentUid,
          hint: 'Add a task here…',
        ),
      ],
    );
  }
}

/// A task's page (peek pane or main tab): read view with the status menu, or
/// the editor while a draft is open.
class TaskDetail extends StatelessWidget {
  const TaskDetail({
    super.key,
    required this.state,
    required this.uid,
    required this.onClose,
    this.full = false,
    this.inHeader = false,
  });
  final AppState state;
  final String uid;
  final VoidCallback onClose;
  final bool full;
  final bool inHeader;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final task = state.taskById(uid);
    if (task == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final path = <String>[];
    var cur = task.parentUid;
    for (var i = 0; cur != null && i < 50; i++) {
      final item = state.findItem(cur);
      if (item is Note) {
        path.insert(0, item.summary);
        cur = item.parentUid;
      } else if (item is Task) {
        path.insert(0, item.summary);
        cur = item.parentUid;
      } else {
        break;
      }
    }
    final draft = state.taskDraftFor(uid);
    final edit = state.tasksEditable;
    final status = task.boardStatus;
    final blocked = state.taskCompletionBlockerFor(uid) != null;
    Widget meta(String label, Widget value) => Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: t.sizes.metaLabel,
            child: Text(
              label,
              style: t.type.monoStyle.copyWith(color: t.muted),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
    final parentItem = task.parentUid == null
        ? null
        : state.findItem(task.parentUid!);
    final parentName = parentItem is Note
        ? parentItem.summary
        : parentItem is Task
        ? parentItem.summary
        : null;
    Widget page = Column(
      children: [
        PaneHeaderRow(
          key: const Key('peek-toolbar'),
          startPad: inHeader ? t.space.xxl : t.space.xs,
          children: [
            if (!full && !inHeader)
              IconAction(
                tooltip: 'Close',
                icon: FLucideIcons.arrowLeft,
                onPress: onClose,
              ),
            Expanded(
              child: full
                  ? const SizedBox.shrink()
                  : Text(
                      key: const Key('breadcrumb'),
                      path.join('  /  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.type.captionStyle.copyWith(color: t.muted),
                    ),
            ),
            if (edit) ...[
              if (state.spaces.length > 1)
                IconAction(
                  key: const Key('move-note'),
                  tooltip: 'Move to another space',
                  icon: FLucideIcons.folderInput,
                  onPress: () => showMoveTaskDialog(context, state, task),
                ),
              if (draft == null)
                IconAction(
                  key: const Key('edit-note'),
                  tooltip: 'Edit',
                  icon: FLucideIcons.pencil,
                  onPress: () => state.startTaskEdit(uid),
                ),
              IconAction(
                key: const Key('delete-note'),
                tooltip: 'Delete',
                icon: FLucideIcons.trash2,
                onPress: () => confirmDeleteTask(context, state, task),
              ),
            ],
          ],
        ),
        if (draft != null) TaskEditBar(state: state, draft: draft),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              t.space.xxl,
              t.space.xs,
              t.space.xxl,
              t.space.huge,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: t.sizes.pageMax),
                child: Column(
                  key: const Key('task-detail'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (draft != null)
                      TaskEditor(
                        state: state,
                        draft: draft,
                        task: task,
                        full: full,
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              top: t.space.sm,
                              right: t.space.md,
                            ),
                            child: TaskCheckbox(state: state, task: task),
                          ),
                          Expanded(
                            child: Text(
                              task.summary,
                              style: task.isClosed
                                  ? t.type.displayStyle.copyWith(
                                      color: t.muted,
                                      decoration: TextDecoration.lineThrough,
                                    )
                                  : t.type.displayStyle,
                            ),
                          ),
                        ],
                      ),
                    SizedBox(height: t.space.md),
                    Row(
                      children: [
                        Text('Status', style: TextStyle(color: t.muted)),
                        SizedBox(width: t.space.lg),
                        if (edit)
                          SizedBox(
                            width: t.sizes.statusField,
                            child: FSelect<String>.rich(
                              key: const Key('task-status-menu'),
                              format: (v) => _statusWords
                                  .firstWhere(
                                    (e) => e.$1 == v,
                                    orElse: () => (v, v),
                                  )
                                  .$2,
                              hint: status,
                              control: FSelectControl.lifted(
                                value: _statusWords.any((e) => e.$1 == status)
                                    ? status
                                    : null,
                                onChange: (v) {
                                  if (v != null && v != status) {
                                    state.setTaskStatus(uid, v);
                                  }
                                },
                              ),
                              children: [
                                for (final e in _statusWords)
                                  FSelectItem<String>(
                                    title: Text(e.$2),
                                    value: e.$1,
                                    enabled: !(e.$1 == 'done' && blocked),
                                  ),
                              ],
                            ),
                          )
                        else
                          Text(
                            _statusWords
                                .firstWhere(
                                  (e) => e.$1 == status,
                                  orElse: () => (status, status),
                                )
                                .$2,
                            key: const Key('task-status-text'),
                          ),
                      ],
                    ),
                    if (draft == null) ...[
                      SizedBox(height: t.space.lg),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(t.space.lg),
                        decoration: BoxDecoration(
                          color: t.card,
                          border: Border.all(color: t.cardBorder),
                          borderRadius: BorderRadius.circular(t.radii.card),
                        ),
                        child: Column(
                          children: [
                            meta(
                              'due',
                              task.due == null
                                  ? Text('none', style: t.type.bodyStyle)
                                  : Align(
                                      alignment: Alignment.centerLeft,
                                      child: DueChip(
                                        task,
                                        key: const Key('task-due'),
                                        now: now,
                                        overdue: task.isClosed ? false : null,
                                      ),
                                    ),
                            ),
                            meta(
                              'priority',
                              Text(
                                priorityBucket(task.priority),
                                key: const Key('task-priority'),
                                style: t.type.bodyStyle,
                              ),
                            ),
                            if (parentName != null)
                              meta(
                                'inside',
                                Text(parentName, style: t.type.bodyStyle),
                              ),
                            if (task.rrule != null)
                              meta(
                                'repeats',
                                Text(
                                  '${task.rrule} (edit in another app)',
                                  key: const Key('task-rrule'),
                                  style: t.type.bodyStyle,
                                ),
                              ),
                            if (task.completed != null)
                              meta(
                                'completed',
                                Text(
                                  task.completed!
                                      .toLocal()
                                      .toString()
                                      .substring(0, 16),
                                  style: t.type.bodyStyle,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (state.taskTagsOf(task).isNotEmpty) ...[
                        SizedBox(height: t.space.lg),
                        Wrap(
                          spacing: t.space.sm,
                          runSpacing: t.space.sm,
                          children: [
                            for (final c in state.taskTagsOf(task)) TagChip(c),
                          ],
                        ),
                      ],
                      if (task.description.trim().isNotEmpty) ...[
                        SizedBox(height: t.space.xl),
                        MarkdownLite(task.description),
                      ],
                    ] else if (task.rrule != null) ...[
                      SizedBox(height: t.space.lg),
                      Text(
                        'Repeats: ${task.rrule} (edit in another app)',
                        key: const Key('task-rrule'),
                        style: t.type.captionStyle.copyWith(color: t.muted),
                      ),
                    ],
                    SizedBox(height: t.space.xxl),
                    ChildTasks(state: state, parentUid: uid),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    page = CallbackShortcuts(
      bindings: {
        if (draft != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (draft.dirty) state.saveTaskDraft(uid);
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (draft.dirty) state.saveTaskDraft(uid);
          },
        },
      },
      child: page,
    );
    return page;
  }
}
