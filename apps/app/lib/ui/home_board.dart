import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import '../state/note_drag.dart';
import '../state/task_rules.dart';
import '../theme/tokens.dart';
import 'board_layout.dart';
import 'drag_drop.dart';
import 'key_nav_ui.dart';
import 'new_note_dialog.dart';
import 'note_menu.dart';
import 'overflow_tip.dart';
import 'task_menu.dart';
import 'task_parts.dart';
import 'theme.dart';

/// The glyph of a card's kind: a document for a note, a check-circle for a
/// task (also the kind-filter menu's icons).
IconData kindIcon(bool isTask) =>
    isTask ? FLucideIcons.circleCheck : FLucideIcons.fileText;

/// Publishes the Home board's cards (column by column) as the keyboard rows
/// of the Home grid; a collapsed Board is skipped at move time.
void publishBoardNav(AppState state) {
  final cols = state.homeColumns();
  final open = cols.isEmpty ? '' : boardDefaultOpen(cols);
  state.nav.publishHome('board', [
    for (final (name, items) in cols)
      for (final i in boardCapped(
        name,
        items,
        (i) => i.lastModified,
        showAll: state.nav.boardOpen[boardDoneAllKey] ?? false,
      ))
        NavEntry(
          'card-${i.uid}',
          uid: i.uid,
          block: 'col:$name',
          open: (mode) async {
            await state.openNote(i.uid, mode: mode);
          },
          hidden: () =>
              state.nav.boardAccordion &&
              !(state.nav.boardOpen[name] ?? name == open),
        ),
  ]);
}

/// Home's unified Board: notes and tasks that have a status, grouped by the
/// fixed status set, in the shared [BoardLayout]. The cards are rows of the
/// keyboard grid. Which kinds show is [AppState.homeKind].
class HomeBoard extends StatelessWidget {
  const HomeBoard({super.key, required this.state, this.embedded = false});
  final AppState state;

  /// Phone Home: the accordion sizes to its content and does not scroll, so
  /// a parent scroll view carries it with the strip.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (state.error != null && state.notes.isEmpty) {
      return Center(
        child: Text(state.error!, style: TextStyle(color: t.muted)),
      );
    }
    final cols = state.homeColumns();
    if (cols.isEmpty && !state.loading) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Text(
            state.filtered.isNotEmpty || state.tasks.isNotEmpty
                ? 'No work items yet. Give a note or task a status (backlog, todo, doing...) and it shows up here.'
                : 'No notes',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted),
          ),
        ),
      );
    }
    return BoardLayout<BoardItem>(
      cols: cols,
      openMap: state.nav.boardOpen,
      modified: (i) => i.lastModified,
      embedded: embedded,
      dot: (n) => n == otherColumn ? null : n,
      onShowAll: () => publishBoardNav(state),
      onAccordion: (a) => state.nav.boardAccordion = a,
      wrap: (name, child) => _drop(name, context, child),
      itemBuilder: (name, i, compact) => _CardDrop(
        // Phone accordion: no drag (stage 3). Done is ordered by time and
        // Other is not a status, so only the other columns take a position.
        enabled: !compact && name != 'done' && name != otherColumn,
        accepts: (d) => _canDropOn(d, i, name),
        onDrop: (d, after) => _dropAt(name, i.uid, d, after),
        child: _Card(state: state, item: i, column: name, compact: compact),
      ),
    );
  }

  /// Whether [d] can be dropped on the card [target] of [column]: same rules
  /// as the column, but a card of its own column may be reordered.
  bool _canDropOn(NoteDrag d, BoardItem target, String column) {
    if (d.uid == target.uid) return false;
    final item = state.findItem(d.uid);
    if (item is Task) return state.tasksEditable;
    return item is Note && state.editable && !AppState.isFolder(item);
  }

  /// Places the dragged card before or after the card [targetUid] of
  /// [column] (a different column also changes its status).
  void _dropAt(String column, String targetUid, NoteDrag d, bool after) {
    final cards = [
      for (final (name, items) in state.homeColumns(all: true))
        if (name == column)
          for (final i in items)
            if (i.uid != d.uid) i.uid,
    ];
    final at = cards.indexOf(targetUid);
    if (at < 0) return;
    state.placeBoardItem(d.uid, column, index: after ? at + 1 : at);
  }

  /// A column is a drop target that sets the dropped item's status (a task
  /// by its board status, a note by its status line); right-click adds a note
  /// in that status.
  Widget _drop(String name, BuildContext context, Widget column) {
    // Other holds words outside the fixed set: it is not a status to drop on.
    if (name == otherColumn) return column;
    return NoteDropTarget(
      key: Key('board-drop-$name'),
      accepts: (d) {
        final item = state.findItem(d.uid);
        if (item is Task) {
          if (!state.tasksEditable) return false;
          if (name == 'done' && taskCompletionBlocker(item) != null) {
            return false;
          }
          final s = item.boardStatus;
          return statusColumn(canonicalStatus(s) ?? s) != name;
        }
        return item is Note &&
            state.editable &&
            !AppState.isFolder(item) &&
            PlanItem.fromNote(item).status != name;
      },
      onDrop: (d) => state.placeBoardItem(d.uid, name),
      child: ActionContextMenu(
        groups: [
          if (state.editable && state.homeKind != HomeKind.tasks)
            [
              NoteMenuItem(
                'New note in $name…',
                FLucideIcons.filePlus,
                () => showNewNoteDialog(context, state, status: name),
                key: Key('menu-board-new-$name'),
              ),
            ],
        ],
        child: column,
      ),
    );
  }
}

/// A card as a drop target within its column: while a card is dragged over
/// it, a line shows above or below it (upper or lower half) where the card
/// would land.
class _CardDrop extends StatefulWidget {
  const _CardDrop({
    required this.enabled,
    required this.accepts,
    required this.onDrop,
    required this.child,
  });
  final bool enabled;
  final bool Function(NoteDrag d) accepts;
  final void Function(NoteDrag d, bool after) onDrop;
  final Widget child;

  @override
  State<_CardDrop> createState() => _CardDropState();
}

class _CardDropState extends State<_CardDrop> {
  bool _after = false;

  bool _isAfter(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return _after;
    return box.globalToLocal(global).dy > box.size.height / 2;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final t = tokensOf(context);
    return DragTarget<NoteDrag>(
      onWillAcceptWithDetails: (d) => widget.accepts(d.data),
      onMove: (d) {
        final a = _isAfter(d.offset);
        if (a != _after) setState(() => _after = a);
      },
      onAcceptWithDetails: (d) => widget.onDrop(d.data, _isAfter(d.offset)),
      builder: (context, candidates, _) => Stack(
        children: [
          widget.child,
          if (candidates.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: _after ? null : 0,
              bottom: _after ? 0 : null,
              child: IgnorePointer(
                child: Container(
                  key: Key(_after ? 'drop-line-after' : 'drop-line-before'),
                  height: t.borders.focus,
                  color: t.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.state,
    required this.item,
    required this.column,
    required this.compact,
  });
  final AppState state;
  final BoardItem item;
  final String column;

  /// Narrow layout: glyph and title, plus the task meta line.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final task = item.task;
    final note = item.note;
    final selected = task != null
        ? state.peekUid == task.uid || state.mainTaskUid == task.uid
        : state.peekUid == note!.uid;
    final plan = note == null ? null : PlanItem.fromNote(note);
    final tags = task == null || compact
        ? const <String>[]
        : state.taskTagsOf(task);
    final title = task != null
        ? OverflowTip(task.summary, maxLines: 3, style: t.type.semiboldStyle)
        : Text(
            compact ? note!.summary : (plan!.itemId ?? note!.summary),
            style: t.type.semiboldStyle,
          );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: t.space.xxs, right: t.space.md),
              child: Icon(
                kindIcon(item.isTask),
                key: Key('card-kind-${item.uid}'),
                size: t.icons.md,
                color: t.muted,
              ),
            ),
            Expanded(child: title),
          ],
        ),
        if (note != null && !compact && plan!.itemId != null) ...[
          SizedBox(height: t.space.xxs),
          OverflowTip(
            note.summary,
            maxLines: 2,
            style: t.type.bodyStyle.copyWith(color: t.muted),
          ),
        ],
        if (tags.isNotEmpty) ...[
          SizedBox(height: t.space.sm),
          Text(
            tags.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.type.captionStyle.copyWith(color: t.muted),
          ),
        ],
        if (task != null && taskHasMeta(task)) ...[
          SizedBox(height: t.space.sm),
          TaskCardMeta(task: task),
        ],
        if (note != null && plan!.priorityWord != null) ...[
          SizedBox(height: t.space.sm),
          Text(
            '${plan.priorityWord![0].toUpperCase()}'
            '${plan.priorityWord!.substring(1)}',
            key: Key('card-priority-${note.uid}'),
            style: t.type.captionStyle.copyWith(
              color: plan.priorityWord == 'high' ? t.accent : t.muted,
            ),
          ),
        ],
        if (note != null && !compact && plan!.owner != null) ...[
          SizedBox(height: t.space.sm),
          Text(
            plan.owner!,
            style: t.type.captionStyle.copyWith(color: t.muted),
          ),
        ],
      ],
    );
    final card = FTappable(
      key: task == null ? null : Key('task-card-${task.uid}'),
      onPress: () => state.clickNote(item.uid),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.radii.card),
          border: Border.all(color: selected ? t.accent : t.cardBorder),
        ),
        child: Padding(padding: EdgeInsets.all(t.space.lg), child: body),
      ),
    );
    final draggable = NoteDraggable(
      uid: item.uid,
      source: NoteDragSource.board,
      atPointer: true,
      label: item.title,
      child: _keyRow(t, card),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: Opacity(
        opacity: item.canceled || column == 'canceled' ? 0.5 : 1,
        child: task != null
            ? TaskContextMenu(state: state, uid: task.uid, child: draggable)
            : NoteContextMenu(
                state: state,
                uid: item.uid,
                items: [
                  if (state.editable && column != otherColumn)
                    NoteMenuItem(
                      'New note in $column…',
                      FLucideIcons.filePlus,
                      () => showNewNoteDialog(context, state, status: column),
                      key: Key('menu-card-new-$column'),
                    ),
                ],
                child: draggable,
              ),
      ),
    );
  }

  Widget _keyRow(Tokens t, Widget child) => NavRow(
    key: ValueKey('nav-card-${item.uid}'),
    nav: state.nav,
    list: KeyNav.homeList,
    id: 'card-${item.uid}',
    radius: t.radii.card,
    child: child,
  );
}
