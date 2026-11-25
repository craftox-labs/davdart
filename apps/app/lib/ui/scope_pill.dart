import 'dart:async';

import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'note_menu.dart';
import 'projects_panel.dart';
import 'scope_bar.dart';
import 'shell_frame.dart';
import 'sidebar.dart';
import 'theme.dart';

/// The folder's path below the Space: its name and its ancestors', with the
/// Projects container level skipped.
String folderPath(AppState state, String uid) {
  final names = <String>[];
  for (var n = state.tree.find(uid); n != null; n = n.parent) {
    if (isProjectsContainer(n.note)) continue;
    names.insert(0, n.note.summary.isEmpty ? 'Untitled' : n.note.summary);
  }
  return names.join(' › ');
}

/// The scope picker's sheet groups: this Space's projects with Everything
/// first (the scope is the common change) and the projects opened most
/// recently ahead of the rest, then the open folder's actions, then the
/// Spaces (the Space sheet's own rows). Picking a project or Everything sets the folder scope and closes
/// the sheet. [host] is the widget that opened the sheet: dialogs launch from
/// it, since the sheet's own context is gone by the time a row acts.
List<FItemGroupMixin> scopePickerGroups(
  BuildContext host,
  AppState state,
  FPopoverController c,
) {
  final t = tokensOf(host);
  final ix = state.projectIndex;
  // Recent projects first (newest first), then the rest in listed order.
  final rest = [...ix.projects()];
  final projects = <Note>[];
  for (final uid in state.recentProjects) {
    final i = rest.indexWhere((p) => p.uid == uid);
    if (i >= 0) projects.add(rest.removeAt(i));
  }
  projects.addAll(rest);
  final scope = state.scopeUid;
  final current = scope == null ? null : ix.projectOf(scope)?.uid;

  void pick(String? uid) {
    c.hide();
    unawaited(state.guarded(() => state.openFolder(uid)));
  }

  // A folder that belongs to no project: its own path is the scope, shown as
  // a selected row (there is no project row to mark).
  final loose = scope != null && current == null
      ? FItem(
          key: const Key('scope-pick-path'),
          selected: true,
          prefix: Icon(FLucideIcons.folder, size: t.icons.md, color: t.muted),
          title: Text(
            folderPath(state, scope),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: const Text('The folder in scope'),
          onPress: () => pick(scope),
        )
      : null;

  // The row for a project: name, derived counts.
  FItem project(Note p) {
    final s = ix.statsOf(p.uid);
    final name = p.summary.isEmpty ? 'Untitled' : p.summary;
    return FItem(
      key: Key('scope-pick-${p.uid}'),
      selected: current == p.uid,
      prefix: Icon(FLucideIcons.folderKanban, size: t.icons.md, color: t.muted),
      title: Text(name, overflow: TextOverflow.ellipsis),
      subtitle: Text(projectCounts(s)),
      onPress: () => pick(p.uid),
    );
  }

  return [
    FItemGroup(
      children: [
        FItem(
          key: const Key('scope-pick-all'),
          selected: scope == null,
          prefix: Icon(
            FLucideIcons.layoutList,
            size: t.icons.md,
            color: t.muted,
          ),
          title: const Text('Everything'),
          subtitle: const Text('The whole space, no project'),
          onPress: () => pick(null),
        ),
        ?loose,
        if (projects.isEmpty)
          FItem(
            key: const Key('scope-pick-none'),
            prefix: Icon(
              FLucideIcons.folderKanban,
              size: t.icons.md,
              color: t.muted,
            ),
            title: const Text('No projects yet'),
            subtitle: const Text('Add one from the Projects panel'),
          )
        else
          for (final p in projects) project(p),
      ],
    ),
    ...scopeActionsGroup(host, state, c),
    ...spaceMenuGroups(host, state, c, host: host),
  ];
}

/// The narrow top bar's one joined tab: the open Space and the project the
/// scope sits in, at any depth below it ("Space › Project": the Space becomes
/// its icon); a loose folder or the Space root keeps the Space name.
/// Tapping it opens [scopePickerGroups] as a bottom sheet. The pill looks the
/// same on every screen, so the bar never swaps its title.
class ScopePill extends StatefulWidget {
  const ScopePill({super.key, required this.state});
  final AppState state;

  @override
  State<ScopePill> createState() => _ScopePillState();
}

class _ScopePillState extends State<ScopePill> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final state = widget.state;
    final space = state.currentSpaceName ?? 'Spaces';
    final scope = state.scopeUid;
    final p = scope == null ? null : state.projectIndex.projectOf(scope);
    final project = p == null
        ? null
        : (p.summary.isEmpty ? 'Untitled' : p.summary);
    final label = project == null ? space : '$space › $project';
    final style = t.type.captionStyle.copyWith(color: t.fg);
    // The active desktop header tab: panel tone, flared concave bottom
    // corners, flush on the top bar's bottom edge (over its hairline).
    final flare = t.radii.tab;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Transform.translate(
        offset: Offset(0, t.borders.hairline),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: flare),
          child: FTappable(
            key: const Key('space-chip'),
            semanticsLabel: label,
            behavior: HitTestBehavior.opaque,
            onPress: () => showMenuSheet(
              context,
              this,
              (ctx, c) => scopePickerGroups(context, state, c),
            ),
            // The tab takes the whole header height (it is its own hit box)
            // and its content sits on the logo's centre line.
            child: Align(
              alignment: Alignment.bottomCenter,
              child: JoinedTab(
                active: true,
                height: t.sizes.paneHeader,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.space.lg),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: t.space.sm,
                    children: [
                      // Same size as the logo.
                      Icon(spacesIcon, size: t.icons.lg, color: t.fg),
                      if (project == null)
                        Flexible(
                          child: Text(
                            space,
                            key: const Key('scope-pill-space'),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: style,
                          ),
                        )
                      else ...[
                        Text('›', style: style.copyWith(color: t.muted)),
                        Flexible(
                          child: Text(
                            project,
                            key: const Key('scope-pill-project'),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: style,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
