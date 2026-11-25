import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import '../state/event_rules.dart';
import '../state/task_rules.dart';
import '../theme/tokens.dart';
import 'drag_drop.dart';
import 'parts.dart';
import 'task_detail.dart' show priorityBucket;
import 'task_menu.dart';
import 'theme.dart';
import 'overflow_tip.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The due chip text: 'Today', 'Tomorrow', 'Yesterday', else 'Mon 24' (with
/// the month, and the year when not this one, once it is not this month).
/// Empty without a due date.
String dueLabel(Task t, DateTime now) {
  final d = taskDueDay(t);
  if (d == null) return '';
  final today = wallDay(wallNow(now));
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  final base = '${_weekdays[d.weekday - 1]} ${d.day}';
  if (d.year != today.year) return '$base ${_months[d.month - 1]} ${d.year}';
  if (d.month != today.month) return '$base ${_months[d.month - 1]}';
  return base;
}

/// A task's due day as a date for the pickers (UTC midnight), or null.
DateTime? dueDate(Task t) => t.due == null ? null : taskDueDay(t);

/// The due value for a picked viewer-zone day. With a timed [existing] value
/// the local time of day stays and the flavour is kept (Z stays Z, a TZID
/// stays in its zone, floating stays floating). Otherwise all-day.
ICalDate dueOfDay(DateTime d, [ICalDate? existing]) {
  final day = ICalDate.date(d.year, d.month, d.day);
  if (existing == null || existing.allDay) return day;
  final l = existing.localWall;
  if (l == null) return day;
  return ICalDate.fromLocalWall(
    DateTime.utc(d.year, d.month, d.day, l.hour, l.minute, l.second),
    existing,
  );
}

/// The local calendar day [days] from today, as a UTC-flagged date.
DateTime dayFromToday(int days, [DateTime? now]) {
  final n = wallNow(now ?? DateTime.now());
  return DateTime.utc(n.year, n.month, n.day + days);
}

/// The small outlined due label; overdue ones use the error colour.
class DueChip extends StatelessWidget {
  const DueChip(this.task, {super.key, required this.now, this.overdue});
  final Task task;
  final DateTime now;

  /// Overrides the overdue test (for a closed task, which is never overdue).
  final bool? overdue;

  @override
  Widget build(BuildContext context) {
    final label = dueLabel(task, now);
    if (label.isEmpty) return const SizedBox.shrink();
    final t = tokensOf(context);
    final late = overdue ?? isTaskOverdue(task, now);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: t.space.sm,
        vertical: t.space.xxs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.radii.small),
        border: Border.all(color: late ? t.error : t.cardBorder),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: t.type.captionStyle.copyWith(color: late ? t.error : t.muted),
      ),
    );
  }
}

/// Whether a card has a priority or a due date to show.
bool taskHasMeta(Task t) =>
    t.due != null || priorityBucket(t.priority) != 'none';

/// The priority word ('High', 'Medium', 'Low') or null when none is set.
String? priorityLabel(Task t) {
  final b = priorityBucket(t.priority);
  return b == 'none' ? null : '${b[0].toUpperCase()}${b.substring(1)}';
}

/// The compact meta line of a task card: priority (when set) then the due
/// chip (when set; overdue in the error colour, never for a closed task).
/// The caller shows it only when [taskHasMeta].
class TaskCardMeta extends StatelessWidget {
  const TaskCardMeta({super.key, required this.task, this.now});
  final Task task;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = priorityLabel(task);
    return Wrap(
      spacing: t.space.md,
      runSpacing: t.space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (p != null)
          Text(
            p,
            key: Key('card-priority-${task.uid}'),
            style: t.type.captionStyle.copyWith(
              color: priorityBucket(task.priority) == 'high'
                  ? t.accent
                  : t.muted,
            ),
          ),
        if (task.due != null)
          DueChip(
            task,
            key: Key('card-due-${task.uid}'),
            now: now ?? DateTime.now(),
            overdue: task.isClosed ? false : null,
          ),
      ],
    );
  }
}

/// The completion checkbox of a task. A repeating open task is disabled and
/// its tooltip says why; so is every task of a read-only Space.
class TaskCheckbox extends StatelessWidget {
  const TaskCheckbox({super.key, required this.state, required this.task});
  final AppState state;
  final Task task;

  @override
  Widget build(BuildContext context) {
    final blocker = task.isClosed
        ? null
        : state.taskCompletionBlockerFor(task.uid);
    final box = FCheckbox(
      key: Key('task-check-${task.uid}'),
      semanticsLabel: task.isClosed ? 'Reopen task' : 'Complete task',
      value: task.isClosed,
      enabled: state.tasksEditable && blocker == null,
      onChange: (_) => state.toggleTask(task.uid),
    );
    Widget target = box;
    // Narrow: the box sits in a touch-sized hit area.
    if (narrowLayout(context)) {
      final m = tokensOf(context).sizes.touchTarget;
      target = GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: state.tasksEditable && blocker == null
            ? () => state.toggleTask(task.uid)
            : null,
        child: SizedBox(
          width: m,
          height: m,
          child: Center(child: box),
        ),
      );
    }
    if (blocker == null) return target;
    return FTooltip(
      key: Key('task-check-tip-${task.uid}'),
      tipBuilder: (_, _) => Text(blocker),
      child: target,
    );
  }
}

/// One task as a row: checkbox, title, tags (optional) and the due chip.
/// Click opens it per the "open in" setting, double click promotes, right
/// click opens the task menu, and it drags onto a Space.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.state,
    required this.task,
    required this.now,
    this.showTags = false,
    this.source = NoteDragSource.list,
    this.onOpen,
  });
  final AppState state;
  final Task task;
  final DateTime now;
  final bool showTags;
  final NoteDragSource source;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final selected = state.peekUid == task.uid || state.mainTaskUid == task.uid;
    final tags = showTags ? state.taskTagsOf(task) : const <String>[];
    Widget row = TaskContextMenu(
      state: state,
      uid: task.uid,
      onOpen: onOpen,
      child: NoteDraggable(
        uid: task.uid,
        source: source,
        label: task.summary,
        child: FTappable(
          onPress: () {
            state.clickTask(task.uid);
            onOpen?.call();
          },
          child: Container(
            color: selected ? t.selected : null,
            constraints: BoxConstraints(
              minHeight: narrowLayout(context) ? t.sizes.touchTarget : 0,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: t.space.xs,
              vertical: t.space.sm,
            ),
            child: Row(
              children: [
                TaskCheckbox(state: state, task: task),
                SizedBox(width: t.space.md),
                Expanded(
                  child: OverflowTip(
                    task.summary,
                    style: task.isClosed
                        ? TextStyle(
                            color: t.muted,
                            decoration: TextDecoration.lineThrough,
                          )
                        : null,
                  ),
                ),
                for (final tag in tags.take(2)) ...[
                  SizedBox(width: t.space.sm),
                  Flexible(
                    child: OverflowTip(
                      '#$tag',
                      style: t.type.captionStyle.copyWith(color: t.muted),
                    ),
                  ),
                ],
                if (priorityLabel(task) != null) ...[
                  SizedBox(width: t.space.sm),
                  Flexible(
                    child: Text(
                      priorityLabel(task)!,
                      key: Key('row-priority-${task.uid}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.type.captionStyle.copyWith(color: t.muted),
                    ),
                  ),
                ],
                if (task.due != null) ...[
                  SizedBox(width: t.space.md),
                  DueChip(
                    task,
                    key: Key('due-${task.uid}'),
                    now: now,
                    overdue: task.isClosed ? false : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return swipeable(context, t, row);
  }

  /// Narrow: swiping an open task to the right completes it. The row stays
  /// (it never leaves the list by the swipe), and a toast offers Undo. A
  /// closed or blocked task (repeating, read-only Space) does not swipe: the
  /// checkbox and the menu reopen it.
  Widget swipeable(BuildContext context, Tokens t, Widget row) {
    if (!narrowLayout(context) ||
        task.isClosed ||
        !state.tasksEditable ||
        state.taskCompletionBlockerFor(task.uid) != null) {
      return row;
    }
    return Dismissible(
      key: ValueKey('swipe-${source.name}-${task.uid}'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.4},
      background: Container(
        color: t.accent,
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: t.space.lg),
        child: Icon(FLucideIcons.check, color: t.onAccent),
      ),
      confirmDismiss: (_) async {
        // The row may leave the list (a filter) before the toast shows.
        final host = Navigator.of(context, rootNavigator: true).context;
        final ok = await state.toggleTask(task.uid);
        if (ok && host.mounted) {
          showFToast(
            context: host,
            title: Text('Completed "${task.summary}"'),
            suffixBuilder: (_, entry) => FButton(
              key: const Key('swipe-undo'),
              variant: FButtonVariant.outline,
              size: FButtonSizeVariant.xs,
              mainAxisSize: MainAxisSize.min,
              onPress: () async {
                entry.dismiss();
                // Only the task this swipe completed, and only if it is
                // still completed (not reopened or cancelled meanwhile).
                final now = state.taskById(task.uid);
                if (now == null || !now.isCompleted) return;
                final ok = await state.setTaskDone(task.uid, false);
                if (!ok && host.mounted) {
                  showFToast(
                    context: host,
                    title: Text(state.error ?? 'Could not reopen the task'),
                  );
                }
              },
              child: const Text('Undo'),
            ),
          );
        }
        // The row stays; its state redraws it struck through.
        return false;
      },
      child: row,
    );
  }
}

/// A one-line "Add a task…" field: Enter adds an open task with no due date
/// (under [parentUid] when given) and clears the field. Hidden in a
/// read-only Space.
class TaskQuickAdd extends StatefulWidget {
  const TaskQuickAdd({
    super.key,
    required this.state,
    this.parentUid,
    this.hint = 'Add a task…',
    this.focusNode,
  });
  final AppState state;
  final String? parentUid;
  final String hint;
  final FocusNode? focusNode;

  @override
  State<TaskQuickAdd> createState() => _TaskQuickAddState();
}

class _TaskQuickAddState extends State<TaskQuickAdd> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String text) async {
    final title = text.trim();
    if (title.isEmpty) return;
    final uid = await widget.state.addTask(title, parentUid: widget.parentUid);
    if (uid != null) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.state.tasksEditable) return const SizedBox.shrink();
    return field(
      key: Key(
        widget.parentUid == null
            ? 'task-quick-add'
            : 'task-quick-add-${widget.parentUid}',
      ),
      controller: _controller,
      focusNode: widget.focusNode,
      hint: widget.hint,
      prefixIcon: FLucideIcons.plus,
      onSubmit: _submit,
    );
  }
}
