import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

/// Signs in to the server once. Every collection the user has appears as a
/// Space; new Spaces can then be created on the server from the app.
Future<void> showAccountDialog(BuildContext context, AppState state) {
  final user = TextEditingController();
  final password = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      void submit() {
        if (user.text.trim().isEmpty) return;
        Navigator.of(ctx).pop();
        state.signIn(user.text, password.text);
      }

      return AlertDialog(
        title: const Text('Sign in'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('account-user'),
                controller: user,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'User'),
              ),
              TextField(
                key: const Key('account-password'),
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your collections become Spaces and sync here. The login is '
                'kept in this browser.',
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
            key: const Key('account-go'),
            onPressed: submit,
            child: const Text('Sign in'),
          ),
        ],
      );
    },
  );
}
