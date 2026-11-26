import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/event_rules.dart';
import '../state/key_nav.dart';
import 'edit_note_dialog.dart';
import 'new_folder_dialog.dart';
import 'key_nav_ui.dart';
import 'note_menu.dart';
import 'move_space_dialog.dart';
import 'scope_bar.dart';
import 'overflow_tip.dart';
import 'parts.dart';
import 'placeholder_card.dart';
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

/// The Projects panel: the Space's projects, most recent first, each with its
/// own views. A project row expands (chevron) to Overview, Board, Notes and
/// Calendar: picking one sets the project scope and the section together.
/// The row's name sets the scope alone (as before). "No project" clears the
/// scope. Row actions are behind the ⋯ and a long press. Folders are not
/// drilled here: their notes are the project's Notes view. [onPick] runs after
/// a pick, to close the phone's side menu.
class ProjectsPanel extends StatefulWidget {
  const ProjectsPanel({super.key, required this.state, this.onPick});
  final AppState state;
  final VoidCallback? onPick;

  @override
  State<ProjectsPanel> createState() => _ProjectsPanelState();
}

class _ProjectsPanelState extends State<ProjectsPanel> {
  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final state = widget.state;
    final onPick = widget.onPick;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final ix = state.projectIndex;
        // Recent projects first (newest first), then the rest in listed
        // order.
        final projects = state.projectsByRecent;
        final scope = state.scopeUid;
        // The card of the project whose page is open is highlighted.
        final current =
            state.mainProjectUid ??
            (scope == null ? null : ix.projectOf(scope)?.uid);

        /// Selecting a project opens (or focuses) its own tab; the panel stays
        /// the project list. 'No project' leaves any project and goes Home.
        Future<void> open(String? uid) async {
          var picked = false;
          await state.guarded(() {
            if (uid == null) {
              state.openFolder(null);
              state.showHome();
            } else {
              state.openProjectTab(uid);
            }
            picked = true;
          });
          if (picked) onPick?.call();
        }

        final rows = <NavEntry>[
          NavEntry('all', open: (_) => open(null)),
          for (final p in projects)
            NavEntry(p.uid, uid: p.uid, open: (_) => open(p.uid)),
        ];
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
        /// opens them on the card too).
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
            tooltip: 'Project actions',
            icon: FLucideIcons.ellipsis,
            onPress: controller.toggle,
          ),
        );

        /// A project's actions: rename, a folder inside, a move, delete.
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
                    'Move to Space…',
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

        String name(Note n) => n.summary.isEmpty ? 'Untitled' : n.summary;

        /// A flat project card: name, progress bar and percent, open and
        /// overdue counts, last changed, and one marked placeholder slot for
        /// status and members. Styling comes later.
        Widget project(Note p) {
          final on = current == p.uid;
          final counts = state.projectTaskCounts(p.uid);
          final percent = counts.total == 0
              ? 0
              : (counts.done * 100 / counts.total).round();
          final at = state.projectLastChanged(p.uid);
          final muted = t.type.captionStyle.copyWith(color: t.muted);
          final summary = [
            '${counts.open} open',
            if (counts.overdue > 0) '${counts.overdue} overdue',
          ].join(' · ');
          return withActions(
            p,
            row(
              key: Key('project-${p.uid}'),
              id: p.uid,
              on: on,
              onPress: () => open(p.uid),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: t.space.xxs),
                child: Column(
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
                    Row(
                      children: [
                        Expanded(
                          child: KeyedSubtree(
                            key: Key('project-progress-${p.uid}'),
                            child: ProjectProgressBar(percent / 100),
                          ),
                        ),
                        SizedBox(width: t.space.sm),
                        Text(
                          '$percent%',
                          key: Key('proj-percent-${p.uid}'),
                          style: muted,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary,
                            key: Key('project-counts-${p.uid}'),
                            style: muted,
                          ),
                        ),
                        Text(
                          at == null
                              ? 'No changes yet'
                              : dayLabel(wallDay(wallNow(at))),
                          key: Key('proj-changed-${p.uid}'),
                          style: muted,
                        ),
                      ],
                    ),
                    DashedOutline(
                      key: Key('proj-placeholder-${p.uid}'),
                      radius: t.radii.card,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: t.space.sm,
                          vertical: t.space.xxs,
                        ),
                        child: Text('Status, members', style: muted),
                      ),
                    ),
                  ],
                ),
              ),
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
                      'Not in a project',
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
