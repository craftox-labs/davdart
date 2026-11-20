import 'dart:math' as math;
import 'dart:typed_data' show Float64List;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'logo.dart';
import 'sidebar.dart';
import 'theme.dart';

/// The window-filling frame in the frame colour. On a wide screen it
/// holds the [IconRail], a header row in the frame tone (the document tabs)
/// and below it the content in one rounded, bordered panel, with the frame
/// margin on all four sides; otherwise the content fills the frame. The
/// active header tab is panel-coloured and sits flush on the panel's top
/// edge, covering the border there. With [LayoutSide.end] the rail sits on
/// the right edge and the panel to its left.
///
/// [header] builds the header row for a panel of the given outer width; it
/// has [headerHeight] below the margin and is drawn above the panel.
class ShellFrame extends StatelessWidget {
  const ShellFrame({
    super.key,
    required this.state,
    required this.showRail,
    required this.child,
    this.header,
  });
  final AppState state;
  final bool showRail;
  final Widget child;
  final Widget Function(BuildContext context, double panelWidth)? header;

  /// Header row height: the top margin plus the tab height. The panel starts
  /// right below it.
  static double headerHeight(Tokens t) => t.sizes.frameInset + t.sizes.tabStrip;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final mirror = state.layoutSide == LayoutSide.end;
    final top = header == null ? t.sizes.frameInset : headerHeight(t);
    if (!showRail) {
      return ColoredBox(color: t.frame, child: child);
    }
    return ColoredBox(
      color: t.frame,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            left: mirror ? 0 : t.sizes.rail,
            right: mirror ? t.sizes.rail : 0,
            top: top,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                mirror ? t.sizes.frameInset : 0,
                0,
                mirror ? 0 : t.sizes.frameInset,
                t.sizes.frameInset,
              ),
              // A Container insets its child by the border width, so the
              // hairline shows all round.
              child: Container(
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
          if (header != null)
            Positioned(
              left: mirror ? 0 : t.sizes.rail,
              right: mirror ? t.sizes.rail : 0,
              top: 0,
              // One hairline lower than the panel's top, so the active tab
              // reaches over the border.
              height: top + t.borders.hairline,
              child: Padding(
                // Spans exactly the panel's inner width (inside its border).
                padding: EdgeInsets.fromLTRB(
                  (mirror ? t.sizes.frameInset : 0) + t.borders.hairline,
                  t.sizes.frameInset,
                  (mirror ? 0 : t.sizes.frameInset) + t.borders.hairline,
                  0,
                ),
                child: LayoutBuilder(
                  builder: (context, c) => header!(context, c.maxWidth),
                ),
              ),
            ),
          // The rail sits above the panel so the active tab can paint over
          // the panel's border on the rail side.
          Positioned(
            left: mirror ? null : 0,
            right: mirror ? 0 : null,
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
    this.flip = false,
    this.vertical = false,
    this.squareStart = false,
    this.squareEnd = false,
  });
  final Color fill, border;
  final double borderWidth, radius, margin;

  /// A header tab: the tab sits above the panel and opens downwards into its
  /// top edge (the painting is the rail tab turned a quarter, so [margin] and
  /// [flip] are in that turned frame: the tab box ends at the panel's outer
  /// top edge, so [margin] is normally 0).
  final bool vertical;

  /// A header tab that starts (or ends) at a divider rather than in free
  /// space: that side has no concave corner at its base, so the tab's edge
  /// runs straight into the divider (its top corner stays rounded like any
  /// tab's). Only with [vertical].
  final bool squareStart, squareEnd;

  /// Mirrors the tab to open leftwards (the rail is on the right).
  final bool flip;

  /// How far the tab reaches past the item box: the margin plus the panel's
  /// border, so its right edge ends flush with the panel's inner edge.
  double get reach => margin + borderWidth;

  /// The tab body in the item's coordinates.
  Rect body(Size size) =>
      Rect.fromLTWH(flip ? -reach : 0, 0, size.width + reach, size.height);

  @override
  void paint(Canvas canvas, Size size) {
    if (vertical) {
      // Swap the axes: the item's width runs along the panel edge.
      canvas.transform(
        Float64List.fromList([0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
      );
      size = Size(size.height, size.width);
    }
    if (flip) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final edge = size.width + margin; // x of the panel's outer left edge
    final r = radius;
    final fillPaint = Paint()..color = fill;
    // A tab at a divider reaches one border width further out on that side,
    // so its edge stroke lands in the divider's own pixel column.
    final y0 = vertical && squareStart ? -borderWidth : 0.0;
    final y1 = size.height + (vertical && squareEnd ? borderWidth : 0.0);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(0, y0, size.width + reach, y1),
        topLeft: Radius.circular(r),
        bottomLeft: Radius.circular(r),
      ),
      fillPaint,
    );
    final arc = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    if (vertical) {
      // The tab's outline in the panel's border colour: top and both sides
      // (inset by half the width so the stroke stays inside the box), left
      // open at the base where the tab joins the panel.
      final o = borderWidth / 2;
      final inner = Radius.circular(r - o);
      final to = edge + borderWidth; // past the panel's outer top edge
      canvas.drawPath(
        Path()
          ..moveTo(squareStart ? to : edge - r, y0 + o)
          ..lineTo(r, y0 + o)
          ..arcToPoint(Offset(o, y0 + r), radius: inner, clockwise: false)
          ..lineTo(o, y1 - r)
          ..arcToPoint(Offset(r, y1 - o), radius: inner, clockwise: false)
          ..lineTo(squareEnd ? to : edge - r, y1 - o),
        arc,
      );
    }
    for (final above in [true, false]) {
      if (above ? squareStart : squareEnd) continue;
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
      margin != old.margin ||
      flip != old.flip ||
      vertical != old.vertical ||
      squareStart != old.squareStart ||
      squareEnd != old.squareEnd;
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
    this.mirror = false,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPress;
  final bool tab;
  final double tabMargin;
  final bool tipRight;

  /// The rail is on the right edge: the tab opens leftwards and the tooltip
  /// opens to the left of the icon.
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final asTab = active && tab;
    return FTooltip(
      tipAnchor: tipRight
          ? (mirror ? Alignment.centerRight : Alignment.centerLeft)
          : Alignment.bottomCenter,
      childAnchor: tipRight
          ? (mirror ? Alignment.centerLeft : Alignment.centerRight)
          : Alignment.topCenter,
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
                  flip: mirror,
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
    this.mirror = false,
  });
  final Section section;
  final bool active;
  final VoidCallback onPress;
  final bool tab;
  final double tabMargin;
  final bool tipRight;
  final bool mirror;

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
      mirror: mirror,
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
    this.mirror = false,
    this.onPick,
  });
  final AppState state;
  final bool below;

  /// The rail is on the right edge: the menu opens to the left of the icon.
  final bool mirror;

  /// Runs before a manage action opens a dialog (closes the narrow sheet).
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) => FPopoverMenu(
    menuAnchor: mirror ? Alignment.topRight : Alignment.topLeft,
    childAnchor: below
        ? Alignment.bottomLeft
        : (mirror ? Alignment.topLeft : Alignment.topRight),
    menuBuilder: (ctx, controller, _) =>
        spaceMenuGroups(ctx, state, controller, onPick: onPick),
    builder: (ctx, controller, _) => RailButton(
      icon: spacesIcon,
      label: spacesLabel,
      active: false,
      tipRight: !below,
      mirror: mirror,
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
    final mirror = state.layoutSide == LayoutSide.end;
    Widget button(Section s) => SectionButton(
      key: Key('rail-${s.name}'),
      section: s,
      active: state.section == s,
      tab: !state.sidebarCollapsed,
      tabMargin: (t.sizes.rail - t.sizes.railItem) / 2,
      tipRight: true,
      mirror: mirror,
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
            SpacesMenuButton(
              key: const Key('rail-spaces'),
              state: state,
              mirror: mirror,
            ),
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

/// A header tab. Active, it is a panel-coloured [RailTabPainter] tab that
/// ends flush on the panel's top edge, covering the panel border and flaring
/// into it with concave corners; inactive, it is [child] on the frame tone
/// with [hovered] feedback. The box is [tabStrip] high and its bottom edge is
/// the panel's outer top edge.
class JoinedTab extends StatelessWidget {
  const JoinedTab({
    super.key,
    required this.active,
    required this.child,
    this.hovered = false,
    this.flushStart = false,
    this.flushEnd = false,
  });

  /// The tab starts or ends at a divider: see [RailTabPainter.squareStart].
  final bool flushStart, flushEnd;
  final bool active;
  final bool hovered;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final box = SizedBox(height: t.sizes.tabStrip, child: child);
    if (active) {
      return CustomPaint(
        key: const Key('joined-tab'),
        painter: RailTabPainter(
          fill: t.panel,
          border: t.panelBorder,
          borderWidth: t.borders.hairline,
          radius: t.radii.tab,
          margin: 0,
          vertical: true,
          squareStart: flushStart,
          squareEnd: flushEnd,
        ),
        child: box,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hovered ? t.hover : null,
        borderRadius: BorderRadius.vertical(top: Radius.circular(t.radii.tab)),
      ),
      child: box,
    );
  }
}
