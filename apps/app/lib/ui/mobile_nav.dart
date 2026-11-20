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
                e.run(context);
              },
            ),
        ],
      ),
    ];
  });
}

/// The floating bottom bar: Back, Search, +, the open-items counter, Home.
class MobileBar extends StatefulWidget {
  const MobileBar({
    super.key,
    required this.state,
    required this.canBack,
    required this.onBack,
    required this.onSearch,
    required this.onGrid,
    required this.onHome,
  });
  final AppState state;
  final bool canBack;
  final VoidCallback onBack, onSearch, onGrid, onHome;

  @override
  State<MobileBar> createState() => _MobileBarState();
}

class _MobileBarState extends State<MobileBar> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final count = widget.state.tabs.length;
    final canAdd = addEntries(widget.state).isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        t.space.lg,
        t.space.xs,
        t.space.lg,
        t.space.md,
      ),
      child: Container(
        key: const Key('mobile-bar'),
        padding: EdgeInsets.symmetric(horizontal: t.space.sm),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(t.radii.panel + t.space.md),
          border: Border.all(color: t.panelBorder, width: t.borders.hairline),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconAction(
              key: const Key('bar-back'),
              tooltip: 'Back',
              icon: FLucideIcons.arrowLeft,
              onPress: widget.canBack ? widget.onBack : null,
            ),
            IconAction(
              key: const Key('bar-search'),
              tooltip: 'Search',
              icon: FLucideIcons.search,
              onPress: widget.onSearch,
            ),
            IconAction(
              key: const Key('bar-add'),
              tooltip: 'New',
              icon: FLucideIcons.plus,
              onPress: canAdd
                  ? () => showAddMenu(context, this, widget.state)
                  : null,
            ),
            FTappable(
              key: const Key('bar-count'),
              semanticsLabel: 'Open items: $count',
              behavior: HitTestBehavior.opaque,
              onPress: widget.onGrid,
              child: SizedBox(
                width: t.sizes.touchTarget,
                height: t.sizes.touchTarget,
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      minWidth: t.icons.lg + t.space.sm,
                      minHeight: t.icons.lg + t.space.sm,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.radii.control),
                      border: Border.all(
                        color: t.fg,
                        width: t.borders.hairline * 2,
                      ),
                    ),
                    child: Text('$count', style: t.type.captionStyle),
                  ),
                ),
              ),
            ),
            IconAction(
              key: const Key('bar-home'),
              tooltip: 'Home',
              icon: FLucideIcons.house,
              onPress: widget.onHome,
            ),
          ],
        ),
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

/// The full-screen side menu: the Space chip, a filter pill choosing the
/// panel (bound to [AppState.section]), that panel (with its toolbar and tags
/// drawer), and Account and Settings in the footer. [onClose] closes it;
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
  String _label(Section s) {
    final state = widget.state;
    final name = sectionMeta(s).$2;
    return switch (s) {
      Section.notes => '$name · ${_noteCount(state)}',
      Section.tasks => '$name · ${state.tasks.length}',
      Section.events => '$name · ${state.events.length}',
      _ => name,
    };
  }

  void _pickFilter() {
    final state = widget.state;
    final t = tokensOf(context);
    showMenuSheet(context, this, (ctx, c) {
      return [
        FItemGroup(
          children: [
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
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final state = widget.state;
    final section = visibleSection(state);
    final inFilter = filterSections(state).contains(section);
    Widget footer(Section s, String key) => IconAction(
      key: Key(key),
      tooltip: sectionMeta(s).$2,
      icon: sectionMeta(s).$1,
      onPress: () => state.setSection(s),
    );
    return GestureDetector(
      key: const Key('side-menu'),
      behavior: HitTestBehavior.translucent,
      // Swiping left closes it (rows swipe only to the right).
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -400) widget.onClose();
      },
      child: FScaffold(
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
                  SpaceChip(state: state),
                  const Spacer(),
                  IconAction(
                    key: const Key('menu-close'),
                    tooltip: 'Close menu',
                    icon: FLucideIcons.x,
                    onPress: widget.onClose,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: touchBox(
                  context,
                  FButton(
                    key: const Key('menu-filter'),
                    variant: FButtonVariant.secondary,
                    size: FButtonSizeVariant.xs,
                    mainAxisSize: MainAxisSize.min,
                    prefix: Icon(sectionMeta(section).$1),
                    suffix: const Icon(FLucideIcons.chevronDown),
                    onPress: _pickFilter,
                    child: Text(
                      inFilter ? _label(section) : sectionMeta(section).$2,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: AreaMark(
                nav: state.nav,
                area: NavArea.panel,
                child: sectionBody(state, section, widget.onClose),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space.sm),
              child: Row(
                children: [
                  if (state.canSignIn) footer(Section.account, 'menu-account'),
                  const Spacer(),
                  footer(Section.settings, 'menu-settings'),
                ],
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
  });
  final AppState state;
  final VoidCallback onDone;

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
