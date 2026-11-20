import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;

import '../data/key_value_storage.dart';
import '../data/note_source.dart';
import '../data/space_catalog.dart';
import 'note_draft.dart';
import 'tab_state.dart';

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

/// A named combination of view, search text, tag filter and folder scope.
/// Stored as a `kind-view` note in the Space, so it syncs; the stored format
/// is documented on [SavedViewSpec] in the core.
class SavedView {
  SavedView(
    this.name,
    this.view,
    this.query,
    this.tags, {
    this.folderUid,
    this.uid = '',
  });
  final String name;
  final ViewMode view;
  final String query;

  /// The tags the view filters by (the app filters by one at a time).
  final List<String> tags;

  /// The folder the view is scoped to; null means the whole Space.
  final String? folderUid;

  /// The uid of the note that stores the view.
  final String uid;

  String? get tag => tags.isEmpty ? null : tags.first;

  SavedViewSpec toSpec() => SavedViewSpec(
    uid: uid,
    name: name,
    mode: view.name,
    search: query,
    tags: tags,
    folderUid: folderUid,
  );

  /// The note that stores this view.
  Note toNote() => toSpec().toNote();

  /// Reads a `kind-view` note; null for any other note.
  static SavedView? fromNote(Note n) {
    final s = SavedViewSpec.fromNote(n);
    if (s == null) return null;
    return SavedView(
      s.name,
      s.mode == 'list' ? ViewMode.list : ViewMode.board,
      s.search,
      s.tags,
      folderUid: s.folderUid,
      uid: s.uid,
    );
  }

  /// Reads a view from the old local-prefs form (name, view, query, tag).
  static SavedView? fromLegacyJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return SavedView(
      name.trim(),
      ViewMode.values.firstWhere(
        (v) => v.name == j['view'],
        orElse: () => ViewMode.board,
      ),
      j['query'] is String ? j['query'] as String : '',
      [if (j['tag'] is String && (j['tag'] as String).isNotEmpty) j['tag']],
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

/// Where a plain click on a note opens it: the side peek or the main area.
enum OpenMode { peek, main }

class AppState extends ChangeNotifier {
  AppState(this.source, {this.prefs, this.catalog}) {
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
    openMode = prefs?.read(_openModeKey) == OpenMode.main.name
        ? OpenMode.main
        : OpenMode.peek;
  }

  static const _openModeKey = 'davdart.open.mode.v1';

  /// The setting "Open notes in": what a plain click on a note does in the
  /// tree, lists, board, search and saved-view results. The context menu
  /// offers both whatever this says.
  OpenMode openMode = OpenMode.peek;

  void setOpenMode(OpenMode m) {
    if (openMode == m) return;
    openMode = m;
    if (m == OpenMode.peek) {
      prefs?.remove(_openModeKey);
    } else {
      prefs?.write(_openModeKey, m.name);
    }
    notifyListeners();
  }

  /// Opens note [uid] in [mode] (default: the setting). The peek asks about
  /// unsaved edits only when its own draft would be lost; focusing a note
  /// that already has a main tab never asks.
  /// Returns false when nothing opened (unknown note, or the user chose to
  /// keep editing the peek draft).
  Future<bool> openNote(String uid, {OpenMode? mode}) async {
    if (tree.find(uid) == null) return false;
    if ((mode ?? openMode) == OpenMode.main) {
      openNoteTab(uid);
    } else if (_tabs.contains(DocTab.note(uid)) || peekUid == uid) {
      select(uid);
    } else {
      var done = false;
      await guarded(() {
        select(uid);
        done = true;
      });
      return done;
    }
    return true;
  }

  String? _clickUid;
  String? _clickSurface;
  DateTime? _clickAt;

  /// A plain click on a note entry: opens it per [openMode], and a second
  /// click on the same note within [doubleClickWindow] promotes it to main.
  Future<void> clickNote(String uid) {
    final now = DateTime.now();
    final dbl =
        _clickUid == uid &&
        _clickSurface == 'entry' &&
        _clickAt != null &&
        now.difference(_clickAt!) < doubleClickWindow;
    _clickUid = dbl ? null : uid;
    _clickSurface = 'entry';
    _clickAt = dbl ? null : now;
    return dbl ? Future.sync(() => openNoteTab(uid)) : openNote(uid);
  }

  /// Registers a click on a note that is already open (the peek tab) and
  /// promotes it when it is a double click.
  void clickOpenNote(String uid) {
    if (uid.isEmpty) return;
    final now = DateTime.now();
    final dbl =
        _clickUid == uid &&
        _clickSurface == 'peek' &&
        _clickAt != null &&
        now.difference(_clickAt!) < doubleClickWindow;
    _clickUid = dbl ? null : uid;
    _clickSurface = 'peek';
    _clickAt = dbl ? null : now;
    if (dbl) openNoteTab(uid);
  }

  static const doubleClickWindow = Duration(milliseconds: 400);

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
  String? get currentSpaceName => catalog?.currentInfo?.name;
  String? get currentSpaceId => catalog?.current;

  /// True when there is a catalog but no Space in it (a new install, or
  /// every Space deleted): the app shows the first-run screen.
  bool get noSpace => catalog != null && catalog!.current == null;

  /// Opens another Space: fresh selection and filters, its own notes.
  /// Returns false when it stayed put (same Space, or the user chose to keep
  /// editing unsaved changes).
  Future<bool> switchSpace(String id) async {
    final c = catalog;
    if (c == null || id == c.current) return false;
    if (!c.spaces.any((s) => s.id == id)) return false;
    if (!await _settleDrafts(_drafts.keys.toList())) return false;
    _drafts.clear();
    c.select(id);
    await _openCurrent();
    return true;
  }

  /// Resets the view state and loads the catalog's current Space (or the
  /// empty source when there is none).
  Future<void> _openCurrent() async {
    final c = catalog!;
    final id = c.current;
    source = id == null ? const EmptyNoteSource() : c.sourceFor(id);
    notes = [];
    tree = NoteTree.build(const []);
    peekUid = null;
    query = '';
    searchController.text = '';
    tag = null;
    syncMessage = null;
    syncing = false;
    _syncAgain = false;
    collapsed.clear();
    _tagsOpen = false;
    scopeUid = null;
    savedViews.clear();
    _resetTabs();
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
      if (src is EmptyNoteSource && c.current != null) {
        await _openCurrent(); // the first Space came with the account
      } else if (src is SpaceNoteSource &&
          c.currentInfo?.onServer == true &&
          src.account == null) {
        source = c.sourceFor(c.current!);
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
    final cur = c.current;
    source = cur == null ? const EmptyNoteSource() : c.sourceFor(cur);
    syncMessage = null;
    syncing = false;
    _syncAgain = false;
    await load();
  }

  /// Whether the open Space belongs to the account (its notes sync).
  bool get currentOnServer => catalog?.currentInfo?.onServer ?? false;

  /// Renames the open Space (on the server too for an account Space).
  /// Returns null when done, else why not.
  Future<String?> renameSpace(String name) async {
    final c = catalog;
    final id = c?.current;
    if (c == null || id == null) return 'No spaces here';
    final err = await c.renameSpace(id, name);
    if (err == null) notifyListeners();
    return err;
  }

  /// What deleting the open Space would lose beyond this device's copy:
  /// notes with unsaved edits plus notes not yet synced to the server.
  Future<int> unsyncedInCurrent() async {
    final src = source;
    final synced = src is SpaceNoteSource ? await src.unsyncedCount() : 0;
    return _drafts.keys.where(dirtyFor).length + synced;
  }

  /// Deletes the open Space from this device only (server notes are never
  /// touched). The nearest remaining Space opens, or the first-run screen
  /// shows when none is left.
  Future<void> deleteSpace() async {
    final c = catalog;
    final id = c?.current;
    if (c == null || id == null) return;
    final viewsKey = _viewsKeyNow;
    // Open the neighbour first so nothing writes to the doomed Space after.
    final next = c.neighbourOf(id);
    if (next != null) {
      if (!await switchSpace(next)) return;
    } else {
      if (!await _settleDrafts(_drafts.keys.toList())) return;
      _drafts.clear();
    }
    prefs?.remove(viewsKey);
    prefs?.remove('$viewsKey.migrated');
    prefs?.remove('davdart.tabs.v1.$id');
    prefs?.remove('davdart.folders.collapsed.v1.$id');
    prefs?.remove('davdart.tags.open.v1.$id');
    c.remove(id);
    if (next == null) await _openCurrent();
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
        if (isViewNote(n)) continue;
        if (n.summary.toLowerCase().contains(needle) ||
            n.description.toLowerCase().contains(needle)) {
          hits.add(SpaceHit(sp, n));
        }
      }
    }
    return hits;
  }

  /// Opens a search hit: switches to its Space and selects the note.
  Future<void> openHit(SpaceHit h, {OpenMode? mode}) async {
    if (catalog?.spaces.any((s) => s.id == h.space.id) != true) return;
    final sameSpace = h.space.id == currentSpaceId;
    if (sameSpace) {
      await openNote(h.note.uid, mode: mode);
      return;
    }
    if (!await switchSpace(h.space.id)) return;
    await openNote(h.note.uid, mode: mode);
  }

  /// Where the old local saved views (and the done-marker of their one-time
  /// move into notes) are kept.
  final KeyValueStorage? prefs;
  static const _viewsKey = 'davdart.views.v1';

  /// The saved views of the open Space, read from its `kind-view` notes.
  final List<SavedView> savedViews = [];

  String get _viewsKeyNow {
    final id = catalog?.current;
    return id == null || id == SpaceCatalog.planningId
        ? _viewsKey
        : '$_viewsKey.$id';
  }

  /// Moves the views of the old prefs key into notes, once per Space, when
  /// the source is writable. The old key stays until every view is saved,
  /// then a marker says it is done, so nothing is duplicated (a view whose
  /// name already exists as a note is skipped, which also covers a retry
  /// after a partly failed run).
  Future<void> _migrateViews(EditableNoteSource src) async {
    final p = prefs;
    if (p == null) return;
    final key = _viewsKeyNow;
    final done = '$key.migrated';
    if (p.read(done) == '1') return;
    final raw = p.read(key);
    final old = <SavedView>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final j in jsonDecode(raw) as List<dynamic>) {
          final v = SavedView.fromLegacyJson(j);
          if (v != null) old.add(v);
        }
      } catch (_) {
        // Unreadable old data: nothing to move; mark done below.
      }
    }
    final have = {for (final v in savedViews) v.name};
    var stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    for (final v in old) {
      if (!have.add(v.name)) continue;
      await src.save(
        SavedView(
          v.name,
          v.view,
          v.query,
          v.tags,
          uid: 'davdart-view-${stamp++}',
        ).toNote(),
      );
    }
    p.write(done, '1');
  }

  /// Backs the sidebar search box so applying a saved view shows its text.
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  bool get hasFilter =>
      query.trim().isNotEmpty || tag != null || scopeUid != null;

  SavedView _current(String name, {String uid = ''}) => SavedView(
    name,
    view,
    query.trim(),
    [?tag],
    folderUid: scopeUid,
    uid: uid,
  );

  SavedView? _viewNamed(String name) {
    for (final v in savedViews) {
      if (v.name == name) return v;
    }
    return null;
  }

  /// Saves the current view, search, tag and folder under [name]; a view
  /// with that name is updated instead.
  Future<void> saveView(String name) async {
    final n = name.trim();
    if (n.isEmpty || !_canEditViews()) return;
    final old = _viewNamed(n);
    if (old != null) return updateView(old);
    final uid = 'davdart-view-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    await _save(_current(n, uid: uid).toNote());
  }

  /// Re-saves the current state into [v] (name unchanged).
  Future<void> updateView(SavedView v) async {
    if (!_canEditViews()) return;
    final note = _viewNotes[v.uid];
    if (note == null) return;
    await _save(_current(v.name, uid: v.uid).toSpec().writeTo(note.copyWith()));
  }

  /// Renames [v]. Returns null when done, else why not.
  Future<String?> renameView(SavedView v, String name) async {
    final n = name.trim();
    if (n.isEmpty) return 'Give the view a name';
    if (n == v.name) return null;
    if (_viewNamed(n) != null) return 'A view with that name exists';
    if (!_canEditViews()) return 'This source is read-only';
    final note = _viewNotes[v.uid];
    if (note == null) return 'View not found';
    final spec = SavedView.fromNote(note)!.toSpec();
    final renamed = SavedViewSpec(
      uid: spec.uid,
      name: n,
      mode: spec.mode,
      search: spec.search,
      tags: spec.tags,
      folderUid: spec.folderUid,
    );
    await _save(renamed.writeTo(note.copyWith()));
    return error;
  }

  final Map<String, Note> _viewNotes = {};

  bool _canEditViews() {
    if (editable) return true;
    error = 'Save failed: this source is read-only';
    notifyListeners();
    return false;
  }

  /// Shows what [v] saved, including its folder (if it still exists).
  void applyView(SavedView v) {
    view = v.view;
    query = v.query;
    searchController.text = v.query;
    tag = v.tags.cast<String?>().firstWhere(
      (t) => notes.any((n) => n.categories.contains(t)),
      orElse: () => null,
    );
    scopeUid = v.folderUid != null && tree.find(v.folderUid!) != null
        ? v.folderUid
        : null;
    if (v.uid.isNotEmpty) {
      final t = DocTab.view(v.uid);
      _tabs.add(t);
      _activeViewTab = t;
      _saveTabs();
    }
    notifyListeners();
  }

  Future<void> deleteView(String name) async {
    final v = _viewNamed(name);
    if (v == null || !_canEditViews()) return;
    await _edit((src) => src.delete(v.uid));
  }

  List<Note> notes = [];
  NoteTree tree = NoteTree.build(const []);

  void _setNotes(List<Note> loaded) {
    // Saved views are notes too, but they are not content: keep them out of
    // the tree, lists and search.
    notes = [
      for (final n in loaded)
        if (!isViewNote(n)) n,
    ];
    _viewNotes
      ..clear()
      ..addEntries([
        for (final n in loaded)
          if (isViewNote(n)) MapEntry(n.uid, n),
      ]);
    savedViews
      ..clear()
      ..addAll(
        [
          for (final n in loaded) ?SavedView.fromNote(n),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );
    tree = NoteTree.build(notes);
    if (scopeUid != null && tree.find(scopeUid!) == null) scopeUid = null;
    if (_tabsLoaded) _pruneTabs();
    if (peekUid != null && tree.find(peekUid!) == null) peekUid = null;
    if (peekUid == null) peekCollapsed = false;
    _drafts.removeWhere((u, _) => tree.find(u) == null);
  }

  /// Notes with this tag are folders: containers that may carry text (for
  /// example instructions for an agent). The `kind-` prefix is hidden from
  /// the tag list, like `status-`.
  static const folderTag = 'kind-folder';
  static bool isFolder(Note n) => isFolderNote(n);

  /// The folder whose notes Board and List show; null means the whole Space.
  String? scopeUid;
  Note? get scope => scopeUid == null ? null : tree.find(scopeUid!)?.note;

  /// Shows only what is inside folder [uid] (null: the whole Space).
  void openFolder(String? uid) {
    scopeUid = uid;
    final a = _activeViewTab;
    if (a != null && a.kind == TabKind.note) _activeViewTab = null;
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
    // Unsaved edits would be lost with the old notes: settle them first.
    if (!await _settleDrafts([for (final n in group) n.uid])) return null;
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
      if (peekUid != null && tree.find(peekUid!) == null) {
        _setPeek(null);
      }
      _drafts.removeWhere((u, _) => tree.find(u) == null);
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

  /// The note shown in the side peek panel: a single slot, never a tab.
  /// Board and List clicks replace it; [promote] moves it to the main area.
  String? peekUid;

  /// The peek is folded away but keeps its note; expanding shows it again.
  bool peekCollapsed = false;

  void setPeekCollapsed(bool v) {
    if (peekCollapsed == v) return;
    peekCollapsed = v;
    notifyListeners();
  }

  /// Sets the peek note. A dropped peek note loses its edit draft unless the
  /// note is also a main tab (one place per note, so the draft is shared).
  void _setPeek(String? uid) {
    final old = peekUid;
    peekUid = uid;
    if (uid != null) peekCollapsed = false;
    if (old != null && old != uid && !_tabs.contains(DocTab.note(old))) {
      _drafts.remove(old);
    }
  }

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
      var loaded = await src.load();
      if (src != source) return; // another Space was opened meanwhile
      _setNotes(loaded);
      if (src is EditableNoteSource) {
        try {
          await _migrateViews(src);
          if (src != source) return;
          loaded = await src.load();
          if (src != source) return;
          _setNotes(loaded);
        } catch (_) {
          // The old views stay in prefs; the next load tries again.
        }
      }
      if (tag != null && !notes.any((n) => n.categories.contains(tag))) {
        tag = null;
      }
      _restoreCollapsed();
      _tagsOpen = prefs?.read(_tagsOpenKey) == 'true';
      _restoreTabs();
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
  /// A null [status] clears it (removes the status line and tag).
  Future<void> setStatus(String uid, String? status) async {
    final n = tree.find(uid)?.note;
    if (n == null) return;
    final copy = n.copyWith();
    final p = PlanItem.fromNote(copy);
    if (status == null) {
      p.clearStatus();
    } else {
      p.setStatus(status);
    }
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

  /// Moves note [uid] under [parentUid] (null: the top level). Returns false,
  /// changing nothing, when the Space is read-only, the note is already
  /// there, or the move would put it inside itself or one of its descendants.
  Future<bool> moveNote(String uid, String? parentUid) async {
    final node = tree.find(uid);
    if (node == null || !editable) return false;
    if (node.parent?.note.uid == parentUid) return false;
    if (!tree.canMove(uid, parentUid)) return false;
    error = null;
    await updateNote(uid, setParent: true, parentUid: parentUid);
    return error == null;
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
    if (error == null) {
      _drafts.remove(uid);
      if (peekUid == uid) _setPeek(null);
    }
    notifyListeners();
  }

  /// Adds a note (a child of [parentUid] if given) and selects it.
  Future<void> addNote(
    String title, {
    String? parentUid,
    String? status,
    bool inTab = false,
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
    if (error == null) {
      if (inTab) {
        openNoteTab(n.uid);
      } else {
        await guarded(() => select(n.uid));
      }
    }
  }

  // --- Document tabs ---
  //
  // Two independent places show notes. The MAIN area is a layout of panes,
  // each showing one tab (one pane for now, so a split can be added without
  // reshaping this): the fixed home tab (the Board or List) or a closable tab
  // per note opened full page or saved view applied. The PEEK is a single
  // side slot ([peekUid]): Board, List and tree clicks replace it, and
  // [promote] moves it to the main area as a note tab. A note lives in one
  // place at a time: peeking a note that has a tab focuses the tab instead.
  // Open tabs are saved per Space (by uid).

  final TabList _tabs = TabList();
  DocTab? _activeViewTab; // the main pane's tab; null is home
  bool _tabsLoaded = false;

  /// The open document tabs in strip order (the home tab is not in it).
  List<DocTab> get tabs => List.unmodifiable(_tabs.tabs);

  /// The main pane's tab; null means the home tab.
  DocTab? get activeTab {
    final v = _activeViewTab;
    return v != null && _tabs.contains(v) ? v : null;
  }

  /// The name of the saved view the main pane shows, if its tab is one.
  String? get activeViewName {
    final t = activeTab;
    return t != null && t.kind == TabKind.view ? _viewByUid(t.id)?.name : null;
  }

  /// The note the main pane shows full page, when its tab is a note tab.
  String? get mainNoteUid {
    final t = activeTab;
    return t != null && t.kind == TabKind.note && tree.find(t.id) != null
        ? t.id
        : null;
  }

  String get _tabsKey => 'davdart.tabs.v1.${catalog?.current ?? 'default'}';

  void _saveTabs() {
    if (!_tabsLoaded) return;
    if (_tabs.tabs.isEmpty) {
      prefs?.remove(_tabsKey);
    } else {
      prefs?.write(_tabsKey, _tabs.encode());
    }
  }

  void _resetTabs() {
    _tabsLoaded = false;
    _tabs.tabs.clear();
    _activeViewTab = null;
    peekCollapsed = false;
  }

  bool _tabExists(DocTab t) => switch (t.kind) {
    TabKind.note => tree.find(t.id) != null,
    TabKind.view => _viewNotes.containsKey(t.id),
  };

  void _pruneTabs() {
    if (_tabs.retain(_tabExists)) _saveTabs();
    if (_activeViewTab != null && !_tabs.contains(_activeViewTab!)) {
      _activeViewTab = null;
    }
  }

  /// Brings back the tabs saved for this Space, dropping any whose note or
  /// view is gone. Home is always the focused tab after a restore.
  void _restoreTabs() {
    _tabs.decode(prefs?.read(_tabsKey));
    _tabsLoaded = true;
    _pruneTabs();
    _saveTabs();
  }

  /// Opens (or focuses) the main tab of note [uid]. A peek of the same note
  /// closes (one place per note). The "+" button's new note opens this way.
  void openNoteTab(String uid) {
    if (tree.find(uid) == null) return;
    final t = DocTab.note(uid);
    if (_tabs.add(t)) _saveTabs();
    _show(t);
  }

  /// Moves the peek note ([uid] by default) to the main area as a note tab
  /// and shows it there. The peek empties; the note's edit draft goes along.
  void promote([String? uid]) {
    uid ??= peekUid;
    if (uid == null || tree.find(uid) == null) return;
    openNoteTab(uid);
  }

  /// Moves open tab [t] to index [to] of the strip (clamped) and saves.
  void moveTab(DocTab t, int to) {
    if (_tabs.move(t, to)) {
      _saveTabs();
      notifyListeners();
    }
  }

  /// Title of a tab: the note's title or the view's name.
  String tabTitle(DocTab t) => switch (t.kind) {
    TabKind.note => tree.find(t.id)?.note.summary ?? '',
    TabKind.view => _viewByUid(t.id)?.name ?? '',
  };

  bool tabIsFolder(DocTab t) =>
      t.kind == TabKind.note &&
      tree.find(t.id) != null &&
      isFolder(tree.find(t.id)!.note);

  /// Whether the tab's note has unsaved edits.
  bool tabDirty(DocTab t) => t.kind == TabKind.note && dirtyFor(t.id);

  SavedView? _viewByUid(String uid) {
    for (final v in savedViews) {
      if (v.uid == uid) return v;
    }
    return null;
  }

  /// Shows [t] (null: home) in the main pane without asking about edits.
  void _show(DocTab? t) {
    if (t == null) {
      _activeViewTab = null;
      notifyListeners();
    } else if (t.kind == TabKind.note) {
      if (tree.find(t.id) == null) return;
      _activeViewTab = t;
      if (peekUid == t.id) _setPeek(null);
      notifyListeners();
    } else {
      final v = _viewByUid(t.id);
      if (v != null) applyView(v);
    }
  }

  /// Focuses [t] (null: the home tab). Every note keeps its own draft and the
  /// peek is independent of the main area, so this never asks or closes it.
  Future<void> activateTab(DocTab? t) {
    if (t == activeTab) return Future.value();
    _show(t);
    return Future.value();
  }

  /// Closes [t]. Unsaved edits in its note are asked about first. If it was
  /// focused, its right neighbour (else left, else home) takes over.
  Future<void> closeTab(DocTab t) {
    if (!_tabs.contains(t)) return Future.value();
    void close() {
      final wasActive = activeTab == t;
      final next = _tabs.remove(t);
      if (_activeViewTab == t) _activeViewTab = null;
      if (t.kind == TabKind.note && peekUid != t.id) _drafts.remove(t.id);
      _saveTabs();
      if (wasActive) _show(next);
      notifyListeners();
    }

    return tabDirty(t) ? guarded(close, uids: [t.id]) : Future.sync(close);
  }

  /// Closes every document tab except [keep] (which takes focus first).
  /// Tabs with unsaved edits are asked about one by one.
  Future<void> closeOtherTabs(DocTab keep) async {
    if (!_tabs.contains(keep)) return;
    await activateTab(keep);
    for (final t in List<DocTab>.of(_tabs.tabs)) {
      if (t != keep) await closeTab(t);
    }
  }

  /// Closes every document tab, stopping when the unsaved-changes prompt
  /// cancels one (the tab stays open).
  Future<void> closeAllTabs() async {
    for (final t in List<DocTab>.of(_tabs.tabs)) {
      await closeTab(t);
      if (_tabs.contains(t)) return;
    }
  }

  /// Closes the document tabs to the right of [of] in the strip.
  Future<void> closeTabsToRight(DocTab of) async {
    final i = _tabs.tabs.indexOf(of);
    if (i < 0) return;
    for (final t in List<DocTab>.of(_tabs.tabs.skip(i + 1))) {
      await closeTab(t);
    }
  }

  /// Closes the focused document tab (not the home tab).
  Future<void> closeActiveTab() async {
    final t = activeTab;
    if (t != null) await closeTab(t);
  }

  // --- In-place editing ---
  //
  // One draft per note, kept while the note is open anywhere, so the peek
  // and a main tab never hold two sessions of one note.

  final Map<String, NoteDraft> _drafts = {};

  /// Every open edit (the tab strip listens to them for its dirty dots).
  List<NoteDraft> get drafts => List.unmodifiable(_drafts.values);

  NoteDraft? draftFor(String uid) => _drafts[uid];
  bool dirtyFor(String uid) => _drafts[uid]?.dirty ?? false;

  /// The peek note's edit session, if any.
  NoteDraft? get draft => peekUid == null ? null : _drafts[peekUid];
  NoteDraft? get activeDraft => draft;
  bool get dirty => draft?.dirty ?? false;

  /// Asks the user what to do with unsaved edits; set by the shell.
  Future<DraftChoice> Function()? leaveGuard;

  /// Starts editing note [uid] (the peek note by default).
  void startEdit([String? uid]) {
    uid ??= peekUid;
    if (uid == null) return;
    final n = tree.find(uid)?.note;
    if (n == null || !editable || _drafts.containsKey(uid)) return;
    final p = PlanItem.fromNote(n);
    _drafts[uid] = NoteDraft(
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

  void discardDraft([String? uid]) {
    // The fields may still be on screen until the next frame, so the
    // controllers are left to the garbage collector, not disposed.
    _drafts.remove(uid ?? peekUid);
    notifyListeners();
  }

  /// Saves the edit of note [uid] (the peek note by default) through
  /// [updateNote] (and [setStatus] when the status changed). False if
  /// nothing was saved (empty title, failure).
  Future<bool> saveDraft([String? uid]) async {
    final key = uid ?? peekUid;
    final d = key == null ? null : _drafts[key];
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
    if (_drafts[key] == d) _drafts.remove(key);
    notifyListeners();
    return true;
  }

  /// Runs [action] once unsaved edits are settled: saved or discarded as the
  /// user chooses, or not run at all. Settles the drafts of [uids] (the peek
  /// note by default: navigating away from the peek).
  Future<void> guarded(void Function() action, {Iterable<String>? uids}) async {
    if (await _settleDrafts(uids ?? [?peekUid])) action();
  }

  /// True once the drafts of [uids] are settled (nothing to settle, saved,
  /// or discarded as the user chose); false when the user keeps editing.
  Future<bool> _settleDrafts(Iterable<String> uids) async {
    final g = leaveGuard;
    for (final u in uids) {
      if (!dirtyFor(u) || g == null) continue;
      switch (await g()) {
        case DraftChoice.keep:
          return false;
        case DraftChoice.save:
          if (!await saveDraft(u)) return false;
        case DraftChoice.discard:
          _drafts.remove(u);
      }
    }
    return true;
  }

  Note? get peek => peekUid == null ? null : tree.find(peekUid!)?.note;

  /// Shows note [uid] in the peek (null closes it). A note that has a main
  /// tab is focused there instead: it lives in one place.
  void select(String? uid) {
    if (uid != null && _tabs.contains(DocTab.note(uid))) {
      _show(DocTab.note(uid));
      return;
    }
    // Showing a note outside the open folder leaves the folder.
    if (uid != null &&
        scopeUid != null &&
        uid != scopeUid &&
        !tree.descendants(scopeUid!).any((n) => n.uid == uid)) {
      scopeUid = null;
    }
    _setPeek(uid);
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
    _saveCollapsed();
    notifyListeners();
  }

  String get _spaceKey => catalog?.current ?? 'default';
  String get _foldersKey => 'davdart.folders.collapsed.v1.$_spaceKey';
  String get _tagsOpenKey => 'davdart.tags.open.v1.$_spaceKey';

  void _saveCollapsed() {
    if (collapsed.isEmpty) {
      prefs?.remove(_foldersKey);
    } else {
      prefs?.write(_foldersKey, jsonEncode(collapsed.toList()));
    }
  }

  /// Brings back the folders this Space had collapsed, dropping uids that no
  /// longer exist. Nothing saved (or a corrupt value) means all expanded.
  void _restoreCollapsed() {
    collapsed.clear();
    final raw = prefs?.read(_foldersKey);
    if (raw == null) return;
    try {
      final v = jsonDecode(raw);
      if (v is! List) return;
      for (final u in v) {
        if (u is String && tree.find(u) != null) collapsed.add(u);
      }
      if (collapsed.length != v.length) _saveCollapsed();
    } catch (_) {
      // Corrupt value: ignored, the next toggle overwrites it.
    }
  }

  /// Whether the user left the Files tags list open in this Space.
  bool get tagsOpen => _tagsOpen;
  bool _tagsOpen = false;

  /// The tags list shows open while a tag filter is active, so the active
  /// tag stays visible.
  bool get tagsExpanded => tagsOpen || tag != null;

  void setTagsOpen(bool v) {
    _tagsOpen = v;
    if (v) {
      prefs?.write(_tagsOpenKey, 'true');
    } else {
      prefs?.remove(_tagsOpenKey);
    }
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

  /// Board columns in a stable order; notes with no status go last, and are
  /// left out when [includeNoStatus] is false (Home shows work items only).
  List<(String, List<Note>)> columns({bool includeNoStatus = true}) {
    final by = <String, List<Note>>{};
    for (final n in filtered) {
      final s = PlanItem.fromNote(n).status;
      if (s == null && !includeNoStatus) continue;
      (by[s ?? 'notes'] ??= []).add(n);
    }
    final keys = [
      ...boardOrder.where(by.containsKey),
      ...by.keys.where((k) => !boardOrder.contains(k) && k != 'notes'),
      if (by.containsKey('notes')) 'notes',
    ];
    return [for (final k in keys) (k, by[k]!)];
  }
}
