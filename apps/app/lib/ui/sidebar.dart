import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'parts.dart';
import 'theme.dart';
import 'account_dialog.dart';
import 'connect_dialog.dart';
import 'new_folder_dialog.dart';
import 'new_note_dialog.dart';
import '../data/space_catalog.dart';
import 'new_space_dialog.dart';
import 'search_all_dialog.dart';
import 'save_view_dialog.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.state, this.inDrawer = false});
  final AppState state;
  final bool inDrawer;

  void _close(BuildContext context) {
    if (inDrawer) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);

    Widget item(IconData icon, String text, bool on, VoidCallback tap) =>
        FSidebarItem(
          icon: Icon(icon),
          label: Text(text, overflow: TextOverflow.ellipsis),
          selected: on,
          onPress: tap,
        );

    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 6, 0),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: t.muted),
        overflow: TextOverflow.ellipsis,
      ),
    );

    final tree = <Widget>[];
    void walk(List<NoteNode> nodes, int depth) {
      for (final n in nodes) {
        final kids = n.children.isNotEmpty;
        final open = !state.collapsed.contains(n.note.uid);
        tree.add(
          FTappable(
            onPress: () {
              if (AppState.isFolder(n.note)) {
                state.openFolder(n.note.uid);
              } else {
                state.select(n.note.uid);
              }
              _close(context);
            },
            child: Container(
              padding: EdgeInsets.fromLTRB(4 + depth * 14.0, 5, 8, 5),
              decoration: BoxDecoration(
                color:
                    (state.selectedUid == n.note.uid ||
                        state.scopeUid == n.note.uid)
                    ? t.surface
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: kids
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => state.toggle(n.note.uid),
                            child: Icon(
                              open
                                  ? FLucideIcons.chevronDown
                                  : FLucideIcons.chevronRight,
                              size: 16,
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
                      size: 15,
                      color: t.muted,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      n.note.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (kids && open) walk(n.children, depth + 1);
      }
    }

    walk(state.tree.roots, 0);

    Widget spaceMenu() => FPopoverMenu(
      menuAnchor: Alignment.topLeft,
      childAnchor: Alignment.bottomLeft,
      menuBuilder: (ctx, controller, _) => spaceMenuGroups(
        context,
        state,
        controller,
        onPick: () => _close(context),
      ),
      builder: (ctx, controller, _) => FTappable(
        key: const Key('space-menu'),
        semanticsLabel: 'Switch space',
        onPress: controller.toggle,
        child: Row(
          children: [
            Flexible(
              child: Text(
                state.currentSpaceName ?? 'davdart',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(FLucideIcons.chevronDown, size: 18, color: t.muted),
          ],
        ),
      ),
    );

    return FSidebar.raw(
      style: const .delta(
        constraints: BoxConstraints.tightFor(width: Tokens.sidebarWidth),
      ),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 12),
              child: state.spaces.isEmpty
                  ? const Text(
                      'davdart',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : spaceMenu(),
            ),
            field(
              controller: state.searchController,
              onChange: state.setQuery,
              hint: 'Search',
              prefixIcon: FLucideIcons.search,
            ),
            if (state.spaces.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: FButton(
                  key: const Key('search-all'),
                  variant: FButtonVariant.ghost,
                  size: FButtonSizeVariant.sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () {
                    _close(context);
                    showSearchAllDialog(context, state);
                  },
                  child: const Flexible(
                    child: Text(
                      'Search all spaces…',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      footer: state.tags.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TAGS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: .8,
                      color: t.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in state.tags)
                        GestureDetector(
                          onTap: () => state.setTag(tag),
                          child: FBadge(
                            variant: state.tag == tag
                                ? FBadgeVariant.secondary
                                : FBadgeVariant.outline,
                            child: Text(tag),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FSidebarGroup(
            label: const Text('VIEWS'),
            children: [
              item(
                FLucideIcons.squareKanban,
                'Board',
                state.view == ViewMode.board,
                () {
                  state.setView(ViewMode.board);
                  state.select(null);
                  _close(context);
                },
              ),
              item(FLucideIcons.list, 'List', state.view == ViewMode.list, () {
                state.setView(ViewMode.list);
                state.select(null);
                _close(context);
              }),
              for (final v in state.savedViews)
                Row(
                  children: [
                    Expanded(
                      child: item(FLucideIcons.bookmark, v.name, false, () {
                        state.applyView(v);
                        _close(context);
                      }),
                    ),
                    IconAction(
                      tooltip: 'Remove saved view',
                      icon: FLucideIcons.x,
                      onPress: () => state.deleteView(v.name),
                    ),
                  ],
                ),
              if (state.hasFilter)
                item(FLucideIcons.bookmarkPlus, 'Save this view', false, () {
                  showSaveViewDialog(context, state);
                }),
            ],
          ),
          if (state.canSignIn)
            FSidebarGroup(
              label: const Text('ACCOUNT'),
              children: [
                if (state.accountUser == null)
                  item(FLucideIcons.circleUser, 'Sign in…', false, () {
                    _close(context);
                    showAccountDialog(context, state);
                  })
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 6, 4),
                    child: Text(
                      'Signed in as ${state.accountUser}',
                      key: const Key('account-label'),
                      style: TextStyle(fontSize: 11, color: t.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  item(
                    FLucideIcons.refreshCw,
                    'Refresh spaces',
                    false,
                    state.refreshSpaces,
                  ),
                  item(FLucideIcons.logOut, 'Sign out', false, state.signOut),
                ],
              ],
            ),
          if (state.canConnect)
            FSidebarGroup(
              label: const Text('SERVER'),
              children: [
                if (!state.connected && state.currentOnServer)
                  item(
                    FLucideIcons.cloudSync,
                    'Retry connecting',
                    false,
                    state.load,
                  )
                else if (!state.connected)
                  item(
                    FLucideIcons.cloud,
                    'Connect a collection by path',
                    false,
                    () {
                      _close(context);
                      showConnectDialog(context, state);
                    },
                  )
                else ...[
                  item(
                    FLucideIcons.refreshCcw,
                    state.syncing ? 'Syncing…' : 'Sync now',
                    false,
                    state.sync,
                  ),
                  if (!state.currentOnServer)
                    item(FLucideIcons.cloudOff, 'Disconnect', false, () {
                      state.disconnect();
                    }),
                ],
                if (state.connected && state.serverLabel != null)
                  note(state.serverLabel!),
                if (state.syncMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 6, 0),
                    child: Text(
                      state.syncMessage!,
                      key: const Key('sync-message'),
                      style: TextStyle(fontSize: 11, color: t.muted),
                    ),
                  ),
              ],
            ),
          FSidebarGroup(
            label: const Text('NOTES'),
            children: [
              if (state.editable)
                item(FLucideIcons.plus, 'New note', false, () {
                  _close(context);
                  showNewNoteDialog(context, state);
                }),
              if (state.editable)
                item(FLucideIcons.folderPlus, 'New folder', false, () {
                  _close(context);
                  showNewFolderDialog(context, state);
                }),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: tree,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Space menu's items (switch, new, rename, delete), shared by the sidebar
/// header and the icon rail. [onPick] runs after the menu closes.
List<FItemGroup> spaceMenuGroups(
  BuildContext context,
  AppState state,
  FPopoverController controller, {
  VoidCallback? onPick,
}) {
  final t = tokensOf(context);
  void pick(VoidCallback act) {
    controller.hide();
    onPick?.call();
    act();
  }

  return [
    FItemGroup(
      children: [
        for (final sp in state.spaces)
          FItem(
            key: Key('space-${sp.id}'),
            selected: sp.id == state.currentSpaceId,
            title: Text(sp.name, overflow: TextOverflow.ellipsis),
            suffix: sp.onServer
                ? Icon(FLucideIcons.cloud, size: 14, color: t.muted)
                : null,
            onPress: () => pick(() => state.switchSpace(sp.id)),
          ),
      ],
    ),
    FItemGroup(
      children: [
        FItem(
          title: const Text('New space…'),
          onPress: () => pick(() => showNewSpaceDialog(context, state)),
        ),
        FItem(
          title: const Text('Rename this space…'),
          onPress: () => pick(() => showRenameSpaceDialog(context, state)),
        ),
        if (state.currentSpaceId != SpaceCatalog.planningId)
          FItem(
            title: const Text('Delete this space…'),
            onPress: () => pick(() => showDeleteSpaceDialog(context, state)),
          ),
      ],
    ),
  ];
}
