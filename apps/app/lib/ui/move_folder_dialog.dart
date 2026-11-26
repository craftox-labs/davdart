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
  final parentUid = state.tree.find(note.uid)?.parent?.note.uid;
  final personal = state.personalContainer;
  // No container yet: an editable Space creates one on the move; a
  // read-only Space's Personal is the top level.
  final canCreatePersonal = personal == null && state.editable;
  final atPersonal = personal != null
      ? parentUid == personal.uid
      : (!canCreatePersonal && parentUid == null);
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
        Widget row(
          String? uid,
          String label,
          int depth,
          IconData icon, {
          String? keyName,
          bool? enabled,
          Future<void> Function()? onPress,
        }) => Padding(
          padding: EdgeInsets.only(left: depth * t.space.lg),
          child: FItem(
            key: Key('move-folder-${keyName ?? uid ?? 'top'}'),
            enabled: enabled ?? uid != parentUid,
            prefix: Icon(icon, size: t.icons.lg),
            title: Text(label, overflow: TextOverflow.ellipsis),
            onPress: () {
              Navigator.of(ctx).pop();
              if (onPress != null) {
                onPress();
              } else {
                state.moveNote(note.uid, uid);
              }
            },
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Personal is the real container (created on the move when it is
            // missing); its row stays hidden from folder/project targets.
            row(
              personal?.uid,
              'Personal',
              0,
              FLucideIcons.arrowUpToLine,
              keyName: 'personal',
              enabled: !atPersonal,
              onPress: () async {
                final target =
                    personal?.uid ?? await state.ensurePersonalContainer();
                await state.moveNote(note.uid, target);
              },
            ),
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
