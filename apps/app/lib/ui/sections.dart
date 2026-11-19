import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'account_dialog.dart';
import 'connect_dialog.dart';
import 'new_folder_dialog.dart';
import 'new_note_dialog.dart';
import 'parts.dart';
import 'save_view_dialog.dart';
import 'theme.dart';

/// The panels the side panel shows, one per rail section. Each takes
/// [onPick], run after an action that should close the narrow sheet.

/// Heading line plus a scrolling body, the frame every section shares.
class _Panel extends StatelessWidget {
  const _Panel({required this.heading, required this.children, this.trailing});
  final Widget heading;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            t.space.xl + t.space.xxs,
            t.space.lg + t.space.xxs,
            t.space.lg,
            t.space.md,
          ),
          child: Row(
            children: [
              Expanded(child: heading),
              ?trailing,
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: t.space.lg),
            children: children,
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: tokensOf(context).type.headingStyle);
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
      label: Text(text, overflow: TextOverflow.ellipsis),
      selected: on,
      onPress: tap,
    );

abstract class _Section extends StatelessWidget {
  const _Section({super.key, required this.state, required this.onPick});
  final AppState state;
  final VoidCallback onPick;
}

/// Files (the notes): the Space name, then the tree with folders and the tags
/// at the end. Spaces are switched from the rail's Spaces popup.
class NotesSection extends _Section {
  const NotesSection({super.key, required super.state, required super.onPick});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final tree = <Widget>[];
    void walk(List<NoteNode> nodes, int depth) {
      for (final n in nodes) {
        final kids = n.children.isNotEmpty;
        final open = !state.collapsed.contains(n.note.uid);
        final on =
            state.selectedUid == n.note.uid || state.scopeUid == n.note.uid;
        tree.add(
          FTappable(
            onPress: () {
              if (AppState.isFolder(n.note)) {
                state.openFolder(n.note.uid);
              } else {
                state.select(n.note.uid);
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
                    child: Text(
                      n.note.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.type.bodyStyle,
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

    final heading = _title(state.currentSpaceName ?? 'davdart');

    return _Panel(
      heading: heading,
      trailing: state.editable
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconAction(
                  key: const Key('new-note'),
                  tooltip: 'New note',
                  icon: FLucideIcons.plus,
                  onPress: () {
                    onPick();
                    showNewNoteDialog(context, state);
                  },
                ),
                IconAction(
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
        ...tree,
        if (state.tags.isNotEmpty) ...[
          _label(context, 'TAGS'),
          _TagWrap(state: state),
          SizedBox(height: t.space.lg),
        ],
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
            FTappable(
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
        ],
      ),
    );
  }
}

/// Views: saved views (apply, remove, save the current one) and the tags as
/// filters.
class ViewsSection extends _Section {
  const ViewsSection({super.key, required super.state, required super.onPick});

  @override
  Widget build(BuildContext context) => _Panel(
    heading: _title('Views'),
    children: [
      if (state.savedViews.isEmpty && !state.hasFilter)
        const _Muted('No saved views yet'),
      for (final v in state.savedViews)
        Row(
          children: [
            Expanded(
              child: _item(FLucideIcons.bookmark, v.name, () {
                state.applyView(v);
                onPick();
              }),
            ),
            IconAction(
              tooltip: 'Remove saved view',
              icon: FLucideIcons.x,
              onPress: () => state.deleteView(v.name),
            ),
          ],
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
    ],
  );
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
    return _Panel(
      heading: _title('Search'),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.xs, 0, t.space.xs, t.space.md),
          child: field(
            key: const Key('search-all-field'),
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
          FItem(
            key: Key('hit-${h.note.uid}'),
            title: Text(h.note.summary, overflow: TextOverflow.ellipsis),
            subtitle: Text(h.space.name),
            onPress: () {
              widget.onPick();
              state.openHit(h);
            },
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
      _label(context, 'ABOUT'),
      const _Muted('davdart: notes and plans, kept in Spaces.'),
    ],
  );
}
