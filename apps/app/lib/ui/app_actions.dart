import 'dart:async';

import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';

import '../state/app_action.dart';
import '../state/app_state.dart';
import '../state/key_nav.dart';
import '../state/tab_state.dart';
import 'account_dialog.dart';
import 'edit_note_dialog.dart';
import 'event_menu.dart';
import 'move_folder_dialog.dart';
import 'move_space_dialog.dart';
import 'new_folder_dialog.dart';
import 'new_note_dialog.dart';
import 'new_space_dialog.dart';
import 'parts.dart';
import 'task_menu.dart';
import 'theme.dart';

/// The uid of the note, task or event the user is on: the one open full page,
/// else the peek, else the task picked in the Tasks list.
String? selectedItemUid(AppState s) {
  final u =
      s.mainItemUid ?? (s.hasPeek ? s.peekUid : null) ?? s.selectedTaskUid;
  return u != null && s.findItem(u) != null ? u : null;
}

/// The selected item itself: a [Note], [Task] or [Event], or null.
Object? selectedItem(AppState s) {
  final u = selectedItemUid(s);
  return u == null ? null : s.findItem(u);
}

/// The uid an item action works on. While the keyboard is in use: the row
/// under the cursor in a list area, the peek's item in the peek; otherwise
/// the one open or picked (see [selectedItemUid]).
String? actionTargetUid(AppState s) {
  final nav = s.nav;
  if (nav.shown) {
    final a = nav.area;
    if (a == NavArea.rail) return null;
    if (a == NavArea.peek) return s.hasPeek ? s.peekUid : null;
    final list = navListId(s, a);
    if (list != null) {
      final u = nav.cursorEntry(list)?.uid;
      return u != null && s.findItem(u) != null ? u : null;
    }
  }
  return selectedItemUid(s);
}

/// The item [actionTargetUid] names: a [Note], [Task] or [Event], or null.
Object? targetItem(AppState s) {
  final u = actionTargetUid(s);
  return u == null ? null : s.findItem(u);
}

/// Gives the side panel the keyboard focus, on its list's cursor.
void focusPanel(AppState s) {
  void f() => s.nav.focusArea(NavArea.panel, list: navListId(s, NavArea.panel));
  f();
  WidgetsBinding.instance.addPostFrameCallback((_) => f());
}

Future<void> _openCursor(ActionContext c, OpenMode? mode) async {
  final s = c.state;
  final list = navListId(s, s.nav.area);
  if (list == null) return;
  await s.nav.cursorEntry(list)?.open?.call(mode);
}

/// h, Left: collapse the folder under the cursor, else go to its parent,
/// else (not in the Notes tree) focus the area to the left.
void _left(ActionContext c) {
  final s = c.state;
  final nav = s.nav;
  if (nav.area == NavArea.panel && s.section == Section.notes) {
    final uid = nav.cursorEntry('notes')?.uid;
    final node = uid == null ? null : s.tree.find(uid);
    if (node != null) {
      if (node.children.isNotEmpty && !s.collapsed.contains(uid)) {
        s.toggle(uid!);
        return;
      }
      final parent = node.parent?.note.uid;
      if (parent != null) {
        nav.setCursor('notes', parent, dir: -1);
        return;
      }
    }
  }
  nav.moveArea(-1, (a) => navListId(s, a));
}

/// l, Right: expand the folder under the cursor, else step into it, else
/// focus the area to the right.
void _right(ActionContext c) {
  final s = c.state;
  final nav = s.nav;
  if (nav.area == NavArea.panel && s.section == Section.notes) {
    final uid = nav.cursorEntry('notes')?.uid;
    final node = uid == null ? null : s.tree.find(uid);
    if (node != null && node.children.isNotEmpty) {
      if (s.collapsed.contains(uid)) {
        s.toggle(uid!);
      } else {
        nav.setCursor('notes', node.children.first.note.uid, dir: 1);
      }
      return;
    }
  }
  nav.moveArea(1, (a) => navListId(s, a));
}

bool _canEditTarget(AppState s) => switch (targetItem(s)) {
  Note() => s.editable,
  Task() => s.tasksEditable,
  Event() => s.eventsEditable,
  _ => false,
};

/// The one list of actions, built from the current [state]. Disabled actions
/// are still in the list (see [AppAction.enabled]); the palette hides them.
///
/// To add an action: append an [AppAction] here with a new stable id, call
/// existing [AppState] methods or dialogs from `run`, and add a test line.
List<AppAction> buildActions(AppState state) {
  bool yes(AppState _) => true;
  bool notes(AppState s) => s.editable;
  AppAction go(
    String id,
    String title,
    Section sec,
    List<String> kw,
    String key,
  ) => AppAction(
    id: id,
    title: title,
    group: 'Go to',
    keywords: ['open', 'show', ...kw],
    shortcuts: ['g $key'],
    enabled: yes,
    run: (c) {
      c.state.setSection(sec);
      focusPanel(c.state);
    },
  );
  AppAction key(
    String id,
    String title,
    String group,
    List<String> keys,
    FutureOr<void> Function(ActionContext c) run, {
    bool Function(AppState s)? enabled,
  }) => AppAction(
    id: id,
    title: title,
    group: group,
    shortcuts: keys,
    listed: false,
    enabled: enabled ?? yes,
    run: run,
  );
  void motion(ActionContext c, int sign) {
    final n = c.state.nav;
    final by = n.takeCount() * sign;
    final l = navListId(c.state, n.area);
    if (l != null) n.move(l, by);
  }

  bool itemIs<T>(AppState s) => targetItem(s) is T;

  return [
    AppAction(
      id: 'palette.open',
      title: 'Command palette',
      group: 'App',
      keywords: const ['actions', 'commands', 'search'],
      shortcuts: const ['Ctrl+K', 'Cmd+K', ':'],
      enabled: yes,
      run: (c) => c.openPalette?.call(),
    ),
    AppAction(
      id: 'go.home',
      title: 'Go to Home',
      group: 'Go to',
      keywords: const ['open', 'today', 'dashboard'],
      shortcuts: const ['g h'],
      enabled: yes,
      run: (c) async {
        await c.state.activateTab(null);
        void f() => c.state.nav.focusArea(
          NavArea.main,
          list: navListId(c.state, NavArea.main),
        );
        f();
        WidgetsBinding.instance.addPostFrameCallback((_) => f());
      },
    ),
    go('go.notes', 'Go to Notes', Section.notes, const ['files', 'tree'], 'n'),
    go('go.tasks', 'Go to Tasks', Section.tasks, const ['todo', 'list'], 't'),
    go('go.events', 'Go to Events', Section.events, const [
      'agenda',
      'calendar',
    ], 'e'),
    go('go.views', 'Go to Views', Section.views, const [
      'saved',
      'filters',
    ], 'v'),
    go('go.search', 'Go to Search', Section.search, const ['find'], 's'),
    AppAction(
      id: 'note.new',
      title: 'New note',
      group: 'Create',
      keywords: const ['add', 'create', 'page'],
      enabled: notes,
      run: (c) => showNewNoteDialog(c.context, c.state),
    ),
    AppAction(
      id: 'folder.new',
      title: 'New folder',
      group: 'Create',
      keywords: const ['add', 'create', 'directory'],
      enabled: notes,
      run: (c) => showNewFolderDialog(c.context, c.state),
    ),
    AppAction(
      id: 'task.new',
      title: 'New task',
      group: 'Create',
      keywords: const ['add', 'create', 'todo'],
      enabled: (s) => s.tasksEditable,
      run: (c) => showNewTaskDialog(c.context, c.state),
    ),
    AppAction(
      id: 'event.new',
      title: 'New event',
      group: 'Create',
      keywords: const ['add', 'create', 'meeting', 'appointment'],
      enabled: (s) => s.eventsEditable,
      run: (c) => showNewEventDialog(c.context, c.state),
    ),
    for (final sp in state.spaces)
      AppAction(
        id: 'space.switch.${sp.id}',
        title: 'Switch to Space: ${sp.name}',
        group: 'Space',
        keywords: const ['space', 'switch', 'change', 'open'],
        enabled: (s) => s.currentSpaceId != sp.id,
        run: (c) => c.state.switchSpace(sp.id),
      ),
    AppAction(
      id: 'space.new',
      title: 'New Space',
      group: 'Space',
      keywords: const ['add', 'create', 'collection'],
      enabled: (s) => s.catalog != null,
      run: (c) => showNewSpaceDialog(c.context, c.state),
    ),
    AppAction(
      id: 'peek.toggle',
      title: state.peekCollapsed ? 'Expand peek' : 'Collapse peek',
      group: 'Panes',
      keywords: const ['peek', 'side', 'detail', 'fold', 'hide', 'show'],
      shortcuts: const ['p'],
      enabled: (s) => s.hasPeek,
      run: (c) => c.state.setPeekCollapsed(!c.state.peekCollapsed),
    ),
    AppAction(
      id: 'peek.close',
      title: 'Close peek',
      group: 'Panes',
      keywords: const ['peek', 'side', 'detail', 'dismiss'],
      enabled: (s) => s.hasPeek,
      run: (c) => c.state.guarded(() => c.state.select(null)),
    ),
    AppAction(
      id: 'peek.promote',
      title: 'Move peek to a main tab',
      group: 'Panes',
      keywords: const ['promote', 'peek', 'open', 'full', 'page'],
      shortcuts: const ['P'],
      enabled: (s) => s.hasPeek,
      run: (c) => c.state.promote(),
    ),
    AppAction(
      id: 'tab.close',
      title: 'Close current tab',
      group: 'Tabs',
      keywords: const ['close', 'tab'],
      shortcuts: const ['Ctrl+W', 'Cmd+W', 'q'],
      enabled: (s) => s.activeTab != null,
      run: (c) => c.state.closeActiveTab(),
    ),
    AppAction(
      id: 'tab.next',
      title: 'Next tab',
      group: 'Tabs',
      keywords: const ['tab', 'switch', 'forward'],
      shortcuts: const [']'],
      enabled: (s) => s.tabs.isNotEmpty,
      run: (c) => _stepTab(c.state, 1),
    ),
    AppAction(
      id: 'tab.previous',
      title: 'Previous tab',
      group: 'Tabs',
      keywords: const ['tab', 'switch', 'back'],
      shortcuts: const ['['],
      enabled: (s) => s.tabs.isNotEmpty,
      run: (c) => _stepTab(c.state, -1),
    ),
    AppAction(
      id: 'setting.open-mode',
      title: state.openMode == OpenMode.peek
          ? 'Open items in Main instead of Peek'
          : 'Open items in Peek instead of Main',
      group: 'Settings',
      keywords: const ['setting', 'open', 'mode', 'peek', 'main', 'click'],
      enabled: yes,
      run: (c) => c.state.setOpenMode(
        c.state.openMode == OpenMode.peek ? OpenMode.main : OpenMode.peek,
      ),
    ),
    AppAction(
      id: 'go.settings',
      title: 'Open Settings',
      group: 'Settings',
      keywords: const ['preferences', 'options', 'configure'],
      enabled: yes,
      run: (c) => c.state.setSection(Section.settings),
    ),
    AppAction(
      id: 'go.account',
      title: 'Open Account',
      group: 'Settings',
      keywords: const ['sign', 'login', 'user', 'server'],
      enabled: (s) => s.canSignIn,
      run: (c) => c.state.setSection(Section.account),
    ),
    AppAction(
      id: 'account.sign-in',
      title: 'Sign in',
      group: 'Settings',
      keywords: const ['login', 'account', 'server'],
      enabled: (s) => s.canSignIn && s.accountUser == null,
      run: (c) => showAccountDialog(c.context, c.state),
    ),
    AppAction(
      id: 'sync.now',
      title: 'Sync now',
      group: 'Sync',
      keywords: const ['synchronise', 'synchronize', 'server', 'update'],
      enabled: (s) => s.connected,
      run: (c) => c.state.sync(),
    ),
    AppAction(
      id: 'spaces.refresh',
      title: 'Refresh Spaces',
      group: 'Sync',
      keywords: const ['reload', 'collections', 'account', 'server'],
      enabled: (s) => s.accountUser != null,
      run: (c) => c.state.refreshSpaces(),
    ),
    AppAction(
      id: 'help.keyboard',
      title: 'Keyboard help',
      group: 'App',
      keywords: const ['help', 'keys', 'keyboard', 'shortcuts', 'bindings'],
      shortcuts: const ['?'],
      enabled: yes,
      run: (c) => showKeyboardHelp(c.context, c.state),
    ),
    AppAction(
      id: 'item.delete',
      title: 'Delete selected item',
      group: 'Selected item',
      keywords: const ['remove', 'trash', 'note', 'task', 'event'],
      shortcuts: const ['D'],
      enabled: _canEditTarget,
      run: (c) => switch (targetItem(c.state)) {
        final Note n => confirmDeleteNote(c.context, c.state, n),
        final Task t => confirmDeleteTask(c.context, c.state, t),
        final Event e => confirmDeleteEvent(c.context, c.state, e),
        _ => null,
      },
    ),
    AppAction(
      id: 'task.toggle',
      title: switch (targetItem(state)) {
        final Task t when t.isClosed => 'Reopen selected task',
        _ => 'Complete selected task',
      },
      group: 'Selected item',
      keywords: const ['done', 'finish', 'check', 'reopen', 'task'],
      enabled: (s) {
        final t = targetItem(s);
        return t is Task &&
            s.tasksEditable &&
            (t.isClosed || s.taskCompletionBlockerFor(t.uid) == null);
      },
      run: (c) async {
        final u = actionTargetUid(c.state);
        if (u != null) await c.state.toggleTask(u);
      },
    ),
    AppAction(
      id: 'item.move-space',
      title: 'Move selected item to another Space',
      group: 'Selected item',
      keywords: const ['move', 'space', 'transfer'],
      enabled: (s) => s.spaces.length > 1 && _canEditTarget(s),
      run: (c) => switch (targetItem(c.state)) {
        final Note n => showMoveSpaceDialog(c.context, c.state, n),
        final Task t => showMoveTaskDialog(c.context, c.state, t),
        final Event e => showMoveEventDialog(c.context, c.state, e),
        _ => null,
      },
    ),
    AppAction(
      id: 'note.move-folder',
      title: 'Move selected note into a folder',
      group: 'Selected item',
      keywords: const ['move', 'folder', 'directory', 'parent'],
      enabled: (s) => itemIs<Note>(s) && s.editable,
      run: (c) {
        final n = targetItem(c.state);
        return n is Note ? showMoveFolderDialog(c.context, c.state, n) : null;
      },
    ),
    AppAction(
      id: 'item.edit',
      title: 'Edit selected item',
      group: 'Selected item',
      keywords: const ['change', 'rename', 'note', 'task', 'event'],
      shortcuts: const ['e'],
      enabled: _canEditTarget,
      run: (c) async {
        final s = c.state;
        final uid = actionTargetUid(s);
        if (uid == null) return;
        if (uid != s.mainItemUid && uid != s.peekUid) {
          if (!await s.openNote(uid)) return;
        }
        switch (s.findItem(uid)) {
          case Note():
            s.startEdit(uid);
          case Task():
            s.startTaskEdit(uid);
          case Event():
            s.startEventEdit(uid);
          default:
        }
      },
    ),
    AppAction(
      id: 'key.complete',
      title: 'Complete or reopen the task, or close the tab',
      group: 'Edit',
      shortcuts: const ['x'],
      listed: false,
      enabled: (s) =>
          _a(s, 'task.toggle').enabled(s) ||
          (s.nav.area == NavArea.main && s.activeTab != null),
      run: (c) {
        final toggle = _a(c.state, 'task.toggle');
        return toggle.enabled(c.state)
            ? toggle.run(c)
            : c.state.closeActiveTab();
      },
    ),
    AppAction(
      id: 'item.new',
      title: 'New note, task or event for this section',
      group: 'Create',
      shortcuts: const ['n'],
      listed: false,
      enabled: (s) => switch (s.section) {
        Section.notes => s.editable,
        Section.tasks => s.tasksEditable,
        Section.events => s.eventsEditable,
        _ => false,
      },
      run: (c) => switch (c.state.section) {
        Section.notes => showNewNoteDialog(c.context, c.state),
        Section.tasks => showNewTaskDialog(c.context, c.state),
        Section.events => showNewEventDialog(c.context, c.state),
        _ => null,
      },
    ),
    AppAction(
      id: 'search.focus',
      title: 'Search',
      group: 'Go to',
      keywords: const ['find', 'filter', 'query'],
      shortcuts: const ['/'],
      listed: false,
      enabled: yes,
      run: (c) {
        c.state.setSection(Section.search);
        focusPanel(c.state);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => c.state.nav.searchNode.requestFocus(),
        );
      },
    ),
    AppAction(
      id: 'setting.vim-keys',
      title: state.vimKeys ? 'Turn Vim keys off' : 'Turn Vim keys on',
      group: 'Settings',
      keywords: const ['setting', 'keyboard', 'vim', 'keys', 'shortcuts'],
      enabled: yes,
      run: (c) => c.state.setVimKeys(!c.state.vimKeys),
    ),
    key('nav.down', 'Move down', 'Navigation', const ['j', 'Down'], (c) {
      motion(c, 1);
    }),
    key('nav.up', 'Move up', 'Navigation', const ['k', 'Up'], (c) {
      motion(c, -1);
    }),
    key('nav.first', 'First item', 'Navigation', const ['g g', 'Home'], (c) {
      final l = navListId(c.state, c.state.nav.area);
      if (l != null) c.state.nav.jump(l, last: false);
    }),
    key('nav.last', 'Last item', 'Navigation', const ['G', 'End'], (c) {
      final l = navListId(c.state, c.state.nav.area);
      if (l != null) c.state.nav.jump(l, last: true);
    }),
    key(
      'nav.left',
      'Collapse folder or go to parent; else focus left',
      'Navigation',
      const ['h', 'Left'],
      _left,
    ),
    key(
      'nav.right',
      'Expand folder or step in; else focus right',
      'Navigation',
      const ['l', 'Right'],
      _right,
    ),
    key('focus.left', 'Focus the area on the left', 'Navigation', const ['H'], (
      c,
    ) {
      c.state.nav.moveArea(-1, (a) => navListId(c.state, a));
    }),
    key(
      'focus.right',
      'Focus the area on the right',
      'Navigation',
      const ['L'],
      (c) {
        c.state.nav.moveArea(1, (a) => navListId(c.state, a));
      },
    ),
    key(
      'nav.escape',
      'Clear typed keys, or move focus up one area',
      'Navigation',
      const ['Esc'],
      (c) {
        c.state.nav.up((a) => navListId(c.state, a));
      },
    ),
    key('nav.open', 'Open the item under the cursor', 'Open', const [
      'Enter',
    ], (c) => _openCursor(c, null)),
    key('nav.open-peek', 'Open in peek', 'Open', const [
      'o',
    ], (c) => _openCursor(c, OpenMode.peek)),
    key('nav.open-main', 'Open in main', 'Open', const [
      'O',
    ], (c) => _openCursor(c, OpenMode.main)),
  ];
}

AppAction _a(AppState s, String id) =>
    buildActions(s).firstWhere((a) => a.id == id);

/// Home, then the document tabs in order, as one ring: focuses the one
/// [by] places after the current one.
Future<void> _stepTab(AppState s, int by) {
  final ring = <DocTab?>[null, ...s.tabs];
  final i = ring.indexOf(s.activeTab);
  final next = ring[((i < 0 ? 0 : i) + by) % ring.length];
  return s.activateTab(next);
}

/// The keyboard help: every binding in the registry, by group.
Future<void> showKeyboardHelp(BuildContext context, AppState state) {
  final t = tokensOf(context);
  final rows = helpRows(buildActions(state));
  return showAppDialog(
    context,
    title: 'Keyboard shortcuts',
    width: t.sizes.dialogXl,
    content: Column(
      key: const Key('keyboard-help'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!state.vimKeys)
          Padding(
            padding: EdgeInsets.only(bottom: t.space.md),
            child: Text(
              'Vim keys are off: only the arrow keys, Enter, Esc and the '
              'Ctrl/Cmd chords work.',
              style: t.type.captionStyle.copyWith(color: t.muted),
            ),
          ),
        for (final (group, items) in rows) ...[
          Padding(
            padding: EdgeInsets.only(top: t.space.md, bottom: t.space.xs),
            child: Text(
              group,
              style: t.type.labelStyle.copyWith(color: t.muted),
            ),
          ),
          for (final (keys, what) in items)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: Text(keys)),
                  Expanded(flex: 3, child: Text(what)),
                ],
              ),
            ),
        ],
      ],
    ),
    actions: const [CancelButton(label: 'Close')],
  );
}
