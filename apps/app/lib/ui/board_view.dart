import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import 'drag_drop.dart';
import 'board_layout.dart';
import 'new_note_dialog.dart';
import 'note_menu.dart';
import 'theme.dart';
import 'overflow_tip.dart';

class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.state,
    this.includeNoStatus = true,
    this.embedded = false,
  });
  final AppState state;

  /// Phone Home: the accordion sizes to its content and does not scroll, so
  /// a parent scroll view carries it with the Today section.
  final bool embedded;

  /// Whether notes with no status get a column (off on Home).
  final bool includeNoStatus;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (state.error != null && state.notes.isEmpty) {
      return Center(
        child: Text(state.error!, style: TextStyle(color: t.muted)),
      );
    }
    final cols = state.columns(includeNoStatus: includeNoStatus);
    if (cols.isEmpty && !state.loading) {
      final hasNotes = state.filtered.isNotEmpty;
      return Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Text(
            hasNotes
                ? 'No work items yet. Give a note a status (backlog, todo, doing...) and it shows up here.'
                : 'No notes',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted),
          ),
        ),
      );
    }
    return BoardLayout<Note>(
      cols: cols,
      openMap: state.nav.boardOpen,
      modified: (n) => n.lastModified,
      embedded: embedded,
      dot: (n) => n == 'notes' || n == otherColumn ? null : n,
      wrap: (name, child) => _drop(name, context, child),
      itemBuilder: (name, n, compact) =>
          _Card(state: state, note: n, column: name, compact: compact),
    );
  }

  /// Makes a column a drop target that sets the dropped note's status, and
  /// gives it a right-click menu to add a note in that status.
  Widget _drop(String name, BuildContext context, Widget column) {
    // Other holds words outside the fixed set: it is not a status to drop on.
    if (name == otherColumn) return column;
    final status = name == 'notes' ? null : name;
    return NoteDropTarget(
      key: Key('board-drop-$name'),
      accepts: (d) {
        final n = state.tree.find(d.uid)?.note;
        return state.editable &&
            n != null &&
            !AppState.isFolder(n) &&
            PlanItem.fromNote(n).status != status;
      },
      onDrop: (d) => state.setStatus(d.uid, status),
      child: ActionContextMenu(
        groups: [
          if (state.editable && status != null)
            [
              NoteMenuItem(
                'New note in $name…',
                FLucideIcons.filePlus,
                () => showNewNoteDialog(context, state, status: status),
                key: Key('menu-board-new-$name'),
              ),
            ],
        ],
        child: column,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.state,
    required this.note,
    required this.column,
    this.compact = false,
  });

  /// Narrow layout: the title alone, no id, description or owner line.
  final bool compact;
  final AppState state;
  final Note note;

  /// The column this card sits in ('notes' is the no-status column, 'other'
  /// the one for words outside the fixed set).
  final String column;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = PlanItem.fromNote(note);
    final selected = state.peekUid == note.uid;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: NoteContextMenu(
        state: state,
        uid: note.uid,
        items: [
          if (state.editable && column != 'notes' && column != otherColumn)
            NoteMenuItem(
              'New note in $column…',
              FLucideIcons.filePlus,
              () => showNewNoteDialog(context, state, status: column),
              key: Key('menu-card-new-$column'),
            ),
        ],
        child: NoteDraggable(
          uid: note.uid,
          source: NoteDragSource.board,
          label: note.summary,
          child: FTappable(
            onPress: () => state.clickNote(note.uid),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(t.radii.card),
                border: Border.all(color: selected ? t.accent : t.cardBorder),
              ),
              child: Padding(
                padding: EdgeInsets.all(t.space.lg),
                child: compact
                    ? Text(note.summary, style: t.type.semiboldStyle)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.itemId ?? note.summary,
                            style: t.type.semiboldStyle,
                          ),
                          if (p.itemId != null) ...[
                            SizedBox(height: t.space.xxs),
                            OverflowTip(
                              note.summary,
                              maxLines: 2,
                              style: t.type.bodyStyle.copyWith(color: t.muted),
                            ),
                          ],
                          if (p.priorityWord != null) ...[
                            SizedBox(height: t.space.sm),
                            Text(
                              _label(p.priorityWord!),
                              key: Key('card-priority-${note.uid}'),
                              style: t.type.captionStyle.copyWith(
                                color: p.priorityWord == 'high'
                                    ? t.accent
                                    : t.muted,
                              ),
                            ),
                          ],
                          if (p.owner != null) ...[
                            SizedBox(height: t.space.sm),
                            Text(
                              p.owner!,
                              style: t.type.captionStyle.copyWith(
                                color: t.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _label(String w) => '${w[0].toUpperCase()}${w.substring(1)}';
}
