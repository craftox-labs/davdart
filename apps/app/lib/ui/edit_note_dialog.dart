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
    text: note.categories.where((c) => !c.startsWith('status-')).join(', '),
  );
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit note'),
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
            TextField(
              key: const Key('edit-body'),
              controller: body,
              minLines: 6,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Text',
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
