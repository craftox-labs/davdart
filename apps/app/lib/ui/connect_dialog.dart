import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

/// Connects the local Space to a CalDAV collection through the board
/// server's /dav/ proxy. The first sync sends every local note and merges by
/// UID with what the server holds.
Future<void> showConnectDialog(BuildContext context, AppState state) {
  final path = TextEditingController();
  final user = TextEditingController();
  final password = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      void submit() {
        if (path.text.trim().isEmpty || user.text.trim().isEmpty) return;
        Navigator.of(ctx).pop();
        state.connect(path.text, user.text, password.text);
      }

      return AlertDialog(
        title: const Text('Connect server'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('connect-path'),
                controller: path,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Collection path',
                  hintText: 'user/collection/',
                ),
              ),
              TextField(
                key: const Key('connect-user'),
                controller: user,
                decoration: const InputDecoration(labelText: 'User'),
              ),
              TextField(
                key: const Key('connect-password'),
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Notes here are sent to this collection and merged with what '
                'it holds. The login is kept in this browser.',
                style: TextStyle(fontSize: 12),
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
            key: const Key('connect-go'),
            onPressed: submit,
            child: const Text('Connect'),
          ),
        ],
      );
    },
  );
}
