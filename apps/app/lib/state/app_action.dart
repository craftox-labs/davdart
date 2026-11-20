import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_state.dart';

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

  /// Whether the action applies now. Disabled actions are not listed.
  final bool Function(AppState state) enabled;

  final FutureOr<void> Function(ActionContext c) run;

  /// The label to show beside the title: the Cmd one on Apple platforms,
  /// else the first other one.
  String? shortcutHint({required bool apple}) {
    if (shortcuts.isEmpty) return null;
    for (final s in shortcuts) {
      if (s.startsWith('Cmd') == apple) {
        return apple ? s.replaceFirst('Cmd+', '⌘') : s;
      }
    }
    return shortcuts.first;
  }
}

/// The shortcuts that work today, for the help dialog. Phase 2 adds to it.
const knownShortcuts = <(String, String)>[
  ('Ctrl+K / Cmd+K', 'Command palette'),
  ('Ctrl+W / Cmd+W', 'Close the current tab'),
  ('Ctrl+S / Cmd+S', 'Save the open edit'),
  ('Up / Down, Enter, Esc', 'Move, run and close in the palette'),
];
