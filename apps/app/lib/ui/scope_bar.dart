import 'package:davdart/davdart.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import 'markdown_lite.dart';
import 'edit_note_dialog.dart';

/// Shown above Board and List while a folder is open: where you are, the
/// folder's text, and a way back to the whole Space.
class ScopeBar extends StatelessWidget {
  const ScopeBar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final folder = state.scope;
    if (folder == null) return const SizedBox.shrink();
    final t = Theme.of(context).extension<TokensTheme>()!.tokens;
    final path = <Note>[];
    for (var n = state.tree.find(folder.uid); n != null; n = n.parent) {
      path.insert(0, n.note);
    }
    return Container(
      key: const Key('scope-bar'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.folder_open, size: 18, color: t.accent),
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
            IconButton(
              key: const Key('scope-edit'),
              tooltip: 'Edit folder',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => showEditNoteDialog(context, state, folder),
            ),
            IconButton(
              key: const Key('scope-delete'),
              tooltip: 'Delete folder',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => confirmDeleteNote(context, state, folder),
            ),
          ],
          IconButton(
            key: const Key('scope-close'),
            tooltip: 'Show the whole space',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => state.openFolder(null),
          ),
        ],
      ),
    );
  }
}
