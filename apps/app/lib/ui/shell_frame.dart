import 'dart:math' as math;

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
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            left: t.sizes.rail,
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
          // The rail sits above the panel so the active tab can paint over
          // the panel's left border.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: t.sizes.rail,
            child: IconRail(state: state),
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

/// Paints the active rail item as a tab that opens into the panel. It is laid
/// out as the item's box and paints beyond it: across the rail margin
/// ([margin], the gap between the item and the panel edge) and over the
/// panel's left border, plus a concave corner above and below where it meets
/// the panel. [fill] is the panel-coloured tab, [border] the panel's border
/// colour (continued along the concave arcs).
class RailTabPainter extends CustomPainter {
  const RailTabPainter({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.radius,
    required this.margin,
  });
  final Color fill, border;
  final double borderWidth, radius, margin;

  /// How far the tab reaches past the item box: the margin plus the panel's
  /// border, so its right edge ends flush with the panel's inner edge.
  double get reach => margin + borderWidth;

  /// The tab body in the item's coordinates.
  Rect body(Size size) => Rect.fromLTWH(0, 0, size.width + reach, size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final edge = size.width + margin; // x of the panel's outer left edge
    final r = radius;
    final fillPaint = Paint()..color = fill;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        body(size),
        topLeft: Radius.circular(r),
        bottomLeft: Radius.circular(r),
      ),
      fillPaint,
    );
    final arc = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    for (final above in [true, false]) {
      final cy = above ? -r : size.height + r;
      final y0 = above ? 0.0 : size.height;
      final center = Offset(edge - r, cy);
      final start = above ? math.pi / 2 : -math.pi / 2;
      final sweep = above ? -math.pi / 2 : math.pi / 2;
      final path = Path()
        ..moveTo(edge - r, y0)
        ..arcTo(Rect.fromCircle(center: center, radius: r), start, sweep, false)
        ..lineTo(edge + borderWidth, cy)
        ..lineTo(edge + borderWidth, y0)
        ..close();
      canvas.drawPath(path, fillPaint);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start,
        sweep,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(RailTabPainter old) =>
      fill != old.fill ||
      border != old.border ||
      borderWidth != old.borderWidth ||
      radius != old.radius ||
      margin != old.margin;
}

/// One rail or selector button: an icon in a rounded square that takes the
/// active tone while [active]. With [tab] (the active item of the docked
/// rail, side panel open) the highlight is a [RailTabPainter] tab joined to the
/// panel by [tabMargin]; without it a plain rounded highlight. [tipRight]
/// opens the tooltip to the right of the icon, centred on it.
class RailButton extends StatelessWidget {
  const RailButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onPress,
    this.tab = false,
    this.tabMargin = 0,
    this.tipRight = false,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPress;
  final bool tab;
  final double tabMargin;
  final bool tipRight;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final asTab = active && tab;
    return FTooltip(
      tipAnchor: tipRight ? Alignment.centerLeft : Alignment.bottomCenter,
      childAnchor: tipRight ? Alignment.centerRight : Alignment.topCenter,
      tipBuilder: (_, _) => Text(label),
      child: FTappable(
        semanticsLabel: label,
        selected: active,
        onPress: onPress,
        builder: (context, states, _) {
          final hovered = states.contains(FTappableVariant.hovered);
          final glyph = Icon(
            icon,
            size: t.icons.rail,
            color: active ? t.onActiveItem : t.rail,
          );
          if (asTab) {
            return SizedBox(
              width: t.sizes.railItem,
              height: t.sizes.railItem,
              child: CustomPaint(
                key: const Key('rail-tab'),
                painter: RailTabPainter(
                  fill: t.activeItem,
                  border: t.panelBorder,
                  borderWidth: t.borders.hairline,
                  radius: t.radii.tab,
                  margin: tabMargin,
                ),
                child: Center(child: glyph),
              ),
            );
          }
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
            child: glyph,
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
    this.tab = false,
    this.tabMargin = 0,
    this.tipRight = false,
  });
  final Section section;
  final bool active;
  final VoidCallback onPress;
  final bool tab;
  final double tabMargin;
  final bool tipRight;

  @override
  Widget build(BuildContext context) {
    final (icon, name) = sectionMeta(section);
    return RailButton(
      icon: icon,
      label: name,
      active: active,
      onPress: onPress,
      tab: tab,
      tabMargin: tabMargin,
      tipRight: tipRight,
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
      tipRight: !below,
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
      tab: !state.sidebarCollapsed,
      tabMargin: (t.sizes.rail - t.sizes.railItem) / 2,
      tipRight: true,
      onPress: () => state.pressRail(s),
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
