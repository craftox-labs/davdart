import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:flutter/foundation.dart';

import '../data/key_value_storage.dart';
import '../data/note_source.dart';

enum ViewMode { board, list }

const boardOrder = ['backlog', 'todo', 'doing', 'blocked', 'done'];

String _clock() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(n.hour)}:${two(n.minute)}';
}

/// A named combination of view, search text and tag filter.
class SavedView {
  SavedView(this.name, this.view, this.query, this.tag);
  final String name;
  final ViewMode view;
  final String query;
  final String? tag;

  Map<String, Object?> toJson() => {
    'name': name,
    'view': view.name,
    'query': query,
    'tag': tag,
  };

  static SavedView? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    if (name is! String || name.isEmpty) return null;
    return SavedView(
      name,
      ViewMode.values.firstWhere(
        (v) => v.name == j['view'],
        orElse: () => ViewMode.board,
      ),
      j['query'] is String ? j['query'] as String : '',
      j['tag'] is String ? j['tag'] as String : null,
    );
  }
}

class AppState extends ChangeNotifier {
  AppState(this.source, {this.prefs}) {
    _loadViews();
  }

  final NoteSource source;

  /// Where saved views are kept; null means they last only this session.
  final KeyValueStorage? prefs;
  static const _viewsKey = 'davdart.views.v1';
  final List<SavedView> savedViews = [];

  void _loadViews() {
    try {
      final raw = prefs?.read(_viewsKey);
      if (raw == null || raw.isEmpty) return;
      for (final j in jsonDecode(raw) as List<dynamic>) {
        final v = SavedView.fromJson(j);
        if (v != null) savedViews.add(v);
      }
    } catch (_) {
      savedViews.clear();
    }
  }

  void _storeViews() => prefs?.write(
    _viewsKey,
    jsonEncode([for (final v in savedViews) v.toJson()]),
  );

  bool get hasFilter => query.trim().isNotEmpty || tag != null;

  /// Saves the current view and filters under [name] (replacing a same name).
  void saveView(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    savedViews
      ..removeWhere((v) => v.name == n)
      ..add(SavedView(n, view, query.trim(), tag));
    _storeViews();
    notifyListeners();
  }

  void applyView(SavedView v) {
    view = v.view;
    query = v.query;
    tag = v.tag;
    selectedUid = null;
    notifyListeners();
  }

  void deleteView(String name) {
    savedViews.removeWhere((v) => v.name == name);
    _storeViews();
    notifyListeners();
  }

  List<Note> notes = [];
  NoteTree tree = NoteTree.build(const []);
  bool loading = false;
  String? error;

  String? selectedUid;
  ViewMode view = ViewMode.board;
  String query = '';
  String? tag;
  final Set<String> collapsed = {};

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      notes = await source.load();
      tree = NoteTree.build(notes);
      if (tag != null && !notes.any((n) => n.categories.contains(tag))) {
        tag = null;
      }
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
    if (error == null && connected) sync();
  }

  bool get editable => source is EditableNoteSource;

  /// Sync state for the sidebar: null when there is no server.
  bool syncing = false;
  String? syncMessage;

  SpaceNoteSource? get _space {
    final s = source;
    return s is SpaceNoteSource ? s : null;
  }

  /// Older text saved by sync merges for [uid] (empty if none or read-only).
  Future<List<Revision>> revisionsFor(String uid) async =>
      await _space?.revisions(uid) ?? const [];

  bool get canConnect => _space != null;
  bool get connected => _space?.connected ?? false;
  String? get serverLabel => _space?.serverLabel;

  Future<void> connect(
    String path,
    String user,
    String password, {
    bool replaceLocal = false,
  }) async {
    final s = _space;
    if (s == null) return;
    syncing = true;
    syncMessage = 'Connecting…';
    notifyListeners();
    try {
      await s.connect(
        path.trim(),
        user.trim(),
        password,
        replaceLocal: replaceLocal,
      );
    } catch (e) {
      syncing = false;
      syncMessage = 'Could not connect: $e';
      notifyListeners();
      return;
    }
    syncing = false;
    await sync();
  }

  Future<void> disconnect() async {
    await _space?.disconnect();
    syncMessage = null;
    notifyListeners();
  }

  /// Syncs with the server (if connected), then reloads.
  Future<void> sync() async {
    final s = _space;
    if (s == null || !s.connected) return;
    if (syncing) {
      _syncAgain = true; // an edit landed mid-sync: run once more after it
      return;
    }
    syncing = true;
    syncMessage = 'Syncing…';
    notifyListeners();
    try {
      final r = await s.sync();
      syncMessage = r == null
          ? null
          : r.errors.isNotEmpty
          ? 'Sync problem: ${r.errors.first}'
          : r.conflicts.isNotEmpty
          ? 'Synced; ${r.conflicts.length} overlapping edit(s) resolved, older text kept in history'
          : 'Synced ${_clock()}';
      notes = await source.load();
      tree = NoteTree.build(notes);
    } catch (e) {
      syncMessage = 'Sync failed: $e';
    }
    syncing = false;
    notifyListeners();
    if (_syncAgain) {
      _syncAgain = false;
      await sync();
    }
  }

  bool _syncAgain = false;

  Future<void> _save(Note n) => _edit((src) => src.save(n));

  Future<void> _edit(Future<void> Function(EditableNoteSource) change) async {
    final src = source;
    if (src is! EditableNoteSource) {
      throw StateError('This source is read-only');
    }
    try {
      await change(src);
      notes = await source.load();
      tree = NoteTree.build(notes);
      error = null;
    } catch (e) {
      error = 'Save failed: $e';
    }
    notifyListeners();
    if (error == null && connected) sync();
  }

  /// Moves a note to another status (keeps the header and status tag in step).
  Future<void> setStatus(String uid, String status) async {
    final n = tree.find(uid)?.note;
    if (n == null) return;
    final copy = n.copyWith();
    final p = PlanItem.fromNote(copy)..setStatus(status);
    await _save(p.apply());
  }

  /// Changes a note's title and/or body text (the header lines stay).
  Future<void> updateNote(
    String uid, {
    String? title,
    String? text,
    List<String>? tags,
  }) async {
    final n = tree.find(uid)?.note;
    if (n == null) return;
    final t = title?.trim();
    if (t != null && t.isEmpty) return;
    final copy = n.copyWith(summary: t);
    final p = PlanItem.fromNote(copy);
    if (text != null) p.text = text;
    if (tags != null) {
      // Status tags are managed by the status menu, not here.
      copy.categories = [
        ...copy.categories.where((c) => c.startsWith('status-')),
        ...tags.where((c) => c.isNotEmpty && !c.startsWith('status-')),
      ];
    }
    await _save(p.apply());
  }

  /// Deletes a note; its children move up to its parent so none are lost.
  Future<void> deleteNote(String uid) async {
    final node = tree.find(uid);
    if (node == null) return;
    final parent = node.note.parentUid;
    final kids = [for (final c in node.children) c.note.copyWith()];
    await _edit((src) async {
      for (final k in kids) {
        k.parentUid = parent;
        await src.save(k);
      }
      await src.delete(uid);
    });
    if (error == null && selectedUid == uid) selectedUid = null;
    notifyListeners();
  }

  /// Adds a note (a child of [parentUid] if given) and selects it.
  Future<void> addNote(
    String title, {
    String? parentUid,
    String? status,
  }) async {
    final t = title.trim();
    if (t.isEmpty) return;
    final now = DateTime.now().toUtc();
    final n = Note(
      uid: 'davdart-${now.microsecondsSinceEpoch}',
      summary: t,
      parentUid: parentUid,
      created: now,
      lastModified: now,
    );
    if (status != null) {
      final p = PlanItem.fromNote(n)..setStatus(status);
      p.apply();
    }
    await _save(n);
    if (error == null) select(n.uid);
  }

  Note? get selected =>
      selectedUid == null ? null : tree.find(selectedUid!)?.note;

  void select(String? uid) {
    selectedUid = uid;
    notifyListeners();
  }

  void setView(ViewMode v) {
    view = v;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setTag(String? t) {
    tag = tag == t ? null : t;
    notifyListeners();
  }

  void toggle(String uid) {
    if (!collapsed.remove(uid)) collapsed.add(uid);
    notifyListeners();
  }

  /// Tags a user can filter by (status tags are shown as columns instead).
  List<String> get tags => ({
    for (final n in notes)
      for (final c in n.categories)
        if (!c.startsWith('status-')) c,
  }.toList()..sort());

  bool matches(Note n) {
    if (tag != null && !n.categories.contains(tag)) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return n.summary.toLowerCase().contains(q) ||
        n.description.toLowerCase().contains(q);
  }

  /// Notes after search and tag filters.
  List<Note> get filtered => [
    for (final n in notes)
      if (matches(n)) n,
  ]..sort(NoteTree.byCreated);

  /// Board columns in a stable order; notes with no status go last.
  List<(String, List<Note>)> get columns {
    final by = <String, List<Note>>{};
    for (final n in filtered) {
      (by[PlanItem.fromNote(n).status ?? 'notes'] ??= []).add(n);
    }
    final keys = [
      ...boardOrder.where(by.containsKey),
      ...by.keys.where((k) => !boardOrder.contains(k) && k != 'notes'),
      if (by.containsKey('notes')) 'notes',
    ];
    return [for (final k in keys) (k, by[k]!)];
  }
}
