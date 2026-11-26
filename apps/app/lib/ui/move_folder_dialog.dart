import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'theme.dart';

/// Moves a note to Personal, a project or a folder of this Space. Folders
/// the note cannot go into (itself and what is under it) are left out.
Future<void> showMoveFolderDialog(
  BuildContext context,
  AppState state,
  Note note,
) {
  final here = state.tree.find(note.uid)?.parent?.note.uid;
  final projects = state.projectsByRecent
      .where((p) => state.tree.canMove(note.uid, p.uid))
      .toList();
  final projectUids = {for (final p in state.projectsByRecent) p.uid};
  final targets = <(String?, String, int)>[];
  void collect(List<NoteNode> nodes, int depth) {
    for (final n in nodes) {
      if (!isPersonalContainer(n.note) &&
          !isProjectsContainer(n.note) &&
          !projectUids.contains(n.note.uid) &&
          AppState.isFolder(n.note) &&
          state.tree.canMove(note.uid, n.note.uid)) {
        targets.add((n.note.uid, n.note.summary, depth));
      }
      collect(n.children, depth + 1);
    }
  }

  collect(state.tree.roots, 0);
  return showAppDialog(
    context,
    title: 'Move "${note.summary}" to…',
    width: tokensOf(context).sizes.dialogSm,
    content: Builder(
      builder: (ctx) {
        final t = tokensOf(ctx);
        Widget row(String? uid, String label, int depth, IconData icon) =>
            Padding(
              padding: EdgeInsets.only(left: depth * t.space.lg),
              child: FItem(
                key: Key('move-folder-${uid ?? 'top'}'),
                enabled: uid != here,
                prefix: Icon(icon, size: t.icons.lg),
                title: Text(label, overflow: TextOverflow.ellipsis),
                onPress: () {
                  Navigator.of(ctx).pop();
                  state.moveNote(note.uid, uid);
                },
              ),
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(null, 'Personal', 0, FLucideIcons.arrowUpToLine),
            for (final p in projects)
              row(
                p.uid,
                p.summary.isEmpty ? 'Untitled' : p.summary,
                0,
                FLucideIcons.folderKanban,
              ),
            for (final (uid, label, depth) in targets)
              row(uid, label, depth, FLucideIcons.folder),
          ],
        );
      },
    ),
    actions: [const CancelButton()],
  );
}
