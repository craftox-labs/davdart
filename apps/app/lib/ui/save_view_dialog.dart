import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

/// Names and saves the current view, search and tag filter.
Future<void> showSaveViewDialog(BuildContext context, AppState state) {
  final name = TextEditingController(text: state.tag ?? state.query.trim());
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      void submit() {
        if (name.text.trim().isEmpty) return;
        Navigator.of(ctx).pop();
        state.saveView(name.text);
      }

      return AlertDialog(
        title: const Text('Save this view'),
        content: TextField(
          key: const Key('view-name'),
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('view-save'),
            onPressed: submit,
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}
