import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/space_catalog.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'new_space_dialog.dart';
import 'sections.dart';
import 'shell_frame.dart';
import 'theme.dart';

/// The side panel: shows the section chosen on the icon rail ([AppState.section]).
/// In the narrow sheet ([inDrawer]) a [SectionBar] on top picks the section,
/// because there is no rail.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.state, this.inDrawer = false});
  final AppState state;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    void close() {
      if (inDrawer) Navigator.of(context).pop();
    }

    var section = state.section;
    if (section == Section.account && !state.canSignIn) section = Section.notes;
    final body = switch (section) {
      Section.notes => NotesSection(state: state, onPick: close),
      Section.views => ViewsSection(state: state, onPick: close),
      Section.search => SearchSection(state: state, onPick: close),
      Section.spaces => SpacesSection(state: state, onPick: close),
      Section.account => AccountSection(state: state, onPick: close),
      Section.settings => SettingsSection(state: state, onPick: close),
    };
    return FSidebar.raw(
      style: const .delta(
        constraints: BoxConstraints.tightFor(width: Tokens.sidebarWidth),
      ),
      header: inDrawer ? SectionBar(state: state) : null,
      child: body,
    );
  }
}

/// The Space menu's items (switch, new, rename, delete). [onPick] runs after
/// the menu closes; [quickOnly] keeps just the list of Spaces to switch to.
List<FItemGroup> spaceMenuGroups(
  BuildContext context,
  AppState state,
  FPopoverController controller, {
  VoidCallback? onPick,
  bool quickOnly = false,
}) {
  final t = tokensOf(context);
  void pick(VoidCallback act) {
    controller.hide();
    onPick?.call();
    act();
  }

  return [
    FItemGroup(
      children: [
        for (final sp in state.spaces)
          FItem(
            key: Key('space-${sp.id}'),
            selected: sp.id == state.currentSpaceId,
            title: Text(sp.name, overflow: TextOverflow.ellipsis),
            suffix: sp.onServer
                ? Icon(FLucideIcons.cloud, size: 14, color: t.muted)
                : null,
            onPress: () => pick(() => state.switchSpace(sp.id)),
          ),
      ],
    ),
    if (!quickOnly)
      FItemGroup(
        children: [
          FItem(
            title: const Text('New space…'),
            onPress: () => pick(() => showNewSpaceDialog(context, state)),
          ),
          FItem(
            title: const Text('Rename this space…'),
            onPress: () => pick(() => showRenameSpaceDialog(context, state)),
          ),
          if (state.currentSpaceId != SpaceCatalog.planningId)
            FItem(
              title: const Text('Delete this space…'),
              onPress: () => pick(() => showDeleteSpaceDialog(context, state)),
            ),
        ],
      ),
  ];
}
