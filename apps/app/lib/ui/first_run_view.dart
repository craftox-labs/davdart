import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'account_dialog.dart';
import 'logo.dart';
import 'new_space_dialog.dart';
import 'theme.dart';

/// Shown in the main area while there is no Space (a new install, or every
/// Space deleted): create one, or sign in to load an account's Spaces.
class FirstRunView extends StatelessWidget {
  const FirstRunView({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final signedIn = state.accountUser != null;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(t.space.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: t.sizes.dialogMd),
          child: Column(
            key: const Key('first-run'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: t.space.lg,
            children: [
              LogoMark(extent: t.sizes.logoLarge),
              Text('Create your first Space', style: t.type.titleStyle),
              Text(
                signedIn
                    ? 'Signed in as ${state.accountUser}. This account has no '
                          'Spaces here yet: create one, or refresh to load '
                          'its Spaces.'
                    : 'A Space holds your notes. Keep one on this device, or '
                          'sign in to load the Spaces of your account.',
                style: t.type.bodyStyle.copyWith(color: t.muted),
              ),
              Wrap(
                spacing: t.space.md,
                runSpacing: t.space.md,
                children: [
                  FButton(
                    key: const Key('first-run-new'),
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => showNewSpaceDialog(context, state),
                    child: const Text('New local Space'),
                  ),
                  if (!signedIn)
                    FButton(
                      key: const Key('first-run-sign-in'),
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () => showAccountDialog(context, state),
                      child: const Text('Sign in'),
                    )
                  else
                    FButton(
                      key: const Key('first-run-refresh'),
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: state.refreshSpaces,
                      child: const Text('Refresh Spaces'),
                    ),
                ],
              ),
              if (state.syncMessage != null)
                Text(
                  state.syncMessage!,
                  key: const Key('first-run-message'),
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
