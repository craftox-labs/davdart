import 'package:davdart/davdart.dart';
import 'package:flutter/foundation.dart';

import '../data/note_source.dart';

enum ViewMode { board, list }

const boardOrder = ['backlog', 'todo', 'doing', 'blocked', 'done'];

class AppState extends ChangeNotifier {
  AppState(this.source);

  final NoteSource source;

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
  }

  bool get editable => source is EditableNoteSource;

  Future<void> _save(Note n) async {
    final src = source;
    if (src is! EditableNoteSource) {
      throw StateError('This source is read-only');
    }
    try {
      await src.save(n);
      notes = await source.load();
      tree = NoteTree.build(notes);
      error = null;
    } catch (e) {
      error = 'Save failed: $e';
    }
    notifyListeners();
  }

  /// Moves a note to another status (keeps the header and status tag in step).
  Future<void> setStatus(String uid, String status) async {
    final n = tree.find(uid)?.note;
    if (n == null) return;
    final copy = n.copyWith();
    final p = PlanItem.fromNote(copy)..setStatus(status);
    await _save(p.apply());
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
