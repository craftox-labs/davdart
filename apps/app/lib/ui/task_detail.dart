import 'package:davdart/davdart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart' show dayLabel;
import '../state/key_nav.dart';
import '../state/task_rules.dart' show isTaskOverdue;
import '../state/task_draft.dart';
import 'chips.dart';
import 'markdown_lite.dart';
import 'mobile_item.dart';
import 'note_editor.dart';
import 'parts.dart';
import 'property/date_property_picker.dart';
import 'property/inline_text.dart';
import 'property/option_picker.dart';
import 'property/parent_property_picker.dart'
    show ParentPropertyPicker, projectRowValue;
import 'property/property_defs.dart';
import 'property/property_picker.dart';
import 'property/property_row.dart';
import 'section_label.dart';
import 'property/tag_property_picker.dart';
import 'task_menu.dart';
import 'task_parts.dart';
import 'theme.dart';

export 'property/property_defs.dart'
    show statusWordOf, priorityBucket, priorityOfBucket;

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
          child: SectionLabel(
            kids.isEmpty ? 'Tasks' : 'Tasks (${kids.length})',
            textKey: Key('child-tasks-label-$parentUid'),
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

/// A task's page (peek pane or main tab): its title and description edited in
/// place, and every selector as a row that opens a picker. Each pick saves at
/// once (with Undo), so there is no edit mode, no Save or Cancel and no
/// pencil.
class TaskDetail extends StatelessWidget {
  const TaskDetail({
    super.key,
    required this.state,
    required this.uid,
    required this.onClose,
    this.full = false,
    this.inHeader = false,
    this.area = NavArea.main,
  });
  final AppState state;
  final String uid;
  final VoidCallback onClose;
  final bool full;
  final bool inHeader;

  /// The pane showing this page: its keyboard scrolling goes to it.
  final NavArea area;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final task = state.taskById(uid);
    if (task == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final draft = state.taskDraftFor(uid);
    final edit = state.tasksEditable;
    // Narrow: no edit toggle, just the ⋯ and the buffer's dot.
    final mobile = narrowLayout(context);
    final status = task.boardStatus;
    final blocked = state.taskCompletionBlockerFor(uid) != null;
    final tags = state.taskTagsOf(task);
    final startDay = task.dtstart?.localDay;

    /// The title itself is the way in: a tap opens the text buffer.
    void titleTap() => state.startTaskEdit(uid);
    void bodyTap() => state.startTaskEdit(uid, focusBody: true);

    Widget value(String text, {Key? key, bool muted = false}) => Text(
      text,
      key: key,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.type.bodyStyle.copyWith(color: muted ? t.muted : null),
    );

    final statusValue = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(status),
        SizedBox(width: t.space.sm),
        Flexible(
          child: Text(
            statusWordOf(status),
            key: const Key('task-status-text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.type.bodyStyle,
          ),
        ),
      ],
    );
    final priority = priorityBucket(task.priority);
    final priorityValue = value(
      priority == 'none' ? '—' : priority,
      key: const Key('task-priority'),
      muted: priority == 'none',
    );
    final dueLate = !task.isClosed && isTaskOverdue(task, now);
    final dueValue = task.due == null
        ? null
        : Text(
            dueLabel(task, now),
            key: const Key('task-due'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.type.bodyStyle.copyWith(color: dueLate ? t.error : null),
          );
    final startValue = startDay == null ? null : value(dayLabel(startDay, now));

    final rows = <Widget>[
      if (edit)
        PropertyPicker<String>(
          id: Props.status.id,
          uid: uid,
          state: state,
          icon: Props.status.icon,
          label: Props.status.label,
          value: statusValue,
          picker: (context, control, apply) => OptionPicker<String>(
            id: Props.status.id,
            value: status,
            onPick: (v) {
              control.hide();
              apply(v);
            },
            options: taskStatusOptions(blocked: blocked),
          ),
          onPick: (v) =>
              v == null ? Future.value(false) : state.setTaskStatus(uid, v),
        )
      else
        PropertyRow(
          key: const Key('property-status'),
          icon: Props.status.icon,
          label: Props.status.label,
          value: statusValue,
          readOnly: true,
        ),
      if (edit)
        PropertyPicker<int>(
          id: Props.priority.id,
          uid: uid,
          state: state,
          icon: Props.priority.icon,
          label: Props.priority.label,
          value: priorityValue,
          picker: (context, control, apply) => OptionPicker<int>(
            id: Props.priority.id,
            value: priorityOfBucket(priority),
            clearable: true,
            clearLabel: Props.noPriority,
            onPick: (v) {
              control.hide();
              apply(v);
            },
            options: priorityOptions<int>((b) => priorityOfBucket(b)!),
          ),
          onPick: (v) => state.setTaskPriority(uid, v),
        )
      else
        PropertyRow(
          key: const Key('property-priority'),
          icon: Props.priority.icon,
          label: Props.priority.label,
          value: priorityValue,
          readOnly: true,
        ),
      _dateRow(
        context,
        id: Props.due.id,
        label: Props.due.label,
        icon: Props.due.icon,
        day: task.due == null ? null : dueDate(task),
        value: dueValue,
        edit: edit,
        pick: (d) =>
            state.setTaskDue(uid, d == null ? null : dueOfDay(d, task.due)),
      ),
      _dateRow(
        context,
        id: Props.start.id,
        label: Props.start.label,
        icon: Props.start.icon,
        day: startDay,
        value: startValue,
        edit: edit,
        pick: (d) => state.setTaskStart(
          uid,
          d == null ? null : dueOfDay(d, task.dtstart),
        ),
      ),
      if (edit)
        PropertyPicker<List<String>>(
          id: Props.labels.id,
          uid: uid,
          state: state,
          icon: Props.labels.icon,
          label: Props.labels.label,
          text: tags.isEmpty ? null : tags.join(', '),
          picker: (context, control, apply) => TagPropertyPicker(
            id: Props.labels.id,
            value: tags,
            suggestions: state.taskTags,
            onPick: apply,
          ),
          onPick: (v) => state.setTaskTags(uid, v ?? const []),
        )
      else
        PropertyRow(
          key: const Key('property-tags'),
          icon: Props.labels.icon,
          label: Props.labels.label,
          text: tags.isEmpty ? null : tags.join(', '),
          readOnly: true,
        ),
      if (edit && state.projectsByRecent.isNotEmpty)
        PropertyPicker<String>(
          id: Props.parent.id,
          uid: uid,
          state: state,
          icon: Props.parent.icon,
          label: Props.parent.label,
          text: projectRowValue(state, uid),
          picker: (context, control, apply) => ParentPropertyPicker(
            id: Props.parent.id,
            state: state,
            uid: uid,
            onPick: (v) {
              control.hide();
              return apply(v);
            },
          ),
          onPick: (v) => state.setTaskParent(uid, v),
        )
      else
        PropertyRow(
          key: const Key('property-parent'),
          icon: Props.parent.icon,
          label: Props.parent.label,
          text: projectRowValue(state, uid),
          readOnly: true,
        ),
      if (task.rrule != null)
        PropertyRow(
          key: const Key('property-repeats'),
          icon: FLucideIcons.repeat,
          label: 'repeats',
          text: '${task.rrule} (edit in another app)',
          readOnly: true,
        ),
      if (task.completed != null)
        PropertyRow(
          key: const Key('property-completed'),
          icon: FLucideIcons.check,
          label: 'completed',
          text: task.completed!.toLocal().toString().substring(0, 16),
          readOnly: true,
        ),
    ];

    final page = Column(
      children: [
        parentCrumb(state, uid),
        ItemHeader(
          title: task.summary,
          strike: task.isClosed,
          leading: TaskCheckbox(state: state, task: task),
          full: full,
          inHeader: inHeader,
          onClose: onClose,
          onTitleTap: edit && draft == null ? titleTap : null,
          editor: draft == null
              ? null
              : InlineText(
                  key: const Key('edit-title'),
                  controller: draft.titleController,
                  focusNode: draft.titleFocus,
                  commitSignal: draft.commitSignal,
                  style: paneTitleStyle(t, muted: task.isClosed).copyWith(
                    decoration: task.isClosed
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  autoBegin: state.taskTextTargets(uid, body: false),
                  onBegan: state.clearTaskTextIntent,
                  onCommit: (_) => state.commitTaskText(uid),
                  preview: (text) => PaneTitle(
                    text,
                    textKey: const Key('pane-title'),
                    muted: task.isClosed,
                    strike: task.isClosed,
                  ),
                ),
          actions: [
            if (mobile)
              MobileItemActions(
                state: state,
                uid: uid,
                editing: false,
                canEdit: false,
                onEdit: titleTap,
                draft: draft,
                groups: TaskContextMenu(
                  state: state,
                  uid: uid,
                  child: const SizedBox.shrink(),
                ).pageGroups,
              )
            else if (edit) ...[
              if (state.spaces.length > 1)
                IconAction(
                  key: const Key('move-note'),
                  tooltip: 'Move to Space…',
                  icon: FLucideIcons.folderInput,
                  onPress: () => showMoveTaskDialog(context, state, task),
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
        Expanded(
          child: SelectableBody(
            enabled: draft == null,
            child: SingleChildScrollView(
              controller: state.nav.pageScroll(area),
              padding: EdgeInsets.fromLTRB(
                t.space.xxl,
                t.space.md,
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
                      PropertySection(rows: rows),
                      SizedBox(height: t.space.xl),
                      if (edit || task.description.trim().isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(bottom: t.space.sm),
                          child: SectionLabel('Description'),
                        ),
                      _description(context, task, draft, edit, bodyTap),
                      SizedBox(height: t.space.xxl),
                      ChildTasks(state: state, parentUid: uid),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    // Ctrl/Cmd+S saves through the fields: each one writes what it shows, so
    // it records the text it saved rather than going stale.
    void saveNow() {
      if (draft != null && draft.dirty) draft.commitSignal.ping();
    }

    Widget withKeys = CallbackShortcuts(
      bindings: {
        if (draft != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              saveNow,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): saveNow,
        },
      },
      child: page,
    );
    return draft == null
        ? withKeys
        : EditKeys(state: state, uid: uid, child: withKeys);
  }

  /// A date row: its chip or word as the value, a date picker as the way in
  /// (plain text in a read-only Space).
  Widget _dateRow(
    BuildContext context, {
    required String id,
    required String label,
    required IconData icon,
    required DateTime? day,
    required Widget? value,
    required bool edit,
    required Future<bool> Function(DateTime? day) pick,
  }) {
    final state = this.state;
    if (!edit) {
      return PropertyRow(
        key: Key('property-$id'),
        icon: icon,
        label: label,
        value: value,
        readOnly: true,
      );
    }
    return PropertyPicker<DateTime>(
      id: id,
      uid: uid,
      state: state,
      icon: icon,
      label: label,
      value: value,
      picker: (context, control, apply) => DatePropertyPicker(
        id: id,
        value: day,
        onPick: (d) {
          control.hide();
          apply(d);
        },
      ),
      onPick: pick,
    );
  }

  /// The description: markdown until it is picked, then the inline field.
  Widget _description(
    BuildContext context,
    Task task,
    TaskDraft? draft,
    bool edit,
    VoidCallback onTap,
  ) {
    final t = tokensOf(context);
    if (draft != null) {
      return InlineText(
        key: const Key('edit-body'),
        controller: draft.bodyController,
        focusNode: draft.bodyFocus,
        commitSignal: draft.commitSignal,
        multiline: true,
        placeholder: 'Description',
        autoBegin: state.taskTextTargets(uid, body: true),
        onBegan: state.clearTaskTextIntent,
        onCommit: (_) => state.commitTaskText(uid),
        preview: MarkdownLite.new,
      );
    }
    if (task.description.trim().isEmpty) {
      if (!edit) return const SizedBox.shrink();
      return FTappable(
        key: const Key('task-description-tap'),
        onPress: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: t.space.xs),
          child: Text(
            'Description',
            style: t.type.bodyStyle.copyWith(color: t.muted),
          ),
        ),
      );
    }
    return FTappable(
      key: const Key('task-description-tap'),
      onPress: edit ? onTap : null,
      child: MarkdownLite(task.description),
    );
  }
}
