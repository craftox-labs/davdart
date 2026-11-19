import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/tab_state.dart';
import 'new_note_dialog.dart';
import 'shell_frame.dart';
import 'theme.dart';

/// The document tab strip across the top of the content area: the pinned home
/// tab (the Board or List), one closable tab per open note or applied saved
/// view, and a "+" that adds a note. It lives in the shell's header row, on
/// the frame tone. The active tab is a [JoinedTab]: panel-coloured and flush
/// on the panel's top edge; the others are unframed. Tabs shrink to a least
/// width, then the strip scrolls. [startPad] and [endPad] keep the active
/// tab's concave corners clear of whatever borders the strip. All look values
/// come from tokens, so the whole look is changed in one place.
class TabStrip extends StatelessWidget {
  const TabStrip({
    super.key,
    required this.state,
    this.startPad = 0,
    this.endPad = 0,
  });
  final AppState state;
  final double startPad, endPad;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final draft = state.draft;
    return ListenableBuilder(
      // The dirty dot follows the open edit, which notifies on its own.
      listenable: Listenable.merge([state, ?draft]),
      builder: (context, _) {
        final tabs = state.tabs;
        final active = state.activeTab;
        final plus = t.sizes.tabStrip; // square "+" box
        final flare = t.radii.tab; // concave corner reach beside a tab
        return SizedBox(
          key: const Key('tab-strip'),
          // One hairline past the tab boxes: the active tab paints over the
          // panel border below it.
          height: t.sizes.tabStrip + t.borders.hairline,
          child: Padding(
            padding: EdgeInsets.only(left: startPad, right: endPad),
            child: LayoutBuilder(
              builder: (context, c) {
                final n = tabs.length + 1;
                final per = (((c.maxWidth - plus - 2 * flare) / n)).clamp(
                  t.sizes.tabMin,
                  t.sizes.tabMax,
                );
                return Row(
                  children: [
                    TabItem(
                      key: const Key('tab-home'),
                      width: per,
                      icon: state.view == ViewMode.board
                          ? FLucideIcons.squareKanban
                          : FLucideIcons.list,
                      title:
                          state.scope?.summary ??
                          state.currentSpaceName ??
                          'Notes',
                      active: active == null,
                      onPress: () => state.activateTab(null),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: const Key('tab-scroll'),
                        scrollDirection: Axis.horizontal,
                        // Room for the active tab's concave corners.
                        padding: EdgeInsets.symmetric(horizontal: flare),
                        child: Row(
                          children: [
                            for (final tab in tabs)
                              TabItem(
                                key: Key('tab-${tab.code}'),
                                width: math.min(per, t.sizes.tabMax),
                                icon: tab.kind == TabKind.view
                                    ? FLucideIcons.bookmark
                                    : state.tabIsFolder(tab)
                                    ? FLucideIcons.folder
                                    : FLucideIcons.fileText,
                                title: state.tabTitle(tab),
                                active: active == tab,
                                dirty: state.tabDirty(tab),
                                onPress: () => state.activateTab(tab),
                                onClose: () => state.closeTab(tab),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: plus,
                      height: t.sizes.tabStrip,
                      child: Center(
                        child: FTooltip(
                          tipBuilder: (_, _) => const Text('New note'),
                          child: FTappable(
                            key: const Key('tab-new'),
                            semanticsLabel: 'New note',
                            onPress: () =>
                                showNewNoteDialog(context, state, inTab: true),
                            builder: (context, states, _) => _Box(
                              size: t.sizes.tabClose + t.space.sm,
                              hovered: states.contains(
                                FTappableVariant.hovered,
                              ),
                              child: Icon(
                                FLucideIcons.plus,
                                size: t.icons.md,
                                color: t.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// A small rounded square that takes the hover tone.
class _Box extends StatelessWidget {
  const _Box({required this.size, required this.hovered, required this.child});
  final double size;
  final bool hovered;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hovered ? t.hover : null,
        borderRadius: BorderRadius.circular(t.radii.small),
      ),
      child: child,
    );
  }
}

/// One tab: icon, title, dirty dot and close button. Without [onClose] it is
/// the pinned home tab. Shared by the strip and the detail pane's header.
class TabItem extends StatefulWidget {
  const TabItem({
    super.key,
    required this.width,
    required this.icon,
    required this.title,
    required this.active,
    required this.onPress,
    this.onClose,
    this.dirty = false,
  });
  final double width;
  final IconData icon;
  final String title;
  final bool active, dirty;
  final VoidCallback onPress;
  final VoidCallback? onClose;

  @override
  State<TabItem> createState() => TabItemState();
}

class TabItemState extends State<TabItem> {
  @override
  void initState() {
    super.initState();
    if (widget.active) _reveal();
  }

  @override
  void didUpdateWidget(TabItem old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _reveal();
  }

  /// Scrolls the strip so the active tab is in view.
  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.onClose != null) {
      Scrollable.ensureVisible(context);
    }
  });

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Align(
      alignment: Alignment.topLeft,
      widthFactor: 1,
      child: SizedBox(
        width: widget.width,
        child: FTappable(
          semanticsLabel: widget.title,
          selected: widget.active,
          onPress: widget.onPress,
          builder: (context, states, _) {
            final hovered = states.contains(FTappableVariant.hovered);
            final closable = widget.onClose != null;
            return JoinedTab(
              active: widget.active,
              hovered: hovered,
              child: Padding(
                padding: EdgeInsets.only(left: t.space.md, right: t.space.xs),
                child: Row(
                  spacing: t.space.sm,
                  children: [
                    Icon(
                      widget.icon,
                      size: t.icons.sm,
                      color: widget.active ? t.fg : t.muted,
                    ),
                    Expanded(
                      child: Text(
                        widget.title.isEmpty ? 'Untitled' : widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.type.captionStyle.copyWith(
                          color: widget.active ? t.fg : t.muted,
                        ),
                      ),
                    ),
                    if (widget.dirty)
                      Container(
                        key: const Key('tab-dirty'),
                        width: t.sizes.statusDot,
                        height: t.sizes.statusDot,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (closable)
                      SizedBox(
                        width: t.sizes.tabClose,
                        height: t.sizes.tabClose,
                        child: (widget.active || hovered)
                            ? FTappable(
                                key: const Key('tab-close'),
                                semanticsLabel: 'Close tab',
                                onPress: widget.onClose,
                                builder: (context, s, _) => _Box(
                                  size: t.sizes.tabClose,
                                  hovered: s.contains(FTappableVariant.hovered),
                                  child: Icon(
                                    FLucideIcons.x,
                                    size: t.icons.sm,
                                    color: t.muted,
                                  ),
                                ),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
