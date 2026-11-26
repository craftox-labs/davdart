import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import 'drag_drop.dart';
import 'chips.dart';
import 'note_menu.dart';
import 'theme.dart';
import 'overflow_tip.dart';

/// Notes as an indented tree; a flat list of matches while searching.
class NoteListView extends StatelessWidget {
  const NoteListView({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (state.error != null && state.notes.isEmpty) {
      return Center(
        child: Text(state.error!, style: TextStyle(color: t.muted)),
      );
    }
    final rows = <(Note, int)>[];
    final filtering = state.query.trim().isNotEmpty || state.tag != null;
    if (filtering) {
      rows.addAll([for (final n in state.filtered) (n, 0)]);
    } else {
      void walk(List<NoteNode> nodes, int depth) {
        for (final n in nodes) {
          rows.add((n.note, depth));
          if (!state.collapsed.contains(n.note.uid)) {
            walk(n.children, depth + 1);
          }
        }
      }

      walk(state.spaceTreeRoots, 0);
    }
    if (rows.isEmpty && !state.loading) {
      return Center(
        child: Text('No notes', style: TextStyle(color: t.muted)),
      );
    }
    final list = ListView.separated(
      padding: EdgeInsets.only(bottom: fabInset(context)),
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          Container(height: t.borders.hairline, color: t.divider),
      itemBuilder: (context, i) {
        final (n, depth) = rows[i];
        final p = PlanItem.fromNote(n);
        final kids = state.tree.find(n.uid)?.children.isNotEmpty ?? false;
        Widget row = NoteContextMenu(
          state: state,
          uid: n.uid,
          child: NoteDraggable(
            uid: n.uid,
            source: NoteDragSource.list,
            label: n.summary,
            child: FTappable(
              onPress: () => state.clickNote(n.uid),
              child: Container(
                color: state.peekUid == n.uid ? t.selected : null,
                padding: EdgeInsets.fromLTRB(
                  t.space.lg + depth * t.sizes.listIndent,
                  t.space.lg - t.space.xxs,
                  t.space.lg,
                  t.space.lg - t.space.xxs,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: t.sizes.listChevronBox,
                      child: kids && !filtering
                          ? FTappable(
                              semanticsLabel: state.collapsed.contains(n.uid)
                                  ? 'Expand'
                                  : 'Collapse',
                              behavior: HitTestBehavior.opaque,
                              onPress: () => state.toggle(n.uid),
                              child: Icon(
                                state.collapsed.contains(n.uid)
                                    ? FLucideIcons.chevronRight
                                    : FLucideIcons.chevronDown,
                                size: t.icons.lg,
                                color: t.muted,
                              ),
                            )
                          : null,
                    ),
                    StatusDot(p.status),
                    SizedBox(width: t.space.lg - t.space.xxs),
                    Expanded(child: OverflowTip(n.summary)),
                    if (p.owner != null)
                      Text(
                        p.owner!,
                        style: t.type.captionStyle.copyWith(color: t.muted),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (!filtering && AppState.isFolder(n)) {
          row = MoveDropTarget(
            state: state,
            folderUid: n.uid,
            rounded: false,
            child: row,
          );
        }
        return row;
      },
    );
    if (filtering) return list;
    return MoveDropTarget(
      key: const Key('list-drop-root'),
      state: state,
      folderUid: null,
      rounded: false,
      child: list,
    );
  }
}
