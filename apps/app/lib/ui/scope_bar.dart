import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'edit_note_dialog.dart';
import 'move_space_dialog.dart';
import 'note_menu.dart';
import 'overflow_tip.dart';
import 'parts.dart';
import 'theme.dart';

/// The breadcrumb in the Home top bar: "[house] Space" or, inside a folder,
/// "[house] Space › folder". The Space is the root crumb, with the house icon,
/// and a link back to the whole Space. It sits plain on the header row, at a
/// fixed left position: the folder actions live in [ScopeActions] on the
/// right, so scoping never moves it. [label] replaces the Space name (a saved
/// view's name) while no folder is open.
class ScopeCrumbs extends StatelessWidget {
  const ScopeCrumbs({super.key, required this.state, this.label});
  final AppState state;
  final String? label;

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
    return _crumbs(context, t, path, folder != null);
  }

  Widget _crumbs(BuildContext context, Tokens t, List<Note> path, bool scoped) {
    final space =
        (!scoped ? label : null) ??
        state.currentSpaceName ??
        (state.noSpace ? 'No space' : 'Notes');
    final style = paneTitleStyle(t);
    final sep = Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.sm),
      child: Text('›', style: style.copyWith(color: t.muted)),
    );
    final folders = path.map((n) => n.summary).where((e) => e.isNotEmpty);
    return Row(
      children: [
        Icon(FLucideIcons.house, size: t.icons.lg, color: t.accent),
        SizedBox(width: t.space.md),
        Flexible(
          child: scoped
              ? FTappable(
                  key: const Key('crumb-space'),
                  semanticsLabel: 'Show the whole space',
                  onPress: () => state.openFolder(null),
                  builder: (_, _, _) =>
                      OverflowTip(space, style: style.copyWith(color: t.muted)),
                )
              : OverflowTip(
                  space,
                  textKey: const Key('crumb-space'),
                  style: style,
                ),
        ),
        if (folders.isNotEmpty) ...[
          sep,
          Flexible(
            flex: 2,
            child: OverflowTip(
              folders.join('  ›  '),
              textKey: const Key('crumb-folder'),
              style: style,
            ),
          ),
        ],
      ],
    );
  }
}

/// Folder actions (move, edit, delete, close) for the right end of the top
/// bar, folded into one "more" menu on every width; empty when no folder is
/// open.
class ScopeActions extends StatelessWidget {
  const ScopeActions({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final folder = state.scope;
    if (folder == null) return const SizedBox.shrink();
    return _menu(context, folder);
  }
}

extension on ScopeActions {
  Widget _menu(BuildContext context, Note folder) => FPopoverMenu(
    menuAnchor: Alignment.topRight,
    childAnchor: Alignment.bottomRight,
    menuBuilder: (ctx, controller, _) => [
      FItemGroup(
        children: menuRows(ctx, controller, [
          if (state.editable) ...[
            if (state.spaces.length > 1)
              NoteMenuItem(
                'Move to another space',
                FLucideIcons.folderInput,
                () => showMoveSpaceDialog(context, state, folder),
                key: const Key('scope-move'),
              ),
            NoteMenuItem(
              'Edit folder',
              FLucideIcons.pencil,
              () => showEditNoteDialog(context, state, folder),
              key: const Key('scope-edit'),
            ),
            NoteMenuItem(
              'Delete folder',
              FLucideIcons.trash2,
              () => confirmDeleteNote(context, state, folder),
              key: const Key('scope-delete'),
            ),
          ],
          NoteMenuItem(
            'Show the whole space',
            FLucideIcons.x,
            () => state.openFolder(null),
            key: const Key('scope-close'),
          ),
        ]),
      ),
    ],
    builder: (ctx, controller, _) => IconAction(
      key: const Key('scope-more'),
      compact: true,
      tooltip: 'Folder actions',
      icon: FLucideIcons.ellipsis,
      onPress: controller.toggle,
    ),
  );
}

/// The open folder's description, plain and full width under the header row.
/// Nothing when there is no folder or no text.
class ScopeText extends StatelessWidget {
  const ScopeText({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final folder = state.scope;
    final text = folder?.description.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final t = tokensOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        t.space.md,
        t.space.sm,
        t.space.md,
        t.space.sm,
      ),
      child: SizedBox(
        width: double.infinity,
        child: OverflowTip(
          text,
          textKey: const Key('scope-text'),
          maxLines: 3,
          style: t.type.captionStyle.copyWith(color: t.muted),
        ),
      ),
    );
  }
}

/// The active search as one slim chip, `search "foo" x`: its x clears the
/// search. The folder scope is not repeated here (the breadcrumb shows it and
/// has its own clear). Nothing, and no space, when no search is active. The
/// Home switcher places it: in its row on wide screens, on a line above it on
/// phones.
class FilterChips extends StatelessWidget {
  const FilterChips({super.key, required this.state, this.fullWidth = false});
  final AppState state;

  /// Phone: the chip runs the full width of its parent, text left, x right.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final q = state.query.trim();
    if (q.isEmpty) return const SizedBox.shrink();
    final t = tokensOf(context);
    return Semantics(
      container: true,
      label: 'Filtered by search "$q"',
      child: ConstrainedBox(
        key: const Key('filter-chips'),
        constraints: BoxConstraints(maxHeight: t.sizes.filterChipRow),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: fullWidth ? null : 1,
          heightFactor: 1,
          child: SizedBox(
            width: fullWidth ? double.infinity : null,
            child: FBadge(
              key: const Key('filter-chip-search'),
              variant: FBadgeVariant.outline,
              child: Row(
                mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (fullWidth)
                    Expanded(
                      child: Text(
                        'search "$q"',
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                      ),
                    )
                  else
                    Flexible(
                      child: Text(
                        'search "$q"',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  SizedBox(width: t.space.xs),
                  FTappable(
                    key: const Key('clear-filter-search'),
                    semanticsLabel: 'Clear search',
                    onPress: state.clearSearch,
                    builder: (_, _, _) =>
                        Icon(FLucideIcons.x, size: t.icons.sm),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
