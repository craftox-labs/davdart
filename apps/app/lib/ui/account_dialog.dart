import 'package:flutter/widgets.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'theme.dart';

/// Signs in to the server once. Every collection the user has appears as a
/// Space; new Spaces can then be created on the server from the app.
Future<void> showAccountDialog(BuildContext context, AppState state) {
  final user = TextEditingController();
  final password = TextEditingController();
  void submit(BuildContext ctx) {
    if (user.text.trim().isEmpty) return;
    Navigator.of(ctx).pop();
    state.signIn(user.text, password.text);
  }

  return showAppDialog(
    context,
    title: 'Sign in',
    width: tokensOf(context).sizes.dialogMd,
    content: Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: tokensOf(ctx).space.lg,
        children: [
          field(
            key: const Key('account-user'),
            controller: user,
            autofocus: true,
            label: 'User',
          ),
          field(
            key: const Key('account-password'),
            controller: password,
            obscure: true,
            label: 'Password',
            onSubmit: (_) => submit(ctx),
          ),
          Text(
            'The Spaces of your account sync here. The login is kept in '
            'this browser.',
            style: tokensOf(ctx).type.captionStyle,
          ),
        ],
      ),
    ),
    actions: [
      const CancelButton(),
      ActionButton('Sign in', key: const Key('account-go'), onPress: submit),
    ],
  );
}
