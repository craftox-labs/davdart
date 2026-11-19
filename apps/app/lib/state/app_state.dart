import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;

import '../data/key_value_storage.dart';
import '../data/note_source.dart';
import '../data/space_catalog.dart';
import 'note_draft.dart';

enum ViewMode { board, list }

/// The section the side panel shows, chosen with the icon rail.
/// `notes` is shown as "Files"; the id stays so saved selections still load.
/// Spaces is a popup on the rail, not a section.
enum Section { notes, views, search, account, settings }

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

/// A note found by a search across every Space.
class SpaceHit {
  const SpaceHit(this.space, this.note);
  final SpaceInfo space;
  final Note note;
}

/// Which edge of the window the shell's icon rail sits on.
enum LayoutSide { start, end }

class AppState extends ChangeNotifier {
  AppState(this.source, {this.prefs, this.catalog}) {
    _loadViews();
    final saved = prefs?.read(_sectionKey);
    section = Section.values.firstWhere(
      (v) => v.name == saved,
      orElse: () => Section.notes,
    );
    sidebarCollapsed = prefs?.read(_collapsedKey) == 'true';
    final w = double.tryParse(prefs?.read(_widthKey) ?? '');
    sidebarWidth = (w == null || !w.isFinite) ? null : w;
    final dw = double.tryParse(prefs?.read(_detailWidthKey) ?? '');
    detailWidth = (dw == null || !dw.isFinite) ? null : dw;
    layoutSide = prefs?.read(_layoutSideKey) == LayoutSide.end.name
        ? LayoutSide.end
        : LayoutSide.start;
  }

  static const _detailWidthKey = 'davdart.detail.width.v1';
  static const _layoutSideKey = 'davdart.layout.side.v1';

  /// Dragged width of the detail pane in the split layout; null means the
  /// default token. Callers clamp it.
  double? detailWidth;

  /// Which edge the icon rail sits on; [LayoutSide.end] mirrors the shell.
  LayoutSide layoutSide = LayoutSide.start;

  void setDetailWidth(double? w, {bool save = true}) {
    if (detailWidth != w) {
      detailWidth = w;
      notifyListeners();
    }
    if (!save) return;
    if (w == null) {
      prefs?.remove(_detailWidthKey);
    } else {
      prefs?.write(_detailWidthKey, '$w');
    }
  }

  void setLayoutSide(LayoutSide side) {
    if (layoutSide == side) return;
    layoutSide = side;
    if (side == LayoutSide.start) {
      prefs?.remove(_layoutSideKey);
    } else {
      prefs?.write(_layoutSideKey, side.name);
    }
    notifyListeners();
  }

  static const _sectionKey = 'davdart.section.v1';
  static const _collapsedKey = 'davdart.sidebar.collapsed.v1';
  static const _widthKey = 'davdart.sidebar.width.v1';

  /// Whether the docked side panel is folded away (wide layout only; the
  /// narrow sheet ignores it).
  bool sidebarCollapsed = false;

  /// Dragged width of the docked side panel; null means the default token.
  /// Callers clamp it to the token limits.
  double? sidebarWidth;

  void setSidebarCollapsed(bool v) {
    if (sidebarCollapsed == v) return;
    sidebarCollapsed = v;
    prefs?.write(_collapsedKey, '$v');
    notifyListeners();
  }

  /// Sets the side panel width (null restores the default). While dragging,
  /// pass `save: false` and save once at the end.
  void setSidebarWidth(double? w, {bool save = true}) {
    if (sidebarWidth != w) {
      sidebarWidth = w;
      notifyListeners();
    }
    if (!save) return;
    if (w == null) {
      prefs?.remove(_widthKey);
    } else {
      prefs?.write(_widthKey, '$w');
    }
  }

  /// A press on a rail icon: the open section folds the side panel away,
  /// any other section (or any icon while folded) opens that section.
  void pressRail(Section s) {
    if (s == section && !sidebarCollapsed) {
      setSidebarCollapsed(true);
    } else {
      setSection(s);
    }
  }

  /// Which section the side panel shows.
  Section section = Section.notes;

  void setSection(Section s) {
    setSidebarCollapsed(false);
    if (section == s) return;
    section = s;
    prefs?.write(_sectionKey, s.name);
    notifyListeners();
  }

  NoteSource source;

  /// The Spaces on this device; null when the app has just one fixed source.
  final SpaceCatalog? catalog;

  List<SpaceInfo> get spaces => catalog?.spaces ?? const [];
  String? get currentSpaceName => catalog?.currentInfo.name;
  String? get currentSpaceId => catalog?.current;

  /// Opens another Space: fresh selection and filters, its own notes.
  Future<void> switchSpace(String id) async {
    final c = catalog;
    if (c == null || id == c.current) return;
    c.select(id);
    source = c.sourceFor(id);
    notes = [];
    tree = NoteTree.build(const []);
    selectedUid = null;
    query = '';
    searchController.text = '';
    tag = null;
    syncMessage = null;
    syncing = false;
    _syncAgain = false;
    collapsed.clear();
    scopeUid = null;
    savedViews.clear();
    _loadViews();
    await load();
  }

  /// Creates a Space and opens it. With [onServer] (and an account) the
  /// collection is created on the server too; otherwise it stays local.
  Future<void> createSpace(String name, {bool onServer = false}) async {
    final c = catalog;
    if (c == null || name.trim().isEmpty) return;
    if (!(onServer && c.account != null)) {
      await switchSpace(c.add(name).id);
      return;
    }
    syncMessage = 'Creating on server…';
    notifyListeners();
    try {
      final info = await c.addOnServer(name);
      await switchSpace(info.id);
    } catch (e) {
      syncMessage = 'Could not create on server: $e';
      notifyListeners();
    }
  }

  /// The signed-in account's user name, if any.
  String? get accountUser => catalog?.account?.user;
  bool get canSignIn => catalog != null;

  /// Signs in at the account level and adds a Space per collection.
  Future<void> signIn(String user, String password) async {
    final c = catalog;
    if (c == null) return;
    syncMessage = 'Signing in…';
    notifyListeners();
    try {
      final n = await c.signIn(user.trim(), password);
      syncMessage = n == 0
          ? 'Signed in; no new collections'
          : 'Signed in; added $n space${n == 1 ? '' : 's'}';
      // The open Space may just have been linked to the server.
      final src = source;
      if (src is SpaceNoteSource &&
          c.currentInfo.onServer &&
          src.account == null) {
        source = c.sourceFor(c.current);
        notifyListeners();
        await load();
      }
    } catch (e) {
      syncMessage = 'Could not sign in: $e';
    }
    notifyListeners();
  }

  /// Picks up collections created elsewhere since sign-in.
  Future<void> refreshSpaces() async {
    final c = catalog;
    if (c == null || c.account == null) return;
    try {
      final n = await c.refresh();
      syncMessage = n == 0 ? 'No new collections' : 'Added $n';
    } catch (e) {
      syncMessage = 'Could not refresh: $e';
    }
    notifyListeners();
  }

  /// Signs out. Account Spaces stay here as local copies.
  Future<void> signOut() async {
    final c = catalog;
    if (c == null || c.account == null) return;
    c.signOut();
    source = c.sourceFor(c.current);
    syncMessage = null;
    syncing = false;
    _syncAgain = false;
    await load();
  }

  /// Whether the open Space belongs to the account (its notes sync).
  bool get currentOnServer => catalog?.currentInfo.onServer ?? false;

  /// Renames the open Space (on the server too for an account Space).
  /// Returns null when done, else why not.
  Future<String?> renameSpace(String name) async {
    final c = catalog;
    if (c == null) return 'No spaces here';
    final err = await c.renameSpace(c.current, name);
    if (err == null) notifyListeners();
    return err;
  }

  /// Deletes the open Space (never Planning) and opens Planning.
  Future<void> deleteSpace() async {
    final c = catalog;
    if (c == null || c.current == SpaceCatalog.planningId) return;
    final id = c.current;
    final viewsKey = _viewsKeyNow;
    // Open Planning first so nothing writes to the doomed Space afterwards.
    await switchSpace(SpaceCatalog.planningId);
    prefs?.remove(viewsKey);
    c.remove(id);
    notifyListeners();
  }

  /// Notes in any Space whose title or text contain [q] (case-insensitive).
  Future<List<SpaceHit>> searchAllSpaces(String q) async {
    final needle = q.trim().toLowerCase();
    final c = catalog;
    if (needle.isEmpty || c == null) return const [];
    final hits = <SpaceHit>[];
    final cur = c.current; // snapshot: the user may switch while we search
    final curNotes = List.of(notes);
    for (final sp in List.of(c.spaces)) {
      List<Note> list;
      if (sp.id == cur) {
        list = curNotes;
      } else {
        try {
          list = await c.sourceFor(sp.id).load();
        } catch (_) {
          continue; // one unreadable Space should not hide the others
        }
      }
      for (final n in list) {
        if (n.summary.toLowerCase().contains(needle) ||
            n.description.toLowerCase().contains(needle)) {
          hits.add(SpaceHit(sp, n));
        }
      }
    }
    return hits;
  }

  /// Opens a search hit: switches to its Space and selects the note.
  Future<void> openHit(SpaceHit h) async {
    if (catalog?.spaces.any((s) => s.id == h.space.id) != true) return;
    await switchSpace(h.space.id);
    select(h.note.uid);
  }

  /// Where saved views are kept; null means they last only this session.
  final KeyValueStorage? prefs;
  static const _viewsKey = 'davdart.views.v1';
  final List<SavedView> savedViews = [];

  String get _viewsKeyNow {
    final id = catalog?.current;
    return id == null || id == SpaceCatalog.planningId
        ? _viewsKey
        : '$_viewsKey.$id';
  }

  void _loadViews() {
    try {
      final raw = prefs?.read(_viewsKeyNow);
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
    _viewsKeyNow,
    jsonEncode([for (final v in savedViews) v.toJson()]),
  );

  /// Backs the sidebar search box so applying a saved view shows its text.
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

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
    searchController.text = v.query;
    tag = v.tag != null && notes.any((n) => n.categories.contains(v.tag))
        ? v.tag
        : null;
    selectedUid = null;
    scopeUid = null;
    notifyListeners();
  }

  void deleteView(String name) {
    savedViews.removeWhere((v) => v.name == name);
    _storeViews();
    notifyListeners();
  }

  List<Note> notes = [];
  NoteTree tree = NoteTree.build(const []);

  void _setNotes(List<Note> loaded) {
    notes = loaded;
    tree = NoteTree.build(notes);
    if (scopeUid != null && tree.find(scopeUid!) == null) scopeUid = null;
  }

  /// Notes with this tag are folders: containers that may carry text (for
  /// example instructions for an agent). The `kind-` prefix is hidden from
  /// the tag list, like `status-`.
  static const folderTag = 'kind-folder';
  static bool isFolder(Note n) => n.categories.contains(folderTag);

  /// The folder whose notes Board and List show; null means the whole Space.
  String? scopeUid;
  Note? get scope => scopeUid == null ? null : tree.find(scopeUid!)?.note;

  /// Shows only what is inside folder [uid] (null: the whole Space).
  void openFolder(String? uid) {
    scopeUid = uid;
    selectedUid = null;
    notifyListeners();
  }

  /// Moves note [uid] and everything under it to Space [targetId], at its
  /// top level. The notes are copied into the other Space first and removed
  /// here only after that worked, so a failure leaves a duplicate, never a
  /// loss. The copies get new ids; earlier versions stay behind. A server
  /// Space syncs the new notes the next time it is opened. Returns how many
  /// notes moved, or null with [error] set.
  Future<int?> moveToSpace(String uid, String targetId) async {
    final c = catalog;
    final src = source;
    final node = tree.find(uid);
    if (c == null || node == null || src is! EditableNoteSource) return null;
    if (targetId == c.current || !c.spaces.any((s) => s.id == targetId)) {
      return null;
    }
    final target = c.sourceFor(targetId);
    final group = [node.note, ...tree.descendants(uid)];
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final fresh = {
      for (var i = 0; i < group.length; i++) group[i].uid: 'davdart-$stamp-$i',
    };
    try {
      for (final n in group) {
        await target.save(
          Note(
            uid: fresh[n.uid]!,
            summary: n.summary,
            description: n.description,
            categories: List.of(n.categories),
            status: n.status,
            parentUid: n.uid == uid ? null : fresh[n.parentUid],
            created: n.created,
            lastModified: DateTime.now().toUtc(),
            extraLines: List.of(n.extraLines),
            propertyParams: Map.of(n.propertyParams),
          ),
        );
      }
      // Something may have changed the notes while they were being copied
      // (an edit, a sync). Keep the originals then; nothing is lost.
      final current = {for (final n in await src.load()) n.uid: n};
      for (final n in group) {
        final now = current[n.uid];
        if (now == null ||
            now.summary != n.summary ||
            now.description != n.description ||
            now.lastModified != n.lastModified ||
            now.parentUid != n.parentUid) {
          if (src == source) {
            error =
                'A note changed while moving. The copies are in the other '
                'space; the originals were kept.';
            notifyListeners();
          }
          return null;
        }
      }
      for (final n in group.reversed) {
        await src.delete(n.uid);
      }
      if (src != source) return group.length;
      final loaded = await src.load();
      if (src != source) return group.length;
      _setNotes(loaded);
      if (selectedUid != null && tree.find(selectedUid!) == null) {
        selectedUid = null;
      }
      error = null;
      notifyListeners();
      if (connected) sync();
      return group.length;
    } catch (e) {
      if (src == source) {
        // Some originals may already be gone: show what is really there.
        try {
          _setNotes(await src.load());
        } catch (_) {}
        error = 'Move failed: $e';
        notifyListeners();
      }
      return null;
    }
  }

  /// Adds a folder (a container note), optionally with text, and opens it.
  Future<void> addFolder(
    String title, {
    String? parentUid,
    String text = '',
  }) async {
    final t = title.trim();
    if (t.isEmpty) return;
    final now = DateTime.now().toUtc();
    final n = Note(
      uid: 'davdart-${now.microsecondsSinceEpoch}',
      summary: t,
      description: text.trim(),
      categories: [folderTag],
      parentUid: parentUid,
      created: now,
      lastModified: now,
    );
    await _save(n);
    if (error == null) openFolder(n.uid);
  }

  bool loading = false;
  String? error;

  String? selectedUid;
  ViewMode view = ViewMode.board;
  String query = '';
  String? tag;
  final Set<String> collapsed = {};

  Future<void> load() async {
    final src = source;
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (src is SpaceNoteSource && src.needsFirstConnect) {
        try {
          await src.connectAccount();
        } catch (e) {
          if (src != source) return;
          syncMessage = 'Could not reach the server: $e';
        }
      }
      final loaded = await src.load();
      if (src != source) return; // another Space was opened meanwhile
      _setNotes(loaded);
      if (tag != null && !notes.any((n) => n.categories.contains(tag))) {
        tag = null;
      }
    } catch (e) {
      if (src != source) return;
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

  /// Collections [user] can see on the server, for the Connect dialog.
  Future<List<FoundCollection>> discoverCollections(
    String user,
    String password,
  ) async => await _space?.discover(user.trim(), password) ?? const [];

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
      if (s != _space) return;
      syncing = false;
      syncMessage = 'Could not connect: $e';
      notifyListeners();
      return;
    }
    if (s != _space) return;
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
      if (s != _space) return;
      syncMessage = r == null
          ? null
          : r.errors.isNotEmpty
          ? 'Sync problem: ${r.errors.first}'
          : r.conflicts.isNotEmpty
          ? 'Synced; ${r.conflicts.length} overlapping edit(s) resolved, older text kept in history'
          : 'Synced ${_clock()}';
      final loaded = await s.load();
      if (s != _space) return;
      _setNotes(loaded);
    } catch (e) {
      if (s != _space) return;
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
      final loaded = await src.load();
      if (src != source) return;
      _setNotes(loaded);
      error = null;
    } catch (e) {
      if (src != source) return;
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
    bool setParent = false,
    String? parentUid,
  }) async {
    final n = tree.find(uid)?.note;
    if (n == null) return;
    final t = title?.trim();
    if (t != null && t.isEmpty) return;
    // A move that is no longer valid (the parent went away, or a sync put
    // the note under its own child) is dropped; the rest of the edit saves.
    final move = setParent && tree.canMove(uid, parentUid);
    final copy = n.copyWith(
      summary: t,
      parentUid: move ? parentUid : null,
      clearParent: move && parentUid == null,
    );
    final p = PlanItem.fromNote(copy);
    if (text != null) p.text = text;
    if (tags != null) {
      // Status tags are managed by the status menu, not here.
      copy.categories = [
        ...copy.categories.where(
          (c) => c.startsWith('status-') || c.startsWith('kind-'),
        ),
        ...tags.where(
          (c) =>
              c.isNotEmpty &&
              !c.startsWith('status-') &&
              !c.startsWith('kind-'),
        ),
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

  // --- Full page and in-place editing ---

  bool _fullPage = false;

  /// The selected note fills the main area (not persisted). Ends by itself
  /// when nothing is selected.
  bool get fullPage => _fullPage && selected != null;

  void openFullPage() {
    if (selected == null) return;
    _fullPage = true;
    notifyListeners();
  }

  void closeFullPage() {
    if (!_fullPage) return;
    _fullPage = false;
    notifyListeners();
  }

  /// The open edit session, if it belongs to the selected note.
  NoteDraft? draft;
  NoteDraft? get activeDraft =>
      draft != null && draft!.uid == selectedUid ? draft : null;
  bool get dirty => activeDraft?.dirty ?? false;

  /// Asks the user what to do with unsaved edits; set by the shell.
  Future<DraftChoice> Function()? leaveGuard;

  void startEdit() {
    final n = selected;
    if (n == null || !editable || activeDraft != null) return;
    _dropDraft();
    final p = PlanItem.fromNote(n);
    draft = NoteDraft(
      uid: n.uid,
      title: n.summary,
      body: p.text,
      tags: n.categories
          .where((c) => !c.startsWith('status-') && !c.startsWith('kind-'))
          .join(', '),
      originalParent: tree.find(n.uid)?.parent?.note.uid,
      originalStatus: boardOrder.contains(p.status) ? p.status : null,
    );
    notifyListeners();
  }

  void _dropDraft() {
    // The fields may still be on screen until the next frame, so the
    // controllers are left to the garbage collector, not disposed.
    draft = null;
  }

  void discardDraft() {
    _dropDraft();
    notifyListeners();
  }

  /// Saves the open edit through [updateNote] (and [setStatus] when the
  /// status changed). False if nothing was saved (empty title, failure).
  Future<bool> saveDraft() async {
    final d = activeDraft;
    if (d == null || d.titleEmpty) return false;
    await updateNote(
      d.uid,
      title: d.titleController.text,
      text: d.bodyController.text,
      tags: d.tagList,
      setParent: d.parent != d.originalParent,
      parentUid: d.parent,
    );
    if (error == null && d.status != null && d.status != d.originalStatus) {
      await setStatus(d.uid, d.status!);
    }
    if (error != null) return false;
    if (draft == d) _dropDraft();
    notifyListeners();
    return true;
  }

  /// Runs [action] (a navigation away from the note) once unsaved edits are
  /// settled: saved or discarded as the user chooses, or not run at all.
  Future<void> guarded(void Function() action) async {
    final g = leaveGuard;
    if (!dirty || g == null) {
      action();
      return;
    }
    switch (await g()) {
      case DraftChoice.keep:
        return;
      case DraftChoice.save:
        if (!await saveDraft()) return;
      case DraftChoice.discard:
        _dropDraft();
    }
    action();
  }

  Note? get selected =>
      selectedUid == null ? null : tree.find(selectedUid!)?.note;

  void select(String? uid) {
    // Showing a note outside the open folder leaves the folder.
    if (uid != null &&
        scopeUid != null &&
        uid != scopeUid &&
        !tree.descendants(scopeUid!).any((n) => n.uid == uid)) {
      scopeUid = null;
    }
    selectedUid = uid;
    if (draft != null && draft!.uid != uid) _dropDraft();
    notifyListeners();
  }

  void setView(ViewMode v) {
    view = v;
    _fullPage = false;
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
        if (!c.startsWith('status-') && !c.startsWith('kind-')) c,
  }.toList()..sort());

  bool matches(Note n) {
    if (tag != null && !n.categories.contains(tag)) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return n.summary.toLowerCase().contains(q) ||
        n.description.toLowerCase().contains(q);
  }

  /// Notes after search and tag filters.
  List<Note> get filtered {
    final inScope = scopeUid == null
        ? null
        : {for (final n in tree.descendants(scopeUid!)) n.uid};
    return [
      for (final n in notes)
        if (!isFolder(n) &&
            (inScope == null || inScope.contains(n.uid)) &&
            matches(n))
          n,
    ]..sort(NoteTree.byCreated);
  }

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
