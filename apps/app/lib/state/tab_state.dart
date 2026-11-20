import 'dart:convert';

/// What a document tab shows.
enum TabKind { note, view, task, event }

/// One closable tab of the strip: a note opened full page, or an applied
/// saved view. Identified by the note's uid (for a view, the uid of the note
/// that stores it, so renaming a view keeps its tab). The home tab is not a
/// [DocTab]: it is the strip's fixed first entry.
class DocTab {
  const DocTab(this.kind, this.id);
  const DocTab.note(String uid) : this(TabKind.note, uid);
  const DocTab.view(String uid) : this(TabKind.view, uid);
  const DocTab.task(String uid) : this(TabKind.task, uid);
  const DocTab.event(String uid) : this(TabKind.event, uid);

  final TabKind kind;
  final String id;

  String get code =>
      '${switch (kind) {
        TabKind.note => 'n',
        TabKind.view => 'v',
        TabKind.task => 't',
        TabKind.event => 'e',
      }}:$id';

  static DocTab? parse(String s) {
    if (s.length < 3 || s[1] != ':') return null;
    final id = s.substring(2);
    return switch (s[0]) {
      'n' => DocTab.note(id),
      'v' => DocTab.view(id),
      't' => DocTab.task(id),
      'e' => DocTab.event(id),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DocTab && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// The open tabs of one Space, in strip order, and their stored form.
class TabList {
  final List<DocTab> tabs = [];

  bool contains(DocTab t) => tabs.contains(t);

  /// Adds [t] at the end unless it is open. True if it was added.
  bool add(DocTab t) {
    if (tabs.contains(t)) return false;
    tabs.add(t);
    return true;
  }

  /// Removes [t]; returns the tab to show instead (the neighbour to its
  /// right, else to its left), or null when none is left or [t] was not open.
  DocTab? remove(DocTab t) {
    final i = tabs.indexOf(t);
    if (i < 0) return null;
    tabs.removeAt(i);
    if (tabs.isEmpty) return null;
    return tabs[i < tabs.length ? i : i - 1];
  }

  /// Moves [t] to index [to] (clamped; the index it ends at). True if the
  /// order changed.
  bool move(DocTab t, int to) {
    final i = tabs.indexOf(t);
    if (i < 0) return false;
    tabs.removeAt(i);
    final j = to.clamp(0, tabs.length);
    tabs.insert(j, t);
    return j != i;
  }

  /// Keeps only the tabs [keep] accepts. True if any were dropped.
  bool retain(bool Function(DocTab) keep) {
    final before = tabs.length;
    tabs.removeWhere((t) => !keep(t));
    return tabs.length != before;
  }

  String encode() => jsonEncode([for (final t in tabs) t.code]);

  /// Replaces the tabs with the stored list (unreadable text gives none).
  void decode(String? s) {
    tabs.clear();
    if (s == null) return;
    try {
      final list = jsonDecode(s);
      if (list is! List) return;
      for (final e in list) {
        final t = e is String ? DocTab.parse(e) : null;
        if (t != null) add(t);
      }
    } catch (_) {}
  }
}
