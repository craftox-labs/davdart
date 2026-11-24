import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import 'edit_note_dialog.dart';
import 'key_nav_ui.dart';
import 'new_folder_dialog.dart';
import 'note_menu.dart';
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

/// The Projects side panel section: All, one row per project with derived
/// counts and a progress bar, then "Everything else" (a count only: the
/// folder scope cannot express "outside every project", so it is not
/// tappable). Tapping a project opens it as the folder scope. [onPick] runs
/// after a pick, to close the narrow sheet.
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
        final projects = ix.projects();
        final current = state.scopeUid == null
            ? null
            : ix.projectOf(state.scopeUid!)?.uid;
        Future<void> open(String? uid) async {
          await state.guarded(() => state.openFolder(uid));
          onPick?.call();
        }

        state.nav.publish('projects', [
          NavEntry('all', open: (_) => open(null)),
          for (final p in projects)
            NavEntry(p.uid, uid: p.uid, open: (_) => open(p.uid)),
        ]);

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

        Widget project(Note p) {
          final s = ix.statsOf(p.uid);
          final name = p.summary.isEmpty ? 'Untitled' : p.summary;
          return ActionContextMenu(
            groups: [
              if (state.editable)
                [
                  NoteMenuItem(
                    'Rename…',
                    FLucideIcons.pencil,
                    () => showEditNoteDialog(context, state, p),
                    key: Key('menu-project-rename-${p.uid}'),
                  ),
                  NoteMenuItem(
                    'New folder inside…',
                    FLucideIcons.folderPlus,
                    () => showNewFolderDialog(context, state, under: p),
                    key: Key('menu-project-new-folder-${p.uid}'),
                  ),
                ],
              if (state.editable)
                [
                  NoteMenuItem(
                    'Delete…',
                    FLucideIcons.trash2,
                    () => confirmDeleteNote(context, state, p),
                    key: Key('menu-project-delete-${p.uid}'),
                  ),
                ],
            ],
            child: row(
              key: Key('project-${p.uid}'),
              id: p.uid,
              on: current == p.uid,
              onPress: () => open(p.uid),
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
                        child: OverflowTip(name, style: t.type.bodyStyle),
                      ),
                    ],
                  ),
                  Text(
                    projectCounts(s),
                    key: Key('project-counts-${p.uid}'),
                    style: t.type.captionStyle.copyWith(color: t.muted),
                  ),
                  KeyedSubtree(
                    key: Key('project-progress-${p.uid}'),
                    child: ProjectProgressBar(s.progress),
                  ),
                ],
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
                on: state.scopeUid == null,
                onPress: () => open(null),
                child: Row(
                  children: [
                    Icon(
                      FLucideIcons.layoutList,
                      size: t.icons.tree,
                      color: t.muted,
                    ),
                    SizedBox(width: t.space.sm),
                    Expanded(child: Text('All', style: t.type.bodyStyle)),
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
