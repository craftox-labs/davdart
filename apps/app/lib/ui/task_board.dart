import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import '../state/task_rules.dart';
import 'board_layout.dart';
import 'drag_drop.dart';
import 'overflow_tip.dart';
import 'task_menu.dart';
import 'task_parts.dart';
import 'theme.dart';

/// Read-only board of the Space's tasks, laid out exactly like the note board
/// ([BoardLayout]: equal columns, one collapsible column on a phone). It
/// follows the Tasks view's tag and folder filters. A card opens the task;
/// status changes in the task page. Cancelled tasks sit dimmed in done.
class TaskBoard extends StatelessWidget {
  const TaskBoard({super.key, required this.state, this.embedded = false});
  final AppState state;
  final bool embedded;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      // The note board's keyboard rows are not on screen in this focus.
      state.nav.publishHome('board', const []);
      return BoardLayout<Task>(
        cols: state.taskColumns(),
        openMap: state.nav.taskBoardOpen,
        modified: (t) => t.lastModified,
        embedded: embedded,
        wrap: (name, child) => NoteDropTarget(
          key: Key('task-board-col-$name'),
          // Drop a task on a column to set its status (cancelled counts as
          // done: it shares that column).
          accepts: (d) {
            final item = state.findItem(d.uid);
            return state.tasksEditable &&
                item is Task &&
                !(name == 'done' && taskCompletionBlocker(item) != null) &&
                (item.boardStatus == 'cancelled' ? 'done' : item.boardStatus) !=
                    name;
          },
          onDrop: (d) => state.setTaskStatus(d.uid, name),
          child: child,
        ),
        itemBuilder: (name, task, compact) =>
            _TaskCard(state: state, task: task, compact: compact),
      );
    },
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.state,
    required this.task,
    required this.compact,
  });
  final AppState state;
  final Task task;

  /// Phone: the title alone, no tags line.
  final bool compact;

  bool get _hasMeta => taskHasMeta(task);

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final selected = state.peekUid == task.uid || state.mainTaskUid == task.uid;
    final tags = compact ? const <String>[] : state.taskTagsOf(task);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: Opacity(
        opacity: task.isCancelled ? 0.5 : 1,
        child: TaskContextMenu(
          state: state,
          uid: task.uid,
          child: NoteDraggable(
            uid: task.uid,
            source: NoteDragSource.board,
            label: task.summary,
            child: FTappable(
              key: Key('task-card-${task.uid}'),
              onPress: () => state.clickTask(task.uid),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(t.radii.card),
                  border: Border.all(color: selected ? t.accent : t.cardBorder),
                ),
                child: Padding(
                  padding: EdgeInsets.all(t.space.lg),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(task.summary, style: t.type.semiboldStyle),
                            if (_hasMeta) ...[
                              SizedBox(height: t.space.sm),
                              TaskCardMeta(task: task),
                            ],
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OverflowTip(
                              task.summary,
                              maxLines: 3,
                              style: t.type.semiboldStyle,
                            ),
                            if (tags.isNotEmpty) ...[
                              SizedBox(height: t.space.sm),
                              Text(
                                tags.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.type.captionStyle.copyWith(
                                  color: t.muted,
                                ),
                              ),
                            ],
                            if (_hasMeta) ...[
                              SizedBox(height: t.space.sm),
                              TaskCardMeta(task: task),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
