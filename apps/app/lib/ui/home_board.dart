import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import '../state/note_drag.dart';
import '../state/task_rules.dart';
import '../theme/tokens.dart';
import 'board_layout.dart';
import 'chips.dart' show priorityColorOf;
import 'task_detail.dart' show priorityBucket;
import 'drag_drop.dart';
import 'key_nav_ui.dart';
import 'new_note_dialog.dart';
import 'note_menu.dart';
import 'overflow_tip.dart';
import 'task_menu.dart';
import 'task_parts.dart';
import 'theme.dart';

/// The glyph of a card's kind: a document for a note, a checklist (the rail icon) for a
/// task (also the kind-filter menu's icons).
IconData kindIcon(bool isTask) =>
    isTask ? FLucideIcons.listChecks : FLucideIcons.fileText;

/// Most tags a board card lists; the rest show as "+N".
const boardCardMaxTags = 2;

/// The first two lines' worth of a note body for a card: markdown noise
/// stripped lightly, whitespace collapsed. Empty when there is no body.
String noteSnippet(String body) => body
    .replaceAll(RegExp(r'^\s*#+\s*', multiLine: true), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A plan item's card title: its summary without the leading `item_id: `
/// slug (the slug is in the item view); the whole summary when it has none.
String _cardTitle(Note note, PlanItem plan) {
  final id = plan.itemId;
  final s = note.summary;
  if (id != null && s.startsWith('$id:')) {
    final rest = s.substring(id.length + 1).trim();
    if (rest.isNotEmpty) return rest;
  }
  return s;
}

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
        // Done is ordered by time and Other is not a status, so only the
        // other columns take a position (phone sections included).
        enabled: name != 'done' && name != otherColumn,
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
        // On a phone a long press belongs to the cards and their grips, not
        // to the column behind them.
        touchMenu: !state.narrow,
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

  /// Narrow layout: no snippet or tag names; the footer keeps kind, the
  /// priority flag (no word), due and tag count.
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
    final allTags = task != null
        ? state.taskTagsOf(task)
        : state.noteTagsOf(note!);
    final shownTags = compact
        ? const <String>[]
        : allTags.take(boardCardMaxTags).toList();
    final moreTags = allTags.length - shownTags.length;
    final folder = compact || state.scopeUid != null
        ? null
        : state.folderNameOf(item.uid);
    final snippet = note == null || compact ? '' : noteSnippet(plan!.text);
    // Phone and desktop share one title size (one step under the old desktop
    // title).
    final titleStyle = t.type.bodyStrong;
    final title = task != null
        ? OverflowTip(task.summary, maxLines: 3, style: titleStyle)
        : Text(_cardTitle(note!, plan!), style: titleStyle);
    final bucket = task != null
        ? priorityBucket(task.priority)
        : (plan!.priorityWord ?? 'none');
    final now = DateTime.now();
    final due = task == null ? '' : dueLabel(task, now);
    final late = task != null && !task.isClosed && isTaskOverdue(task, now);
    final footer = _footer(
      t,
      bucket: bucket == 'none' ? null : bucket,
      due: due,
      late: late,
      tags: shownTags,
      moreTags: moreTags,
      tagCount: allTags.length,
      folder: folder,
      compact: compact,
    );
    // Title and body read as one block (xs gaps); the footer stands off from
    // it by the card padding (lg).
    final bodyItems = <Widget>[
      if (snippet.isNotEmpty)
        Text(
          snippet,
          key: Key('card-snippet-${item.uid}'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.type.bodyStyle.copyWith(color: t.muted),
        ),
    ];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        if (bodyItems.isNotEmpty) SizedBox(height: t.space.xs),
        for (var i = 0; i < bodyItems.length; i++) ...[
          if (i > 0) SizedBox(height: t.space.xs),
          bodyItems[i],
        ],
        SizedBox(height: t.space.lg),
        footer,
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
        child: Padding(
          padding: compact
              ? EdgeInsets.fromLTRB(
                  t.space.lg,
                  t.space.lg,
                  t.space.huge,
                  t.space.lg,
                )
              : EdgeInsets.all(t.space.lg),
          child: body,
        ),
      ),
    );
    final draggable = NoteDraggable(
      uid: item.uid,
      source: NoteDragSource.board,
      atPointer: true,
      label: item.title,
      // On the phone the card itself does not drag (a touch scrolls, a long
      // press opens the menu); the grip does.
      child: _keyRow(t, card),
    );
    final menu = task != null
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
          );
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: Opacity(
        opacity: item.canceled || column == 'canceled' ? 0.5 : 1,
        // The grip sits beside the menu, not inside it: a press on the grip
        // never reaches the card's long press or tap, so holding it for any
        // length of time still lets the card be dragged.
        child: compact ? Stack(children: [menu, _grip(t)]) : menu,
      ),
    );
  }

  /// The phone drag grip: a full-height strip at the right edge, a touch
  /// target of its own.
  Widget _grip(Tokens t) => Positioned(
    top: 0,
    right: 0,
    bottom: 0,
    child: NoteDraggable(
      uid: item.uid,
      source: NoteDragSource.board,
      atPointer: true,
      handle: true,
      label: item.title,
      child: SizedBox(
        key: Key('card-grip-${item.uid}'),
        width: t.space.huge,
        child: Center(
          child: Icon(
            FLucideIcons.gripVertical,
            size: t.icons.sm,
            color: t.muted,
          ),
        ),
      ),
    ),
  );

  /// The footer row, left-aligned with the title: kind, priority, due, tags,
  /// and the folder at the right end. Phones show the priority flag without
  /// its word, and list tags as an icon with the count.
  Widget _footer(
    Tokens t, {
    required String? bucket,
    required String due,
    required bool late,
    required List<String> tags,
    required int moreTags,
    required int tagCount,
    required String? folder,
    required bool compact,
  }) {
    final uid = item.uid;
    final small = t.type.captionStyle;
    Widget pair(IconData icon, Widget text, Color color, {Key? key}) => Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: t.icons.sm, color: color),
        SizedBox(width: t.space.xs),
        Flexible(child: text),
      ],
    );
    Text txt(String s, Color c, {Key? key}) => Text(
      s,
      key: key,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: small.copyWith(color: c),
    );
    final gap = SizedBox(width: t.space.md);
    final parts = <Widget>[
      Icon(
        kindIcon(item.isTask),
        key: Key('card-kind-$uid'),
        size: t.icons.sm,
        color: t.muted,
      ),
      if (bucket != null) ...[
        gap,
        Row(
          key: Key('card-priority-$uid'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FLucideIcons.flag,
              size: t.icons.sm,
              color: priorityColorOf(t, bucket),
            ),
            if (!compact) ...[
              SizedBox(width: t.space.xs),
              Flexible(
                child: txt(
                  '${bucket[0].toUpperCase()}${bucket.substring(1)}',
                  priorityColorOf(t, bucket),
                ),
              ),
            ],
          ],
        ),
      ],
      if (due.isNotEmpty) ...[
        gap,
        Flexible(
          child: pair(
            FLucideIcons.calendar,
            txt(due, late ? t.error : t.muted),
            late ? t.error : t.muted,
            key: Key('card-due-$uid'),
          ),
        ),
      ],
      if (compact && tagCount > 0) ...[
        gap,
        pair(
          FLucideIcons.tag,
          txt('$tagCount', t.muted, key: Key('card-tag-count-$uid')),
          t.muted,
        ),
      ],
      if (tags.isNotEmpty) ...[
        gap,
        Flexible(
          child: txt(
            [
              for (final g in tags) '#$g',
              if (moreTags > 0) '+$moreTags',
            ].join(' '),
            t.muted,
            key: Key('card-tags-$uid'),
          ),
        ),
      ],
    ];
    final label = [
      item.isTask ? 'Task' : 'Note',
      if (bucket != null) '$bucket priority',
      if (due.isNotEmpty) '${late ? 'overdue, ' : ''}due $due',
      if (tagCount > 0) 'tags ${tags.isEmpty ? '$tagCount' : tags.join(', ')}',
      if (folder != null) 'in $folder',
    ].join(', ');
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            // The left group takes the row; the folder sits at the right end
            // (capped, so a long name cannot squeeze the tags).
            Expanded(child: Row(children: parts)),
            if (folder != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4),
                child: Padding(
                  padding: EdgeInsets.only(left: t.space.md),
                  child: pair(
                    FLucideIcons.folder,
                    txt(folder, t.muted),
                    t.muted,
                    key: Key('card-folder-$uid'),
                  ),
                ),
              ),
          ],
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
