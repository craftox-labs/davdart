import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import 'drag_drop.dart';
import 'key_nav_ui.dart';
import 'events_panel.dart';
import 'new_space_dialog.dart';
import 'note_menu.dart';
import 'projects_panel.dart';
import 'resize_handle.dart';
import 'sections.dart';
import 'space_actions.dart';
import 'shell_frame.dart';
import 'tasks_panel.dart';
import 'theme.dart';
import 'overflow_tip.dart';

/// The side panel: shows the section chosen on the icon rail ([AppState.section]).
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.state,
    this.width,
    this.mirror = false,
  });
  final AppState state;

  /// Draws the panel's border on its start edge (the rail is on the right).
  final bool mirror;

  /// Width of the docked panel; null uses the default token.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final section = visibleSection(state);
    final body = sectionBody(state, section, () {});
    final t = tokensOf(context);
    return FSidebar.raw(
      style: .delta(
        constraints: BoxConstraints.tightFor(width: width ?? t.sizes.sidebar),
        // No top inset: the section's header row starts at the panel top,
        // level with the main area's top bar.
        contentPadding: EdgeInsetsGeometryDelta.value(
          EdgeInsets.only(bottom: t.space.sm),
        ),
        decoration: mirror
            ? DecorationDelta.value(
                BoxDecoration(
                  color: t.panel,
                  border: Border(
                    left: BorderSide(
                      color: t.panelBorder,
                      width: t.borders.hairline,
                    ),
                  ),
                ),
              )
            : DecorationDelta.boxDelta(
                border: Border(
                  right: BorderSide(
                    color: t.panelBorder,
                    width: t.borders.hairline,
                  ),
                ),
              ),
      ),
      child: AreaMark(nav: state.nav, area: NavArea.panel, child: body),
    );
  }
}

/// The section the panel shows: the chosen one, or the first the Space (and
/// sign-in) allow.
Section visibleSection(AppState state) {
  var section = state.section;
  if (section == Section.account && !state.canSignIn) section = Section.notes;
  // A section the Space's collection cannot hold falls back to one it can.
  if (!topSections(state).contains(section) &&
      section != Section.account &&
      section != Section.settings) {
    final tops = topSections(state);
    // Projects and Spaces lead the rail but are pickers, not landing pages.
    section = tops.firstWhere(
      (o) => o != Section.projects && o != Section.spaces,
      orElse: () => tops.first,
    );
  }
  return section;
}

/// The panel of [section]; [onPick] runs after an action that should close
/// the narrow sheet.
Widget sectionBody(AppState state, Section section, VoidCallback onPick) =>
    switch (section) {
      Section.spaces => SpacesSection(state: state, onPick: onPick),
      Section.notes => NotesSection(state: state, onPick: onPick),
      Section.tasks => TasksPanel(state: state, onPick: onPick),
      Section.events => EventsPanel(state: state, onPick: onPick),
      Section.projects => ProjectsPanel(state: state, onPick: onPick),
      Section.views => ViewsSection(state: state, onPick: onPick),
      Section.search => SearchSection(state: state, onPick: onPick),
      Section.account => AccountSection(state: state, onPick: onPick),
      Section.settings => SettingsSection(state: state, onPick: onPick),
    };

/// An item row of a menu group wrapped in other widgets (a drop target, a
/// right-click menu). The group only accepts item widgets, so this stands in
/// for one.
class _WrappedItem extends StatelessWidget with FItemMixin {
  const _WrappedItem({super.key, required this.item, required this.wrap});
  final FItem item;
  final Widget Function(Widget item) wrap;

  @override
  Widget build(BuildContext context) => wrap(item);
}

/// The Spaces popup's groups: every Space (the current one first, marked)
/// with its sync state, then the manage actions (new, rename, delete).
/// Picking a Space switches to it and keeps Tasks or Events, else shows Notes;
/// [onPick] runs only before a manage action opens a dialog. Dialogs launch
/// from [host] when given (the widget that opened the sheet): a sheet's own
/// context is gone by the time a row's action runs, so its `mounted` check
/// would swallow the dialog. [othersOnly] leaves out the open Space (the
/// narrow picker lists the other Spaces).
List<FItemGroup> spaceMenuGroups(
  BuildContext context,
  AppState state,
  FPopoverController controller, {
  VoidCallback? onPick,
  BuildContext? host,
  bool othersOnly = false,
}) {
  final t = tokensOf(context);
  final dialogs = host ?? context;
  if (state.catalog == null) {
    return [
      FItemGroup(
        children: [FItem(title: const OverflowTip('One fixed notes source'))],
      ),
    ];
  }
  void pick(VoidCallback act) {
    controller.hide();
    act();
  }

  void manage(VoidCallback act) => pick(() {
    onPick?.call();
    act();
  });

  final spaces = [
    if (!othersOnly) ...state.spaces.where((s) => s.id == state.currentSpaceId),
    ...state.spaces.where((s) => s.id != state.currentSpaceId),
  ];
  return [
    FItemGroup(
      children: [
        for (final sp in spaces)
          _WrappedItem(
            key: Key('space-drop-${sp.id}'),
            wrap: (item) => NoteDropTarget(
              accepts: (d) =>
                  sp.id != state.currentSpaceId &&
                  state.editable &&
                  state.findItem(d.uid) != null,
              onDrop: (d) =>
                  moveNoteToSpace(context, state, controller.hide, d.uid, sp),
              child: ActionContextMenu(
                groups: [
                  [
                    if (sp.id != state.currentSpaceId)
                      NoteMenuItem(
                        'Switch to this space',
                        FLucideIcons.arrowRightToLine,
                        () {
                          state.switchSpace(sp.id);
                          state.keepListSection();
                        },
                        key: Key('menu-space-switch-${sp.id}'),
                      ),
                    NoteMenuItem('Rename…', FLucideIcons.pencil, () {
                      onPick?.call();
                      showRenameSpaceDialog(
                        dialogs,
                        state,
                        id: sp.id,
                        currentName: sp.name,
                      );
                    }, key: Key('menu-space-rename-${sp.id}')),
                    if (sp.onServer)
                      NoteMenuItem(
                        'Delete from server…',
                        FLucideIcons.trash2,
                        () async {
                          onPick?.call();
                          // Opens it first: the dialog acts on the open Space.
                          if (!await state.switchSpace(sp.id)) return;
                          if (!dialogs.mounted) return;
                          showDeleteFromServerDialog(dialogs, state);
                        },
                        key: Key('menu-space-server-delete-${sp.id}'),
                      ),
                  ],
                ],
                child: item,
              ),
            ),
            item: FItem(
              key: Key('space-${sp.id}'),
              selected: sp.id == state.currentSpaceId,
              prefix: Icon(
                sp.onServer ? FLucideIcons.cloud : FLucideIcons.hardDrive,
                size: t.icons.md,
                color: t.muted,
              ),
              title: Text(sp.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(spaceSyncLabel(state, sp)),
              suffix: sp.id == state.currentSpaceId
                  ? Icon(FLucideIcons.check, size: t.icons.md, color: t.accent)
                  : null,
              onPress: () => pick(() {
                state.switchSpace(sp.id);
                state.keepListSection();
              }),
            ),
          ),
      ],
    ),
    FItemGroup(
      children: [
        FItem(
          prefix: Icon(FLucideIcons.plus, size: t.icons.md, color: t.muted),
          title: const Text('New space…'),
          onPress: () => manage(() => showNewSpaceDialog(dialogs, state)),
        ),
        if (state.currentSpaceId != null) ...[
          FItem(
            prefix: Icon(FLucideIcons.pencil, size: t.icons.md, color: t.muted),
            title: const Text('Rename this space…'),
            onPress: () => manage(() => showRenameSpaceDialog(dialogs, state)),
          ),
          FItem(
            prefix: Icon(FLucideIcons.trash2, size: t.icons.md, color: t.muted),
            title: const Text('Delete this space…'),
            onPress: () => manage(() => showDeleteSpaceDialog(dialogs, state)),
          ),
          if (state.currentOnServer)
            FItem(
              key: const Key('space-server-delete'),
              prefix: Icon(
                FLucideIcons.cloudOff,
                size: t.icons.md,
                color: t.muted,
              ),
              title: const Text('Delete from server…'),
              onPress: () =>
                  manage(() => showDeleteFromServerDialog(dialogs, state)),
            ),
        ],
      ],
    ),
  ];
}

/// The docked side panel width: the dragged one clamped to the token limits,
/// else the default.
double sidebarWidthOf(BuildContext context, AppState state) {
  final z = tokensOf(context).sizes;
  return (state.sidebarWidth ?? z.sidebar).clamp(z.sidebarMin, z.sidebarMax);
}

/// The docked side panel with a drag handle on its inner edge (the edge
/// facing the content: right at [LayoutSide.start], left at
/// [LayoutSide.end]). Dragging resizes it between the token limits and saves
/// the width on release; a double-click restores the default.
class DockedSidebar extends StatelessWidget {
  const DockedSidebar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final z = tokensOf(context).sizes;
    final width = sidebarWidthOf(context, state);
    final mirror = state.layoutSide == LayoutSide.end;
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Sidebar(state: state, width: width, mirror: mirror),
          Positioned(
            top: 0,
            bottom: 0,
            left: mirror ? 0 : null,
            right: mirror ? null : 0,
            child: PaneResizeHandle(
              key: const Key('sidebar-handle'),
              width: width,
              min: z.sidebarMin,
              max: z.sidebarMax,
              grow: mirror ? -1 : 1,
              onResize: (w) => state.setSidebarWidth(w, save: false),
              onEnd: () => state.setSidebarWidth(state.sidebarWidth),
              onReset: () => state.setSidebarWidth(null),
            ),
          ),
        ],
      ),
    );
  }
}
