import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

/// Names a new local Space and opens it.
Future<void> showNewSpaceDialog(BuildContext context, AppState state) {
  final name = TextEditingController();
  var onServer = state.accountUser != null;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        void submit() {
          if (name.text.trim().isEmpty) return;
          Navigator.of(ctx).pop();
          state.createSpace(name.text, onServer: onServer);
        }

        return AlertDialog(
          title: const Text('New space'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('space-name'),
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Name, for example Inbox',
                ),
                onSubmitted: (_) => submit(),
              ),
              if (state.accountUser != null)
                CheckboxListTile(
                  key: const Key('space-on-server'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: onServer,
                  onChanged: (v) => setLocal(() => onServer = v ?? false),
                  title: const Text('Create on the server and sync'),
                ),
            ],
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
    ),
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
        Future<void> submit() async {
          final err = await state.renameSpace(name.text);
          if (!ctx.mounted) return;
          if (err == null) {
            Navigator.of(ctx).pop();
          } else {
            setState(() => error = err);
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
      content: Text(
        state.currentOnServer
            ? 'This removes the space from this device only. The collection '
                  'and its notes stay on the server, and Refresh spaces '
                  'brings it back.'
            : 'Its notes and saved views are removed from this device. A '
                  'server collection it was connected to is not touched.',
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
