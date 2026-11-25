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
class ScopeCrumbs extends StatefulWidget {
  const ScopeCrumbs({
    super.key,
    required this.state,
    this.label,
    this.compact = false,
  });
  final AppState state;
  final String? label;

  /// Phone: inside a folder the row is "[house] › … › Current", the current
  /// folder taking all the remaining width (up to two lines) and the
  /// ancestors folded into the "…" sheet.
  final bool compact;

  @override
  State<ScopeCrumbs> createState() => _ScopeCrumbsState();
}

class _ScopeCrumbsState extends State<ScopeCrumbs>
    with TickerProviderStateMixin {
  AppState get state => widget.state;

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
    // The Projects container level is skipped: Space > Project > folders.
    if (path.length > 1) {
      final last = path.last;
      path.removeWhere((n) => n != last && isProjectsContainer(n));
    }
    return widget.compact && folder != null
        ? _compact(context, t, path)
        : _crumbs(context, t, path, folder != null);
  }

  String get _space =>
      state.currentSpaceName ?? (state.noSpace ? 'No space' : 'Notes');

  /// Phone breadcrumb inside a folder: house › … › current.
  Widget _compact(BuildContext context, Tokens t, List<Note> path) {
    final style = paneTitleStyle(t);
    final names = [
      for (final n in path) n.summary.isEmpty ? 'Untitled' : n.summary,
    ];
    final ancestors = path.length > 1
        ? path.sublist(0, path.length - 1)
        : <Note>[];
    Widget sep() => Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.xs),
      child: Text('›', style: style.copyWith(color: t.muted)),
    );
    return Row(
      children: [
        FTappable(
          key: const Key('crumb-space'),
          semanticsLabel: 'Show the whole space',
          onPress: () => state.openFolder(null),
          builder: (_, _, _) => Padding(
            padding: EdgeInsets.all(t.space.xs),
            child: Icon(FLucideIcons.house, size: t.icons.lg, color: t.accent),
          ),
        ),
        sep(),
        if (ancestors.isNotEmpty) ...[
          FTappable(
            key: const Key('crumb-more'),
            semanticsLabel: 'Parent folders',
            onPress: () => _showAncestors(context, t, path),
            builder: (_, _, _) => Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space.xs),
              child: Text('…', style: style.copyWith(color: t.muted)),
            ),
          ),
          sep(),
        ],
        Expanded(
          child: Semantics(
            label: [_space, ...names].join(' › '),
            excludeSemantics: true,
            child: OverflowTip(
              names.last,
              textKey: const Key('crumb-folder'),
              maxLines: 2,
              style: style,
            ),
          ),
        ),
      ],
    );
  }

  /// Sheet listing the Space root and every ancestor, top-down, indented.
  void _showAncestors(BuildContext context, Tokens t, List<Note> path) {
    final ancestors = path.sublist(0, path.length - 1);
    showMenuSheet(context, this, (ctx, c) {
      FItem row(Key key, IconData icon, String label, int level, String? uid) =>
          FItem(
            key: key,
            prefix: Padding(
              padding: EdgeInsets.only(left: t.space.lg * level),
              child: Icon(icon, size: t.icons.md, color: t.muted),
            ),
            title: Text(label),
            onPress: () {
              c.hide();
              state.openFolder(uid);
            },
          );
      return [
        FItemGroup(
          children: [
            row(
              const Key('crumb-anc-root'),
              FLucideIcons.house,
              _space,
              0,
              null,
            ),
            for (var i = 0; i < ancestors.length; i++)
              row(
                Key('crumb-anc-${i + 1}'),
                FLucideIcons.folder,
                ancestors[i].summary.isEmpty
                    ? 'Untitled'
                    : ancestors[i].summary,
                i + 1,
                ancestors[i].uid,
              ),
          ],
        ),
      ];
    });
  }

  Widget _crumbs(BuildContext context, Tokens t, List<Note> path, bool scoped) {
    final space = (!scoped ? widget.label : null) ?? _space;
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

/// The thin row above the narrow layout's content: the folder path once the
/// scope is below a project (or a folder outside one), and the name of a
/// saved view. Nothing at the Space root or on a project itself: the top
/// bar's pill shows those.
class NarrowCrumbs extends StatelessWidget {
  const NarrowCrumbs({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final scope = state.scopeUid;
    final project = scope == null ? null : state.projectIndex.projectOf(scope);
    final belowProject = scope != null && project?.uid != scope;
    final view = state.activeViewName;
    if (!belowProject && view == null) return const SizedBox.shrink();
    return SizedBox(
      key: const Key('content-crumbs'),
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space.md, t.space.xs, t.space.md, 0),
        child: ScopeCrumbs(state: state, label: view, compact: true),
      ),
    );
  }
}

/// The open folder's actions as sheet groups, for the narrow scope picker:
/// the same rows as [ScopeActions]. Empty when no folder is open.
List<FItemGroupMixin> scopeActionsGroup(
  BuildContext context,
  AppState state,
  FPopoverController controller,
) {
  final folder = state.scope;
  if (folder == null) return const [];
  return [
    FItemGroup(
      children: menuRows(context, controller, [
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
  ];
}

/// Folder actions (move, edit, delete, close) for the right end of the top
/// bar, folded into one "more" menu on every width; empty when no folder is
/// open. The narrow layout puts the same rows in the scope picker sheet,
/// see [scopeActionsGroup].
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
    menuBuilder: (ctx, controller, _) =>
        scopeActionsGroup(context, state, controller),
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
