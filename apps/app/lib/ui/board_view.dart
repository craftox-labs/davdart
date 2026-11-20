import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import 'key_nav_ui.dart';
import '../state/note_drag.dart';
import '../theme/tokens.dart';
import 'drag_drop.dart';
import 'chips.dart';
import 'collapsible_section.dart';
import 'content_grid.dart';
import 'new_note_dialog.dart';
import 'note_menu.dart';
import 'theme.dart';
import 'overflow_tip.dart';

/// Publishes the Home board's cards (column by column) as the keyboard rows
/// of the Home grid; a collapsed Board is skipped at move time.
/// The status whose accordion section starts open: doing, else the first
/// status with notes.
String boardDefaultOpen(List<(String, List<Note>)> cols) =>
    cols.any((c) => c.$1 == 'doing' && c.$2.isNotEmpty)
    ? 'doing'
    : cols.firstWhere((c) => c.$2.isNotEmpty, orElse: () => cols.first).$1;

void publishBoardNav(AppState state) {
  final cols = state.columns(includeNoStatus: false);
  final open = cols.isEmpty ? '' : boardDefaultOpen(cols);
  state.nav.publishHome('board', [
    for (final (name, notes) in state.columns(includeNoStatus: false))
      for (final n in notes)
        NavEntry(
          'card-${n.uid}',
          uid: n.uid,
          block: 'col:$name',
          open: (mode) async {
            await state.openNote(n.uid, mode: mode);
          },
          hidden: () =>
              state.prefs?.read('davdart.home.board.collapsed.v1') == 'true' ||
              (state.nav.boardAccordion &&
                  !(state.nav.boardOpen[name] ?? name == open)),
        ),
  ]);
}

class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.state,
    this.includeNoStatus = true,
    this.keyboard = false,
  });
  final AppState state;

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
    final gap = t.space.lg;
    Widget column(String name, List<Note> notes) => _drop(
      name,
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              t.space.xs,
              t.space.xs,
              t.space.xs,
              t.space.md,
            ),
            child: Row(
              children: [
                StatusDot(name == 'notes' ? null : name),
                SizedBox(width: t.space.md),
                Text(
                  name.toUpperCase(),
                  style: t.type.labelStyle.copyWith(
                    fontSize: t.type.caption,
                    color: t.muted,
                  ),
                ),
                SizedBox(width: t.space.sm),
                Text(
                  '${notes.length}',
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              scrollCacheExtent: navCacheExtent,
              children: [
                for (final n in notes)
                  _Card(state: state, note: n, column: name, home: keyboard),
              ],
            ),
          ),
        ],
      ),
    );
    // Phone widths: one column, a collapsible section per status, cards
    // with the title only. Doing (else the first status with notes) starts
    // open. Cards of a collapsed section are not built.
    if (keyboard) state.nav.boardAccordion = false;
    if (MediaQuery.sizeOf(context).width < Tokens.stackBreakpoint) {
      final open = boardDefaultOpen(cols);
      if (keyboard) state.nav.boardAccordion = true;
      return ListView(
        key: const Key('board-accordion'),
        padding: EdgeInsets.all(gap),
        children: [
          for (final (name, notes) in cols)
            _drop(
              name,
              context,
              CollapsibleSection(
                key: ValueKey('board-acc-$name'),
                id: 'board-acc-$name',
                title: name,
                count: notes.length,
                initiallyCollapsed:
                    !(state.nav.boardOpen[name] ?? name == open),
                onChanged: (collapsed) =>
                    state.nav.boardOpen[name] = !collapsed,
                leading: StatusDot(name == 'notes' ? null : name),
                headerPadding: EdgeInsets.only(bottom: t.space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final n in notes)
                      _Card(
                        state: state,
                        note: n,
                        column: name,
                        home: keyboard,
                        compact: true,
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return ContentCap(
      child: LayoutBuilder(
        builder: (context, c) {
          final avail = c.maxWidth - 2 * gap;
          final each = (avail - (cols.length - 1) * gap) / cols.length;
          final fits = each >= t.sizes.boardColumn;
          if (fits) {
            // Equal columns share the full width; gutters sit between them.
            return Padding(
              padding: EdgeInsets.all(gap),
              child: Row(
                children: [
                  for (var i = 0; i < cols.length; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    Expanded(child: column(cols[i].$1, cols[i].$2)),
                  ],
                ],
              ),
            );
          }
          // Too narrow for the minimum: fixed-width columns that scroll.
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.all(gap),
            children: [
              for (var i = 0; i < cols.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                SizedBox(
                  width: t.sizes.boardColumn,
                  child: column(cols[i].$1, cols[i].$2),
                ),
              ],
            ],
          );
        },
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
