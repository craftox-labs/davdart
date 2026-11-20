import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// The parts of the screen that can hold keyboard focus.
enum NavArea { rail, panel, main, peek }

/// One row of a keyboard list: a stable [id] (the cursor survives rebuilds by
/// it), the item [uid] when the row is a note, task or event, and how to open
/// it. [hidden] is asked at move time (a row inside a folded group).
class NavEntry {
  const NavEntry(this.id, {this.uid, this.open, this.hidden});
  final String id;
  final String? uid;

  /// Opens the row; [mode] null means the "open in" setting.
  final Future<void> Function(OpenMode? mode)? open;
  final bool Function()? hidden;
}

/// Keyboard state: the focused area, a cursor row per list, the pending key
/// sequence. Lists publish their visible rows in `build` ([publish]); the
/// cursor is a uid per list and clamps to what is there. Plain Dart, no
/// widgets: it only notifies, the rows and area marks listen.
class KeyNav extends ChangeNotifier {
  /// How long a half-typed sequence (`g`) waits for its next key.
  static const sequenceTimeout = Duration(seconds: 1);

  /// Lists the cursor can sit in: the rail, the Home cards (main) and one
  /// per side-panel section.
  static const railList = 'rail';
  static const homeList = 'home';

  NavArea _area = NavArea.panel;

  /// Whether the keyboard has been used (the area mark and cursor show).
  bool shown = false;

  /// Layout, set by the shell each build: which areas are on screen.
  final Set<NavArea> _visible = {NavArea.main};
  bool _mirror = false;

  final Map<String, List<NavEntry>> _lists = {};
  final Map<String, String?> _cursor = {};
  final Map<String, int> _lastIndex = {};

  /// Direction of the last cursor move (+1 down, -1 up, 0 jump), for
  /// scrolling the row into view.
  int lastDir = 0;

  /// The search field, focused by `/`.
  final FocusNode searchNode = FocusNode(debugLabel: 'search');

  /// The shell's key catcher; Esc in a text field returns here.
  final FocusNode node = FocusNode(debugLabel: 'key-nav', skipTraversal: true);

  List<String> _pending = [];
  int _count = 0;
  Timer? _timer;

  /// The keyboard is in use: the area mark and the cursor appear.
  void markShown() {
    if (shown) return;
    shown = true;
    notifyListeners();
  }

  // --- layout and area ---

  void setLayout({
    required bool rail,
    required bool panel,
    required bool main,
    required bool peek,
    required bool mirror,
  }) {
    _visible
      ..clear()
      ..addAll([
        if (rail) NavArea.rail,
        if (panel) NavArea.panel,
        if (main) NavArea.main,
        if (peek) NavArea.peek,
      ]);
    _mirror = mirror;
  }

  /// The areas on screen, left to right.
  List<NavArea> get ring {
    final l = [
      for (final a in NavArea.values)
        if (_visible.contains(a)) a,
    ];
    return _mirror ? l.reversed.toList() : l;
  }

  /// The focused area; if that one is not on screen, the nearest one that is.
  NavArea get area {
    if (_visible.contains(_area) || _visible.isEmpty) return _area;
    for (final a in [NavArea.panel, NavArea.main, NavArea.peek, NavArea.rail]) {
      if (_visible.contains(a)) return a;
    }
    return _area;
  }

  /// Gives [a] the focus; its list ([list]) gets a cursor row if it has none.
  void focusArea(NavArea a, {String? list, bool byKey = false}) {
    if (byKey) shown = true;
    _area = a;
    if (list != null) _ensureCursor(list);
    notifyListeners();
  }

  /// Moves the focus one area left (-1) or right (+1) on screen. [listOf]
  /// names the list of the area it lands on.
  bool moveArea(int dir, String? Function(NavArea) listOf) {
    final r = ring;
    final i = r.indexOf(area);
    if (i < 0) return false;
    final j = i + dir;
    if (j < 0 || j >= r.length) return false;
    focusArea(r[j], list: listOf(r[j]));
    return true;
  }

  /// Esc: the focus goes up one level (peek, main, panel, rail).
  bool up(String? Function(NavArea) listOf) {
    const order = [NavArea.peek, NavArea.main, NavArea.panel, NavArea.rail];
    final i = order.indexOf(area);
    for (var j = i + 1; j < order.length; j++) {
      if (_visible.contains(order[j])) {
        focusArea(order[j], list: listOf(order[j]));
        return true;
      }
    }
    return false;
  }

  /// A click or tap inside [a]: the area follows the pointer (no mark yet).
  void pointerIn(NavArea a) {
    if (_area == a) return;
    _area = a;
    notifyListeners();
  }

  // --- lists and cursor ---

  static NavArea areaOfList(String list) => switch (list) {
    railList => NavArea.rail,
    homeList => NavArea.main,
    _ => NavArea.panel,
  };

  /// A list's current rows, in order. Called from `build`: stores only.
  void publish(String list, List<NavEntry> rows) => _lists[list] = rows;

  List<NavEntry> _rows(String list) => [
    for (final e in _lists[list] ?? const <NavEntry>[])
      if (!(e.hidden?.call() ?? false)) e,
  ];

  /// The cursor row id of [list], clamped to the rows that exist now.
  String? cursorId(String list) {
    final rows = _rows(list);
    final c = _cursor[list];
    if (c == null || rows.isEmpty) return null;
    if (rows.any((e) => e.id == c)) return c;
    final i = (_lastIndex[list] ?? 0).clamp(0, rows.length - 1);
    return rows[i].id;
  }

  NavEntry? cursorEntry(String list) {
    final c = cursorId(list);
    if (c == null) return null;
    for (final e in _rows(list)) {
      if (e.id == c) return e;
    }
    return null;
  }

  /// Whether row [id] of [list] is the one the keyboard cursor is on.
  bool isCursor(String list, String id) => cursorId(list) == id;

  void _ensureCursor(String list) {
    final rows = _rows(list);
    if (rows.isEmpty) return;
    if (cursorId(list) == null) {
      _cursor[list] = rows.first.id;
      _lastIndex[list] = 0;
    } else {
      _cursor[list] = cursorId(list);
    }
  }

  /// Puts the cursor of [list] on row [id] (a click, or code).
  void setCursor(String list, String id, {int dir = 0, bool silent = false}) {
    final rows = _rows(list);
    final i = rows.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _cursor[list] = id;
    _lastIndex[list] = i;
    lastDir = dir;
    if (!silent) notifyListeners();
  }

  /// A pointer press on a row: the cursor and the area go there.
  void pointerOn(String list, String id) {
    _area = areaOfList(list);
    setCursor(list, id);
  }

  /// Moves the cursor of [list] by [by] rows, clamped.
  void move(String list, int by) {
    final rows = _rows(list);
    if (rows.isEmpty) return;
    final c = cursorId(list);
    final i = c == null ? -1 : rows.indexWhere((e) => e.id == c);
    final j = (i < 0 ? (by > 0 ? by - 1 : 0) : i + by).clamp(
      0,
      rows.length - 1,
    );
    setCursor(list, rows[j].id, dir: by.sign);
  }

  void jump(String list, {required bool last}) {
    final rows = _rows(list);
    if (rows.isEmpty) return;
    setCursor(list, (last ? rows.last : rows.first).id, dir: 0);
  }

  // --- pending sequence and count ---

  List<String> get pending => List.unmodifiable(_pending);
  int get count => _count;

  /// What the indicator shows: a count then the keys typed so far.
  String get pendingLabel => [if (_count > 0) '$_count', ..._pending].join(' ');

  void setPending(List<String> keys, {int? count}) {
    _pending = keys;
    if (count != null) _count = count;
    _timer?.cancel();
    if (keys.isNotEmpty || _count > 0) {
      _timer = Timer(sequenceTimeout, clearPending);
    }
    notifyListeners();
  }

  void clearPending() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty && _count == 0) return;
    _pending = [];
    _count = 0;
    notifyListeners();
  }

  /// The numeric prefix typed before a motion (5j); 1 when none. Resets it.
  int takeCount() {
    final n = _count == 0 ? 1 : _count;
    _count = 0;
    return n;
  }

  @override
  void dispose() {
    _timer?.cancel();
    searchNode.dispose();
    node.dispose();
    super.dispose();
  }
}

/// The list the cursor of [a] moves in right now, or null (no list there).
String? navListId(AppState s, NavArea a) => switch (a) {
  NavArea.rail => KeyNav.railList,
  NavArea.panel => switch (s.section) {
    Section.notes => 'notes',
    Section.tasks => 'tasks',
    Section.events => 'events',
    Section.views => 'views',
    Section.search => 'search',
    _ => null,
  },
  NavArea.main =>
    !s.noSpace && s.activeTab == null && !s.mainIsPage ? KeyNav.homeList : null,
  NavArea.peek => null,
};
