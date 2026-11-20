import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';

import '../state/app_action.dart';
import '../state/app_state.dart';
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

/// The one list of actions, built from the current [state]. Disabled actions
/// are still in the list (see [AppAction.enabled]); the palette hides them.
///
/// To add an action: append an [AppAction] here with a new stable id, call
/// existing [AppState] methods or dialogs from `run`, and add a test line.
List<AppAction> buildActions(AppState state) {
  bool yes(AppState _) => true;
  bool notes(AppState s) => s.editable;
  AppAction go(String id, String title, Section sec, List<String> kw) =>
      AppAction(
        id: id,
        title: title,
        group: 'Go to',
        keywords: ['open', 'show', ...kw],
        enabled: yes,
        run: (c) => c.state.setSection(sec),
      );
  bool itemIs<T>(AppState s) => selectedItem(s) is T;

  return [
    AppAction(
      id: 'palette.open',
      title: 'Command palette',
      group: 'App',
      keywords: const ['actions', 'commands', 'search'],
      shortcuts: const ['Ctrl+K', 'Cmd+K'],
      enabled: yes,
      run: (c) => c.openPalette?.call(),
    ),
    AppAction(
      id: 'go.home',
      title: 'Go to Home',
      group: 'Go to',
      keywords: const ['open', 'today', 'dashboard'],
      enabled: yes,
      run: (c) => c.state.activateTab(null),
    ),
    go('go.notes', 'Go to Notes', Section.notes, const ['files', 'tree']),
    go('go.tasks', 'Go to Tasks', Section.tasks, const ['todo', 'list']),
    go('go.events', 'Go to Events', Section.events, const [
      'agenda',
      'calendar',
    ]),
    go('go.views', 'Go to Views', Section.views, const ['saved', 'filters']),
    go('go.search', 'Go to Search', Section.search, const ['find']),
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
      enabled: (s) => s.hasPeek,
      run: (c) => c.state.promote(),
    ),
    AppAction(
      id: 'tab.close',
      title: 'Close current tab',
      group: 'Tabs',
      keywords: const ['close', 'tab'],
      shortcuts: const ['Ctrl+W', 'Cmd+W'],
      enabled: (s) => s.activeTab != null,
      run: (c) => c.state.closeActiveTab(),
    ),
    AppAction(
      id: 'tab.next',
      title: 'Next tab',
      group: 'Tabs',
      keywords: const ['tab', 'switch', 'forward'],
      enabled: (s) => s.tabs.isNotEmpty,
      run: (c) => _stepTab(c.state, 1),
    ),
    AppAction(
      id: 'tab.previous',
      title: 'Previous tab',
      group: 'Tabs',
      keywords: const ['tab', 'switch', 'back'],
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
      title: 'Show keyboard shortcuts',
      group: 'App',
      keywords: const ['help', 'keys', 'keyboard', 'shortcuts', 'bindings'],
      enabled: yes,
      run: (c) => showKeyboardHelp(c.context),
    ),
    AppAction(
      id: 'item.delete',
      title: 'Delete selected item',
      group: 'Selected item',
      keywords: const ['remove', 'trash', 'note', 'task', 'event'],
      enabled: (s) => switch (selectedItem(s)) {
        Note() => s.editable,
        Task() => s.tasksEditable,
        Event() => s.eventsEditable,
        _ => false,
      },
      run: (c) => switch (selectedItem(c.state)) {
        final Note n => confirmDeleteNote(c.context, c.state, n),
        final Task t => confirmDeleteTask(c.context, c.state, t),
        final Event e => confirmDeleteEvent(c.context, c.state, e),
        _ => null,
      },
    ),
    AppAction(
      id: 'task.toggle',
      title: switch (selectedItem(state)) {
        final Task t when t.isClosed => 'Reopen selected task',
        _ => 'Complete selected task',
      },
      group: 'Selected item',
      keywords: const ['done', 'finish', 'check', 'reopen', 'task'],
      enabled: (s) {
        final t = selectedItem(s);
        return t is Task &&
            s.tasksEditable &&
            (t.isClosed || s.taskCompletionBlockerFor(t.uid) == null);
      },
      run: (c) async {
        final u = selectedItemUid(c.state);
        if (u != null) await c.state.toggleTask(u);
      },
    ),
    AppAction(
      id: 'item.move-space',
      title: 'Move selected item to another Space',
      group: 'Selected item',
      keywords: const ['move', 'space', 'transfer'],
      enabled: (s) =>
          s.spaces.length > 1 &&
          switch (selectedItem(s)) {
            Note() => s.editable,
            Task() => s.tasksEditable,
            Event() => s.eventsEditable,
            _ => false,
          },
      run: (c) => switch (selectedItem(c.state)) {
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
        final n = selectedItem(c.state);
        return n is Note ? showMoveFolderDialog(c.context, c.state, n) : null;
      },
    ),
  ];
}

/// Home, then the document tabs in order, as one ring: focuses the one
/// [by] places after the current one.
Future<void> _stepTab(AppState s, int by) {
  final ring = <DocTab?>[null, ...s.tabs];
  final i = ring.indexOf(s.activeTab);
  final next = ring[((i < 0 ? 0 : i) + by) % ring.length];
  return s.activateTab(next);
}

/// A dialog listing the shortcuts that work now.
Future<void> showKeyboardHelp(BuildContext context) => showAppDialog(
  context,
  title: 'Keyboard shortcuts',
  content: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (keys, what) in knownShortcuts)
        Padding(
          padding: EdgeInsets.only(bottom: tokensOf(context).space.sm),
          child: Text('$keys  -  $what'),
        ),
    ],
  ),
  actions: const [CancelButton(label: 'Close')],
);
