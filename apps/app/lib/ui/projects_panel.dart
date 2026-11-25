import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import 'edit_note_dialog.dart';
import 'new_folder_dialog.dart';
import 'key_nav_ui.dart';
import 'note_menu.dart';
import 'move_space_dialog.dart';
import 'scope_bar.dart';
import 'overflow_tip.dart';
import 'parts.dart';
import 'side_panel.dart';
import 'theme.dart';

/// Names a new project (a folder under the Space's Projects container).
Future<void> showNewProjectDialog(BuildContext context, AppState state) {
  final title = TextEditingController();
  void submit(BuildContext ctx) {
    if (title.text.trim().isEmpty) return;
    Navigator.of(ctx).pop();
    state.addProject(title.text);
  }

  return showAppDialog(
    context,
    title: 'New project',
    width: tokensOf(context).sizes.dialog,
    content: Builder(
      builder: (ctx) => field(
        key: const Key('new-project-title'),
        controller: title,
        autofocus: true,
        hint: 'Name',
        onSubmit: (_) => submit(ctx),
      ),
    ),
    actions: [
      const CancelButton(),
      ActionButton(
        'Create',
        key: const Key('new-project-add'),
        onPress: submit,
      ),
    ],
  );
}

/// "3 open · 1 review · 2 done"; zero parts are left out.
String projectCounts(ProjectStats s) {
  final parts = [
    if (s.open > 0) '${s.open} open',
    if (s.review > 0) '${s.review} review',
    if (s.done > 0) '${s.done} done',
  ];
  return parts.isEmpty ? 'Nothing to count' : parts.join(' · ');
}

/// The thin derived progress bar: the done share of a project's items.
class ProjectProgressBar extends StatelessWidget {
  const ProjectProgressBar(this.progress, {super.key});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final radius = BorderRadius.circular(t.radii.small);
    return Semantics(
      label: 'Progress',
      value: '${(progress * 100).round()}%',
      excludeSemantics: true,
      child: Container(
        height: t.sizes.progressBar,
        decoration: BoxDecoration(color: t.divider, borderRadius: radius),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.statusDone,
                borderRadius: radius,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Projects panel: the scope picker. "All" is the whole Space; the
/// projects follow, opened in the most recent first order. Inside a project
/// the panel drills down a folder level at a time: the parent to go up to,
/// the folder in scope (marked, with its actions behind a ⋯ and a long press)
/// and its own folders. A loose folder (outside every project) is a path row
/// of its own. Tapping a row sets the folder scope. [onPick] runs after a
/// pick, to close the narrow sheet.
class ProjectsPanel extends StatelessWidget {
  const ProjectsPanel({super.key, required this.state, this.onPick});
  final AppState state;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final ix = state.projectIndex;
        // Recent projects first (newest first), then the rest in listed
        // order.
        final projects = state.projectsByRecent;
        final scope = state.scopeUid;
        final current = scope == null ? null : ix.projectOf(scope)?.uid;
        final here = scope == null ? null : state.tree.find(scope);
        Future<void> open(String? uid) async {
          await state.guarded(() => state.openFolder(uid));
          onPick?.call();
        }

        final rows = <NavEntry>[
          NavEntry('all', open: (_) => open(null)),
          for (final p in projects)
            NavEntry(p.uid, uid: p.uid, open: (_) => open(p.uid)),
        ];
        // At a project's own level there is nothing above it to go to (the
        // projects container is not a place).
        final atProject =
            here != null && ix.projectOf(here.note.uid)?.uid == here.note.uid;
        final up = atProject ? null : here?.parent;
        if (here != null) {
          rows.addAll([
            if (up != null) NavEntry('up', open: (_) => open(up.note.uid)),
            NavEntry('here', uid: here.note.uid, open: (_) => open(scope)),
            for (final c in here.children)
              if (isFolderNote(c.note))
                NavEntry(
                  'folder:${c.note.uid}',
                  uid: c.note.uid,
                  open: (_) => open(c.note.uid),
                ),
          ]);
        }
        state.nav.publish('projects', rows);

        Widget row({
          required Key key,
          required String id,
          required Widget child,
          required VoidCallback onPress,
          bool on = false,
        }) => NavRow(
          nav: state.nav,
          list: 'projects',
          id: id,
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
                color: on ? t.selected : null,
                borderRadius: BorderRadius.circular(t.radii.small),
              ),
              child: child,
            ),
          ),
        );

        /// [folder]'s actions, behind its ⋯ (a long press or a right click
        /// opens them on any row too).
        Widget more(Note folder) => FPopoverMenu(
          menuAnchor: Alignment.topRight,
          childAnchor: Alignment.bottomRight,
          menuBuilder: (ctx, controller, _) => scopeActionsGroup(
            context,
            state,
            controller,
            folder,
            includeClose: true,
          ),
          builder: (ctx, controller, _) => IconAction(
            key: Key('scope-more-${folder.uid}'),
            compact: true,
            tooltip: 'Folder actions',
            icon: FLucideIcons.ellipsis,
            onPress: controller.toggle,
          ),
        );

        /// [folder]'s actions: a project keeps its own (rename, a folder
        /// inside, a move, delete); any other folder gets the scope actions
        /// (edit, delete, and back to the whole space).
        Widget withActions(Note folder, Widget child) => ActionContextMenu(
          groups: [
            if (ix.projectOf(folder.uid)?.uid == folder.uid && state.editable)
              [
                NoteMenuItem(
                  'Rename…',
                  FLucideIcons.pencil,
                  () => showEditNoteDialog(context, state, folder),
                  key: Key('menu-project-rename-${folder.uid}'),
                ),
                NoteMenuItem(
                  'New folder inside…',
                  FLucideIcons.folderPlus,
                  () => showNewFolderDialog(context, state, under: folder),
                  key: Key('menu-project-new-folder-${folder.uid}'),
                ),
                if (state.spaces.length > 1)
                  NoteMenuItem(
                    'Move to another space',
                    FLucideIcons.folderInput,
                    () => showMoveSpaceDialog(context, state, folder),
                    key: const Key('scope-move'),
                  ),
                NoteMenuItem(
                  'Delete…',
                  FLucideIcons.trash2,
                  () => confirmDeleteNote(context, state, folder),
                  key: Key('menu-project-delete-${folder.uid}'),
                ),
              ]
            else
              scopeActionItems(context, state, folder, includeClose: true),
          ],
          child: child,
        );

        Widget label(IconData icon, String text, {Color? color}) => Row(
          children: [
            Icon(icon, size: t.icons.tree, color: color ?? t.muted),
            SizedBox(width: t.space.sm),
            Expanded(child: OverflowTip(text, style: t.type.bodyStyle)),
          ],
        );

        String name(Note n) => n.summary.isEmpty ? 'Untitled' : n.summary;

        Widget project(Note p) {
          final s = ix.statsOf(p.uid);
          final on = current == p.uid;
          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: t.space.xs,
            children: [
              Row(
                children: [
                  Icon(
                    FLucideIcons.folderKanban,
                    size: t.icons.tree,
                    color: t.muted,
                  ),
                  SizedBox(width: t.space.sm),
                  Expanded(
                    child: OverflowTip(name(p), style: t.type.bodyStyle),
                  ),
                  if (on) more(p),
                ],
              ),
              Padding(
                padding: EdgeInsets.only(right: on ? t.sizes.touchTarget : 0),
                child: Text(
                  projectCounts(s),
                  key: Key('project-counts-${p.uid}'),
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(right: on ? t.sizes.touchTarget : 0),
                child: KeyedSubtree(
                  key: Key('project-progress-${p.uid}'),
                  child: ProjectProgressBar(s.progress),
                ),
              ),
            ],
          );
          return withActions(
            p,
            row(
              key: Key('project-${p.uid}'),
              id: p.uid,
              on: on,
              onPress: () => open(p.uid),
              child: body,
            ),
          );
        }

        final rest = ix.everythingElse;
        return SidePanelFrame(
          title: const SidePanelTitle('Projects'),
          actions: state.editable
              ? IconAction(
                  compact: true,
                  key: const Key('new-project'),
                  tooltip: 'New project',
                  icon: FLucideIcons.plus,
                  onPress: () {
                    onPick?.call();
                    showNewProjectDialog(context, state);
                  },
                )
              : null,
          body: ListView(
            key: const Key('projects-view'),
            scrollCacheExtent: navCacheExtent,
            padding: EdgeInsets.symmetric(horizontal: t.space.lg),
            children: [
              row(
                key: const Key('projects-all'),
                id: 'all',
                on: scope == null,
                onPress: () => open(null),
                child: Row(
                  children: [
                    Icon(
                      FLucideIcons.layoutList,
                      size: t.icons.tree,
                      color: t.muted,
                    ),
                    SizedBox(width: t.space.sm),
                    Expanded(
                      child: Text(
                        state.currentSpaceName ?? 'Spaces',
                        style: t.type.bodyStyle,
                      ),
                    ),
                    if (scope == null)
                      Text(
                        'No project',
                        style: t.type.captionStyle.copyWith(color: t.muted),
                      ),
                  ],
                ),
              ),
              // Inside a project (or a loose folder): one level at a time.
              if (here != null) ...[
                if (up != null)
                  row(
                    key: const Key('projects-up'),
                    id: 'up',
                    onPress: () => open(up.note.uid),
                    child: label(FLucideIcons.cornerLeftUp, name(up.note)),
                  ),
                if (current == null)
                  // A loose folder has no project row to mark: its own path is
                  // the scope.
                  withActions(
                    here.note,
                    row(
                      key: const Key('projects-path'),
                      id: 'here',
                      on: true,
                      onPress: () => open(scope),
                      child: Row(
                        children: [
                          Expanded(
                            child: label(
                              FLucideIcons.folder,
                              folderPath(state, here.note.uid),
                            ),
                          ),
                          more(here.note),
                        ],
                      ),
                    ),
                  )
                else if (!atProject)
                  // Below a project: the folder in scope, marked, its children
                  // under it. At the project's own level its row carries the
                  // mark instead.
                  withActions(
                    here.note,
                    row(
                      key: const Key('projects-here'),
                      id: 'here',
                      on: true,
                      onPress: () => open(scope),
                      child: Row(
                        children: [
                          Expanded(
                            child: label(FLucideIcons.folder, name(here.note)),
                          ),
                          more(here.note),
                        ],
                      ),
                    ),
                  ),
                for (final c in here.children)
                  if (isFolderNote(c.note))
                    withActions(
                      c.note,
                      row(
                        key: Key('projects-folder-${c.note.uid}'),
                        id: 'folder:${c.note.uid}',
                        onPress: () => open(c.note.uid),
                        child: label(FLucideIcons.folder, name(c.note)),
                      ),
                    ),
              ],
              if (projects.isEmpty)
                Padding(
                  key: const Key('projects-empty'),
                  padding: EdgeInsets.symmetric(
                    horizontal: t.space.md,
                    vertical: t.space.xs,
                  ),
                  child: Text(
                    'No projects yet',
                    style: t.type.captionStyle.copyWith(color: t.muted),
                  ),
                ),
              for (final p in projects) project(p),
              Padding(
                key: const Key('projects-else'),
                padding: EdgeInsets.symmetric(
                  horizontal: t.space.md,
                  vertical: t.space.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: t.space.xs,
                  children: [
                    Text(
                      'Everything else',
                      style: t.type.bodyStyle.copyWith(color: t.muted),
                    ),
                    Text(
                      projectCounts(rest),
                      key: const Key('projects-else-counts'),
                      style: t.type.captionStyle.copyWith(color: t.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
