import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';

/// The one list of sections: the rail (wide [IconRail] and the phone strip)
/// and the palette's "Go to" group are built from it, so a section is added,
/// renamed or reordered in one place.
///
/// Keys stay tied to the [Section] names (`rail-notes`, `drop-…`), so a
/// renamed label ('Calendar' for [Section.events]) keeps its keys.

/// The part of the rail an entry belongs to; the rail spaces the groups
/// apart (nothing else marks them).
enum SectionGroup {
  /// The personal layer: the overview and the Space's own lists.
  personal,

  /// Projects: a picker for the Space's projects and their views.
  projects,

  /// Space-wide tools, under the lists.
  global,
}

/// One rail entry: a side panel section, or an action (Home, whose content is
/// the main area, so it has no panel of its own).
class SectionDef {
  const SectionDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.group,
    this.section,
    this.onRail = true,
  });

  /// The rail key suffix (`rail-<id>`), the palette id suffix (`go.<id>`) and
  /// the rail's keyboard list id. A section entry uses the [Section] name.
  final String id;

  /// The user-facing name (tooltip, panel heading, palette).
  final String label;
  final IconData icon;
  final SectionGroup group;

  /// The panel section it shows; null for Home.
  final Section? section;

  /// Whether the rail lists it: the project views are listed in the Projects
  /// panel, not on the rail.
  final bool onRail;
}

const spacesIcon = FLucideIcons.layoutGrid;
const spacesLabel = 'Spaces';

/// Every entry, in rail order: the personal group, Projects, then the global
/// tools.
const List<SectionDef> sectionDefs = [
  SectionDef(
    id: 'home',
    label: 'Home',
    icon: FLucideIcons.house,
    group: SectionGroup.personal,
  ),
  SectionDef(
    id: 'notes',
    label: 'Notes',
    icon: FLucideIcons.fileText,
    group: SectionGroup.personal,
    section: Section.notes,
  ),
  SectionDef(
    id: 'tasks',
    label: 'Tasks',
    icon: FLucideIcons.listChecks,
    group: SectionGroup.personal,
    section: Section.tasks,
  ),
  // The section keeps its enum value and keys; only the name says Calendar.
  SectionDef(
    id: 'events',
    label: 'Calendar',
    icon: FLucideIcons.calendar,
    group: SectionGroup.personal,
    section: Section.events,
  ),
  SectionDef(
    id: 'projects',
    label: 'Projects',
    icon: FLucideIcons.folderKanban,
    group: SectionGroup.projects,
    section: Section.projects,
  ),
  SectionDef(
    id: 'search',
    label: 'Search',
    icon: FLucideIcons.search,
    group: SectionGroup.global,
    section: Section.search,
  ),
  SectionDef(
    id: 'views',
    label: 'Views',
    icon: FLucideIcons.bookmark,
    group: SectionGroup.global,
    section: Section.views,
  ),
  SectionDef(
    id: 'spaces',
    label: spacesLabel,
    icon: spacesIcon,
    group: SectionGroup.global,
    section: Section.spaces,
  ),
  SectionDef(
    id: 'account',
    label: 'Account',
    icon: FLucideIcons.circleUser,
    group: SectionGroup.global,
    section: Section.account,
  ),
  SectionDef(
    id: 'settings',
    label: 'Settings',
    icon: FLucideIcons.settings,
    group: SectionGroup.global,
    section: Section.settings,
  ),
];

/// The entry for [s], if it has one.
SectionDef? sectionDefOf(Section s) {
  for (final d in sectionDefs) {
    if (d.section == s) return d;
  }
  return null;
}

/// The user-facing name of [s] ('Calendar' for [Section.events]).
String sectionLabel(Section s) => sectionDefOf(s)?.label ?? s.name;

/// The project views, in the order a project expands to: Overview, Board,
/// Notes, Calendar. Board has no panel of its own yet and opens the scoped
/// Tasks list.
const List<({String id, String label, IconData icon, Section section})>
projectViews = [
  (
    id: 'overview',
    label: 'Overview',
    icon: FLucideIcons.layoutDashboard,
    section: Section.overview,
  ),
  (
    id: 'board',
    label: 'Board',
    icon: FLucideIcons.kanban,
    section: Section.tasks,
  ),
  (
    id: 'notes',
    label: 'Notes',
    icon: FLucideIcons.fileText,
    section: Section.notes,
  ),
  (
    id: 'events',
    label: 'Calendar',
    icon: FLucideIcons.calendar,
    section: Section.events,
  ),
];

/// Whether the rail shows [d] in this Space.
bool showsInRail(SectionDef d, AppState? state) {
  if (!d.onRail) return false;
  if (state == null) return d.id != 'account';
  return switch (d.id) {
    'account' => state.canSignIn,
    'notes' => state.supportsNotes,
    'tasks' => state.supportsTasks,
    'events' => state.supportsEvents,
    // Projects are an optional layer: a read-only Space with none leaves the
    // item out. An editable one keeps it, so the first project can be made
    // from the panel's empty state.
    'projects' =>
      state.supportsSection(Section.projects) &&
          (state.hasProjects || state.editable),
    _ => true,
  };
}

/// The rail above the gap: the personal group, then Projects.
List<SectionDef> railEntries(AppState? state) => [
  for (final d in sectionDefs)
    if (d.group != SectionGroup.global && showsInRail(d, state)) d,
];

/// The rail below the gap: Search, Views, Spaces, Account and Settings.
List<SectionDef> railBottomEntries(AppState? state) => [
  for (final d in sectionDefs)
    if (d.group == SectionGroup.global && showsInRail(d, state)) d,
];
