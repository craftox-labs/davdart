import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import 'drag_drop.dart';
import 'chips.dart';
import 'note_menu.dart';
import 'empty_state.dart';
import 'surface.dart';
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
      return EmptyState(state.error!, centered: true, error: true);
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
      return const EmptyState('No notes', centered: true);
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
        final folder = AppState.isFolder(n);
        final body = FTappable(
          onPress: () => state.clickNote(n.uid),
          child: Surface(
            selected: state.peekUid == n.uid,
            square: true,
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
        );
        return NoteContextMenu(
          state: state,
          uid: n.uid,
          // Folders neither drag nor take a drop here: folder moves belong to
          // the Notes tree, so this view has no folder drop targets.
          child: folder
              ? body
              : NoteDraggable(
                  uid: n.uid,
                  source: NoteDragSource.list,
                  label: n.summary,
                  child: body,
                ),
        );
      },
    );
    return list;
  }
}
