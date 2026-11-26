import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/space_catalog.dart';
import '../state/app_state.dart';
import '../state/key_nav.dart';
import '../state/note_drag.dart';
import 'account_dialog.dart';
import 'command_palette.dart';
import 'connect_dialog.dart';
import 'drag_drop.dart';
import 'key_nav_ui.dart';
import 'new_folder_dialog.dart';
import 'new_note_dialog.dart';
import 'new_space_dialog.dart';
import 'note_menu.dart';
import 'parts.dart';
import 'save_view_dialog.dart';
import 'side_panel.dart';
import 'segmented.dart';
import 'theme.dart';
import 'overflow_tip.dart';
import 'panel_tags_drawer.dart';
import 'section_registry.dart' show spacesLabel;
import 'space_actions.dart';

/// The panels the side panel shows, one per rail section. Each takes
/// [onPick], run after an action that should close the narrow sheet.

/// Heading line plus a scrolling list body, on the shared [SidePanelFrame].
class _Panel extends StatelessWidget {
  const _Panel({
    required this.heading,
    required this.children,
    this.trailing,
    this.wrapBody,
    this.drawer,
    this.pinned,
  });
  final Widget heading;

  /// Stays above the scrolling body (a search field must not scroll away).
  final Widget? pinned;
  final List<Widget> children;
  final Widget? trailing;

  /// Wraps the scrolling body (the drop and right-click area).
  final Widget Function(Widget body)? wrapBody;

  /// Wraps the body with the bottom tags drawer.
  final Widget Function(Widget body)? drawer;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final list = ListView(
      scrollCacheExtent: navCacheExtent,
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      children: children,
    );
    final body = pinned == null
        ? list
        : Column(
            children: [
              pinned!,
              Expanded(child: list),
            ],
          );
    return SidePanelFrame(
      title: heading,
      actions: trailing,
      body: drawer == null
          ? (wrapBody == null ? body : wrapBody!(body))
          : drawer!(wrapBody == null ? body : wrapBody!(body)),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => PaneTitle(text);
}

Widget _title(String text) => _Title(text);

class _Muted extends StatelessWidget {
  const _Muted(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: t.space.md,
        vertical: t.space.xs,
      ),
      child: Text(text, style: t.type.captionStyle.copyWith(color: t.muted)),
    );
  }
}

Widget _label(BuildContext context, String text) {
  final t = tokensOf(context);
  return Padding(
    padding: EdgeInsets.fromLTRB(
      t.space.md,
      t.space.lg + t.space.xxs,
      t.space.md,
      t.space.xs,
    ),
    child: Text(text, style: t.type.labelStyle.copyWith(color: t.muted)),
  );
}

Widget _item(IconData icon, String text, VoidCallback tap, {bool on = false}) =>
    FSidebarItem(
      icon: Icon(icon),
      label: OverflowTip(text),
      selected: on,
      onPress: tap,
    );

abstract class _Section extends StatelessWidget {
  const _Section({super.key, required this.state, required this.onPick});
  final AppState state;
  final VoidCallback onPick;
}

/// The Spaces: every Space with its sync state, the open one marked; a tap
/// switches to it. A note dragged over a row drops into that Space. Below,
/// the manage actions (new, rename, delete). Long press or right click a row
/// for its own actions.
class SpacesSection extends _Section {
  const SpacesSection({super.key, required super.state, required super.onPick});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final other = state.spaces.any((s) => s.id != state.currentSpaceId);
    state.nav.publish('spaces', [
      for (final sp in state.spaces)
        NavEntry(
          sp.id,
          uid: sp.id,
          open: (_) async {
            await state.switchSpace(sp.id);
            state.keepListSection();
            onPick();
          },
        ),
    ]);

    Widget row(
      SpaceInfo sp, {
      required Key key,
      required VoidCallback onPress,
      required Widget child,
    }) => NoteDropTarget(
      key: Key('space-drop-${sp.id}'),
      accepts: (d) =>
          sp.id != state.currentSpaceId &&
          state.editable &&
          state.findItem(d.uid) != null,
      onDrop: (d) => moveNoteToSpace(context, state, null, d.uid, sp),
      child: NavRow(
        nav: state.nav,
        list: 'spaces',
        id: sp.id,
        child: FTappable(
          key: key,
          onPress: onPress,
          child: Container(
            constraints: BoxConstraints(minHeight: t.sizes.touchTarget),
            padding: EdgeInsets.symmetric(
              horizontal: t.space.md,
              vertical: t.space.sm,
            ),
            decoration: BoxDecoration(
              color: sp.id == state.currentSpaceId ? t.selected : null,
              borderRadius: BorderRadius.circular(t.radii.small),
            ),
            child: child,
          ),
        ),
      ),
    );

    Widget space(SpaceInfo sp) {
      final on = sp.id == state.currentSpaceId;
      void open() {
        state.switchSpace(sp.id);
        state.keepListSection();
        onPick();
      }

      final rowWidget = row(
        sp,
        key: Key('space-${sp.id}'),
        onPress: open,
        child: Row(
          children: [
            Icon(
              sp.onServer ? FLucideIcons.cloud : FLucideIcons.hardDrive,
              size: t.icons.md,
              color: on ? t.accent : t.muted,
            ),
            SizedBox(width: t.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sp.name, overflow: TextOverflow.ellipsis),
                  Text(
                    spaceSyncLabel(state, sp),
                    style: t.type.captionStyle.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
            if (on) Icon(FLucideIcons.check, size: t.icons.md, color: t.accent),
          ],
        ),
      );
      return ActionContextMenu(
        groups: [
          [
            if (!on)
              NoteMenuItem(
                'Switch to this space',
                FLucideIcons.arrowRightToLine,
                open,
                key: Key('menu-space-switch-${sp.id}'),
              ),
            NoteMenuItem(
              'Rename…',
              FLucideIcons.pencil,
              () => showRenameSpaceDialog(
                context,
                state,
                id: sp.id,
                currentName: sp.name,
              ),
              key: Key('menu-space-rename-${sp.id}'),
            ),
          ],
        ],
        child: rowWidget,
      );
    }

    return _Panel(
      heading: _title(spacesLabel),
      children: [
        // Only a source with no catalog is a single fixed Space; a real one
        // that happens to be alone says nothing extra.
        if (state.catalog == null)
          const _Muted('One fixed notes source')
        else if (other)
          const _Muted('A Space holds its own notes, tasks and Calendar.'),
        for (final sp in [
          ...state.spaces.where((s) => s.id == state.currentSpaceId),
          ...state.spaces.where((s) => s.id != state.currentSpaceId),
        ])
          space(sp),
        if (state.catalog != null) ...[
          _label(context, 'MANAGE'),
          _item(FLucideIcons.plus, 'New space…', () {
            onPick();
            showNewSpaceDialog(context, state);
          }),
          if (state.currentSpaceId != null) ...[
            _item(FLucideIcons.pencil, 'Rename this space…', () {
              onPick();
              showRenameSpaceDialog(context, state);
            }),
            _item(FLucideIcons.trash2, 'Delete this space…', () {
              onPick();
              showDeleteSpaceDialog(context, state);
            }),
            if (state.currentOnServer)
              FSidebarItem(
                key: const Key('space-server-delete'),
                icon: const Icon(FLucideIcons.cloudOff),
                label: const OverflowTip('Delete from server…'),
                onPress: () {
                  onPick();
                  showDeleteFromServerDialog(context, state);
                },
              ),
          ],
        ],
      ],
    );
  }
}

/// Notes: the Space name, then the current scope's notes as a list (the
/// default), with folders named as group labels, or as the folder tree. A
/// Tree | List toggle appears when the scope has sub-folders; the choice is
/// saved ([NotesView]). The tags drawer stays at the end.
class NotesSection extends _Section {
  const NotesSection({
    super.key,
    required super.state,
    required super.onPick,
    this.scoped = false,
  });

  /// A project tab's Notes shows the open scope; the Personal section (the
  /// default) shows the individual's own notes.
  final bool scoped;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final body = <Widget>[];
    final rows = <NavEntry>[];
    final projects = state.projectIndex;
    final folders = scoped ? state.subFolders : state.personalSubFolders;
    // No sub-folders to show: the list, whatever is saved.
    final view = folders.isEmpty ? NotesView.list : state.notesView;
    final scopeOn = scoped ? state.scopeUid : null;

    /// One row's furniture: the context menu, the drag, the selected tone.
    Widget entry(
      String uid, {
      required NoteDragSource source,
      required Widget child,
      bool on = false,
    }) => NoteContextMenu(
      state: state,
      uid: uid,
      onOpen: onPick,
      child: NoteDraggable(
        uid: uid,
        source: source,
        label: state.tree.find(uid)?.note.summary ?? '',
        child: FTappable(
          onPress: () {
            final n = state.tree.find(uid)?.note;
            if (n == null) return;
            if (AppState.isFolder(n)) {
              state.guarded(() => state.openFolder(uid));
            } else {
              state.clickNote(uid);
            }
            onPick();
          },
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: t.space.md,
              vertical: t.space.sm - t.borders.hairline,
            ),
            decoration: BoxDecoration(
              color: on ? t.selected : null,
              borderRadius: BorderRadius.circular(t.radii.small),
            ),
            child: child,
          ),
        ),
      ),
    );

    if (view == NotesView.tree) {
      void walk(List<NoteNode> nodes, int depth) {
        for (final n in nodes) {
          final kids = n.children.isNotEmpty;
          final open = !state.collapsed.contains(n.note.uid);
          final on = state.peekUid == n.note.uid || scopeOn == n.note.uid;
          Widget row = entry(
            n.note.uid,
            source: NoteDragSource.tree,
            on: on,
            child: Padding(
              padding: EdgeInsets.only(left: depth * t.sizes.treeIndent),
              child: Row(
                children: [
                  SizedBox(
                    width: t.sizes.chevronBox,
                    child: kids
                        ? FTappable(
                            semanticsLabel: open ? 'Collapse' : 'Expand',
                            behavior: HitTestBehavior.opaque,
                            onPress: () => state.toggle(n.note.uid),
                            child: Icon(
                              open
                                  ? FLucideIcons.chevronDown
                                  : FLucideIcons.chevronRight,
                              size: t.icons.md,
                              color: t.muted,
                            ),
                          )
                        : null,
                  ),
                  if (AppState.isFolder(n.note)) ...[
                    Icon(
                      projects.isProject(n.note.uid)
                          ? FLucideIcons.folderKanban
                          : open && kids
                          ? FLucideIcons.folderOpen
                          : FLucideIcons.folder,
                      size: t.icons.tree,
                      color: t.muted,
                    ),
                    SizedBox(width: t.space.sm),
                  ],
                  Expanded(
                    child: OverflowTip(n.note.summary, style: t.type.bodyStyle),
                  ),
                ],
              ),
            ),
          );
          if (AppState.isFolder(n.note)) {
            row = MoveDropTarget(
              key: Key('drop-${n.note.uid}'),
              state: state,
              folderUid: n.note.uid,
              child: row,
            );
          }
          final uid = n.note.uid;
          rows.add(
            NavEntry(
              uid,
              uid: uid,
              open: (mode) async {
                if (AppState.isFolder(n.note)) {
                  await state.guarded(() => state.openFolder(uid));
                } else {
                  await state.openNote(uid, mode: mode);
                }
              },
            ),
          );
          body.add(
            NavRow(
              key: ValueKey('nav-notes-$uid'),
              nav: state.nav,
              list: 'notes',
              id: uid,
              child: row,
            ),
          );
          if (kids && open) walk(n.children, depth + 1);
        }
      }

      walk(scoped ? state.noteTreeRoots : state.personalTreeRoots, 0);
    } else {
      // The list: the scope's notes grouped under the folder they sit in.
      final scopeNotes =
          [...(scoped ? state.notesInScope : state.personalNotes)]
            ..sort((a, b) {
              final ga =
                  (scoped
                          ? state.notesGroupOf(a.uid)
                          : state.personalGroupOf(a.uid))
                      ?.summary ??
                  '';
              final gb =
                  (scoped
                          ? state.notesGroupOf(b.uid)
                          : state.personalGroupOf(b.uid))
                      ?.summary ??
                  '';
              final g = ga.toLowerCase().compareTo(gb.toLowerCase());
              return g != 0
                  ? g
                  : a.summary.toLowerCase().compareTo(b.summary.toLowerCase());
            });
      String? group;
      for (final n in scopeNotes) {
        final g =
            (scoped ? state.notesGroupOf(n.uid) : state.personalGroupOf(n.uid))
                ?.summary ??
            '';
        if (g != group) {
          group = g;
          if (g.isNotEmpty) {
            body.add(
              Padding(
                key: Key('notes-group-${n.uid}'),
                padding: EdgeInsets.fromLTRB(
                  t.space.md,
                  t.space.lg + t.space.xxs,
                  t.space.md,
                  t.space.xs,
                ),
                child: Text(
                  g,
                  style: t.type.labelStyle.copyWith(color: t.muted),
                ),
              ),
            );
          }
        }
        final on = state.peekUid == n.uid;
        final uid = n.uid;
        rows.add(
          NavEntry(
            uid,
            uid: uid,
            open: (mode) => state.openNote(uid, mode: mode),
          ),
        );
        body.add(
          NavRow(
            key: ValueKey('nav-notes-$uid'),
            nav: state.nav,
            list: 'notes',
            id: uid,
            child: entry(
              uid,
              source: NoteDragSource.list,
              on: on,
              child: Row(
                children: [
                  Icon(
                    FLucideIcons.fileText,
                    size: t.icons.tree,
                    color: t.muted,
                  ),
                  SizedBox(width: t.space.sm),
                  Expanded(
                    child: OverflowTip(n.summary, style: t.type.bodyStyle),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (scopeNotes.isEmpty) {
        body.add(
          Padding(
            key: const Key('notes-empty'),
            padding: EdgeInsets.all(t.space.md),
            child: Text(
              'No notes here yet',
              style: t.type.captionStyle.copyWith(color: t.muted),
            ),
          ),
        );
      }
    }
    state.nav.publish('notes', rows);

    return _Panel(
      heading: _title('Notes'),
      pinned: folders.isEmpty
          ? null
          : Padding(
              padding: EdgeInsets.fromLTRB(
                t.space.lg,
                t.space.sm,
                t.space.lg,
                t.space.xs,
              ),
              child: Segmented<NotesView>(
                key: const Key('notes-view-toggle'),
                fullWidth: narrowLayout(context),
                value: view,
                onChanged: state.setNotesView,
                segments: const [
                  Segment(NotesView.list, 'List', 'notes-view-list'),
                  Segment(NotesView.tree, 'Tree', 'notes-view-tree'),
                ],
              ),
            ),
      drawer: (body) => PanelTagsDrawer(
        body: body,
        tags: state.tags,
        selected: state.tag,
        onSelect: state.setTag,
        expanded: state.tagsExpanded,
        onExpandedChange: state.setTagsOpen,
        menuBuilder: (tag, chip) => ActionContextMenu(
          groups: [
            [
              if (state.tag != tag)
                NoteMenuItem(
                  'Filter by this tag',
                  FLucideIcons.tag,
                  () => state.setTag(tag),
                  key: const Key('menu-tag-filter'),
                ),
              if (state.tag != null)
                NoteMenuItem(
                  'Clear the tag filter',
                  FLucideIcons.x,
                  () => state.setTag(null),
                  key: const Key('menu-tag-clear'),
                ),
            ],
          ],
          child: chip,
        ),
      ),
      wrapBody: (body) => MoveDropTarget(
        key: const Key('drop-root'),
        state: state,
        folderUid: null,
        rounded: false,
        child: ActionContextMenu(
          groups: [
            if (state.editable)
              [
                NoteMenuItem(
                  'New note…',
                  FLucideIcons.filePlus,
                  () => showNewNoteDialog(context, state, personal: !scoped),
                  key: const Key('menu-tree-new-note'),
                ),
                NoteMenuItem(
                  'New folder…',
                  FLucideIcons.folderPlus,
                  () => showNewFolderDialog(context, state),
                  key: const Key('menu-tree-new-folder'),
                ),
              ],
          ],
          child: body,
        ),
      ),
      trailing: state.editable
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Narrow side menu: collapse or expand all folders, inline.
                if (narrowLayout(context))
                  IconAction(
                    compact: true,
                    key: const Key('menu-fold'),
                    tooltip: 'Collapse or expand folders',
                    icon: FLucideIcons.listChevronsDownUp,
                    onPress: state.toggleAllFolders,
                  ),
                IconAction(
                  compact: true,
                  key: const Key('new-note'),
                  tooltip: 'New note',
                  icon: FLucideIcons.plus,
                  onPress: () {
                    onPick();
                    showNewNoteDialog(context, state, personal: !scoped);
                  },
                ),
                IconAction(
                  compact: true,
                  key: const Key('new-folder'),
                  tooltip: 'New folder',
                  icon: FLucideIcons.folderPlus,
                  onPress: () {
                    onPick();
                    showNewFolderDialog(context, state);
                  },
                ),
              ],
            )
          : null,
      children: [
        if (state.currentSpaceName != null)
          Padding(
            padding: EdgeInsets.fromLTRB(t.space.md, 0, t.space.md, t.space.sm),
            child: OverflowTip(
              state.currentSpaceName!,
              textKey: const Key('space-name'),
              style: t.type.bodyStyle.copyWith(color: t.muted),
            ),
          ),
        ...body,
      ],
    );
  }
}

class _TagWrap extends StatelessWidget {
  const _TagWrap({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.md),
      child: Wrap(
        spacing: t.space.sm,
        runSpacing: t.space.sm,
        children: [
          for (final tag in state.tags)
            ActionContextMenu(
              groups: [
                [
                  if (state.tag != tag)
                    NoteMenuItem(
                      'Filter by this tag',
                      FLucideIcons.tag,
                      () => state.setTag(tag),
                      key: const Key('menu-tag-filter'),
                    ),
                  if (state.tag != null)
                    NoteMenuItem(
                      'Clear the tag filter',
                      FLucideIcons.x,
                      () => state.setTag(null),
                      key: const Key('menu-tag-clear'),
                    ),
                ],
              ],
              child: FTappable(
                key: Key('tag-$tag'),
                semanticsLabel: 'Tag $tag',
                onPress: () => state.setTag(tag),
                child: FBadge(
                  variant: state.tag == tag
                      ? FBadgeVariant.secondary
                      : FBadgeVariant.outline,
                  child: Text(tag),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Views: saved views (apply, update, rename, remove, save the current one) and the tags as
/// filters.
class ViewsSection extends _Section {
  const ViewsSection({super.key, required super.state, required super.onPick});

  @override
  Widget build(BuildContext context) {
    state.nav.publish('views', [
      for (final v in state.savedViews)
        NavEntry(
          'view:${v.name}',
          open: (_) async {
            state.applyView(v);
            onPick();
          },
        ),
    ]);
    return _Panel(heading: _title('Views'), children: _viewsChildren(context));
  }

  List<Widget> _viewsChildren(BuildContext context) => [
    if (state.savedViews.isEmpty && !state.hasFilter)
      const _Muted('No saved views yet'),
    for (final v in state.savedViews)
      NavRow(
        key: ValueKey('nav-views-${v.name}'),
        nav: state.nav,
        list: 'views',
        id: 'view:${v.name}',
        child: ActionContextMenu(
          groups: [
            [
              NoteMenuItem('Open view', FLucideIcons.bookmark, () {
                state.applyView(v);
                onPick();
              }, key: Key('menu-view-open-${v.name}')),
              NoteMenuItem(
                'Update from current view',
                FLucideIcons.refreshCw,
                () => state.updateView(v),
                key: Key('menu-view-update-${v.name}'),
              ),
              NoteMenuItem(
                'Rename…',
                FLucideIcons.pencil,
                () => showRenameViewDialog(context, state, v),
                key: Key('menu-view-rename-${v.name}'),
              ),
            ],
            [
              NoteMenuItem(
                'Remove view',
                FLucideIcons.trash2,
                () => state.deleteView(v.name),
                key: Key('menu-view-delete-${v.name}'),
              ),
            ],
          ],
          child: Row(
            children: [
              Expanded(
                child: _item(FLucideIcons.bookmark, v.name, () {
                  state.applyView(v);
                  onPick();
                }),
              ),
              IconAction(
                key: Key('view-update-${v.name}'),
                tooltip: 'Update from current view',
                icon: FLucideIcons.refreshCw,
                onPress: () => state.updateView(v),
              ),
              IconAction(
                key: Key('view-rename-${v.name}'),
                tooltip: 'Rename saved view',
                icon: FLucideIcons.pencil,
                onPress: () => showRenameViewDialog(context, state, v),
              ),
              IconAction(
                key: Key('view-delete-${v.name}'),
                tooltip: 'Remove saved view',
                icon: FLucideIcons.x,
                onPress: () => state.deleteView(v.name),
              ),
            ],
          ),
        ),
      ),
    if (state.query.trim().isNotEmpty)
      Row(
        children: [
          Expanded(child: _Muted('Search: ${state.query.trim()}')),
          IconAction(
            key: const Key('clear-query'),
            tooltip: 'Clear search',
            icon: FLucideIcons.x,
            onPress: state.clearSearch,
          ),
        ],
      ),
    if (state.hasFilter)
      _item(
        FLucideIcons.bookmarkPlus,
        'Save this view',
        () => showSaveViewDialog(context, state),
      ),
    if (state.tags.isNotEmpty) ...[
      _label(context, 'FILTER BY TAG'),
      _TagWrap(state: state),
    ],
  ];
}

/// Search: one field, and inside a folder scope a toggle between that folder's
/// subtree and the whole Space; matches from the open Space listed here.
/// Tapping a hit opens the note (switching Space when needed). The text also
/// narrows the Board and List of the open Space.
class SearchSection extends StatefulWidget {
  const SearchSection({super.key, required this.state, required this.onPick});
  final AppState state;
  final VoidCallback onPick;

  @override
  State<SearchSection> createState() => _SearchSectionState();
}

class _SearchSectionState extends State<SearchSection> {
  List<SpaceHit>? _hits;
  var _run = 0;

  /// Inside a folder scope: search that folder's subtree, not the whole
  /// Space (the toggle offers both; nothing is saved).
  var _inProject = true;

  /// The scope the hits belong to.
  String? _lastScope;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _lastScope = state.scopeUid;
    if (state.searchController.text.trim().isNotEmpty) {
      _search(state.searchController.text);
    }
  }

  @override
  void didUpdateWidget(SearchSection old) {
    super.didUpdateWidget(old);
    _followScope();
  }

  /// The folder scope changed (or went) while the panel is open: search again
  /// under the new scope, back on "This project", so the hits always match the
  /// hint.
  void _followScope() {
    final scope = state.scopeUid;
    if (scope == _lastScope) return;
    _lastScope = scope;
    _inProject = true;
    final q = state.searchController.text;
    if (q.trim().isNotEmpty) _search(q);
  }

  /// The folder the search is narrowed to, or null for the whole Space.
  String? get _scopeUid => _inProject ? state.scopeUid : null;

  Future<void> _search(String text) async {
    final mine = ++_run;
    final found = await state.searchAllSpaces(text, scopeUid: _scopeUid);
    if (!mounted || mine != _run) return; // a newer search is running
    setState(() => _hits = text.trim().isEmpty ? null : found);
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    final t = tokensOf(context);
    state.nav.publish('search', [
      for (final h in hits ?? const <SpaceHit>[])
        NavEntry(
          'hit:${h.space.id}:${h.note.uid}',
          uid: h.note.uid,
          open: (mode) async {
            widget.onPick();
            await state.openHit(h, mode: mode);
          },
        ),
    ]);
    final scoped = state.scopeUid != null;
    final searchField = field(
      key: const Key('search-all-field'),
      focusNode: state.nav.searchNode,
      controller: state.searchController,
      hint: scoped && _inProject ? 'Search this project' : 'Search this space',
      prefixIcon: FLucideIcons.search,
      onChange: (v) {
        state.setQuery(v);
        _search(v);
      },
    );
    return _Panel(
      heading: _title('Search'),
      pinned: Padding(
        padding: EdgeInsets.fromLTRB(
          t.space.lg + t.space.xs,
          0,
          t.space.lg + t.space.xs,
          t.space.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: t.space.sm,
          children: [
            // Only a folder scope has something to narrow to.
            if (scoped)
              Segmented<bool>(
                key: const Key('search-scope-toggle'),
                fullWidth: true,
                value: _inProject,
                segments: const [
                  Segment(true, 'This project', 'search-scope-project'),
                  Segment(false, 'Whole space', 'search-scope-space'),
                ],
                onChanged: (v) {
                  if (v == _inProject) return;
                  setState(() => _inProject = v);
                  _search(state.searchController.text);
                },
              ),
            Row(
              children: [
                Expanded(child: searchField),
                // Phone: no Ctrl+K, so the palette gets a button here.
                if (narrowLayout(context)) ...[
                  SizedBox(width: t.space.sm),
                  IconAction(
                    key: const Key('search-commands'),
                    tooltip: 'Commands',
                    icon: FLucideIcons.command,
                    onPress: () => showCommandPalette(context, widget.state),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      children: [
        if (hits != null && hits.isEmpty) const _Muted('No matches'),
        for (final h in hits ?? const <SpaceHit>[])
          NavRow(
            key: ValueKey('nav-search-${h.space.id}-${h.note.uid}'),
            nav: state.nav,
            list: 'search',
            id: 'hit:${h.space.id}:${h.note.uid}',
            child: NoteContextMenu(
              state: state,
              uid: h.note.uid,
              hit: h,
              onOpen: widget.onPick,
              child: FItem(
                key: Key('hit-${h.note.uid}'),
                prefix: h.isTask || h.isEvent
                    ? Icon(
                        h.isTask
                            ? FLucideIcons.listChecks
                            : FLucideIcons.calendarDays,
                        size: t.icons.md,
                        color: t.muted,
                      )
                    : null,
                title: OverflowTip(h.note.summary),
                subtitle: Text(h.space.name),
                onPress: () {
                  widget.onPick();
                  state.openHit(h, mode: state.modifierOpenMode);
                },
              ),
            ),
          ),
      ],
    );
  }
}

Widget _syncMessage(AppState state) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (state.syncMessage != null)
      _Muted(state.syncMessage!, key: const Key('sync-message')),
    if (state.orphanDraftNotice != null) ...[
      _Muted(state.orphanDraftNotice!, key: const Key('orphan-draft-notice')),
      Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.symmetric(horizontal: tokensOf(context).space.sm),
          child: FButton(
            key: const Key('orphan-draft-discard'),
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.xs,
            mainAxisSize: MainAxisSize.min,
            onPress: state.discardOrphanDrafts,
            child: const Text('Discard'),
          ),
        ),
      ),
    ],
  ],
);

/// Account: who is signed in, sign in or out, sync status and Sync now.
class AccountSection extends _Section {
  const AccountSection({
    super.key,
    required super.state,
    required super.onPick,
  });

  @override
  Widget build(BuildContext context) => _Panel(
    heading: _title('Account'),
    children: [
      if (state.accountUser == null)
        _item(FLucideIcons.circleUser, 'Sign in…', () {
          onPick();
          showAccountDialog(context, state);
        })
      else ...[
        _Muted(
          'Signed in as ${state.accountUser}',
          key: const Key('account-label'),
        ),
        _item(FLucideIcons.refreshCw, 'Refresh spaces', state.refreshSpaces),
        _item(FLucideIcons.logOut, 'Sign out', state.signOut),
      ],
      if (state.connected) ...[
        _label(context, 'SYNC'),
        _item(
          FLucideIcons.refreshCcw,
          state.syncing ? 'Syncing…' : 'Sync now',
          state.sync,
        ),
        if (state.serverLabel != null) _Muted(state.serverLabel!),
      ],
      _syncMessage(state),
    ],
  );
}

/// Settings: the server connection items, appearance (placeholder) and About.
class SettingsSection extends _Section {
  const SettingsSection({
    super.key,
    required super.state,
    required super.onPick,
  });

  @override
  Widget build(BuildContext context) => _Panel(
    heading: _title('Settings'),
    children: [
      if (state.canConnect) ...[
        _label(context, 'SERVER'),
        if (!state.connected && state.currentOnServer)
          _item(FLucideIcons.cloudSync, 'Retry connecting', state.load)
        else if (!state.connected)
          _item(FLucideIcons.cloud, 'Connect a collection by path', () {
            onPick();
            showConnectDialog(context, state);
          })
        else if (!state.currentOnServer)
          _item(FLucideIcons.cloudOff, 'Disconnect', state.disconnect),
        if (state.connected && state.serverLabel != null)
          _Muted(state.serverLabel!),
        _syncMessage(state),
      ],
      _label(context, 'APPEARANCE'),
      const _Muted('Theme follows the system.'),
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokensOf(context).space.md,
          vertical: tokensOf(context).space.xs,
        ),
        child: FSelectGroup<LayoutSide>(
          key: const Key('layout-side'),
          label: const Text('Layout side'),
          description: const Text('Which edge the icon rail sits on.'),
          control: FMultiValueControl.lifted(
            value: {state.layoutSide},
            onChange: (v) {
              // A lifted group adds to the set: take the newly picked one.
              final picked = v.where((x) => x != state.layoutSide);
              if (picked.isNotEmpty) state.setLayoutSide(picked.first);
            },
          ),
          children: [
            FSelectGroupItemMixin.radio<LayoutSide>(
              value: LayoutSide.start,
              label: const Text('Start'),
            ),
            FSelectGroupItemMixin.radio<LayoutSide>(
              value: LayoutSide.end,
              label: const Text('End'),
            ),
          ],
        ),
      ),
      _label(context, 'NOTES'),
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokensOf(context).space.md,
          vertical: tokensOf(context).space.xs,
        ),
        child: FSelectGroup<OpenMode>(
          key: const Key('open-mode'),
          label: const Text('Open notes in'),
          description: const Text('What a click on a note does.'),
          control: FMultiValueControl.lifted(
            value: {state.openMode},
            onChange: (v) {
              final picked = v.where((x) => x != state.openMode);
              if (picked.isNotEmpty) state.setOpenMode(picked.first);
            },
          ),
          children: [
            FSelectGroupItemMixin.radio<OpenMode>(
              value: OpenMode.peek,
              label: const Text('Peek'),
            ),
            FSelectGroupItemMixin.radio<OpenMode>(
              value: OpenMode.main,
              label: const Text('Main'),
            ),
          ],
        ),
      ),
      _label(context, 'KEYBOARD'),
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokensOf(context).space.md,
          vertical: tokensOf(context).space.xs,
        ),
        child: FCheckbox(
          key: const Key('vim-keys'),
          label: const Text('Vim keys'),
          description: const Text(
            'Letter keys move and open things (press ? for the list).',
          ),
          semanticsLabel: 'Vim keys',
          value: state.vimKeys,
          onChange: state.setVimKeys,
        ),
      ),
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokensOf(context).space.md,
          vertical: tokensOf(context).space.xs,
        ),
        child: FCheckbox(
          key: const Key('vim-editor'),
          label: const Text('Vim editing'),
          description: Text(
            isTouchPlatform
                ? 'Needs a keyboard: off on phones and tablets.'
                : 'Modal editing (Normal, Insert, Visual) in text bodies; '
                      'press ? for the keys.',
          ),
          semanticsLabel: 'Vim editing',
          enabled: !isTouchPlatform,
          value: state.vimEditor && !isTouchPlatform,
          onChange: state.setVimEditor,
        ),
      ),
      _label(context, 'ABOUT'),
      const _Muted('davdart: notes and plans, kept in Spaces.'),
    ],
  );
}
