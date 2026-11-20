import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/tab_state.dart';
import 'edit_note_dialog.dart' show confirmDeleteNote;
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
class NoteMenuItem {
  const NoteMenuItem(this.label, this.icon, this.onPress, {this.key});
  final String label;
  final IconData icon;
  final VoidCallback onPress;
  final Key? key;
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
  Widget build(BuildContext context) => FContextMenu(
    longPress: true,
    secondaryPress: true,
    menuBuilder: (ctx, controller, _) => _groups(ctx, controller),
    child: child,
  );

  List<FItemGroup> _groups(BuildContext context, FPopoverController c) {
    final t = tokensOf(context);
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
    if (items.isNotEmpty) {
      groups.add(
        FItemGroup(
          children: [
            for (final i in items) row(i.label, i.icon, i.onPress, key: i.key),
          ],
        ),
      );
    }
    final own = <FItem>[
      if (state.editable && note != null)
        row(
          'Edit',
          FLucideIcons.pencil,
          () async {
            await state.openNote(uid);
            state.startEdit(uid);
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
      if (surface == NoteSurface.mainTab)
        row(
          'Close tab',
          FLucideIcons.x,
          () => state.closeTab(DocTab.note(uid)),
          key: const Key('menu-close'),
        ),
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
}
