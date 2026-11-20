import 'dart:async';

import 'package:davdart/davdart.dart';

import 'action_match.dart';
import 'app_action.dart';
import 'app_state.dart';

/// One selectable row of the command palette: an action or an item hit.
class PaletteEntry {
  const PaletteEntry({
    required this.group,
    required this.title,
    required this.run,
    this.id,
    this.hint,
    this.uid,
  });

  /// The heading the row sits under (Recent, an action group, Actions,
  /// Notes, Tasks, Events).
  final String group;
  final String title;

  /// The action id, null for an item hit.
  final String? id;

  /// Shortcut label shown at the end.
  final String? hint;

  /// The item's uid, for a hit.
  final String? uid;
  final FutureOr<void> Function(ActionContext c) run;
}

const maxItemHits = 5;

/// The rows for [query]: with no query, the enabled actions with the
/// [recents] first (grouped by their own group); with one, matching actions
/// then matching notes, tasks and events of the open Space. Opening an item
/// goes through [AppState.openMode].
List<PaletteEntry> paletteEntries(
  AppState state,
  List<AppAction> actions,
  String query, {
  List<String> recents = const [],
  bool apple = false,
}) {
  PaletteEntry of(AppAction a, String group) => PaletteEntry(
    group: group,
    title: a.title,
    id: a.id,
    hint: a.shortcutHint(apple: apple),
    run: a.run,
  );
  final on = [
    for (final a in actions)
      if (a.listed && a.enabled(state)) a,
  ];
  final q = query.trim();
  if (q.isEmpty) {
    final byId = {for (final a in on) a.id: a};
    final recent = [
      for (final id in recents)
        if (byId[id] != null) byId[id]!,
    ];
    return [
      for (final a in recent) of(a, 'Recent'),
      for (final a in on)
        if (!recent.contains(a)) of(a, a.group),
    ];
  }
  final out = <PaletteEntry>[
    for (final a in rankBy(
      q,
      on,
      (a) => a.title,
      (a) => [...a.keywords, a.group],
    ))
      of(a, 'Actions'),
  ];
  PaletteEntry hit(String group, String uid, String title) => PaletteEntry(
    group: group,
    title: title,
    uid: uid,
    run: (c) => c.state.openNote(uid),
  );
  out.addAll(
    rankBy(
      q,
      [
        for (final n in state.notes)
          if (!isViewNote(n) && !AppState.isFolder(n)) n,
      ],
      (n) => n.summary,
      (n) => [n.description],
    ).take(maxItemHits).map((n) => hit('Notes', n.uid, n.summary)),
  );
  out.addAll(
    rankBy(
      q,
      state.tasks,
      (t) => t.summary,
      (t) => [t.description],
    ).take(maxItemHits).map((t) => hit('Tasks', t.uid, t.summary)),
  );
  out.addAll(
    rankBy(
      q,
      state.events,
      (e) => e.summary,
      (e) => [e.description, e.location],
    ).take(maxItemHits).map((e) => hit('Events', e.uid, e.summary)),
  );
  return out;
}
