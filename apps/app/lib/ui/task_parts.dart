import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import '../state/task_rules.dart';
import 'drag_drop.dart';
import 'parts.dart';
import 'task_menu.dart';
import 'theme.dart';

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
  final local = now.toLocal();
  final today = DateTime.utc(local.year, local.month, local.day);
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

/// The due value for a picked day. With a timed [existing] value only the
/// date part changes: time of day, Z and TZID/params stay. Otherwise all-day.
ICalDate dueOfDay(DateTime d, [ICalDate? existing]) {
  final day = ICalDate.date(d.year, d.month, d.day);
  if (existing == null || existing.allDay) return day;
  final t = existing.value.indexOf('T');
  if (t != 8) return day;
  return ICalDate(
    '${day.value}${existing.value.substring(t)}',
    existing.params,
  );
}

/// The local calendar day [days] from today, as a UTC-flagged date.
DateTime dayFromToday(int days, [DateTime? now]) {
  final n = (now ?? DateTime.now()).toLocal();
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
    if (blocker == null) return box;
    return FTooltip(
      key: Key('task-check-tip-${task.uid}'),
      tipBuilder: (_, _) => Text(blocker),
      child: box,
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
    return TaskContextMenu(
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
            padding: EdgeInsets.symmetric(
              horizontal: t.space.xs,
              vertical: t.space.sm,
            ),
            child: Row(
              children: [
                TaskCheckbox(state: state, task: task),
                SizedBox(width: t.space.md),
                Expanded(
                  child: Text(
                    task.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                    child: Text(
                      '#$tag',
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
  });
  final AppState state;
  final String? parentUid;
  final String hint;

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
      hint: widget.hint,
      prefixIcon: FLucideIcons.plus,
      onSubmit: _submit,
    );
  }
}
