import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'event_menu.dart';
import 'new_note_dialog.dart';
import 'note_menu.dart';
import 'parts.dart';
import 'shell_frame.dart';
import 'sidebar.dart';
import 'task_menu.dart';
import 'theme.dart';

// The narrow (phone) layout's chrome: bottom navigation, the Space chip and
// its sheet, the quick-add button and the peek as a bottom sheet. All of it
// is built only below Tokens.wideBreakpoint.

/// The bottom navigation items: the list sections the Space supports, then
/// Search and More.
enum NavTab { notes, tasks, events, search, more }

Section sectionOfTab(NavTab t) => switch (t) {
  NavTab.notes => Section.notes,
  NavTab.tasks => Section.tasks,
  NavTab.events => Section.events,
  NavTab.search => Section.search,
  NavTab.more => Section.views,
};

NavTab tabOfSection(Section s) => switch (s) {
  Section.notes => NavTab.notes,
  Section.tasks => NavTab.tasks,
  Section.events => NavTab.events,
  Section.search => NavTab.search,
  Section.views || Section.account || Section.settings => NavTab.more,
};

/// The tabs shown for [state]'s Space: a list section the Space cannot hold is
/// hidden.
List<NavTab> navTabs(AppState state) => [
  if (state.supportsNotes) NavTab.notes,
  if (state.supportsTasks) NavTab.tasks,
  if (state.supportsEvents) NavTab.events,
  NavTab.search,
  NavTab.more,
];

/// The bottom navigation bar. [open] is false while Home or a view page is
/// shown (no tab selected). Tapping a tab runs [onOpen] with its section.
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({
    super.key,
    required this.state,
    required this.open,
    required this.onOpen,
  });
  final AppState state;
  final bool open;
  final ValueChanged<Section> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final tabs = navTabs(state);
    final current = tabOfSection(visibleSection(state));
    final index = open ? tabs.indexOf(current) : -1;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: t.sizes.touchTarget),
      child: FBottomNavigationBar(
        key: const Key('bottom-nav'),
        index: index,
        onChange: (i) {
          final tab = tabs[i];
          // More keeps the last section of its group.
          final keep = tab == NavTab.more && tabOfSection(state.section) == tab;
          onOpen(keep ? state.section : sectionOfTab(tab));
        },
        children: [
          for (final tab in tabs)
            FBottomNavigationBarItem(
              key: Key('bnav-${tab.name}'),
              icon: Icon(_icon(tab)),
              label: Text(_label(tab)),
            ),
        ],
      ),
    );
  }

  static IconData _icon(NavTab t) => switch (t) {
    NavTab.more => FLucideIcons.ellipsis,
    _ => sectionMeta(sectionOfTab(t)).$1,
  };

  static String _label(NavTab t) => switch (t) {
    NavTab.more => 'More',
    _ => sectionMeta(sectionOfTab(t)).$2,
  };
}

/// The page of the More tab: a row of Views, Account and Settings, then the
/// chosen one.
class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final sections = [
      Section.views,
      if (state.canSignIn) Section.account,
      Section.settings,
    ];
    final current = sections.contains(state.section)
        ? state.section
        : Section.views;
    return Column(
      key: const Key('more-page'),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.lg, 0),
          child: Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              for (final s in sections)
                touchBox(
                  context,
                  FButton(
                    key: Key('more-${s.name}'),
                    variant: s == current
                        ? FButtonVariant.secondary
                        : FButtonVariant.outline,
                    size: FButtonSizeVariant.xs,
                    mainAxisSize: MainAxisSize.min,
                    selected: s == current,
                    prefix: Icon(sectionMeta(s).$1),
                    onPress: () => state.setSection(s),
                    child: Text(sectionMeta(s).$2),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: sectionBody(state, current, () {})),
      ],
    );
  }
}

/// The Space chip in the narrow top bar: the current Space's name, opening a
/// bottom sheet with the Space popup's actions.
class SpaceChip extends StatefulWidget {
  const SpaceChip({super.key, required this.state});
  final AppState state;

  @override
  State<SpaceChip> createState() => _SpaceChipState();
}

class _SpaceChipState extends State<SpaceChip> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final state = widget.state;
    final name = state.currentSpaceName ?? 'Spaces';
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: t.sizes.spaceChipMax),
      child: touchBox(
        context,
        FButton(
          key: const Key('space-chip'),
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.xs,
          mainAxisSize: MainAxisSize.min,
          prefix: Icon(spacesIcon, size: t.icons.md),
          onPress: () => showMenuSheet(
            context,
            this,
            (ctx, c) => spaceMenuGroups(context, state, c),
          ),
          // The button does not shrink its label, so the label is capped.
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: t.sizes.spaceChipMax - 56),
            child: Text(name, overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
        ),
      ),
    );
  }
}

/// What the quick-add button adds in [state]'s current section, or null when
/// it has nothing to add (Search, More, a read-only or unsupported section).
({String label, IconData icon, Future<void> Function(BuildContext) run})?
quickAddFor(AppState state) {
  switch (visibleSection(state)) {
    case Section.notes:
      if (!state.editable) return null;
      return (
        label: 'New note',
        icon: FLucideIcons.filePlus,
        run: (c) => showNewNoteDialog(c, state),
      );
    case Section.tasks:
      if (!state.tasksEditable) return null;
      return (
        label: 'New task',
        icon: FLucideIcons.listPlus,
        run: (c) => showNewTaskDialog(c, state),
      );
    case Section.events:
      if (!state.eventsEditable) return null;
      return (
        label: 'New event',
        icon: FLucideIcons.calendarPlus,
        run: (c) async {
          final uid = await showNewEventDialog(c, state);
          if (uid != null) await state.clickEvent(uid);
        },
      );
    default:
      return null;
  }
}

/// The context-sensitive quick-add button, round and [Tokens] touch sized.
class QuickAddButton extends StatelessWidget {
  const QuickAddButton({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final add = quickAddFor(state);
    if (add == null) return const SizedBox.shrink();
    final t = tokensOf(context);
    return SizedBox(
      width: t.sizes.fab,
      height: t.sizes.fab,
      child: FButton.icon(
        key: const Key('fab-add'),
        semanticsLabel: add.label,
        onPress: () => add.run(context),
        child: Icon(add.icon),
      ),
    );
  }
}

/// The peek as a draggable bottom sheet over the page. Its handle row drags
/// it between the half and the full height (below the dismiss line it
/// closes); the row also carries "Open in main", which moves the item to a
/// full-screen page. [child] is the peeked item.
class PeekSheet extends StatefulWidget {
  const PeekSheet({
    super.key,
    required this.state,
    required this.height,
    required this.child,
  });
  final AppState state;

  /// The room the sheet may fill (the page area's height).
  final double height;
  final Widget child;

  @override
  State<PeekSheet> createState() => _PeekSheetState();
}

class _PeekSheetState extends State<PeekSheet> {
  static const _half = 0.55, _full = 1.0, _dismiss = 0.3;
  double _fraction = _half;

  void _drag(DragUpdateDetails d) => setState(
    () =>
        _fraction = (_fraction - d.delta.dy / widget.height).clamp(0.2, _full),
  );

  void _end([DragEndDetails? d]) {
    final v = d?.primaryVelocity ?? 0;
    if (_fraction < _dismiss || v > 900 && _fraction < _half) {
      widget.state.guarded(() => widget.state.select(null));
      setState(() => _fraction = _half);
      return;
    }
    setState(
      () => _fraction = v < -600 || _fraction > (_half + _full) / 2
          ? _full
          : _half,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final h = math.max(t.sizes.touchTarget * 2, widget.height * _fraction);
    final r = Radius.circular(t.radii.panel);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: math.min(h, widget.height),
      child: DecoratedBox(
        key: const Key('peek-sheet'),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.vertical(top: r),
          border: Border(
            top: BorderSide(color: t.panelBorder, width: t.borders.hairline),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: r),
          child: Column(
            children: [
              SizedBox(
                height: t.sizes.touchTarget,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        key: const Key('peek-sheet-handle'),
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: _drag,
                        onVerticalDragEnd: _end,
                        child: Center(
                          child: Container(
                            width: t.sizes.sheetGrip,
                            height: t.sizes.sheetGripThickness,
                            decoration: BoxDecoration(
                              color: t.divider,
                              borderRadius: BorderRadius.circular(
                                t.sizes.sheetGripThickness,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconAction(
                      key: const Key('peek-promote'),
                      tooltip: 'Open in main area',
                      icon: FLucideIcons.squareArrowOutUpRight,
                      onPress: () => widget.state.promote(),
                    ),
                  ],
                ),
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}
