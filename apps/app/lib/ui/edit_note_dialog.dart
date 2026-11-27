import 'popover_track.dart';

import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'scope_bar.dart';
import 'theme.dart';

/// What [showEditNoteDialog] edits, as its title names it: a container is
/// called by its own name (Personal, Projects), a plain folder a folder.
String editKindOf(Note note) => isPersonalContainer(note)
    ? personalTitle
    : isProjectsContainer(note)
    ? projectsTitle
    : AppState.isFolder(note)
    ? 'folder'
    : 'note';

/// Editing a container is not editing a folder: [editKindOf] names it.

/// Edits a note's title and body text. Header lines are kept as they are.
Future<void> showEditNoteDialog(
  BuildContext context,
  AppState state,
  Note note,
) {
  final title = TextEditingController(text: note.summary);
  final body = TextEditingController(text: PlanItem.fromNote(note).text);
  final tags = TextEditingController(
    text: note.categories
        .where((c) => !c.startsWith('status-') && !c.startsWith('kind-'))
        .join(', '),
  );
  // Where the note can move: top level, or under any note that is not it or
  // one of its own descendants. Indented like the sidebar tree.
  final targets = <(String?, String, bool)>[(null, 'Top level', false)];
  void collect(List<NoteNode> nodes, int depth) {
    for (final n in nodes) {
      if (!isPersonalContainer(n.note) &&
          state.tree.canMove(note.uid, n.note.uid)) {
        targets.add((
          n.note.uid,
          '${'    ' * depth}${n.note.summary}',
          AppState.isFolder(n.note),
        ));
      }
      collect(n.children, depth + 1);
    }
  }

  collect(state.tree.roots, 0);
  final originalParent = state.tree.find(note.uid)?.parent?.note.uid;
  var parent = originalParent;
  if (!targets.any((e) => e.$1 == parent)) parent = null;
  final isFolder = AppState.isFolder(note);
  void save(BuildContext ctx) {
    Navigator.of(ctx).pop();
    state.updateNote(
      note.uid,
      title: title.text,
      text: body.text,
      setParent: parent != state.tree.find(note.uid)?.parent?.note.uid,
      parentUid: parent,
      tags: [
        for (final t in tags.text.split(','))
          if (t.trim().isNotEmpty) t.trim(),
      ],
    );
  }

  // The Inside menu: '' stands for the top level.
  final labels = {for (final e in targets) e.$1 ?? '': e};
  return showAppDialog(
    context,
    title: 'Edit ${editKindOf(note)}',
    width: tokensOf(context).sizes.dialogXl,
    content: StatefulBuilder(
      builder: (ctx, setLocal) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: tokensOf(ctx).space.lg,
        children: [
          field(
            key: const Key('edit-title'),
            controller: title,
            label: 'Title',
          ),
          field(
            key: const Key('edit-tags'),
            controller: tags,
            label: 'Tags (comma separated)',
          ),
          TrackPopover(
            builder: (_, pc) => FSelect<String>.rich(
              popoverControl: pc,
              key: const Key('edit-parent'),
              label: const Text('Inside'),
              format: (v) => labels[v]?.$2.trim() ?? v,
              control: FSelectControl.lifted(
                value: parent ?? '',
                onChange: (v) => setLocal(() {
                  parent = (v == null || v.isEmpty) ? null : v;
                }),
              ),
              children: [
                for (final e in targets)
                  FSelectItem<String>(
                    title: Text(
                      e.$3 ? '${e.$2.trim()}  (folder)' : e.$2.trim(),
                      overflow: TextOverflow.ellipsis,
                    ),
                    prefix: SizedBox(
                      width: _indent(e.$2) * tokensOf(ctx).space.lg,
                    ),
                    value: e.$1 ?? '',
                  ),
              ],
            ),
          ),
          field(
            key: const Key('edit-body'),
            controller: body,
            minLines: 6,
            maxLines: 14,
            label: isFolder ? 'Text (about this folder, instructions)' : 'Text',
          ),
        ],
      ),
    ),
    actions: [
      const CancelButton(),
      ActionButton('Save', key: const Key('edit-save'), onPress: save),
    ],
  );
}

double _indent(String label) => (label.length - label.trimLeft().length) / 4;

Future<void> confirmDeleteNote(
  BuildContext context,
  AppState state,
  Note note,
) {
  return showAppDialog(
    context,
    title: 'Delete note?',
    content: Text('"${note.summary}" will be deleted. Notes under it move up.'),
    actions: [
      const CancelButton(),
      ActionButton(
        'Delete',
        key: const Key('delete-confirm'),
        onPress: (ctx) {
          Navigator.of(ctx).pop();
          state.deleteNote(note.uid);
        },
      ),
    ],
  );
}

/// Edits a project's name and description. A project has no "Inside" choice:
/// it always stays under the Projects container.
Future<void> showEditProjectDialog(
  BuildContext context,
  AppState state,
  Note project,
) {
  final title = TextEditingController(text: project.summary);
  final body = TextEditingController(text: PlanItem.fromNote(project).text);
  void save(BuildContext ctx) {
    if (title.text.trim().isEmpty) return;
    Navigator.of(ctx).pop();
    state.updateNote(project.uid, title: title.text, text: body.text);
  }

  return showAppDialog(
    context,
    title: 'Edit project',
    width: tokensOf(context).sizes.dialogXl,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokensOf(context).space.lg,
      children: [
        field(key: const Key('edit-title'), controller: title, label: 'Name'),
        field(
          key: const Key('edit-body'),
          controller: body,
          minLines: 6,
          maxLines: 14,
          label: 'About this project',
        ),
      ],
    ),
    actions: [
      const CancelButton(),
      ActionButton('Save', key: const Key('edit-save'), onPress: save),
    ],
  );
}

/// Confirms deleting a project and says what becomes of its contents.
Future<void> confirmDeleteProject(
  BuildContext context,
  AppState state,
  Note project,
) {
  return showAppDialog(
    context,
    title: 'Delete project?',
    content: Text(
      '"${project.summary}" will be deleted. Its notes, tasks and events are '
      'kept and move to Personal.',
    ),
    actions: [
      const CancelButton(),
      ActionButton(
        'Delete',
        key: const Key('delete-confirm'),
        onPress: (ctx) {
          Navigator.of(ctx).pop();
          if (state.scopeUid == project.uid) leaveProject(state);
          state.deleteProject(project.uid);
        },
      ),
    ],
  );
}
