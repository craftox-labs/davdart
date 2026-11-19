import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/space_catalog.dart';
import '../state/app_state.dart';
import 'new_space_dialog.dart';
import 'resize_handle.dart';
import 'sections.dart';
import 'shell_frame.dart';
import 'theme.dart';

/// The side panel: shows the section chosen on the icon rail ([AppState.section]).
/// In the narrow sheet ([inDrawer]) a [SectionBar] on top picks the section,
/// because there is no rail.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.state,
    this.inDrawer = false,
    this.width,
    this.mirror = false,
  });
  final AppState state;
  final bool inDrawer;

  /// Draws the panel's border on its start edge (the rail is on the right).
  final bool mirror;

  /// Width of the docked panel; null uses the default token.
  final double? width;

  @override
  Widget build(BuildContext context) {
    void close() {
      if (inDrawer) Navigator.of(context).pop();
    }

    var section = state.section;
    if (section == Section.account && !state.canSignIn) section = Section.notes;
    final body = switch (section) {
      Section.notes => NotesSection(state: state, onPick: close),
      Section.views => ViewsSection(state: state, onPick: close),
      Section.search => SearchSection(state: state, onPick: close),
      Section.account => AccountSection(state: state, onPick: close),
      Section.settings => SettingsSection(state: state, onPick: close),
    };
    final t = tokensOf(context);
    return FSidebar.raw(
      style: .delta(
        constraints: BoxConstraints.tightFor(width: width ?? t.sizes.sidebar),
        decoration: mirror
            ? DecorationDelta.value(
                BoxDecoration(
                  color: t.panel,
                  border: Border(
                    left: BorderSide(
                      color: t.divider,
                      width: t.borders.hairline,
                    ),
                  ),
                ),
              )
            : null,
      ),
      header: inDrawer ? SectionBar(state: state, onPick: close) : null,
      child: body,
    );
  }
}

/// Sync state line of a Space in the Spaces popup.
String spaceSyncLabel(AppState state, SpaceInfo sp) =>
    sp.id == state.currentSpaceId && state.syncing
    ? 'Syncing…'
    : sp.onServer
    ? 'Synced with the server'
    : 'On this device only';

/// The Spaces popup's groups: every Space (the current one first, marked)
/// with its sync state, then the manage actions (new, rename, delete).
/// Picking a Space switches to it and shows Files; [onPick] runs only before a
/// manage action opens a dialog.
List<FItemGroup> spaceMenuGroups(
  BuildContext context,
  AppState state,
  FPopoverController controller, {
  VoidCallback? onPick,
}) {
  final t = tokensOf(context);
  if (state.spaces.isEmpty) {
    return [
      FItemGroup(
        children: [FItem(title: const Text('One fixed notes source'))],
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
    ...state.spaces.where((s) => s.id == state.currentSpaceId),
    ...state.spaces.where((s) => s.id != state.currentSpaceId),
  ];
  return [
    FItemGroup(
      children: [
        for (final sp in spaces)
          FItem(
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
              state.setSection(Section.notes);
            }),
          ),
      ],
    ),
    FItemGroup(
      children: [
        FItem(
          prefix: Icon(FLucideIcons.plus, size: t.icons.md, color: t.muted),
          title: const Text('New space…'),
          onPress: () => manage(() => showNewSpaceDialog(context, state)),
        ),
        FItem(
          prefix: Icon(FLucideIcons.pencil, size: t.icons.md, color: t.muted),
          title: const Text('Rename this space…'),
          onPress: () => manage(() => showRenameSpaceDialog(context, state)),
        ),
        if (state.currentSpaceId != SpaceCatalog.planningId)
          FItem(
            prefix: Icon(FLucideIcons.trash2, size: t.icons.md, color: t.muted),
            title: const Text('Delete this space…'),
            onPress: () => manage(() => showDeleteSpaceDialog(context, state)),
          ),
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
