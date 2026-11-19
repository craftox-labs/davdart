import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'account_dialog.dart';
import 'parts.dart';
import 'search_all_dialog.dart';
import 'sidebar.dart';
import 'theme.dart';

/// The window-filling frame in the app background colour. On a wide screen it
/// holds the [IconRail] and the content in a rounded, bordered panel inset
/// from the frame edge; otherwise the content fills the frame.
class ShellFrame extends StatelessWidget {
  const ShellFrame({
    super.key,
    required this.state,
    required this.showRail,
    required this.child,
  });
  final AppState state;
  final bool showRail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (!showRail) {
      return ColoredBox(color: t.bg, child: child);
    }
    return ColoredBox(
      color: t.bg,
      child: Row(
        children: [
          IconRail(state: state),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                Tokens.frameInset,
                Tokens.frameInset,
                Tokens.frameInset,
              ),
              child: DecoratedBox(
                key: const Key('shell-panel'),
                decoration: BoxDecoration(
                  border: Border.all(color: t.line),
                  borderRadius: BorderRadius.circular(Tokens.panelRadius),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Tokens.panelRadius - 1),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A slim vertical rail of icon actions: Spaces and search at the top,
/// account at the bottom. Every action reuses an existing one.
class IconRail extends StatelessWidget {
  const IconRail({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('icon-rail'),
      width: Tokens.railWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          spacing: 4,
          children: [
            if (state.spaces.isNotEmpty)
              FPopoverMenu(
                menuAnchor: Alignment.topLeft,
                childAnchor: Alignment.topRight,
                menuBuilder: (ctx, controller, _) =>
                    spaceMenuGroups(context, state, controller),
                builder: (ctx, controller, _) => IconAction(
                  key: const Key('rail-spaces'),
                  tooltip: 'Spaces',
                  icon: FLucideIcons.layoutGrid,
                  onPress: controller.toggle,
                ),
              ),
            if (state.spaces.length > 1)
              IconAction(
                key: const Key('rail-search'),
                tooltip: 'Search all spaces',
                icon: FLucideIcons.search,
                onPress: () => showSearchAllDialog(context, state),
              ),
            const Spacer(),
            if (state.canSignIn)
              IconAction(
                key: const Key('rail-account'),
                tooltip: state.accountUser == null
                    ? 'Sign in'
                    : 'Account (${state.accountUser})',
                icon: FLucideIcons.circleUser,
                onPress: () => showAccountDialog(context, state),
              ),
          ],
        ),
      ),
    );
  }
}
