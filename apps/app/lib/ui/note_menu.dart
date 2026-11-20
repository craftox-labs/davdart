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
  return [
    for (final i in items)
      if (i.children.isNotEmpty)
        FSubmenuItem(
          key: i.key,
          prefix: Icon(i.icon, size: t.icons.md, color: t.muted),
          title: Text(i.label),
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
  });
  final List<FItemGroupMixin> Function(
    BuildContext context,
    FPopoverController controller,
    List<FItemGroupMixin>? menu,
  )
  menuBuilder;
  final Widget child;

  @override
  State<ExclusiveContextMenu> createState() => _ExclusiveContextMenuState();
}

/// Pointers whose secondary press a menu already took (cleared right after
/// the event has been dispatched).
final Set<int> _claimed = {};

class _ExclusiveContextMenuState extends State<ExclusiveContextMenu>
    with SingleTickerProviderStateMixin {
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
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    child: FContextMenu(
      control: FPopoverControl.managed(controller: _controller),
      longPress: true,
      secondaryPress: true,
      menuBuilder: widget.menuBuilder,
      child: widget.child,
    ),
  );
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
  });
  final List<List<NoteMenuItem>> groups;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final live = [
      for (final g in groups)
        if (g.isNotEmpty) g,
    ];
    if (live.isEmpty) return child;
    return ExclusiveContextMenu(
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
  });
  final AppState state;
  final String uid;
  final Widget child;
  final NoteSurface surface;
  final List<NoteMenuItem> items;
  final VoidCallback? onOpen;

  /// A search result, possibly in another Space: the open actions go through
  /// [AppState.openHit] and Edit and Delete are left out.
  final SpaceHit? hit;

  @override
  Widget build(BuildContext context) => ExclusiveContextMenu(
    menuBuilder: (ctx, controller, _) => _groups(context, ctx, controller),
    child: child,
  );

  /// [context] is the surface's own (it outlives the popup, so dialogs and
  /// flows launched from a row use it); [menuContext] only themes the rows.
  List<FItemGroup> _groups(
    BuildContext context,
    BuildContext menuContext,
    FPopoverController c,
  ) {
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
      FItemGroup(
        children: [
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
      if (state.editable && note != null)
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
  /// folder or Space, set the status, copy the id.
  List<NoteMenuItem> _manage(BuildContext context, Note note) {
    final folder = AppState.isFolder(note);
    final edit = state.editable;
    final status = PlanItem.fromNote(note).status;
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
      NoteMenuItem(
        'Copy id',
        FLucideIcons.copy,
        () => Clipboard.setData(ClipboardData(text: note.uid)),
        key: const Key('menu-copy-id'),
      ),
    ];
  }
}
