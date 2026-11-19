import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'logo.dart';
import 'sidebar.dart';
import 'theme.dart';

/// The window-filling frame in the frame colour. On a wide screen it
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
      return ColoredBox(color: t.frame, child: child);
    }
    return ColoredBox(
      color: t.frame,
      child: Row(
        children: [
          IconRail(state: state),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                t.sizes.frameInset,
                t.sizes.frameInset,
                t.sizes.frameInset,
              ),
              child: DecoratedBox(
                key: const Key('shell-panel'),
                decoration: BoxDecoration(
                  color: t.panel,
                  border: Border.all(
                    color: t.panelBorder,
                    width: t.borders.hairline,
                  ),
                  borderRadius: BorderRadius.circular(t.radii.panel),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    t.radii.panel - t.borders.hairline,
                  ),
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

/// Icon and name of a section, shared by the rail and the narrow selector.
(IconData, String) sectionMeta(Section s) => switch (s) {
  Section.notes => (FLucideIcons.fileText, 'Files'),
  Section.views => (FLucideIcons.bookmark, 'Views'),
  Section.search => (FLucideIcons.search, 'Search'),
  Section.account => (FLucideIcons.circleUser, 'Account'),
  Section.settings => (FLucideIcons.settings, 'Settings'),
};

/// Sections shown on the rail below the Spaces item, top group then bottom
/// group. Account only
/// appears when the app can sign in.
List<Section> topSections() => const [
  Section.notes,
  Section.views,
  Section.search,
];

List<Section> bottomSections(AppState state) => [
  if (state.canSignIn) Section.account,
  Section.settings,
];

/// Icon of the Spaces rail item, which opens a popup instead of a section.
const spacesIcon = FLucideIcons.layoutGrid;
const spacesLabel = 'Spaces';

/// One rail or selector button: an icon in a rounded square that takes the
/// active tone while [active].
class RailButton extends StatelessWidget {
  const RailButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onPress,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return FTooltip(
      tipBuilder: (_, _) => Text(label),
      child: FTappable(
        semanticsLabel: label,
        selected: active,
        onPress: onPress,
        builder: (context, states, _) {
          final hovered = states.contains(FTappableVariant.hovered);
          return Container(
            width: t.sizes.railItem,
            height: t.sizes.railItem,
            decoration: BoxDecoration(
              color: active
                  ? t.activeItem
                  : hovered
                  ? t.hover
                  : null,
              borderRadius: BorderRadius.circular(t.radii.control),
            ),
            child: Icon(
              icon,
              size: t.icons.rail,
              color: active ? t.onActiveItem : t.rail,
            ),
          );
        },
      ),
    );
  }
}

/// A rail or selector button for a section.
class SectionButton extends StatelessWidget {
  const SectionButton({
    super.key,
    required this.section,
    required this.active,
    required this.onPress,
  });
  final Section section;
  final bool active;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final (icon, name) = sectionMeta(section);
    return RailButton(
      icon: icon,
      label: name,
      active: active,
      onPress: onPress,
    );
  }
}

/// The Spaces item: a rail button that pops a menu of the Spaces (current one
/// first) with the manage actions. On the rail the menu opens beside the icon;
/// in the narrow sheet ([below]) under it. Picking a Space switches to it and
/// shows Files.
class SpacesMenuButton extends StatelessWidget {
  const SpacesMenuButton({
    super.key,
    required this.state,
    this.below = false,
    this.onPick,
  });
  final AppState state;
  final bool below;

  /// Runs before a manage action opens a dialog (closes the narrow sheet).
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) => FPopoverMenu(
    menuAnchor: Alignment.topLeft,
    childAnchor: below ? Alignment.bottomLeft : Alignment.topRight,
    menuBuilder: (ctx, controller, _) =>
        spaceMenuGroups(ctx, state, controller, onPick: onPick),
    builder: (ctx, controller, _) => RailButton(
      icon: spacesIcon,
      label: spacesLabel,
      active: false,
      onPress: controller.toggle,
    ),
  );
}

/// A slim vertical rail: the logo slot, the Spaces popup, then Files, Views
/// and Search at the top, Account and Settings at the bottom.
class IconRail extends StatelessWidget {
  const IconRail({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    Widget button(Section s) => SectionButton(
      key: Key('rail-${s.name}'),
      section: s,
      active: state.section == s,
      onPress: () => state.setSection(s),
    );
    return SizedBox(
      key: const Key('icon-rail'),
      width: t.sizes.rail,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.space.lg),
        child: Column(
          spacing: t.space.xs,
          children: [
            const LogoSlot(),
            SizedBox(height: t.space.xs),
            SpacesMenuButton(key: const Key('rail-spaces'), state: state),
            for (final s in topSections()) button(s),
            const Spacer(),
            for (final s in bottomSections(state)) button(s),
          ],
        ),
      ),
    );
  }
}

/// The narrow-screen section selector at the top of the sheet.
class SectionBar extends StatelessWidget {
  const SectionBar({super.key, required this.state, this.onPick});
  final AppState state;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      key: const Key('section-bar'),
      padding: EdgeInsets.fromLTRB(
        t.space.lg,
        t.space.lg,
        t.space.lg,
        t.space.xs,
      ),
      child: Wrap(
        spacing: t.space.xs,
        runSpacing: t.space.xs,
        children: [
          SpacesMenuButton(
            key: const Key('bar-spaces'),
            state: state,
            below: true,
            onPick: onPick,
          ),
          for (final s in [...topSections(), ...bottomSections(state)])
            SectionButton(
              key: Key('bar-${s.name}'),
              section: s,
              active: state.section == s,
              onPress: () => state.setSection(s),
            ),
        ],
      ),
    );
  }
}
