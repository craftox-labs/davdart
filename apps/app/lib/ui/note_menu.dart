import 'package:davdart/davdart.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/tab_state.dart';
import 'edit_note_dialog.dart' show confirmDeleteNote;
import 'move_folder_dialog.dart';
import 'move_space_dialog.dart';
import 'new_folder_dialog.dart';
import 'new_note_dialog.dart';
import 'task_menu.dart';
import 'theme.dart';

/// Where a note's menu was opened; it decides which built-in items appear.
enum NoteSurface {
  /// A tree entry, list row, board card or search result.
  entry,

  /// The peek pane's tab.
  peekTab,

  /// A main strip tab.
  mainTab,
}

/// One extra row of a [NoteContextMenu]. Surfaces pass these in [items]
/// (batch 2 adds per-surface actions this way); the menu hides itself first.
///
/// With [children] the row opens a submenu instead (its [onPress] is unused).
class NoteMenuItem {
  const NoteMenuItem(
    this.label,
    this.icon,
    this.onPress, {
    this.key,
    this.children = const [],
    this.selected = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPress;
  final Key? key;
  final List<NoteMenuItem> children;

  /// Marks the row with a check (the current choice of a submenu).
  final bool selected;
}

/// Builds the rows of a menu group: [items] as plain rows, or submenus. The
/// popup hides itself before an action runs.
List<FItemMixin> menuRows(
  BuildContext context,
  FPopoverController c,
  List<NoteMenuItem> items,
) {
  final t = tokensOf(context);
  // A sheet has no hover submenus: a submenu's row drills into its options
  // (the sheet then shows them alone, under a Back row).
  final nav = SheetMenuScope.navOf(context);
  if (nav != null) {
    return [
      for (final i in items)
        if (i.children.isNotEmpty)
          FItem(
            key: i.key,
            prefix: Icon(i.icon, size: t.icons.md, color: t.muted),
            title: Text(i.label),
            suffix: Icon(
              FLucideIcons.chevronRight,
              size: t.icons.md,
              color: t.muted,
            ),
            onPress: () => nav.open(i),
          )
        else
          FItem(
            key: i.key,
            prefix: Icon(i.icon, size: t.icons.md, color: t.muted),
            title: Text(i.label),
            suffix: i.selected
                ? Icon(FLucideIcons.check, size: t.icons.md, color: t.accent)
                : null,
            onPress: () {
              c.hide();
              i.onPress();
            },
          ),
    ];
  }
  return [
    for (final i in items)
      if (i.children.isNotEmpty)
        FSubmenuItem(
          key: i.key,
          prefix: Icon(i.icon, size: t.icons.md, color: t.muted),
          title: Text(i.label),
          // forui picks the anchors by platform, and the web counts as not
          // desktop: the submenu would open stacked over its row.
          submenuAnchor: Alignment.topLeft,
          itemAnchor: Alignment.topRight,
          submenu: [FItemGroup(children: menuRows(context, c, i.children))],
        )
      else
        FItem(
          key: i.key,
          prefix: Icon(i.icon, size: t.icons.md, color: t.muted),
          title: Text(i.label),
          suffix: i.selected
              ? Icon(FLucideIcons.check, size: t.icons.md, color: t.accent)
              : null,
          onPress: () {
            c.hide();
            i.onPress();
          },
        ),
  ];
}

/// An [FContextMenu] (right-click and long-press) that yields to a menu nested
/// inside it. forui opens on raw pointer-down events, which reach every menu
/// under the pointer, innermost first. Each menu claims the pointer after its
/// own handler ran; one that finds the pointer already claimed closes itself
/// again in the same event, so only the innermost menu is left open.
class ExclusiveContextMenu extends StatefulWidget {
  const ExclusiveContextMenu({
    super.key,
    required this.menuBuilder,
    required this.child,
    this.touchMenu = true,
  });
  final List<FItemGroupMixin> Function(
    BuildContext context,
    FPopoverController controller,
    List<FItemGroupMixin>? menu,
  )
  menuBuilder;
  final Widget child;

  /// Narrow layouts open the sheet on a long press. Off where the child
  /// uses the long press for something else (board cards drag); a mouse
  /// right-click still opens the popup.
  final bool touchMenu;

  @override
  State<ExclusiveContextMenu> createState() => _ExclusiveContextMenuState();
}

/// Pointers whose secondary press a menu already took (cleared right after
/// the event has been dispatched).
final Set<int> _claimed = {};

/// Which submenu a sheet has drilled into (null: the top level).
class SheetMenuNav extends ChangeNotifier {
  NoteMenuItem? current;

  void open(NoteMenuItem item) {
    current = item;
    notifyListeners();
  }

  void back() {
    current = null;
    notifyListeners();
  }
}

/// True inside [showMenuSheet]: menu rows are laid out for a sheet.
class SheetMenuScope extends InheritedWidget {
  const SheetMenuScope({super.key, required this.nav, required super.child});

  final SheetMenuNav nav;

  static bool of(BuildContext context) => navOf(context) != null;

  static SheetMenuNav? navOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<SheetMenuScope>()
      ?.nav;

  @override
  bool updateShouldNotify(SheetMenuScope old) => false;
}

/// Stands in for the popup's controller in a sheet: hiding it closes the
/// sheet, so the menu rows work unchanged.
class SheetPopoverController extends FPopoverController {
  SheetPopoverController({required super.vsync, required this.close});
  final VoidCallback close;

  @override
  Future<void> hide({bool animated = true}) async => close();
}

/// Shows [groups] (built by [build] under the sheet's context) as a sheet
/// from the bottom (or [side]), the touch form of a context menu. Picking a row closes it.
Future<void> showMenuSheet(
  BuildContext context,
  TickerProvider vsync,
  List<FItemGroupMixin> Function(
    BuildContext context,
    FPopoverController controller,
  )
  build, {
  FLayout side = FLayout.btt,
}) async {
  var open = true;
  final nav = SheetMenuNav();
  late final SheetPopoverController c;
  c = SheetPopoverController(
    vsync: vsync,
    close: () {
      if (!open) return;
      open = false;
      Navigator.of(context).pop();
    },
  );
  try {
    await showFSheet<void>(
      context: context,
      side: side,
      mainAxisMaxRatio: 0.8,
      useSafeArea: true,
      builder: (_) => SheetMenuScope(
        nav: nav,
        // Built below the scope: menuRows looks the scope up from this context.
        child: Builder(
          builder: (ctx) => ListenableBuilder(
            listenable: nav,
            builder: (ctx, _) {
              final open = nav.current;
              final tokens = tokensOf(ctx);
              return SingleChildScrollView(
                key: const Key('menu-sheet'),
                child: FItemGroup.merge(
                  children: open == null
                      ? build(ctx, c)
                      : [
                          FItemGroup(
                            children: [
                              FItem(
                                key: const Key('menu-back'),
                                prefix: Icon(
                                  FLucideIcons.chevronLeft,
                                  size: tokens.icons.md,
                                  color: tokens.muted,
                                ),
                                title: Text(
                                  open.label,
                                  style: tokens.type.bodyStrong,
                                ),
                                onPress: nav.back,
                              ),
                              ...menuRows(ctx, c, open.children),
                            ],
                          ),
                        ],
                ),
              );
            },
          ),
        ),
      ),
    );
  } finally {
    open = false;
    nav.dispose();
    c.dispose();
  }
}

class _ExclusiveContextMenuState extends State<ExclusiveContextMenu>
    with TickerProviderStateMixin {
  late final FPopoverController _controller = FPopoverController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (e.buttons & kSecondaryButton == 0) return;
    if (_claimed.add(e.pointer)) {
      Future.microtask(() => _claimed.remove(e.pointer));
    } else {
      _controller.hide(animated: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Narrow (phone): a long press opens the actions as a bottom sheet; the
    // right-click popup stays for a mouse.
    final sheet = narrowLayout(context);
    Widget menu = FContextMenu(
      control: FPopoverControl.managed(controller: _controller),
      longPress: !sheet,
      secondaryPress: true,
      menuBuilder: widget.menuBuilder,
      child: widget.child,
    );
    if (sheet && widget.touchMenu) {
      menu = GestureDetector(
        onLongPress: () => showMenuSheet(
          context,
          this,
          (ctx, c) => widget.menuBuilder(ctx, c, null),
        ),
        child: menu,
      );
    }
    return Listener(onPointerDown: _down, child: menu);
  }
}

/// Right-click (or long-press) menu for a surface that is not a note: a
/// folder-less tree area, a saved view, a Space, a tag, a view tab. [groups]
/// are separated by dividers; empty groups are dropped. With no group left
/// the surface has no menu.
class ActionContextMenu extends StatelessWidget {
  const ActionContextMenu({
    super.key,
    required this.groups,
    required this.child,
    this.touchMenu = true,
  });
  final List<List<NoteMenuItem>> groups;
  final Widget child;

  /// See [ExclusiveContextMenu.touchMenu].
  final bool touchMenu;

  @override
  Widget build(BuildContext context) {
    final live = [
      for (final g in groups)
        if (g.isNotEmpty) g,
    ];
    if (live.isEmpty) return child;
    return ExclusiveContextMenu(
      touchMenu: touchMenu,
      menuBuilder: (ctx, c, _) => [
        for (final g in live) FItemGroup(children: menuRows(ctx, c, g)),
      ],
      child: child,
    );
  }
}

/// Right-click (or long-press on touch) menu for a note. Always has "Open in
/// peek" and "Open in main", whatever the "Open notes in" setting says, then
/// the surface's own [items], then Edit, Close (tabs only) and Delete (when
/// the Space is editable). [onOpen] runs after an open action (the narrow
/// sheet closes with it).
class NoteContextMenu extends StatelessWidget {
  const NoteContextMenu({
    super.key,
    required this.state,
    required this.uid,
    required this.child,
    this.surface = NoteSurface.entry,
    this.items = const [],
    this.onOpen,
    this.hit,
    this.touchMenu = true,
  });
  final AppState state;
  final String uid;
  final Widget child;
  final NoteSurface surface;
  final List<NoteMenuItem> items;
  final VoidCallback? onOpen;

  /// See [ExclusiveContextMenu.touchMenu].
  final bool touchMenu;

  /// A search result, possibly in another Space: the open actions go through
  /// [AppState.openHit] and Edit and Delete are left out.
  final SpaceHit? hit;

  @override
  Widget build(BuildContext context) => ExclusiveContextMenu(
    touchMenu: touchMenu,
    menuBuilder: (ctx, controller, _) => _groups(context, ctx, controller),
    child: child,
  );

  /// [context] is the surface's own (it outlives the popup, so dialogs and
  /// flows launched from a row use it); [menuContext] only themes the rows.
  /// The actions of the open item's own page (the narrow header's ⋯ sheet):
  /// everything but the open, edit and close rows.
  List<FItemGroup> pageGroups(
    BuildContext context,
    BuildContext menuContext,
    FPopoverController c,
  ) => _groups(context, menuContext, c, page: true);

  List<FItemGroup> _groups(
    BuildContext context,
    BuildContext menuContext,
    FPopoverController c, {
    bool page = false,
  }) {
    final t = tokensOf(menuContext);
    FItem row(
      String label,
      IconData icon,
      VoidCallback act, {
      Key? key,
      bool afterOpen = false,
    }) => FItem(
      key: key,
      prefix: Icon(icon, size: t.icons.md, color: t.muted),
      title: Text(label),
      onPress: () {
        c.hide();
        act();
        if (afterOpen) onOpen?.call();
      },
    );

    final note = hit != null ? null : state.tree.find(uid)?.note;
    final groups = <FItemGroup>[
      if (!page)
        FItemGroup(
          children: [
            if (!state.narrow)
              row(
                'Open in peek',
                FLucideIcons.panelRight,
                () => hit != null
                    ? state.openHit(hit!, mode: OpenMode.peek)
                    : state.openNote(uid, mode: OpenMode.peek),
                key: const Key('menu-open-peek'),
                afterOpen: true,
              ),
            row(
              'Open in main',
              FLucideIcons.squareArrowOutUpRight,
              () => hit != null
                  ? state.openHit(hit!, mode: OpenMode.main)
                  : state.openNote(uid, mode: OpenMode.main),
              key: const Key('menu-open-main'),
              afterOpen: true,
            ),
          ],
        ),
    ];
    final manage = note == null ? <NoteMenuItem>[] : _manage(context, note);
    final all = [...manage, ...items];
    if (all.isNotEmpty) {
      groups.add(FItemGroup(children: menuRows(menuContext, c, all)));
    }
    final tab = DocTab.note(uid);
    final own = <FItem>[
      if (!page && state.editable && note != null)
        row(
          'Edit',
          FLucideIcons.pencil,
          () async {
            if (await state.openNote(uid)) state.startEdit(uid);
          },
          key: const Key('menu-edit'),
          afterOpen: true,
        ),
      if (surface == NoteSurface.peekTab)
        row(
          'Close peek',
          FLucideIcons.x,
          () => state.guarded(() => state.select(null)),
          key: const Key('menu-close'),
        ),
      if (surface == NoteSurface.mainTab) ...[
        row(
          'Close tab',
          FLucideIcons.x,
          () => state.closeTab(tab),
          key: const Key('menu-close'),
        ),
        if (state.tabs.length > 1)
          row(
            'Close other tabs',
            FLucideIcons.x,
            () => state.closeOtherTabs(tab),
            key: const Key('menu-close-others'),
          ),
        if (state.tabs.isNotEmpty && state.tabs.last != tab)
          row(
            'Close tabs to the right',
            FLucideIcons.x,
            () => state.closeTabsToRight(tab),
            key: const Key('menu-close-right'),
          ),
      ],
      if (state.editable && note != null)
        row(
          'Delete…',
          FLucideIcons.trash2,
          () => confirmDeleteNote(context, state, note),
          key: const Key('menu-delete'),
        ),
    ];
    if (own.isNotEmpty) groups.add(FItemGroup(children: own));
    return groups;
  }

  /// The actions every note surface shares: new inside a folder, move to a
  /// folder or Space, set the status or priority, copy the id.
  List<NoteMenuItem> _manage(BuildContext context, Note note) {
    final folder = AppState.isFolder(note);
    final edit = state.editable;
    final plan = PlanItem.fromNote(note);
    final status = plan.status;
    final priority = plan.priorityWord;
    return [
      if (edit && folder)
        NoteMenuItem(
          'New note inside…',
          FLucideIcons.filePlus,
          () => showNewNoteDialog(context, state, under: note),
          key: const Key('menu-new-note-inside'),
        ),
      if (edit && folder)
        NoteMenuItem(
          'New folder inside…',
          FLucideIcons.folderPlus,
          () => showNewFolderDialog(context, state, under: note),
          key: const Key('menu-new-folder-inside'),
        ),
      if (state.tasksEditable && !isViewNote(note))
        NoteMenuItem(
          'New task inside…',
          FLucideIcons.listPlus,
          () => showNewTaskDialog(context, state, parentUid: note.uid),
          key: const Key('menu-new-task-inside'),
        ),
      if (edit)
        NoteMenuItem(
          'Move to folder…',
          FLucideIcons.folderInput,
          () => showMoveFolderDialog(context, state, note),
          key: const Key('menu-move-folder'),
        ),
      if (edit && state.spaces.length > 1)
        NoteMenuItem(
          'Move to space…',
          FLucideIcons.arrowRightToLine,
          () => showMoveSpaceDialog(context, state, note),
          key: const Key('menu-move-space'),
        ),
      if (edit && !folder)
        NoteMenuItem(
          'Set status',
          FLucideIcons.circleDot,
          () {},
          key: const Key('menu-status'),
          children: [
            NoteMenuItem(
              'No status',
              FLucideIcons.circle,
              () => state.setStatus(note.uid, null),
              key: const Key('menu-status-none'),
              selected: status == null,
            ),
            for (final s in boardOrder)
              NoteMenuItem(
                s,
                FLucideIcons.circleDot,
                () => state.setStatus(note.uid, s),
                key: Key('menu-status-$s'),
                selected: s == status,
              ),
          ],
        ),
      if (edit && !folder)
        NoteMenuItem(
          'Set priority',
          FLucideIcons.flag,
          () {},
          key: const Key('menu-priority'),
          children: [
            NoteMenuItem(
              'No priority',
              FLucideIcons.circle,
              () => state.setNotePriority(note.uid, null),
              key: const Key('menu-priority-none'),
              selected: priority == null,
            ),
            for (final p in notePriorities.keys)
              NoteMenuItem(
                p,
                FLucideIcons.flag,
                () => state.setNotePriority(note.uid, p),
                key: Key('menu-priority-$p'),
                selected: p == priority,
              ),
          ],
        ),
      NoteMenuItem(
        'Copy id',
        FLucideIcons.copy,
        () => Clipboard.setData(ClipboardData(text: note.uid)),
        key: const Key('menu-copy-id'),
      ),
    ];
  }
}
