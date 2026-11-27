import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:flutter/gestures.dart' show kMiddleMouseButton;

import '../state/app_state.dart';
import '../state/note_drag.dart';
import '../state/tab_state.dart';
import 'event_menu.dart';
import 'new_note_dialog.dart';
import 'note_menu.dart';
import 'save_view_dialog.dart';
import 'shell_frame.dart';
import 'task_menu.dart';
import 'surface.dart';
import 'theme.dart';
import 'overflow_tip.dart';

/// The icon a document tab shows: the desktop strip and the phone's top tab
/// use this one mapping.
IconData tabStripIcon(AppState state, DocTab tab) => switch (tab.kind) {
  TabKind.project => FLucideIcons.folderKanban,
  TabKind.view => FLucideIcons.bookmark,
  TabKind.task => FLucideIcons.listChecks,
  TabKind.event => FLucideIcons.calendar,
  TabKind.note =>
    state.tabIsFolder(tab) ? FLucideIcons.folder : FLucideIcons.fileText,
};

/// The fixed Home tab's icon (it is not a [DocTab]).
const homeTabIcon = FLucideIcons.house;

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
    this.flushStart = false,
  });
  final AppState state;
  final double startPad, endPad;

  /// The strip starts at a divider (the side panel or the peek), so the home
  /// tab lines up with it: no concave corner on its start side.
  final bool flushStart;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      // The dirty dot follows the open edit, which notifies on its own.
      listenable: Listenable.merge([
        state,
        ...state.drafts,
        ...state.taskDrafts,
        ...state.eventDrafts,
      ]),
      builder: (context, _) {
        final tabs = state.tabs;
        final active = state.activeTab;
        final plus = t.sizes.tabStrip; // square "+" box
        final flare = t.radii.tab; // concave corner reach beside a tab
        return SizedBox(
          key: const Key('tab-strip'),
          // One hairline past the tab boxes: the active tab paints over the
          // panel border below it.
          height: t.sizes.tabStripLine,
          child: Padding(
            padding: EdgeInsets.only(left: startPad, right: endPad),
            child: LayoutBuilder(
              builder: (context, c) {
                // Home is sized to its content; the rest share what is left.
                final label = TextPainter(
                  text: TextSpan(text: 'Home', style: t.type.captionStyle),
                  textDirection: TextDirection.ltr,
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout();
                final homeW =
                    t.space.md +
                    t.icons.sm +
                    t.space.sm +
                    label.width.ceilToDouble() +
                    t.space.xs +
                    t.space.md;
                final n = math.max(tabs.length, 1);
                final per = (((c.maxWidth - plus - homeW - 2 * flare) / n))
                    .clamp(t.sizes.tabMin, t.sizes.tabMax);
                return Row(
                  // Top-aligned, so the "+" shares the centreline of every
                  // other header control (tabStrip / 2 below the top).
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ActionContextMenu(
                      groups: [
                        [
                          if (state.tabs.isNotEmpty)
                            NoteMenuItem(
                              'Close all tabs',
                              FLucideIcons.x,
                              () async {
                                await state.closeAllTabs();
                              },
                              key: const Key('menu-home-close-all'),
                            ),
                        ],
                      ],
                      child: TabItem(
                        key: const Key('tab-home'),
                        flushStart: flushStart,
                        width: homeW,
                        icon: FLucideIcons.house,
                        title: 'Home',
                        tooltip: 'Home: your personal dashboard',
                        active: active == null,
                        onPress: () => state.activateTab(null),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, sc) => Row(
                          children: [
                            // The tabs' own width, capped at the room there is;
                            // the end drop zone gets what is left.
                            SizedBox(
                              width: math.min(
                                sc.maxWidth,
                                tabs.length * math.min(per, t.sizes.tabMax) +
                                    2 * flare,
                              ),
                              child: SingleChildScrollView(
                                key: const Key('tab-scroll'),
                                scrollDirection: Axis.horizontal,
                                // Room for the active tab's concave corners.
                                padding: EdgeInsets.symmetric(
                                  horizontal: flare,
                                ),
                                child: Row(
                                  children: [
                                    for (var i = 0; i < tabs.length; i++)
                                      _ReorderableTab(
                                        state: state,
                                        tab: tabs[i],
                                        index: i,
                                        width: math.min(per, t.sizes.tabMax),
                                        active: active == tabs[i],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            // Empty strip space after the last tab: a drop here
                            // moves the tab to the end.
                            Expanded(child: _EndDropZone(state: state)),
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
                            onPress: () => showNewNoteDialog(
                              context,
                              state,
                              inTab: true,
                              personal: createsPersonal(state),
                            ),
                            builder: (context, states, _) => _Box(
                              size: t.sizes.tabCloseHit,
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

/// One main tab: drag it to reorder (drop on another tab to take its place),
/// middle-click closes it, right-click or long-press opens the note menu.
class _ReorderableTab extends StatelessWidget {
  const _ReorderableTab({
    required this.state,
    required this.tab,
    required this.index,
    required this.width,
    required this.active,
  });
  final AppState state;
  final DocTab tab;
  final int index;
  final double width;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final title = state.tabTitle(tab);
    Widget item = TabItem(
      key: Key('tab-${tab.code}'),
      width: width,
      icon: tabStripIcon(state, tab),
      title: title,
      active: active,
      dirty: state.tabDirty(tab),
      onPress: () => state.activateTab(tab),
      onClose: () => state.closeTab(tab),
    );
    if (tab.kind == TabKind.note) {
      item = NoteContextMenu(
        state: state,
        uid: tab.id,
        surface: NoteSurface.mainTab,
        child: item,
      );
    } else if (tab.kind == TabKind.task) {
      item = TaskContextMenu(
        state: state,
        uid: tab.id,
        surface: NoteSurface.mainTab,
        child: item,
      );
    } else if (tab.kind == TabKind.event) {
      item = EventContextMenu(
        state: state,
        uid: tab.id,
        surface: NoteSurface.mainTab,
        child: item,
      );
    } else if (tab.kind == TabKind.project) {
      item = ActionContextMenu(
        groups: [
          [
            NoteMenuItem(
              'Close tab',
              FLucideIcons.x,
              () => state.closeTab(tab),
              key: const Key('menu-close'),
            ),
            if (state.tabs.length > 1)
              NoteMenuItem(
                'Close other tabs',
                FLucideIcons.x,
                () => state.closeOtherTabs(tab),
                key: const Key('menu-close-others'),
              ),
          ],
        ],
        child: item,
      );
    } else {
      final view = state.savedViews.where((v) => v.uid == tab.id).firstOrNull;
      item = ActionContextMenu(
        groups: [
          [
            NoteMenuItem(
              'Open view',
              FLucideIcons.bookmark,
              () => state.activateTab(tab),
              key: const Key('menu-tab-open-view'),
            ),
            if (view != null && state.editable)
              NoteMenuItem(
                'Rename view…',
                FLucideIcons.pencil,
                () => showRenameViewDialog(context, state, view),
                key: const Key('menu-tab-rename-view'),
              ),
            if (view != null && state.editable)
              NoteMenuItem(
                'Remove view',
                FLucideIcons.trash2,
                () => state.deleteView(view.name),
                key: const Key('menu-tab-delete-view'),
              ),
          ],
          [
            NoteMenuItem(
              'Close tab',
              FLucideIcons.x,
              () => state.closeTab(tab),
              key: const Key('menu-close'),
            ),
            if (state.tabs.length > 1)
              NoteMenuItem(
                'Close other tabs',
                FLucideIcons.x,
                () => state.closeOtherTabs(tab),
                key: const Key('menu-close-others'),
              ),
            if (state.tabs.last != tab)
              NoteMenuItem(
                'Close tabs to the right',
                FLucideIcons.x,
                () => state.closeTabsToRight(tab),
                key: const Key('menu-close-right'),
              ),
          ],
        ],
        child: item,
      );
    }
    final drag = Draggable<TabDrag>(
      key: Key('tab-drag-${tab.code}'),
      data: TabDrag(tab.code),
      axis: Axis.horizontal,
      // The feedback's offset is then the pointer, which the drop targets
      // read to tell a tab's left half from its right.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: DefaultTextStyle(
        style: t.type.captionStyle.copyWith(color: t.fg),
        child: Container(
          width: width,
          height: t.sizes.tabStrip,
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(horizontal: t.space.md),
          decoration: BoxDecoration(
            color: t.panel,
            border: Border.all(color: t.divider),
            borderRadius: BorderRadius.circular(t.radii.small),
          ),
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      childWhenDragging: Opacity(opacity: t.motion.dragGhost, child: item),
      child: item,
    );
    return Listener(
      onPointerDown: (e) {
        if (e.buttons == kMiddleMouseButton) state.closeTab(tab);
      },
      child: _TabDropTarget(state: state, tab: tab, index: index, child: drag),
    );
  }
}

/// Moves [moved] to the insertion slot [slot] (0..n, before the tab now at
/// that index; n is the end), allowing for its own removal.
void _dropTab(AppState state, DocTab moved, int slot) {
  final from = state.tabs.indexOf(moved);
  if (from < 0) return;
  state.moveTab(moved, slot > from ? slot - 1 : slot);
}

/// A tab's drop target: the left half inserts before it, the right half after
/// it. The accent edge shows on the side the tab will land.
class _TabDropTarget extends StatefulWidget {
  const _TabDropTarget({
    required this.state,
    required this.tab,
    required this.index,
    required this.child,
  });
  final AppState state;
  final DocTab tab;
  final int index;
  final Widget child;

  @override
  State<_TabDropTarget> createState() => _TabDropTargetState();
}

class _TabDropTargetState extends State<_TabDropTarget> {
  bool _after = false;

  bool _isAfter(Offset global) {
    final box = context.findRenderObject() as RenderBox;
    return box.globalToLocal(global).dx > box.size.width / 2;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return DragTarget<TabDrag>(
      onWillAcceptWithDetails: (d) =>
          d.data.code != widget.tab.code && DocTab.parse(d.data.code) != null,
      onMove: (d) {
        final after = _isAfter(d.offset);
        if (after != _after) setState(() => _after = after);
      },
      onAcceptWithDetails: (d) {
        final moved = DocTab.parse(d.data.code);
        if (moved != null) {
          _dropTab(
            widget.state,
            moved,
            widget.index + (_isAfter(d.offset) ? 1 : 0),
          );
        }
      },
      builder: (context, candidates, _) {
        final side = BorderSide(color: t.accent, width: t.borders.focus);
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: candidates.isEmpty
                ? null
                : _after
                ? Border(right: side)
                : Border(left: side),
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// The empty strip space after the last tab; dropping a tab moves it last.
class _EndDropZone extends StatelessWidget {
  const _EndDropZone({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return DragTarget<TabDrag>(
      key: const Key('tab-end-drop'),
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (d) => DocTab.parse(d.data.code) != null,
      onAcceptWithDetails: (d) {
        final moved = DocTab.parse(d.data.code);
        if (moved != null) _dropTab(state, moved, state.tabs.length);
      },
      builder: (context, candidates, _) => DecoratedBox(
        decoration: BoxDecoration(
          border: candidates.isEmpty
              ? null
              : Border(
                  left: BorderSide(color: t.accent, width: t.borders.focus),
                ),
        ),
        child: const SizedBox.expand(),
      ),
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
    return SizedBox(
      width: size,
      height: size,
      child: Surface(
        hovered: hovered,
        child: Center(child: child),
      ),
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
    this.tooltip,
    this.dirty = false,
    this.flushStart = false,
    this.flushEnd = false,
  });
  final bool flushStart, flushEnd;
  final double width;
  final IconData icon;
  final String title;
  final bool active, dirty;
  final VoidCallback onPress;
  final VoidCallback? onClose;
  final String? tooltip;

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
  void didUpdateWidget(TabItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _reveal();
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
    final tab = Align(
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
              flushStart: widget.flushStart,
              flushEnd: widget.flushEnd,
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
                      child: OverflowTip(
                        widget.title.isEmpty ? 'Untitled' : widget.title,
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
    final tip = widget.tooltip;
    return tip == null
        ? tab
        : FTooltip(tipBuilder: (_, _) => Text(tip), child: tab);
  }
}

/// Accepts a peek note dragged from the side panel and promotes it to a main
/// tab; outlines itself while a drag is over it.
class PromoteTarget extends StatelessWidget {
  const PromoteTarget({super.key, required this.state, required this.child});
  final AppState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return DragTarget<NoteDrag>(
      // Board cards and list rows already sit in the main area: only the peek,
      // the tree and the like promote.
      onWillAcceptWithDetails: (d) =>
          d.data.source != NoteDragSource.board &&
          d.data.source != NoteDragSource.list &&
          state.findItem(d.data.uid) != null,
      onAcceptWithDetails: (d) => state.promote(d.data.uid),
      builder: (context, candidates, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: candidates.isEmpty
              ? null
              : Border.all(color: t.accent, width: t.borders.focus),
        ),
        child: child,
      ),
    );
  }
}
