import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/key_nav.dart';
import '../state/tab_state.dart';
import 'event_menu.dart';
import 'key_nav_ui.dart';
import 'new_note_dialog.dart';
import 'note_menu.dart';
import 'overflow_tip.dart';
import 'parts.dart';
import 'shell_frame.dart';
import 'sidebar.dart';
import 'task_menu.dart';
import 'theme.dart';
import '../theme/tokens.dart';

// The narrow (phone) layout's chrome, built only below Tokens.wideBreakpoint:
// the floating bottom bar, the + menu, the side menu page, the open-items
// grid and the Space chip. Everything reuses the panels and actions of the
// desktop layout.

/// One thing the + menu can add.
class AddEntry {
  const AddEntry(this.key, this.label, this.icon, this.run, this.section);
  final String key, label;
  final IconData icon;
  final Future<void> Function(BuildContext) run;
  final Section section;
}

/// What + can add in [state]'s Space (a type the Space cannot hold, or a
/// read-only one, is left out), the type of the side menu's current filter
/// first.
List<AddEntry> addEntries(AppState state) {
  final all = [
    if (state.editable)
      AddEntry(
        'add-note',
        'New note',
        FLucideIcons.filePlus,
        (c) => showNewNoteDialog(c, state),
        Section.notes,
      ),
    if (state.tasksEditable)
      AddEntry(
        'add-task',
        'New task',
        FLucideIcons.listPlus,
        (c) => showNewTaskDialog(c, state),
        Section.tasks,
      ),
    if (state.eventsEditable)
      AddEntry('add-event', 'New event', FLucideIcons.calendarPlus, (c) async {
        final uid = await showNewEventDialog(c, state);
        if (uid != null) await state.clickEvent(uid);
      }, Section.events),
  ];
  final first = visibleSection(state);
  return [
    ...all.where((e) => e.section == first),
    ...all.where((e) => e.section != first),
  ];
}

/// Shows the + menu (a sheet of [addEntries]); [before] runs first when a
/// row is picked, [prefix] namespaces the row keys.
void showAddMenu(
  BuildContext context,
  TickerProvider vsync,
  AppState state, {
  String prefix = '',
  VoidCallback? before,
  BuildContext? host,
}) {
  final entries = addEntries(state);
  if (entries.isEmpty) return;
  final t = tokensOf(context);
  showMenuSheet(context, vsync, (ctx, c) {
    return [
      FItemGroup(
        children: [
          for (final e in entries)
            FItem(
              key: Key('$prefix${e.key}'),
              prefix: Icon(e.icon, size: t.icons.md, color: t.muted),
              title: Text(e.label),
              onPress: () {
                c.hide();
                before?.call();
                // The caller may be gone by now (the grid closes): run in
                // a stable context when given.
                final run = host ?? context;
                if (run.mounted) e.run(run);
              },
            ),
        ],
      ),
    ];
  });
}

/// The bottom bar: Menu, Back, Home, Search and the open-items counter, directly
/// under a hairline (no pill or card). New items come from [AddFab].
class MobileBar extends StatelessWidget {
  const MobileBar({
    super.key,
    required this.state,
    required this.canBack,
    required this.onBack,
    required this.onSearch,
    required this.onGrid,
    required this.onHome,
    required this.menuOpen,
    required this.onMenu,
  });
  final AppState state;
  final bool canBack, menuOpen;
  final VoidCallback onBack, onSearch, onGrid, onHome, onMenu;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final count = state.tabs.length;
    return DecoratedBox(
      key: const Key('mobile-bar'),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.panelBorder, width: t.borders.hairline),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.space.lg,
          vertical: t.space.xs,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Toggles the side menu; the icon says what a press does.
            IconAction(
              key: const Key('menu'),
              tooltip: menuOpen ? 'Close menu' : 'Menu',
              icon: menuOpen ? FLucideIcons.panelLeftClose : FLucideIcons.menu,
              onPress: onMenu,
            ),
            IconAction(
              key: const Key('bar-back'),
              tooltip: 'Back',
              icon: FLucideIcons.arrowLeft,
              onPress: canBack ? onBack : null,
            ),
            IconAction(
              key: const Key('bar-home'),
              tooltip: 'Home',
              icon: FLucideIcons.house,
              onPress: onHome,
            ),
            IconAction(
              key: const Key('bar-search'),
              tooltip: 'Search',
              icon: FLucideIcons.search,
              onPress: onSearch,
            ),
            FTappable(
              key: const Key('bar-count'),
              semanticsLabel: 'Open items: $count',
              behavior: HitTestBehavior.opaque,
              onPress: onGrid,
              child: SizedBox(
                width: t.sizes.touchTarget,
                height: t.sizes.touchTarget,
                child: Center(
                  // A quiet outlined box: the count reads as a bigger icon.
                  child: Container(
                    key: const Key('bar-count-box'),
                    width: t.sizes.touchTarget - t.space.md,
                    height: t.sizes.touchTarget - t.space.md,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: t.muted,
                        width: t.borders.hairline,
                      ),
                      borderRadius: BorderRadius.circular(t.space.xs),
                    ),
                    child: Text('$count', style: t.type.labelStyle),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The floating accent + button above the bar's right end; opens the + menu.
class AddFab extends StatefulWidget {
  const AddFab({super.key, required this.state});
  final AppState state;

  @override
  State<AddFab> createState() => _AddFabState();
}

class _AddFabState extends State<AddFab> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (addEntries(widget.state).isEmpty) return const SizedBox.shrink();
    final size = t.sizes.touchTarget + t.space.sm;
    return FTappable(
      key: const Key('bar-add'),
      semanticsLabel: 'New',
      behavior: HitTestBehavior.opaque,
      onPress: () => showAddMenu(context, this, widget.state),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
        child: Icon(FLucideIcons.plus, size: t.icons.lg, color: t.onAccent),
      ),
    );
  }
}

/// The Space chip: the current Space's name, opening a bottom sheet with the
/// Space popup's actions.
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
    // The active desktop header tab: panel tone, flared concave bottom
    // corners, flush on the top bar's bottom edge (over its hairline).
    final flare = t.radii.tab;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Transform.translate(
        offset: Offset(0, t.borders.hairline),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: flare),
          child: FTappable(
            key: const Key('space-chip'),
            semanticsLabel: name,
            behavior: HitTestBehavior.opaque,
            onPress: () => showMenuSheet(
              context,
              this,
              (ctx, c) => spaceMenuGroups(context, state, c),
            ),
            // The tab takes the whole header height (it is its own hit box)
            // and its content sits on the logo's centre line.
            child: Align(
              alignment: Alignment.bottomCenter,
              child: JoinedTab(
                active: true,
                height: t.sizes.paneHeader,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.space.lg),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: t.space.sm,
                    children: [
                      // Same size as the logo.
                      Icon(spacesIcon, size: t.icons.lg, color: t.fg),
                      Flexible(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: t.type.captionStyle.copyWith(color: t.fg),
                        ),
                      ),
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
}

/// How many notes (not folders) the current Space holds.
int _noteCount(AppState state) {
  var n = 0;
  void walk(List<NoteNode> nodes) {
    for (final x in nodes) {
      if (!AppState.isFolder(x.note)) n++;
      walk(x.children);
    }
  }

  walk(state.tree.roots);
  return n;
}

/// The sections the side menu's filter offers for [state]'s Space.
List<Section> filterSections(AppState state) => topSections(state);

/// The full-screen side menu: a filter pill choosing the panel (bound to
/// [AppState.section]) and that panel (with its toolbar and tags drawer).
/// Account and Settings are in the filter pill's list. [onClose] closes it;
/// picking an item runs it too.
class SideMenuPage extends StatefulWidget {
  const SideMenuPage({super.key, required this.state, required this.onClose});
  final AppState state;
  final VoidCallback onClose;

  @override
  State<SideMenuPage> createState() => _SideMenuPageState();
}

class _SideMenuPageState extends State<SideMenuPage>
    with TickerProviderStateMixin {
  int? _count(Section s) => switch (s) {
    Section.notes => _noteCount(widget.state),
    Section.tasks => widget.state.tasks.where(widget.state.taskInScope).length,
    Section.events =>
      widget.state.events.where(widget.state.eventInScope).length,
    Section.projects => widget.state.projectIndex.projects().length,
    _ => null,
  };

  String _label(Section s) {
    final name = sectionMeta(s).$2;
    final n = _count(s);
    return n == null ? name : '$name · $n';
  }

  void _pickFilter() {
    final state = widget.state;
    final t = tokensOf(context);
    showMenuSheet(context, this, (ctx, c) {
      return [
        FItemGroup(
          children: [
            // As on the desktop rail, Spaces comes first and opens the Space
            // switcher (the top chip's sheet).
            FItem(
              key: const Key('filter-spaces'),
              prefix: Icon(spacesIcon, size: t.icons.md, color: t.muted),
              title: Text(spacesLabel),
              onPress: () {
                c.hide();
                showMenuSheet(
                  context,
                  this,
                  (ctx, c) => spaceMenuGroups(context, state, c),
                );
              },
            ),
            for (final s in filterSections(state))
              FItem(
                key: Key('filter-${s.name}'),
                prefix: Icon(
                  sectionMeta(s).$1,
                  size: t.icons.md,
                  color: t.muted,
                ),
                title: Text(_label(s)),
                suffix: visibleSection(state) == s
                    ? Icon(
                        FLucideIcons.check,
                        size: t.icons.md,
                        color: t.accent,
                      )
                    : null,
                onPress: () {
                  c.hide();
                  state.setSection(s);
                },
              ),
          ],
        ),
        // As at the foot of the desktop rail, below Spaces and the sections: Account (when signing in is
        // possible) and Settings, set apart by the group divider.
        FItemGroup(
          children: [
            for (final s in bottomSections(state))
              FItem(
                key: Key('menu-${s.name}'),
                prefix: Icon(
                  sectionMeta(s).$1,
                  size: t.icons.md,
                  color: t.muted,
                ),
                title: Text(sectionMeta(s).$2),
                suffix: visibleSection(state) == s
                    ? Icon(
                        FLucideIcons.check,
                        size: t.icons.md,
                        color: t.accent,
                      )
                    : null,
                onPress: () {
                  c.hide();
                  state.setSection(s);
                },
              ),
          ],
        ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final state = widget.state;
    final section = visibleSection(state);
    final inFilter = filterSections(state).contains(section);
    return GestureDetector(
      key: const Key('side-menu'),
      behavior: HitTestBehavior.translucent,
      // Swiping left closes it (rows swipe only to the right).
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -400) widget.onClose();
      },
      child: FScaffold(
        childPad: false,
        // Inside the shell's scaffold, which already makes room for the
        // keyboard: resizing again would squeeze the panel to nothing.
        resizeToAvoidBottomInset: false,
        child: Column(
          children: [
            Expanded(
              child: AreaMark(
                nav: state.nav,
                area: NavArea.panel,
                child: sectionBody(state, section, widget.onClose),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                t.space.lg,
                t.space.xs,
                t.space.lg,
                t.space.xs,
              ),
              child: touchBox(
                context,
                // Full width, space between: icon and label left, count and
                // chevron right.
                FTappable(
                  key: const Key('menu-filter'),
                  semanticsLabel: 'Filter',
                  behavior: HitTestBehavior.opaque,
                  onPress: _pickFilter,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: t.space.md),
                    decoration: BoxDecoration(
                      color: context.theme.colors.secondary,
                      borderRadius: BorderRadius.circular(t.radii.control),
                    ),
                    child: Row(
                      children: [
                        Icon(sectionMeta(section).$1, size: t.icons.md),
                        SizedBox(width: t.space.sm),
                        Expanded(
                          child: Text(
                            sectionMeta(section).$2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (inFilter && _count(section) != null) ...[
                          Text(
                            '${_count(section)}',
                            style: t.type.captionStyle.copyWith(color: t.muted),
                          ),
                          SizedBox(width: t.space.sm),
                        ],
                        Icon(FLucideIcons.chevronDown, size: t.icons.md),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The first line of text worth showing on a card of [tab].
String tabPreview(AppState state, DocTab tab) {
  String first(String s) {
    for (final l in s.split('\n')) {
      final x = l.trim();
      if (x.isNotEmpty) return x;
    }
    return '';
  }

  switch (tab.kind) {
    case TabKind.note:
      return first(state.tree.find(tab.id)?.note.description ?? '');
    case TabKind.task:
      return first(state.taskById(tab.id)?.description ?? '');
    case TabKind.event:
      final e = state.eventById(tab.id);
      if (e == null) return '';
      final d = first(e.description);
      return d.isNotEmpty ? d : e.location;
    case TabKind.view:
      return 'Saved view';
  }
}

IconData tabIcon(AppState state, DocTab tab) => switch (tab.kind) {
  TabKind.note =>
    state.tabIsFolder(tab) ? FLucideIcons.folder : FLucideIcons.fileText,
  TabKind.task => FLucideIcons.listChecks,
  TabKind.event => FLucideIcons.calendar,
  TabKind.view => FLucideIcons.bookmark,
};

/// The open items as a full page of two-column cards. A card opens its item,
/// its X closes it (the last one leaves for Home), + adds, Done goes back.
class OpenItemsGrid extends StatefulWidget {
  const OpenItemsGrid({
    super.key,
    required this.state,
    required this.onDone,
    required this.onOpen,
    required this.host,
  });
  final AppState state;
  final VoidCallback onDone;

  /// A context that outlives the grid (dialogs launched from it).
  final BuildContext host;

  /// Shows tab [t] (null: Home) and closes the grid.
  final void Function(DocTab? t) onOpen;

  @override
  State<OpenItemsGrid> createState() => _OpenItemsGridState();
}

class _OpenItemsGridState extends State<OpenItemsGrid>
    with TickerProviderStateMixin {
  Future<void> _close(DocTab tab) async {
    final state = widget.state;
    await state.closeTab(tab);
    if (state.tabs.isEmpty) widget.onOpen(null);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final state = widget.state;
    final tabs = state.tabs;
    return FScaffold(
      key: const Key('open-grid'),
      childPad: false,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              t.space.lg,
              t.space.sm,
              t.space.sm,
              t.space.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Open items (${tabs.length})',
                    style: t.type.labelStyle,
                  ),
                ),
                IconAction(
                  key: const Key('grid-add'),
                  tooltip: 'New',
                  icon: FLucideIcons.plus,
                  onPress: addEntries(state).isEmpty
                      ? null
                      : () => showAddMenu(
                          context,
                          this,
                          state,
                          prefix: 'grid-',
                          before: widget.onDone,
                          host: widget.host,
                        ),
                ),
                touchBox(
                  context,
                  FButton(
                    key: const Key('grid-done'),
                    variant: FButtonVariant.outline,
                    size: FButtonSizeVariant.xs,
                    mainAxisSize: MainAxisSize.min,
                    onPress: widget.onDone,
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: tabs.isEmpty
                ? Center(
                    child: Text(
                      'No open items',
                      style: t.type.captionStyle.copyWith(color: t.muted),
                    ),
                  )
                : GridView.count(
                    crossAxisCount: 2,
                    padding: EdgeInsets.all(t.space.lg),
                    mainAxisSpacing: t.space.md,
                    crossAxisSpacing: t.space.md,
                    childAspectRatio: 1.25,
                    children: [for (final tab in tabs) _card(t, tab)],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(Tokens t, DocTab tab) {
    final state = widget.state;
    final active = state.activeTab == tab;
    final title = state.tabTitle(tab);
    final preview = tabPreview(state, tab);
    return FTappable(
      key: Key('grid-card-${tab.code}'),
      semanticsLabel: title,
      onPress: () => widget.onOpen(tab),
      child: Container(
        padding: EdgeInsets.all(t.space.md),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(t.radii.card),
          border: Border.all(
            color: active ? t.accent : t.panelBorder,
            width: active ? t.borders.hairline * 2 : t.borders.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(tabIcon(state, tab), size: t.icons.md, color: t.muted),
                const Spacer(),
                SizedBox(
                  width: t.sizes.touchTarget,
                  height: t.sizes.touchTarget,
                  child: FTappable(
                    key: Key('grid-close-${tab.code}'),
                    semanticsLabel: 'Close $title',
                    behavior: HitTestBehavior.opaque,
                    onPress: () => _close(tab),
                    child: Center(
                      child: Icon(FLucideIcons.x, size: t.icons.md),
                    ),
                  ),
                ),
              ],
            ),
            OverflowTip(
              title.isEmpty ? '(untitled)' : title,
              style: t.type.labelStyle,
            ),
            if (preview.isNotEmpty)
              Expanded(
                child: Text(
                  preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
