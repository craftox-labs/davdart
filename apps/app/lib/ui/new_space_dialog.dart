import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

/// Names a new local Space and opens it.
Future<void> showNewSpaceDialog(BuildContext context, AppState state) {
  final name = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      void submit() {
        if (name.text.trim().isEmpty) return;
        Navigator.of(ctx).pop();
        state.createSpace(name.text);
      }

      return AlertDialog(
        title: const Text('New space'),
        content: TextField(
          key: const Key('space-name'),
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Name, for example Inbox',
          ),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('space-create'),
            onPressed: submit,
            child: const Text('Create'),
          ),
        ],
      );
    },
  );
}
