import 'dart:math' as math;
import 'dart:typed_data' show Float64List;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import '../state/note_drag.dart';
import 'app_actions.dart';
import 'key_nav_ui.dart';
import '../theme/tokens.dart';
import 'logo.dart';
import 'section_registry.dart';
import 'sidebar.dart';
import 'surface.dart';
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
    // Rail only (side panel collapsed): the panel's corner at the rail is
    // square, flush with the divider, rather than rounded.
    final square = state.sidebarCollapsed;
    final r = Radius.circular(t.radii.panel);
    final ri = Radius.circular(t.radii.panel - t.borders.hairline);
    final none = Radius.zero;
    BorderRadius corners(Radius r) => BorderRadius.only(
      topLeft: square && !mirror ? none : r,
      topRight: square && mirror ? none : r,
      bottomLeft: r,
      bottomRight: r,
    );
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
                  borderRadius: corners(r),
                ),
                child: ClipRRect(borderRadius: corners(ri), child: child),
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
          // The divider between the rail and the panel runs on up through
          // the header row, so the first tab sits flush at it.
          if (header != null && square)
            Positioned(
              left: mirror ? null : t.sizes.rail,
              right: mirror ? t.sizes.rail : null,
              top: 0,
              height: top + t.borders.hairline,
              width: t.borders.hairline,
              child: ColoredBox(
                key: const Key('rail-divider'),
                color: t.panelBorder,
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
            child: AreaMark(
              nav: state.nav,
              area: NavArea.rail,
              bar: false,
              child: IconRail(state: state),
            ),
          ),
        ],
      ),
    );
  }
}

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
    this.size,
    this.tipRight = false,
    this.mirror = false,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPress;
  final bool tab;
  final double tabMargin;

  /// The button's side; [SizeTokens.railItem] by default.
  final double? size;
  final bool tipRight;

  /// The rail is on the right edge: the tab opens leftwards and the tooltip
  /// opens to the left of the icon.
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final side = size ?? t.sizes.railItem;
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
              width: side,
              height: side,
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
          return SizedBox(
            width: side,
            height: side,
            child: Surface(
              color: active ? t.activeItem : null,
              hovered: hovered,
              radius: t.radii.control,
              child: Center(child: glyph),
            ),
          );
        },
      ),
    );
  }
}

/// A rail or selector button for an entry of the [sectionDefs] registry.
class SectionButton extends StatelessWidget {
  const SectionButton({
    super.key,
    required this.def,
    required this.active,
    required this.onPress,
    this.tab = false,
    this.tabMargin = 0,
    this.size,
    this.tipRight = false,
    this.mirror = false,
  });
  final SectionDef def;
  final bool active;
  final VoidCallback onPress;
  final bool tab;
  final double tabMargin;

  /// The tap target's side; [SizeTokens.railItem] by default.
  final double? size;
  final bool tipRight;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    return RailButton(
      icon: def.icon,
      label: def.label,
      active: active,
      onPress: onPress,
      tab: tab,
      tabMargin: tabMargin,
      size: size,
      tipRight: tipRight,
      mirror: mirror,
    );
  }
}

/// A slim vertical rail, built from the [sectionDefs] registry: the logo, the
/// personal group (Home, Notes, Tasks, Calendar), Projects, a gap, then the
/// global tools (Search, Views, Spaces, Account, Settings). Entries whose
/// section the Space cannot hold are left out.
///
/// [strip] is the phone's version, inside the side menu: no logo, the
/// touch-target size (44dp) and a press that only sets the section.
class IconRail extends StatelessWidget {
  const IconRail({
    super.key,
    required this.state,
    this.strip = false,
    this.onHome,
  });
  final AppState state;

  /// Phone: the strip in the side menu. No logo; [SizeTokens.touchTarget] tap
  /// targets; the active section is always on a tab (the phone never folds
  /// the panel); a press only sets the section, as [AppState.pressRail] would
  /// fold the desktop panel and write its shared pref.
  final bool strip;

  /// Runs after a press on Home on the strip: the main area is hidden behind
  /// the side menu there, so the menu closes on it.
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final mirror = !strip && state.layoutSide == LayoutSide.end;
    final item = strip ? t.sizes.touchTarget : t.sizes.railItem;
    // The strip marks the section the panel shows, which is not
    // [AppState.section] when the Space cannot hold the stored one. Home is
    // not a panel section, so only the wide rail marks it, as the place the
    // main area shows.
    final active = strip ? visibleSection(state) : state.section;
    final top = railEntries(state);
    final bottom = railBottomEntries(state);
    final all = [...top, ...bottom];

    /// Home: the main area's personal overview, not a panel.
    Future<void> home() async {
      state.clearSearch();
      await state.activateTab(null);
      if (strip) {
        // The phone has no docked panel, so a press only shows Home.
        state.showHome();
      } else {
        state.pressRailHome();
      }
      state.nav.focusArea(NavArea.main, list: navListId(state, NavArea.main));
      onHome?.call();
    }

    state.nav.publish(KeyNav.railList, [
      for (final d in all)
        NavEntry(
          d.id,
          open: (_) async {
            if (d.section == null) {
              await home();
              return;
            }
            state.setSection(d.section!);
            focusPanel(state);
            // Search opens on its field, like the bar's button and `/`.
            if (d.section == Section.search) state.nav.focusSearch();
          },
        ),
    ]);

    void open(SectionDef d) {
      if (d.section == null) {
        home();
        return;
      }
      if (strip) {
        state.setSection(d.section!);
      } else {
        state.pressRail(d.section!);
      }
      if (d.section == Section.search) state.nav.focusSearch();
    }

    Widget button(SectionDef d, {bool tabJoined = true}) {
      final s = d.section;
      final b = NavRow(
        nav: state.nav,
        list: KeyNav.railList,
        id: d.id,
        radius: t.radii.control,
        child: SectionButton(
          key: Key('rail-${d.id}'),
          def: d,
          // Home has no panel: it is marked while the main area shows it,
          // never as a tab joined to the panel.
          active: s == null
              ? !strip && state.atHome
              : active == s ||
                    (s == Section.projects && state.mainProjectUid != null),
          tab: s != null && tabJoined && (strip || !state.sidebarCollapsed),
          tabMargin: (t.sizes.rail - item) / 2,
          size: item,
          tipRight: !strip,
          mirror: mirror,
          onPress: () => open(d),
        ),
      );
      if (s != Section.spaces) return b;
      // A note dragged over it shows the Spaces panel, where the rows take
      // the drop (the panel replaced the popup).
      return DragTarget<NoteDrag>(
        onWillAcceptWithDetails: (d) =>
            state.editable && state.spaces.length > 1,
        onMove: (_) {
          if (state.section != Section.spaces) state.setSection(Section.spaces);
          if (!strip) state.setSidebarCollapsed(false);
        },
        builder: (_, _, _) => b,
      );
    }

    /// The entries with a wider gap between groups: the personal group and
    /// Projects stay together, the global tools are set apart.
    List<Widget> entries(List<SectionDef> defs) => [
      for (final (i, d) in defs.indexed) ...[
        if (i > 0 && d.group != defs[i - 1].group) SizedBox(height: t.space.md),
        button(d),
      ],
    ];

    if (strip) {
      return SizedBox(
        key: const Key('icon-rail'),
        width: t.sizes.rail,
        child: ColoredBox(
          color: t.frame,
          child: Padding(
            padding: EdgeInsets.only(bottom: t.space.lg),
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      spacing: t.space.xs,
                      children: [
                        ...entries(top),
                        const Spacer(),
                        ...entries(bottom),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final tabMid = math.max(0.0, t.sizes.frameInset + t.sizes.tabStrip / 2);
    final logoBand = tabMid + t.sizes.railItem / 2;
    return SizedBox(
      key: const Key('icon-rail'),
      width: t.sizes.rail,
      child: Padding(
        padding: EdgeInsets.only(bottom: t.space.lg),
        // Scrolls when the window is too short for every item (the Spacer
        // still pushes the global tools to the bottom when it fits).
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  spacing: t.space.xs,
                  children: [
                    // The logo's centre is on the header tab row's centreline.
                    SizedBox(
                      height: logoBand,
                      child: const Align(
                        alignment: Alignment.bottomCenter,
                        child: LogoSlot(),
                      ),
                    ),
                    ...entries(top),
                    const Spacer(),
                    ...entries(bottom),
                  ],
                ),
              ),
            ),
          ),
        ),
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
    this.height,
  });

  /// The tab's height; [Sizes.tabStrip] by default.
  final double? height;

  /// The tab starts or ends at a divider: see [RailTabPainter.squareStart].
  final bool flushStart, flushEnd;
  final bool active;
  final bool hovered;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final box = SizedBox(height: height ?? t.sizes.tabStrip, child: child);
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
