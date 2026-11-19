import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

/// Names a new folder. Its text is optional: notes about the folder, or
/// instructions for whoever (or whatever agent) works inside it.
Future<void> showNewFolderDialog(BuildContext context, AppState state) {
  final inside = state.scope;
  final title = TextEditingController();
  final text = TextEditingController();
  var underScope = inside != null;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        void submit() {
          if (title.text.trim().isEmpty) return;
          Navigator.of(ctx).pop();
          state.addFolder(
            title.text,
            parentUid: underScope ? inside?.uid : null,
            text: text.text,
          );
        }

        return AlertDialog(
          title: const Text('New folder'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('new-folder-title'),
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Name, for example Deployment',
                  ),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('new-folder-text'),
                  controller: text,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Text (optional)',
                    hintText: 'About this folder, or instructions for agents',
                    alignLabelWithHint: true,
                  ),
                ),
                if (inside != null)
                  CheckboxListTile(
                    key: const Key('new-folder-inside'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: underScope,
                    onChanged: (v) => setLocal(() => underScope = v ?? false),
                    title: Text(
                      'Inside "${inside.summary}"',
                      overflow: TextOverflow.ellipsis,
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
              key: const Key('new-folder-add'),
              onPressed: submit,
              child: const Text('Create'),
            ),
          ],
        );
      },
    ),
  );
}
