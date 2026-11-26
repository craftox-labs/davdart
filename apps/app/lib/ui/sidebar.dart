import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import 'key_nav_ui.dart';
import 'events_panel.dart';
import 'projects_panel.dart';
import 'resize_handle.dart';
import 'sections.dart';
import 'tasks_panel.dart';
import 'theme.dart';

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
/// sign-in, and scope) allow.
Section visibleSection(AppState state) {
  var section = state.section;
  if (section == Section.account && !state.canSignIn) section = Section.notes;
  // A section the Space (or the scope) cannot hold falls back to one it can.
  if (!state.supportsSection(section) && section != Section.account) {
    section = state.resolveSection(section);
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
      Section.overview => ProjectOverviewPanel(state: state, onPick: onPick),
      Section.views => ViewsSection(state: state, onPick: onPick),
      Section.search => SearchSection(state: state, onPick: onPick),
      Section.account => AccountSection(state: state, onPick: onPick),
      Section.settings => SettingsSection(state: state, onPick: onPick),
    };

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
