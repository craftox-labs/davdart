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
import 'section_registry.dart';
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
  /// The projects whose views are shown; the one in scope starts open.
  late final Set<String> _open = _openProjects();

  Set<String> _openProjects() {
    final scope = widget.state.scopeUid;
    if (scope == null) return {};
    final ix = widget.state.projectIndex;
    final project = ix.projectOf(scope)?.uid ??
        (ix.isProject(scope) ? scope : null);
    return {?project};
  }

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
        final current = scope == null ? null : ix.projectOf(scope)?.uid;
        Future<void> open(String? uid) async {
          await state.guarded(() => state.openFolder(uid));
          onPick?.call();
        }

        bool expanded(Note p) => _open.contains(p.uid);
        void toggle(Note p) => setState(() {
          if (!_open.remove(p.uid)) _open.add(p.uid);
        });

        /// A project view: the project becomes the scope and the section
        /// follows it in one step (Board is the Tasks list scoped, until the
        /// board itself lands in the panel).
        Future<void> openView(String uid, Section section) async {
          await state.guarded(() => state.openFolder(uid));
          state.setSection(section);
          onPick?.call();
        }

        final rows = <NavEntry>[
          NavEntry('all', open: (_) => open(null)),
          for (final p in projects) ...[
            NavEntry(p.uid, uid: p.uid, open: (_) => open(p.uid)),
            if (expanded(p))
              for (final v in projectViews)
                NavEntry(
                  'view:${p.uid}:${v.id}',
                  uid: p.uid,
                  open: (_) => openView(p.uid, v.section),
                ),
          ],
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
          final showing = expanded(p);
          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: t.space.xs,
            children: [
              Row(
                children: [
                  // The chevron shows the project's views; the row's name
                  // still sets the scope alone.
                  SizedBox(
                    width: t.sizes.chevronBox,
                    child: FTappable(
                      key: Key('project-toggle-${p.uid}'),
                      semanticsLabel: showing
                          ? 'Hide the views of ${name(p)}'
                          : 'Show the views of ${name(p)}',
                      behavior: HitTestBehavior.opaque,
                      onPress: () => toggle(p),
                      child: Icon(
                        showing
                            ? FLucideIcons.chevronDown
                            : FLucideIcons.chevronRight,
                        size: t.icons.md,
                        color: t.muted,
                      ),
                    ),
                  ),
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              withActions(
                p,
                row(
                  key: Key('project-${p.uid}'),
                  id: p.uid,
                  on: on,
                  onPress: () => open(p.uid),
                  child: body,
                ),
              ),
              if (showing)
                for (final v in projectViews)
                  row(
                    key: Key('project-view-${p.uid}-${v.id}'),
                    id: 'view:${p.uid}:${v.id}',
                    on: on && state.section == v.section,
                    onPress: () => openView(p.uid, v.section),
                    child: Padding(
                      padding: EdgeInsets.only(left: t.sizes.treeIndent),
                      child: label(
                        v.icon,
                        v.label,
                        color: on && state.section == v.section
                            ? t.fg
                            : null,
                      ),
                    ),
                  ),
            ],
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

/// A project's own page: a placeholder for now. The project's name, what it
/// holds (open tasks, notes, events in scope) and that more is coming.
class ProjectOverviewPanel extends StatelessWidget {
  const ProjectOverviewPanel({
    super.key,
    required this.state,
    this.onPick,
  });
  final AppState state;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final scope = state.scope;
        final name = scope == null || scope.summary.isEmpty
            ? 'These projects'
            : scope.summary;
        final ix = state.projectIndex;
        final project = state.scopeUid == null
            ? null
            : ix.projectOf(state.scopeUid!)?.uid ??
                  (ix.isProject(state.scopeUid!) ? state.scopeUid : null);
        final counts = project == null
            ? null
            : ix.statsOf(project);
        final notes = state.scopeUid == null
            ? 0
            : state.tree
                  .descendants(state.scopeUid!)
                  .where((n) => !AppState.isFolder(n))
                  .length;
        final tasks = state.openTasks().length;
        final events = state.scopedEvents.length;
        Widget line(String text) => Padding(
          padding: EdgeInsets.only(top: t.space.xs),
          child: Text(text, style: t.type.captionStyle.copyWith(color: t.muted)),
        );
        return SidePanelFrame(
          key: const Key('overview-panel'),
          title: SidePanelTitle(name),
          body: ListView(
            padding: EdgeInsets.symmetric(horizontal: t.space.lg),
            children: [
              Padding(
                padding: EdgeInsets.only(top: t.space.md),
                child: Text(
                  'Project overview',
                  key: const Key('overview-heading'),
                  style: t.type.bodyStyle,
                ),
              ),
              line('$tasks open ${tasks == 1 ? 'task' : 'tasks'}'),
              line('$notes ${notes == 1 ? 'note' : 'notes'}'),
              line('$events ${events == 1 ? 'event' : 'events'}'),
              if (counts != null) line(projectCounts(counts)),
              line('More coming: a summary of this project here.'),
            ],
          ),
        );
      },
    );
  }
}
