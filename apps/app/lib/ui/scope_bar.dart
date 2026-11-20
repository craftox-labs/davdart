import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import '../theme/tokens.dart';
import 'theme.dart';
import 'edit_note_dialog.dart';
import 'move_space_dialog.dart';

/// The Home breadcrumb above Board and List: "Home › Space" or, inside a
/// folder, "Home › Space › folder". The Space name is a link back to the whole
/// Space. A folder adds its text and actions.
class ScopeBar extends StatelessWidget {
  const ScopeBar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final folder = state.scope;
    final t = tokensOf(context);
    final path = <Note>[];
    for (
      var n = folder == null ? null : state.tree.find(folder.uid);
      n != null;
      n = n.parent
    ) {
      path.insert(0, n.note);
    }
    return Container(
      key: const Key('scope-bar'),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        t.space.xl,
        t.space.md,
        t.space.md,
        t.space.md,
      ),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(
          bottom: BorderSide(color: t.divider, width: t.borders.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                folder == null ? FLucideIcons.house : FLucideIcons.folderOpen,
                size: t.icons.lg,
                color: t.accent,
              ),
              SizedBox(width: t.space.md),
              Expanded(child: _crumbs(context, t, path, folder != null)),
              if (folder != null && state.editable) ...[
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
              if (folder != null)
                IconAction(
                  key: const Key('scope-close'),
                  tooltip: 'Show the whole space',
                  icon: FLucideIcons.x,
                  onPress: () => state.openFolder(null),
                ),
            ],
          ),
          if (folder != null && folder.description.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: t.space.sm),
              child: Text(
                folder.description.trim(),
                key: const Key('scope-text'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: t.type.captionStyle.copyWith(color: t.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _crumbs(BuildContext context, Tokens t, List<Note> path, bool scoped) {
    final space = state.currentSpaceName ?? 'Notes';
    final style = t.type.bodyStrong;
    final sep = Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.sm),
      child: Text('›', style: style.copyWith(color: t.muted)),
    );
    final folders = path.map((n) => n.summary).where((e) => e.isNotEmpty);
    return Row(
      children: [
        Flexible(
          child: Text(
            'Home',
            key: const Key('crumb-home'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (space.isNotEmpty) ...[
          sep,
          Flexible(
            child: scoped
                ? FTappable(
                    key: const Key('crumb-space'),
                    semanticsLabel: 'Show the whole space',
                    onPress: () => state.openFolder(null),
                    builder: (_, _, _) => Text(
                      space,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(color: t.muted),
                    ),
                  )
                : Text(
                    space,
                    key: const Key('crumb-space'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
          ),
        ],
        if (folders.isNotEmpty) ...[
          sep,
          Flexible(
            flex: 2,
            child: Text(
              folders.join('  ›  '),
              key: const Key('crumb-folder'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ],
    );
  }
}
