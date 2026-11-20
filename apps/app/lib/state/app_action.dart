import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_state.dart';
import 'vim_editor/vim_keys.dart';

/// What an action runs with: the app state, plus a [context] below the
/// Navigator for the actions that open a dialog. [openPalette] reopens the
/// command palette (set by the UI that hosts it).
class ActionContext {
  const ActionContext(this.state, this.context, {this.openPalette});
  final AppState state;
  final BuildContext context;
  final void Function()? openPalette;
}

/// One thing the user can do, by name: the unit the command palette lists
/// and a later key map binds. Actions hold no logic of their own: [run] calls
/// the same [AppState] methods and dialogs the menus and buttons use.
///
/// The list is rebuilt from the state each time it is needed (see
/// `buildActions`), so [title] and [enabled] may read the state freely.
class AppAction {
  const AppAction({
    required this.id,
    required this.title,
    required this.group,
    required this.enabled,
    required this.run,
    this.keywords = const [],
    this.shortcuts = const [],
    this.listed = true,
    this.chords = const [],
  });

  /// Stable, dotted id (`go.tasks`, `item.delete`); persisted in recents and
  /// the key a phase-2 key map refers to. Never rename one.
  final String id;
  final String title;

  /// The palette's heading and what a help list groups by (Go to, Create...).
  final String group;

  /// Extra words the palette also matches (not shown).
  final List<String> keywords;

  /// Display labels of the keys bound to this action, `Ctrl+K`, `Cmd+K`.
  /// Labels only: binding happens where the action is wired.
  final List<String> shortcuts;

  /// Labels of the global chords (they work while typing) for the active
  /// platform: `Alt+J`, `Ctrl+Shift+J`. Set by `buildActions` from the
  /// chord keymap.
  final List<String> chords;

  /// A copy with [chords] set.
  AppAction withChords(List<String> chords) => AppAction(
    id: id,
    title: title,
    group: group,
    enabled: enabled,
    run: run,
    keywords: keywords,
    shortcuts: shortcuts,
    listed: listed,
    chords: chords,
  );

  /// False for key-only actions (cursor moves) the palette does not list.
  final bool listed;

  /// Whether the action applies now. Disabled actions are not listed.
  final bool Function(AppState state) enabled;

  final FutureOr<void> Function(ActionContext c) run;

  /// What the help dialog calls it.
  String get helpTitle => title;

  /// The label to show beside the title: the Cmd one on Apple platforms,
  /// else the first other one.
  String? shortcutHint({required bool apple}) {
    if (chords.isNotEmpty && !shortcuts.any((s) => s.contains('+'))) {
      return apple ? chords.first.replaceAll('Cmd+', '⌘') : chords.first;
    }
    if (shortcuts.isEmpty) return null;
    for (final s in shortcuts) {
      if (s.startsWith('Cmd') == apple) {
        return apple ? s.replaceFirst('Cmd+', '⌘') : s;
      }
    }
    return shortcuts.first;
  }
}

/// Shortcuts bound outside the registry (not actions), for the help dialog.
const knownShortcuts = <(String, String)>[
  ('Ctrl+S / Cmd+S', 'Save the open edit'),
  ('Up / Down, Enter, Esc', 'Move, run and close in the palette'),
];

/// Keys of an open edit that live in the editors, for the Edit group of the
/// help dialog (Ctrl/Cmd+Enter is a registry action).
const editShortcuts = <(String, String)>[
  (
    'Esc',
    'Leave edit mode (asks first if unsaved); in the Vim editor: leave Insert',
  ),
];

/// The help dialog's groups, in order. An action sits in the group named by
/// [helpGroupOf] its own group.
const chordGroup =
    'Chords (work while typing; letters are key positions on a QWERTY keyboard)';
const helpGroups = [
  'Navigation',
  'Open',
  'Edit',
  'Go to',
  'Panes',
  'App',
  chordGroup,
  vimHelpGroup,
];

String helpGroupOf(String group) => switch (group) {
  'Navigation' || 'Open' || 'Edit' || 'Go to' || 'Panes' => group,
  'Tabs' => 'Panes',
  'Selected item' || 'Create' => 'Edit',
  _ => 'App',
};

/// The help dialog's rows, from the registry (the single source of truth):
/// per group, `(keys, what)` for every action that has shortcuts.
List<(String, List<(String, String)>)> helpRows(List<AppAction> actions) {
  final by = <String, List<(String, String)>>{
    for (final g in helpGroups) g: [],
  };
  for (final a in actions) {
    if (a.chords.isNotEmpty) {
      by[chordGroup]!.add((a.chords.join(' / '), a.helpTitle));
    }
    if (a.shortcuts.isEmpty) continue;
    by[helpGroupOf(a.group)]!.add((a.shortcuts.join(' / '), a.helpTitle));
  }
  by['Edit']!.addAll(editShortcuts);
  by['App']!.addAll(knownShortcuts);
  by[vimHelpGroup]!.addAll(vimHelpRows);
  return [
    for (final g in helpGroups)
      if (by[g]!.isNotEmpty) (g, by[g]!),
  ];
}
