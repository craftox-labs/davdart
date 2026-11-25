import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// The parts of the screen that can hold keyboard focus.
enum NavArea { rail, panel, main, peek }

/// One row of a keyboard list: a stable [id] (the cursor survives rebuilds by
/// it), the item [uid] when the row is a note, task or event, and how to open
/// it. [hidden] is asked at move time (a row inside a folded group).
class NavEntry {
  const NavEntry(this.id, {this.uid, this.open, this.hidden, this.block});
  final String id;
  final String? uid;

  /// Home grid only: the block (Tasks card, Events card, a board column) the
  /// row belongs to. Board columns are named `col:<status>`.
  final String? block;

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

  /// Keyboard modality, like `:focus-visible`: the area mark, the cursor and
  /// the rings show only after a navigation key and are hidden by any pointer
  /// press or Esc. The key handler itself stays alive either way.
  bool shown = false;

  /// The Home day sections are one stacked column (true while they show).
  bool homeStacked = false;

  /// The Home board is a status accordion (narrow); set by the board each
  /// build. [boardOpen] holds the sections the user opened or closed, by
  /// status; a status not in it follows the default (see boardDefaultOpen).
  bool boardAccordion = false;
  final Map<String, bool> boardOpen = {};

  /// Layout, set by the shell each build: which areas are on screen.
  final Set<NavArea> _visible = {NavArea.main};
  bool _mirror = false;

  final Map<String, List<NavEntry>> _lists = {};
  final Map<String, String?> _cursor = {};
  final Map<String, int> _lastIndex = {};

  // Home: the block and row-in-block of the cursor's last known row.
  String? _homeBlock;
  int _homeRow = 0;

  void _noteHome(List<NavEntry> rows, int i) {
    if (i < 0 || i >= rows.length) return;
    _homeBlock = rows[i].block;
    _homeRow = rows.sublist(0, i).where((e) => e.block == rows[i].block).length;
  }

  /// Direction of the last cursor move (+1 down, -1 up, 0 jump), for
  /// scrolling the row into view.
  int lastDir = 0;

  /// The search field, focused by `/` and whenever the Search section is
  /// opened by hand.
  final FocusNode searchNode = FocusNode(debugLabel: 'search');

  /// Focuses the search field once its panel is built, for a user action that
  /// opens Search (a rail or bar press, the palette): the panel may mount a
  /// frame later (the narrow side menu opens in the same setState), so a node
  /// without a context is retried once on the next frame. Nothing happens when
  /// the field already has the focus, so it is never stolen back.
  void focusSearch() {
    void tryFocus(int attempt) {
      if (searchNode.hasFocus) return;
      if (searchNode.context != null) {
        searchNode.requestFocus();
        return;
      }
      if (attempt >= 1) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => tryFocus(attempt + 1),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryFocus(0));
  }

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

  /// A pointer press or Esc: the mark, cursor and rings hide; the next
  /// navigation key shows them again where they were.
  void hide() {
    if (!shown) return;
    shown = false;
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

  final Map<String, List<NavEntry>> _homeGroups = {};

  /// Fills one group of the Home grid (`today`: the Tasks and Events card
  /// rows; `board`: the board cards, column by column). The `home` list is
  /// the groups in that order.
  void publishHome(String group, List<NavEntry> rows) {
    _homeGroups[group] = rows;
    _lists[homeList] = [...?_homeGroups['today'], ...?_homeGroups['board']];
  }

  /// The visible rows of [list] (for tests).
  @visibleForTesting
  List<NavEntry> rowsOf(String list) => _rows(list);

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
    if (list == homeList && _homeBlock != null) {
      // Home: its row went (completed, deleted, moved): the previous row of
      // the same card or column, else the next block's first row.
      final same = [
        for (final e in rows)
          if (e.block == _homeBlock) e,
      ];
      if (same.isNotEmpty) {
        return same[(_homeRow - 1).clamp(0, same.length - 1)].id;
      }
    }
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
      if (list == homeList) _noteHome(rows, 0);
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
    if (list == homeList) _noteHome(rows, i);
    lastDir = dir;
    if (!silent) notifyListeners();
  }

  /// A pointer press on a row: the cursor and the area go there.
  void pointerOn(String list, String id) {
    _area = areaOfList(list);
    setCursor(list, id);
  }

  // --- Home grid: blocks (Tasks card, Events card, board columns) ---

  static String _sectionOf(String? block) =>
      block != null && block.startsWith('col:') ? 'board' : (block ?? '');

  /// The visible Home rows grouped by block, in order.
  List<List<NavEntry>> _homeBlocks() {
    final out = <List<NavEntry>>[];
    String? last;
    for (final e in _rows(homeList)) {
      if (e.block != last || out.isEmpty) {
        out.add([]);
        last = e.block;
      }
      out.last.add(e);
    }
    return out;
  }

  (int, int) _homePos(List<List<NavEntry>> blocks) {
    final c = cursorId(homeList);
    for (var b = 0; b < blocks.length; b++) {
      final i = blocks[b].indexWhere((e) => e.id == c);
      if (i >= 0) return (b, i);
    }
    return (-1, -1);
  }

  /// One step down (+1) or up (-1) on Home: stays inside the card or board
  /// column; when the cards are stacked it flows into the next block.
  void _homeStep(int dir) {
    final blocks = _homeBlocks();
    final (b, i) = _homePos(blocks);
    if (b < 0) {
      if (blocks.isNotEmpty) {
        setCursor(homeList, blocks.first.first.id, dir: dir);
      }
      return;
    }
    final j = i + dir;
    if (j >= 0 && j < blocks[b].length) {
      setCursor(homeList, blocks[b][j].id, dir: dir);
      return;
    }
    if (!homeStacked) return;
    // The vertical chain when stacked: the card blocks, then the first board
    // column (any column's top leads back up to the last card).
    final chain = <int>[
      for (var k = 0; k < blocks.length; k++)
        if (_sectionOf(blocks[k].first.block) != 'board') k,
    ];
    final board = blocks.indexWhere(
      (bl) => _sectionOf(bl.first.block) == 'board',
    );
    if (board >= 0) chain.add(board);
    final onBoard = _sectionOf(blocks[b].first.block) == 'board';
    final at = chain.indexOf(onBoard ? board : b);
    final k = at + dir;
    if (at < 0 || k < 0 || k >= chain.length) return;
    final target = blocks[chain[k]];
    setCursor(homeList, (dir > 0 ? target.first : target.last).id, dir: dir);
  }

  /// h/l on Home: to the card or column beside this one, on the same row
  /// number (clamped). False when there is none (the area moves instead).
  bool homeSide(int dir) {
    final blocks = _homeBlocks();
    final (b, i) = _homePos(blocks);
    if (b < 0) return false;
    final sec = _sectionOf(blocks[b].first.block);
    final peers = [
      for (var k = 0; k < blocks.length; k++)
        if (sec == 'board'
            ? _sectionOf(blocks[k].first.block) == 'board'
            : !homeStacked && _sectionOf(blocks[k].first.block) != 'board')
          k,
    ];
    final at = peers.indexOf(b);
    final k = at + dir;
    if (at < 0 || k < 0 || k >= peers.length) return false;
    final target = blocks[peers[k]];
    setCursor(homeList, target[i.clamp(0, target.length - 1)].id);
    return true;
  }

  /// `{` and `}`: the first row of the previous or next section (Events section,
  /// Tasks section, Board), skipping empty ones. False at either end.
  bool homeSection(int dir) {
    final blocks = _homeBlocks();
    final (b, _) = _homePos(blocks);
    final firsts = <String, NavEntry>{};
    for (final bl in blocks) {
      firsts.putIfAbsent(_sectionOf(bl.first.block), () => bl.first);
    }
    final secs = firsts.keys.toList();
    final cur = b < 0 ? -1 : secs.indexOf(_sectionOf(blocks[b].first.block));
    final k = cur < 0 ? (dir > 0 ? 0 : secs.length - 1) : cur + dir;
    if (k < 0 || k >= secs.length) return false;
    setCursor(homeList, firsts[secs[k]]!.id, dir: dir);
    return true;
  }

  /// Moves the cursor of [list] by [by] rows, clamped.
  void move(String list, int by) {
    if (list == homeList) {
      for (var n = 0; n < by.abs(); n++) {
        _homeStep(by.sign);
      }
      return;
    }
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

  // --- Scrolling an open item page (peek or main) ---

  final Map<NavArea, ScrollController> _pages = {};

  /// The scroll controller of the item page shown in [a] (peek or main); the
  /// page's scroll view uses it so the keyboard can scroll it.
  ScrollController pageScroll(NavArea a) =>
      _pages.putIfAbsent(a, ScrollController.new);

  /// Whether an item page is shown in [a] and has something to scroll.
  bool hasPage(NavArea a) {
    final c = _pages[a];
    if (c == null || c.positions.isEmpty) return false;
    final p = c.positions.last;
    return p.maxScrollExtent > p.minScrollExtent;
  }

  /// Scrolls the item page of [a] by [dy] px (negative: up), short animation.
  /// False when no page is shown there or its content fits.
  bool scrollPageBy(NavArea a, double dy) =>
      _scrollPage(a, (p) => p.pixels + dy);

  /// Scrolls the item page of [a] to its top or bottom.
  bool scrollPageTo(NavArea a, {required bool end}) =>
      _scrollPage(a, (p) => end ? p.maxScrollExtent : p.minScrollExtent);

  bool _scrollPage(NavArea a, double Function(ScrollPosition) target) {
    final c = _pages[a];
    if (c == null || c.positions.isEmpty) return false;
    final p = c.positions.last;
    if (p.maxScrollExtent <= p.minScrollExtent) return false;
    final to = target(p).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (to != p.pixels) {
      p.animateTo(
        to,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    }
    return true;
  }

  @override
  void dispose() {
    for (final c in _pages.values) {
      c.dispose();
    }
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
    Section.projects => 'projects',
    Section.views => 'views',
    Section.search => 'search',
    _ => null,
  },
  NavArea.main =>
    !s.noSpace && s.activeTab == null && !s.mainIsPage ? KeyNav.homeList : null,
  NavArea.peek => null,
};
