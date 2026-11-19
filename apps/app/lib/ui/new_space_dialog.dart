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

/// Renames the open Space.
Future<void> showRenameSpaceDialog(BuildContext context, AppState state) {
  final name = TextEditingController(text: state.currentSpaceName ?? '');
  String? error;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          if (state.renameSpace(name.text)) {
            Navigator.of(ctx).pop();
          } else {
            setState(
              () => error = name.text.trim().isEmpty
                  ? 'Enter a name'
                  : 'Another space already has that name',
            );
          }
        }

        return AlertDialog(
          title: const Text('Rename space'),
          content: TextField(
            key: const Key('space-rename-name'),
            controller: name,
            autofocus: true,
            decoration: InputDecoration(errorText: error),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('space-rename'),
              onPressed: submit,
              child: const Text('Rename'),
            ),
          ],
        );
      },
    ),
  );
}

/// Confirms deleting the open (non-Planning) Space.
Future<void> showDeleteSpaceDialog(BuildContext context, AppState state) {
  final name = state.currentSpaceName ?? 'this space';
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete $name?'),
      content: const Text(
        'Its notes and saved views are removed from this device. A server '
        'collection it was connected to is not touched.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('space-delete'),
          onPressed: () {
            Navigator.of(ctx).pop();
            state.deleteSpace();
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
