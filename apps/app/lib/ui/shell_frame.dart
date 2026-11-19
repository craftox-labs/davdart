import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
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
              padding: const EdgeInsets.fromLTRB(
                0,
                Tokens.frameInset,
                Tokens.frameInset,
                Tokens.frameInset,
              ),
              child: DecoratedBox(
                key: const Key('shell-panel'),
                decoration: BoxDecoration(
                  color: t.panel,
                  border: Border.all(color: t.panelBorder),
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

/// Icon and name of a section, shared by the rail and the narrow selector.
(IconData, String) sectionMeta(Section s) => switch (s) {
  Section.notes => (FLucideIcons.fileText, 'Notes'),
  Section.views => (FLucideIcons.bookmark, 'Views'),
  Section.search => (FLucideIcons.search, 'Search'),
  Section.spaces => (FLucideIcons.layoutGrid, 'Spaces'),
  Section.account => (FLucideIcons.circleUser, 'Account'),
  Section.settings => (FLucideIcons.settings, 'Settings'),
};

/// Sections shown on the rail, top group then bottom group. Account only
/// appears when the app can sign in.
List<Section> topSections() => const [
  Section.notes,
  Section.views,
  Section.search,
  Section.spaces,
];

List<Section> bottomSections(AppState state) => [
  if (state.canSignIn) Section.account,
  Section.settings,
];

/// One rail or selector button: an icon in a rounded square that takes the
/// active tone while its section is shown.
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
    final t = tokensOf(context);
    final (icon, name) = sectionMeta(section);
    return FTooltip(
      tipBuilder: (_, _) => Text(name),
      child: FTappable(
        semanticsLabel: name,
        selected: active,
        onPress: onPress,
        builder: (context, states, _) {
          final hovered = states.contains(FTappableVariant.hovered);
          return Container(
            width: Tokens.railItem,
            height: Tokens.railItem,
            decoration: BoxDecoration(
              color: active
                  ? t.activeItem
                  : hovered
                  ? t.hover
                  : null,
              borderRadius: BorderRadius.circular(Tokens.railItemRadius),
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? t.onActiveItem : t.rail,
            ),
          );
        },
      ),
    );
  }
}

/// A slim vertical rail that switches the side panel's section: Notes, Views,
/// Search and Spaces at the top, Account and Settings at the bottom.
class IconRail extends StatelessWidget {
  const IconRail({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    Widget button(Section s) => SectionButton(
      key: Key('rail-${s.name}'),
      section: s,
      active: state.section == s,
      onPress: () => state.setSection(s),
    );
    return SizedBox(
      key: const Key('icon-rail'),
      width: Tokens.railWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          spacing: 4,
          children: [
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
  const SectionBar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('section-bar'),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
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
