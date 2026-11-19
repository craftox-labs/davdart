import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

/// Asks for a title and adds the note, under the selected note if chosen.
Future<void> showNewNoteDialog(BuildContext context, AppState state) {
  final parent = state.selected;
  final title = TextEditingController();
  var underParent = parent != null;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        void submit() {
          final text = title.text;
          if (text.trim().isEmpty) return;
          Navigator.of(ctx).pop();
          state.addNote(
            text,
            parentUid: underParent ? parent?.uid : null,
            status: 'backlog',
          );
        }

        return AlertDialog(
          title: const Text('New note'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('new-note-title'),
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Title'),
                onSubmitted: (_) => submit(),
              ),
              if (parent != null)
                CheckboxListTile(
                  key: const Key('new-note-under'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: underParent,
                  onChanged: (v) => setLocal(() => underParent = v ?? false),
                  title: Text(
                    'Under "${parent.summary}"',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('new-note-add'),
              onPressed: submit,
              child: const Text('Add'),
            ),
          ],
        );
      },
    ),
  );
}
