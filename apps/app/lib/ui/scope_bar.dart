import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'theme.dart';
import 'edit_note_dialog.dart';
import 'move_space_dialog.dart';

/// Shown above Board and List while a folder is open: where you are, the
/// folder's text, and a way back to the whole Space.
class ScopeBar extends StatelessWidget {
  const ScopeBar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final folder = state.scope;
    if (folder == null) return const SizedBox.shrink();
    final t = tokensOf(context);
    final path = <Note>[];
    for (var n = state.tree.find(folder.uid); n != null; n = n.parent) {
      path.insert(0, n.note);
    }
    return Container(
      key: const Key('scope-bar'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FLucideIcons.folderOpen, size: 18, color: t.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    state.currentSpaceName ?? '',
                    ...path.map((n) => n.summary),
                  ].where((e) => e.isNotEmpty).join('  /  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (folder.description.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      folder.description.trim(),
                      key: const Key('scope-text'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ),
              ],
            ),
          ),
          if (state.editable) ...[
            if (state.spaces.length > 1)
              IconAction(
                key: const Key('scope-move'),
                tooltip: 'Move folder to another space',
                icon: FLucideIcons.folderInput,
                onPress: () => showMoveSpaceDialog(context, state, folder),
              ),
            IconAction(
              key: const Key('scope-edit'),
              tooltip: 'Edit folder',
              icon: FLucideIcons.pencil,
              onPress: () => showEditNoteDialog(context, state, folder),
            ),
            IconAction(
              key: const Key('scope-delete'),
              tooltip: 'Delete folder',
              icon: FLucideIcons.trash2,
              onPress: () => confirmDeleteNote(context, state, folder),
            ),
          ],
          IconAction(
            key: const Key('scope-close'),
            tooltip: 'Show the whole space',
            icon: FLucideIcons.x,
            onPress: () => state.openFolder(null),
          ),
        ],
      ),
    );
  }
}
