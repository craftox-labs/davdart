import 'package:davdart/davdart.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import 'chips.dart';
import 'markdown_lite.dart';

/// Notes as an indented tree; a flat list of matches while searching.
class NoteListView extends StatelessWidget {
  const NoteListView({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TokensTheme>()!.tokens;
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

      walk(state.tree.roots, 0);
    }
    if (rows.isEmpty && !state.loading) {
      return Center(
        child: Text('No notes', style: TextStyle(color: t.muted)),
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: t.line),
      itemBuilder: (context, i) {
        final (n, depth) = rows[i];
        final p = PlanItem.fromNote(n);
        final kids = state.tree.find(n.uid)?.children.isNotEmpty ?? false;
        return InkWell(
          onTap: () => state.select(n.uid),
          child: Container(
            color: state.selectedUid == n.uid ? t.surface : null,
            padding: EdgeInsets.fromLTRB(12 + depth * 20.0, 10, 12, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: kids && !filtering
                      ? InkWell(
                          onTap: () => state.toggle(n.uid),
                          child: Icon(
                            state.collapsed.contains(n.uid)
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            size: 18,
                            color: t.muted,
                          ),
                        )
                      : null,
                ),
                StatusDot(p.status),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    n.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (p.owner != null)
                  Text(
                    p.owner!,
                    style: TextStyle(fontSize: 12, color: t.muted),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
