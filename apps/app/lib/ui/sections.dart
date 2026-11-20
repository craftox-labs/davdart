import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import '../state/note_drag.dart';
import 'account_dialog.dart';
import 'connect_dialog.dart';
import 'drag_drop.dart';
import 'key_nav_ui.dart';
import 'new_folder_dialog.dart';
import 'new_note_dialog.dart';
import 'note_menu.dart';
import 'parts.dart';
import 'save_view_dialog.dart';
import 'side_panel.dart';
import 'theme.dart';
import 'overflow_tip.dart';
import 'panel_tags_drawer.dart';

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
  });
  final Widget heading;
  final List<Widget> children;
  final Widget? trailing;

  /// Wraps the scrolling body (the drop and right-click area).
  final Widget Function(Widget body)? wrapBody;

  /// Wraps the body with the bottom tags drawer.
  final Widget Function(Widget body)? drawer;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final body = ListView(
      scrollCacheExtent: navCacheExtent,
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      children: children,
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

/// Notes (the tree): the Space name, then the tree with folders and the tags
/// at the end. Spaces are switched from the rail's Spaces popup.
class NotesSection extends _Section {
  const NotesSection({super.key, required super.state, required super.onPick});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final tree = <Widget>[];
    final rows = <NavEntry>[];
    void walk(List<NoteNode> nodes, int depth) {
      for (final n in nodes) {
        final kids = n.children.isNotEmpty;
        final open = !state.collapsed.contains(n.note.uid);
        final on = state.peekUid == n.note.uid || state.scopeUid == n.note.uid;
        Widget entry = NoteContextMenu(
          state: state,
          uid: n.note.uid,
          onOpen: onPick,
          child: NoteDraggable(
            uid: n.note.uid,
            source: NoteDragSource.tree,
            label: n.note.summary,
            child: FTappable(
              onPress: () {
                if (AppState.isFolder(n.note)) {
                  state.guarded(() => state.openFolder(n.note.uid));
                } else {
                  state.clickNote(n.note.uid);
                }
                onPick();
              },
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  t.space.xs + depth * t.sizes.treeIndent,
                  t.space.sm - t.borders.hairline,
                  t.space.md,
                  t.space.sm - t.borders.hairline,
                ),
                decoration: BoxDecoration(
                  color: on ? t.selected : null,
                  borderRadius: BorderRadius.circular(t.radii.small),
                ),
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
                        open && kids
                            ? FLucideIcons.folderOpen
                            : FLucideIcons.folder,
                        size: t.icons.tree,
                        color: t.muted,
                      ),
                      SizedBox(width: t.space.sm),
                    ],
                    Expanded(
                      child: OverflowTip(
                        n.note.summary,
                        style: t.type.bodyStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (AppState.isFolder(n.note)) {
          entry = MoveDropTarget(
            key: Key('drop-${n.note.uid}'),
            state: state,
            folderUid: n.note.uid,
            child: entry,
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
        tree.add(
          NavRow(
            key: ValueKey('nav-notes-$uid'),
            nav: state.nav,
            list: 'notes',
            id: uid,
            child: entry,
          ),
        );
        if (kids && open) walk(n.children, depth + 1);
      }
    }

    walk(state.tree.roots, 0);
    state.nav.publish('notes', rows);

    final heading = _title('Notes');

    return _Panel(
      heading: heading,
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
                  () => showNewNoteDialog(context, state),
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
                    showNewNoteDialog(context, state);
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
        ...tree,
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
            onPress: () {
              state.searchController.clear();
              state.setQuery('');
            },
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

/// Search: one field; matches from every Space listed here. Tapping a hit
/// opens the note (switching Space when needed). The text also narrows the
/// Board and List of the open Space.
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

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    if (state.searchController.text.trim().isNotEmpty) {
      _search(state.searchController.text);
    }
  }

  Future<void> _search(String text) async {
    final mine = ++_run;
    final found = await state.searchAllSpaces(text);
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
    return _Panel(
      heading: _title('Search'),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.xs, 0, t.space.xs, t.space.md),
          child: field(
            key: const Key('search-all-field'),
            focusNode: state.nav.searchNode,
            controller: state.searchController,
            hint: 'Search all spaces',
            prefixIcon: FLucideIcons.search,
            onChange: (v) {
              state.setQuery(v);
              _search(v);
            },
          ),
        ),
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
                            ? FLucideIcons.listTodo
                            : FLucideIcons.calendarDays,
                        size: t.icons.md,
                        color: t.muted,
                      )
                    : null,
                title: OverflowTip(h.note.summary),
                subtitle: Text(h.space.name),
                onPress: () {
                  widget.onPick();
                  state.openHit(h);
                },
              ),
            ),
          ),
      ],
    );
  }
}

Widget _syncMessage(AppState state) => state.syncMessage == null
    ? const SizedBox.shrink()
    : _Muted(state.syncMessage!, key: const Key('sync-message'));

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
