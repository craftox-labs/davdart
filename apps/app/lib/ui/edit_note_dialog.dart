import 'package:davdart/davdart.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

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
      if (state.tree.canMove(note.uid, n.note.uid)) {
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
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(isFolder ? 'Edit folder' : 'Edit note'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('edit-title'),
                controller: title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('edit-tags'),
                controller: tags,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma separated)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('edit-parent'),
                initialValue: parent,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Inside'),
                items: [
                  for (final e in targets)
                    DropdownMenuItem<String?>(
                      value: e.$1,
                      child: Text(
                        e.$3 ? '${e.$2}  (folder)' : e.$2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setLocal(() => parent = v),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('edit-body'),
                controller: body,
                minLines: 6,
                maxLines: 14,
                decoration: InputDecoration(
                  labelText: isFolder
                      ? 'Text (about this folder, instructions)'
                      : 'Text',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('edit-save'),
            onPressed: () {
              Navigator.of(ctx).pop();
              state.updateNote(
                note.uid,
                title: title.text,
                text: body.text,
                setParent:
                    parent != state.tree.find(note.uid)?.parent?.note.uid,
                parentUid: parent,
                tags: [
                  for (final t in tags.text.split(','))
                    if (t.trim().isNotEmpty) t.trim(),
                ],
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<void> confirmDeleteNote(
  BuildContext context,
  AppState state,
  Note note,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete note?'),
      content: Text(
        '"${note.summary}" will be deleted. Notes under it move up.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('delete-confirm'),
          onPressed: () {
            Navigator.of(ctx).pop();
            state.deleteNote(note.uid);
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
