import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import 'key_nav_ui.dart';
import '../state/note_drag.dart';
import '../theme/tokens.dart';
import 'drag_drop.dart';
import 'board_layout.dart';
import 'new_note_dialog.dart';
import 'note_menu.dart';
import 'theme.dart';
import 'overflow_tip.dart';

/// Publishes the Home board's cards (column by column) as the keyboard rows
/// of the Home grid; a collapsed Board is skipped at move time.
void publishBoardNav(AppState state) {
  final cols = state.homeColumns();
  final open = cols.isEmpty ? '' : boardDefaultOpen(cols);
  state.nav.publishHome('board', [
    for (final (name, notes) in cols)
      for (final n in boardCapped(
        name,
        notes,
        (n) => n.lastModified,
        showAll: state.nav.boardOpen[boardDoneAllKey] ?? false,
      ))
        NavEntry(
          'card-${n.uid}',
          uid: n.uid,
          block: 'col:$name',
          open: (mode) async {
            await state.openNote(n.uid, mode: mode);
          },
          hidden: () =>
              state.nav.boardAccordion &&
              !(state.nav.boardOpen[name] ?? name == open),
        ),
  ]);
}

class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.state,
    this.includeNoStatus = true,
    this.keyboard = false,
    this.embedded = false,
  });
  final AppState state;

  /// Phone Home: the accordion sizes to its content and does not scroll, so
  /// a parent scroll view carries it with the Today section.
  final bool embedded;

  /// Home's board: the cards are rows of the keyboard grid.
  final bool keyboard;

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
    final cols = keyboard
        ? state.homeColumns()
        : state.columns(includeNoStatus: includeNoStatus);
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
      dot: (n) => n == 'notes' ? null : n,
      onShowAll: keyboard ? () => publishBoardNav(state) : null,
      onAccordion: keyboard ? (a) => state.nav.boardAccordion = a : null,
      wrap: (name, child) => _drop(name, context, child),
      itemBuilder: (name, n, compact) => _Card(
        state: state,
        note: n,
        column: name,
        home: keyboard,
        compact: compact,
      ),
    );
  }

  /// Makes a column a drop target that sets the dropped note's status, and
  /// gives it a right-click menu to add a note in that status.
  Widget _drop(String name, BuildContext context, Widget column) {
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
    this.home = false,
    this.compact = false,
  });
  final bool home;

  /// Narrow layout: the title alone, no id, description or owner line.
  final bool compact;
  final AppState state;
  final Note note;

  /// The column this card sits in ('notes' is the no-status column).
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
          if (state.editable && column != 'notes')
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
          child: _keyRow(
            t,
            FTappable(
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
                                style: t.type.bodyStyle.copyWith(
                                  color: t.muted,
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
      ),
    );
  }

  Widget _keyRow(Tokens t, Widget child) => home
      ? NavRow(
          key: ValueKey('nav-card-${note.uid}'),
          nav: state.nav,
          list: KeyNav.homeList,
          id: 'card-${note.uid}',
          radius: t.radii.card,
          child: child,
        )
      : child;
}
