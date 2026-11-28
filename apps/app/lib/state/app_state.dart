import 'dart:async';
import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/widgets.dart' show TextEditingController;

import '../data/key_value_storage.dart';
import '../data/note_source.dart';
import '../data/space_catalog.dart';
import 'board_item.dart';
import 'chord_keymap.dart';
import 'key_nav.dart';
import 'note_draft.dart';
import 'tab_state.dart';
import 'event_draft.dart';
import 'event_rules.dart';
import 'task_draft.dart';
import 'task_rules.dart';
import 'uid.dart';

export 'board_item.dart' show BoardItem, HomeKind, compareBoardItems;

enum ViewMode { board, list }

/// The section the side panel shows, chosen with the icon rail.
/// `notes` is shown as "Notes"; the ids stay so saved selections still load.
/// Spaces leads the rail and Projects is the scope picker: neither is a
/// landing page, so neither opens on start.
enum Section {
  /// The Spaces list: switch, add and manage. On the rail in place of a popup.
  spaces,
  notes,
  tasks,
  events,
  projects,

  /// A project's own page (a placeholder for now); needs a project scope.
  overview,
  views,
  search,
  account,
  settings,
}

/// How the Notes panel lists the current scope: a plain list (the default)
/// or the folder tree.
enum NotesView { list, tree }

/// The tabs of a project's page, in switcher order.
enum ProjectTab { overview, board, notes, calendar }

/// The views of Home, in switcher order (the same shape as [ProjectTab]).
enum HomeView { overview, calendar }

/// The fixed status set, in board order.
const boardOrder = allowedStatuses;

/// The board column for notes (or tasks) whose status word is not in
/// [boardOrder]: nothing is rewritten, so nothing disappears.
const otherColumn = 'other';

/// The column a status word belongs in: itself when it is in the fixed set,
/// else [otherColumn].
String statusColumn(String status) =>
    boardOrder.contains(status) ? status : otherColumn;

String _clock() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(n.hour)}:${two(n.minute)}';
}

/// A named combination of view, search text, tag filter and folder scope.
/// Stored as a `kind-view` note in the Space, so it syncs; the stored format
/// is documented on [SavedViewSpec] in the core.
/// A board change Undo can revert: [label] names the item and the change.
/// A task's status-related fields, captured before a change so Undo can put
/// them back exactly (a plain status word would re-stamp COMPLETED/percent).
class _TaskStatusState {
  _TaskStatusState(Task t)
    : status = t.status,
      percentComplete = t.percentComplete,
      completed = t.completed,
      tags = [
        for (final c in t.categories)
          if (c.startsWith('status-')) c,
      ];
  final String? status;
  final int? percentComplete;
  final DateTime? completed;
  final List<String> tags;

  void applyTo(Task t) {
    t.status = status;
    t.percentComplete = percentComplete;
    t.completed = completed;
    t.categories
      ..removeWhere((c) => c.startsWith('status-'))
      ..addAll(tags);
  }
}

class BoardUndo {
  BoardUndo(this.label, this.undo);
  final String label;
  final Future<void> Function() undo;
}

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
  const SpaceHit(this.space, this.note, {this.task, this.event});

  /// A hit on a task: [note] is a stand-in carrying its uid, title, text and
  /// tags so code that only reads those keeps working; [task] is the real
  /// item.
  SpaceHit.forTask(this.space, Task t)
    : task = t,
      event = null,
      note = Note(
        uid: t.uid,
        summary: t.summary,
        description: t.description,
        categories: List.of(t.categories),
        parentUid: t.parentUid,
        created: t.created,
        lastModified: t.lastModified,
      );

  /// A hit on an event, built like [SpaceHit.forTask]: [event] is the real
  /// item.
  SpaceHit.forEvent(this.space, Event e)
    : event = e,
      task = null,
      note = Note(
        uid: e.uid,
        summary: e.summary,
        description: e.description,
        categories: List.of(e.categories),
        parentUid: e.parentUid,
        created: e.created,
        lastModified: e.lastModified,
      );
  final SpaceInfo space;
  final Note note;
  final Task? task;
  final Event? event;
  bool get isTask => task != null;
  bool get isEvent => event != null;
}

/// Which edge of the window the shell's icon rail sits on.
enum LayoutSide { start, end }

/// Where a plain click on a note opens it: the side peek or the main area.
enum OpenMode { peek, main }

/// Which tasks the Tasks view lists.
enum TaskFilter { open, all, completed }

class AppState extends ChangeNotifier {
  AppState(this.source, {this.prefs, this.catalog}) {
    // Home collapse prefs of headers that no longer exist.
    prefs?.remove('davdart.home.board.collapsed.v1');
    prefs?.remove('davdart.home.today.collapsed.v1');
    final saved = prefs?.read(_sectionKey);
    final savedSection = Section.values.firstWhere(
      (v) => v.name == saved,
      orElse: () => Section.notes,
    );
    section = _landing(savedSection);
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
    notesView = prefs?.read(_notesViewKey) == NotesView.tree.name
        ? NotesView.tree
        : NotesView.list;
    vimKeys = prefs?.read(_vimKeysKey) != 'false';
    vimEditor = prefs?.read(_vimEditorKey) != 'false';
    _readScopePrefs();
  }

  static const _vimKeysKey = 'davdart.vim.keys.v1';
  static const _vimEditorKey = 'davdart.vim.editor.v1';

  ChordKeymap? _chords;
  String? _chordsSig;

  /// The global chord keymap for the platform and the stored overrides
  /// (read once per platform change; see [ChordKeymap]).
  ChordKeymap get chords {
    final raw = prefs?.read(ChordKeymap.prefKey);
    final sig =
        '$defaultTargetPlatform|${ChordKeymap.debugIsWeb ?? kIsWeb}|$raw';
    if (_chords == null || _chordsSig != sig) {
      _chords = ChordKeymap.fromPref(raw);
      _chordsSig = sig;
    }
    return _chords!;
  }

  /// The setting "Vim keys" (default on): bare-letter keyboard bindings. Off
  /// leaves Ctrl/Cmd+K and the arrow keys and Enter in focused lists.
  bool vimKeys = true;

  void setVimKeys(bool v) {
    if (vimKeys == v) return;
    vimKeys = v;
    if (v) {
      prefs?.remove(_vimKeysKey);
    } else {
      prefs?.write(_vimKeysKey, 'false');
    }
    nav.clearPending();
    notifyListeners();
  }

  /// The setting "Vim editing" (default on): modal editing (Normal, Insert,
  /// Visual) in the long text fields of the note, task and event editors.
  /// Keyboard only: the touch layout never uses it. Off keeps the plain
  /// field and Esc leaving edit mode.
  bool vimEditor = true;

  void setVimEditor(bool v) {
    if (vimEditor == v) return;
    vimEditor = v;
    if (v) {
      prefs?.remove(_vimEditorKey);
    } else {
      prefs?.write(_vimEditorKey, 'false');
    }
    notifyListeners();
  }

  /// Keyboard focus and cursors (see [KeyNav]).
  final KeyNav nav = KeyNav();

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
    final isItem = _isTask(uid) || _isEvent(uid);
    if (tree.find(uid) == null && !isItem) return false;
    // Narrow (phone): there is no peek, every item opens full screen.
    if (narrow || (mode ?? openMode) == OpenMode.main) {
      _openTab(uid);
    } else if (_tabs.contains(_tabOf(uid)) || peekUid == uid) {
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

  /// The uid and name of the item [uid] sits inside: its parent note, folder,
  /// task or event, or null at the top level. A personal container is not a
  /// place to go back to, so it stands in as the top level.
  ({String uid, String label})? parentItemOf(String uid) {
    final item = findItem(uid);
    final parentUid = switch (item) {
      Note n => n.parentUid,
      Task t => t.parentUid,
      Event e => e.parentUid,
      _ => null,
    };
    if (parentUid == null) return null;
    final parent = findItem(parentUid);
    final label = switch (parent) {
      Note n => isPersonalContainer(n) ? null : n.summary,
      Task t => t.summary,
      Event e => e.summary,
      _ => null,
    };
    if (label == null) return null;
    return (uid: parentUid, label: label);
  }

  /// Opens the item [uid] sits inside where [uid] is shown: in the peek when
  /// the peek holds it, else in the main area.
  Future<void> openParentOf(String uid) async {
    final parent = parentItemOf(uid);
    if (parent == null) return;
    if (peekUid == uid) {
      select(parent.uid);
      return;
    }
    await openNote(parent.uid, mode: OpenMode.main);
  }

  /// What the item [uid] really sits in, as the "Belongs to" row reads: the
  /// parent task it is a sub-task of, else the project it belongs to, else its
  /// parent (a note or a folder outside every project), else 'Personal'.
  String belongsToOf(String uid) {
    final parent = parentItemOf(uid);
    final parentUid = parent?.uid;
    if (parent == null || parentUid == null) return 'Personal';
    if (_taskById(parentUid) != null) return parent.label;
    final project =
        projectIndex.projectOf(uid) ?? projectIndex.projectOf(parentUid);
    if (project != null) return project.summary;
    return parent.label;
  }

  /// Set by the shell: the narrow layout is showing. It has no peek pane, so
  /// opening an item always opens it as a main tab.
  bool narrow = false;

  /// Opens task [uid] like [openNote] (peek or main per the setting).
  Future<bool> openTask(String uid, {OpenMode? mode}) =>
      _isTask(uid) ? openNote(uid, mode: mode) : Future.value(false);

  /// A plain click on a task entry; same rules as [clickNote].
  Future<void> clickTask(String uid) => clickNote(uid);

  /// Opens event [uid] like [openNote] (peek or main per the setting).
  Future<bool> openEvent(String uid, {OpenMode? mode}) =>
      _isEvent(uid) ? openNote(uid, mode: mode) : Future.value(false);

  /// A plain click on an event entry; same rules as [clickNote].
  Future<void> clickEvent(String uid) => clickNote(uid);

  /// True when [uid] names a task (and no note).
  bool _isTask(String uid) => tree.find(uid) == null && _taskById(uid) != null;

  /// True when [uid] names an event (and no note or task).
  bool _isEvent(String uid) =>
      tree.find(uid) == null &&
      _taskById(uid) == null &&
      _eventById(uid) != null;

  DocTab _tabOf(String uid) => _isTask(uid)
      ? DocTab.task(uid)
      : _isEvent(uid)
      ? DocTab.event(uid)
      : DocTab.note(uid);

  void _openTab(String uid) => _isTask(uid)
      ? openTaskTab(uid)
      : _isEvent(uid)
      ? openEventTab(uid)
      : openNoteTab(uid);

  /// Ctrl or Cmd held during a click: the opposite of [openMode]; else null.
  OpenMode? get modifierOpenMode {
    final kb = HardwareKeyboard.instance;
    if (!kb.isControlPressed && !kb.isMetaPressed) return null;
    return openMode == OpenMode.peek ? OpenMode.main : OpenMode.peek;
  }

  String? _clickUid;
  String? _clickSurface;
  DateTime? _clickAt;

  /// A click on a note entry: opens it per [openMode] (the opposite with
  /// Ctrl or Cmd held), and a second
  /// click on the same note within [doubleClickWindow] promotes it to main.
  Future<void> clickNote(String uid) {
    final opposite = modifierOpenMode;
    if (opposite != null) {
      _clickUid = null;
      _clickAt = null;
      return openNote(uid, mode: opposite);
    }
    final now = DateTime.now();
    final dbl =
        _clickUid == uid &&
        _clickSurface == 'entry' &&
        _clickAt != null &&
        now.difference(_clickAt!) < doubleClickWindow;
    _clickUid = dbl ? null : uid;
    _clickSurface = 'entry';
    _clickAt = dbl ? null : now;
    return dbl ? Future.sync(() => _openTab(uid)) : openNote(uid);
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
    if (dbl) _openTab(uid);
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
    // The panel is gone: the keyboard focus it held moves to the main pane.
    if (v && nav.area == NavArea.panel) nav.focusArea(NavArea.main);
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
  /// The rail's Home entry is not a section: see [pressRailHome].
  void pressRail(Section s) {
    if (s == section && !sidebarCollapsed) {
      setSidebarCollapsed(true);
      notifyListeners();
    } else {
      // Only opening a section leaves Home; folding the panel does not.
      setSection(s);
    }
  }

  /// Which section the side panel shows.
  Section section = Section.notes;

  /// Whether the current Space's collection can hold what [s] lists.
  bool supportsSection(Section s) => switch (s) {
    Section.notes => supportsNotes,
    Section.tasks => supportsTasks,
    Section.events => supportsEvents,
    Section.projects => supportsNotes,
    // The old main-area Overview section is retired: projects open in tabs.
    Section.overview => false,
    _ => true,
  };

  /// Whether the open scope is a project or a folder inside one.
  bool get scopeInProject {
    final uid = scopeUid;
    return uid != null && projectIndex.projectOf(uid) != null;
  }

  /// True when the Space has a Projects container or any project folder.
  bool get hasProjects {
    final ix = projectIndex;
    return ix.projects().isNotEmpty || ix.containers().isNotEmpty;
  }

  /// The section to open on: the rail's pickers (Spaces, Projects) lead the
  /// rail but are not landing pages, so a saved one falls back to a list.
  Section _landing(Section s) =>
      s == Section.spaces || s == Section.projects || s == Section.overview
      ? _supportedSection(Section.notes)
      : s;

  /// [s], or the first list section the Space supports (Views when none).
  Section _supportedSection(Section s) {
    if (supportsSection(s)) return s;
    for (final o in const [Section.notes, Section.tasks, Section.events]) {
      if (supportsSection(o)) return o;
    }
    return Section.views;
  }

  /// [s] as the panel can show it: the section itself, or the first list
  /// section this Space (and scope) allows.
  Section resolveSection(Section s) => _supportedSection(s);

  void setSection(Section s) {
    s = _supportedSection(s);
    setSidebarCollapsed(false);
    if (section == s) {
      notifyListeners();
      return;
    }
    section = s;
    prefs?.write(_sectionKey, s.name);
    notifyListeners();
  }

  /// Shows the Home tab in the main area (the Home rail action and the
  /// palette entry). Home is personal, so it clears the project scope.
  void showHome() => _show(null);

  /// True when the main area shows Home: no document tab is focused.
  bool get atHome => activeTab == null;

  /// A press on the rail's Home entry: shows Home and folds the docked side
  /// panel away (the same persisted pref as folding a section), so Home takes
  /// the whole width. Only this press folds; reaching Home any other way (the
  /// tab strip, the palette, a 'Go to' action, a keyboard shortcut) leaves the
  /// panel exactly as it is.
  void pressRailHome() {
    showHome();
    setSidebarCollapsed(true);
  }

  /// After a Space switch: the Tasks and Events lists stay (the choice on
  /// the rail survives), any other section falls back to Notes (a project
  /// page too: the other Space's project scope is gone).
  void keepListSection() {
    if (section == Section.tasks ||
        section == Section.events ||
        section == Section.projects) {
      return;
    }
    // A Space switch keeps the main area where it was (Home stays Home); it
    // only moves a panel that cannot land in the new Space. Writing the
    // field directly is deliberate: setSection would also leave Home.
    final s = _supportedSection(Section.notes);
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
    if (!await _settleDrafts(_allDraftUids())) return false;
    _drafts.clear();
    _taskDrafts.clear();
    _eventDrafts.clear();
    c.select(id);
    nav.clearPending();
    await _openCurrent();
    return true;
  }

  /// Resets the view state and loads the catalog's current Space (or the
  /// empty source when there is none).
  Future<void> _openCurrent() async {
    final c = catalog!;
    final id = c.current;
    // An Undo belongs to the Space it was posted in.
    pendingUndo = null;
    // A new Space starts with its done columns capped again.
    nav.boardOpen.remove('done#all');
    source = id == null ? const EmptyNoteSource() : c.sourceFor(id);
    notes = [];
    tasks = [];
    taskError = null;
    events = [];
    eventError = null;
    selectedTaskUid = null;
    taskFilter = TaskFilter.open;
    taskTagFilter = null;
    eventTagFilter = null;
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
    _taskTagsOpen = false;
    _eventTagsOpen = false;
    scopeUid = null;
    savedViews.clear();
    homeDay = null;
    calendarSectionCollapsed = const {};
    _resetTabs();
    _restoreScopePending = true;
    await load();
  }

  /// Creates a Space and opens it. With [onServer] (and an account) the
  /// collection is created on the server too; otherwise it stays local.
  Future<void> createSpace(
    String name, {
    bool onServer = false,
    bool notes = true,
  }) async {
    final c = catalog;
    if (c == null || name.trim().isEmpty) return;
    if (!(onServer && c.account != null)) {
      await switchSpace(c.add(name).id);
      return;
    }
    syncMessage = 'Creating on server…';
    notifyListeners();
    try {
      final info = await c.addOnServer(name, notes: notes);
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
      final g = c.gone.length;
      syncMessage = [
        n == 0 ? 'No new collections' : 'Added $n',
        if (g > 0) '$g no longer on the server',
      ].join('; ');
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

  /// Renames Space [id] (default: the open one) without switching to it; on
  /// the server too for an account Space.
  /// Returns null when done, else why not.
  Future<String?> renameSpace(String name, {String? id}) async {
    final c = catalog;
    id ??= c?.current;
    if (c == null || id == null) return 'No spaces here';
    final err = await c.renameSpace(id, name);
    if (err == null) notifyListeners();
    return err;
  }

  /// What the server holds for the open account Space (its name there and
  /// item count); throws when it cannot be read.
  Future<({String name, int items})> serverCollectionOfCurrent() {
    final c = catalog, id = catalog?.current;
    if (c == null || id == null) throw StateError('No space open');
    return c.serverCollection(id);
  }

  /// Deletes the open account Space's collection from the server for
  /// everyone, then removes the Space here. Null when done, else the reason
  /// (the Space stays untouched).
  Future<String?> deleteCurrentFromServer({
    required String confirmName,
    bool keepBackup = true,
  }) async {
    final c = catalog, id = catalog?.current;
    if (c == null || id == null || !currentOnServer) return 'No account space';
    final err = await c.deleteOnServer(
      id,
      confirmName: confirmName,
      keepBackup: keepBackup,
    );
    if (err != null) return err;
    await deleteSpace();
    return null;
  }

  /// What deleting the open Space would lose beyond this device's copy:
  /// notes with unsaved edits plus notes not yet synced to the server.
  Future<int> unsyncedInCurrent() async {
    final src = source;
    final synced = src is SpaceNoteSource ? await src.unsyncedCount() : 0;
    return _drafts.keys.where(dirtyFor).length +
        _taskDrafts.keys.where(dirtyTaskFor).length +
        _eventDrafts.keys.where(dirtyEventFor).length +
        synced;
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
      if (!await _settleDrafts(_allDraftUids())) return;
      _drafts.clear();
      _taskDrafts.clear();
      _eventDrafts.clear();
    }
    prefs?.remove(viewsKey);
    prefs?.remove('$viewsKey.migrated');
    _removeSpacePrefs(id);
    // Its scope and recents go with it.
    if (_scopes.remove(id) != null) {
      prefs?.write(_scopeKey, jsonEncode(_scopes));
    }
    if (_recents.remove(id) != null) {
      prefs?.write(_recentsKey, jsonEncode(_recents));
    }
    c.remove(id);
    if (next == null) await _openCurrent();
    notifyListeners();
  }

  /// Per-Space pref keys are `<base>.<id>`; the Home card keys carry a slug
  /// before the id and the project tab keys a uid after it.
  static const _spacePrefBases = [
    'davdart.tabs.v1',
    'davdart.activetab.v1',
    'davdart.folders.collapsed.v1',
    'davdart.tags.open.v1',
    'davdart.tasktags.open.v1',
    'davdart.eventtags.open.v1',
    'davdart.home.focus.v1', // dropped feature, may linger
    'davdart.home.cal.open.v1',
    'davdart.home.kind.v1',
    'davdart.home.hidden.v1.board',
    'davdart.home.hidden.v1.tasks',
    'davdart.home.card.collapsed.v1.tasks',
    'davdart.home.card.collapsed.v1.events',
  ];

  /// Removes every pref saved for Space [id]. Matches exact keys, so a Space
  /// whose id merely starts with [id] and a dot keeps its own.
  void _removeSpacePrefs(String id) {
    final p = prefs;
    if (p == null) return;
    final lookalikes = [
      for (final o in catalog?.spaces ?? const <SpaceInfo>[])
        if (o.id != id && o.id.startsWith('$id.')) o.id,
    ];
    for (final k in p.keys.toList()) {
      if (!k.startsWith('davdart.')) continue;
      final exact = [for (final b in _spacePrefBases) '$b.$id'].contains(k);
      final projTab = 'davdart.proj.tab.v1.$id.';
      final isProjTab =
          k.startsWith(projTab) &&
          !lookalikes.any((o) => k.startsWith('davdart.proj.tab.v1.$o.'));
      if (exact || isProjTab) p.remove(k);
    }
  }

  /// Notes, tasks and events whose title or text contain [q]
  /// (case-insensitive), in the open Space only, or in every Space with
  /// [allSpaces] (tm 2026-11-25: Search is per Space for now). With
  /// [scopeUid] the open Space's matches are narrowed to that folder's
  /// subtree: notes inside it, tasks and events whose folder chain leads into
  /// it (loose ones are left out). Task hits have [SpaceHit.task] set, event
  /// hits [SpaceHit.event].
  Future<List<SpaceHit>> searchAllSpaces(
    String q, {
    bool allSpaces = false,
    String? scopeUid,
  }) async {
    final needle = q.trim().toLowerCase();
    final c = catalog;
    if (needle.isEmpty || c == null) return const [];
    final hits = <SpaceHit>[];
    final cur = c.current; // snapshot: the user may switch while we search
    final curNotes = List.of(notes);
    final curTasks = List.of(tasks);
    final curEvents = List.of(events);
    final scoped = scopeUid == null
        ? null
        : {for (final n in tree.descendants(scopeUid)) n.uid};
    for (final sp in List.of(c.spaces)) {
      if (!allSpaces && sp.id != cur) continue;
      List<Note> list = const [];
      List<Task> taskList = const [];
      List<Event> eventList = const [];
      if (sp.id == cur) {
        list = curNotes;
        taskList = curTasks;
        eventList = curEvents;
      } else {
        final other = c.sourceFor(sp.id);
        try {
          list = await other.load();
        } catch (_) {
          // one unreadable Space should not hide the others
        }
        try {
          taskList = await other.loadTasks();
        } catch (_) {
          // an unreadable task store never hides notes
        }
        try {
          eventList = await other.loadEvents();
        } catch (_) {
          // nor does an unreadable event store
        }
      }
      for (final n in list) {
        if (isViewNote(n)) continue;
        if (sp.id == cur && scoped != null && !scoped.contains(n.uid)) {
          continue;
        }
        if (n.summary.toLowerCase().contains(needle) ||
            n.description.toLowerCase().contains(needle)) {
          hits.add(SpaceHit(sp, n));
        }
      }
      for (final t in taskList) {
        if (sp.id == cur && scopeUid != null && !taskIsUnder(t, scopeUid)) {
          continue;
        }
        if (t.summary.toLowerCase().contains(needle) ||
            t.description.toLowerCase().contains(needle)) {
          hits.add(SpaceHit.forTask(sp, t));
        }
      }
      for (final e in eventList) {
        if (sp.id == cur && scopeUid != null && !eventIsUnder(e, scopeUid)) {
          continue;
        }
        if (e.summary.toLowerCase().contains(needle) ||
            e.description.toLowerCase().contains(needle) ||
            e.location.toLowerCase().contains(needle)) {
          hits.add(SpaceHit.forEvent(sp, e));
        }
      }
    }
    return hits;
  }

  /// Opens a search hit: switches to its Space and selects the note.
  Future<void> openHit(SpaceHit h, {OpenMode? mode}) async {
    if (catalog?.spaces.any((s) => s.id == h.space.id) != true) return;
    final sameSpace = h.space.id == currentSpaceId;
    if (!sameSpace && !await switchSpace(h.space.id)) return;
    if (h.isTask) {
      if (tasks.any((t) => t.uid == h.note.uid)) selectedTaskUid = h.note.uid;
      await openTask(h.note.uid, mode: mode);
      return;
    }
    if (h.isEvent) {
      await openEvent(h.note.uid, mode: mode);
      return;
    }
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
    for (final v in old) {
      if (!have.add(v.name)) continue;
      await src.save(
        SavedView(
          v.name,
          v.view,
          v.query,
          v.tags,
          uid: newUid(prefix: 'davdart-view'),
        ).toNote(),
      );
    }
    p.write(done, '1');
  }

  /// Backs the sidebar search box so applying a saved view shows its text.
  final searchController = TextEditingController();

  @override
  void dispose() {
    // A pending autosave is dropped, not flushed: a save finishing after
    // this would notify a disposed notifier. The shell flushes on pause and
    // on leaving an item, so nothing normally waits here.
    for (final t in _autosaveTimers.values) {
      t.cancel();
    }
    nav.dispose();
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

  /// Whether a view other than [except] already has this name (ignoring
  /// case and surrounding spaces).
  bool _viewNameTaken(String name, {String? except}) {
    final n = name.trim().toLowerCase();
    return savedViews.any(
      (v) => v.uid != except && v.name.trim().toLowerCase() == n,
    );
  }

  /// Saves the current view, search, tag and folder under a new [name].
  /// Returns null when done, else why not (an existing view's name is
  /// refused: use [updateView] to re-save it).
  Future<String?> saveView(String name) async {
    final n = name.trim();
    if (n.isEmpty) return 'Give the view a name';
    if (_viewNameTaken(n)) return 'A view with that name exists';
    if (!_canEditViews()) return 'This source is read-only';
    final uid = newUid(prefix: 'davdart-view');
    await _save(_current(n, uid: uid).toNote());
    return error;
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
    if (_viewNameTaken(n, except: v.uid)) return 'A view with that name exists';
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

  // Saved views are notes, so they are off in a Space with no VJOURNAL.
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
    _dropCaches(); // pruning below reads the index
    if (scopeUid != null && tree.find(scopeUid!) == null) scopeUid = null;
    // A project page left open without its project (a deleted project, a
    // reload): the panel falls back to the list.
    if (section == Section.overview) {
      section = _supportedSection(section);
    }
    if (_tabsLoaded) _pruneTabs();
    if (peekUid != null && findItem(peekUid!) == null) peekUid = null;
    if (peekUid == null) peekCollapsed = false;
    _drafts.removeWhere((u, d) => !d.dirty && tree.find(u) == null);
  }

  /// Notes with this tag are folders: containers that may carry text (for
  /// example instructions for an agent). The `kind-` prefix is hidden from
  /// the tag list, like `status-`.
  static const folderTag = 'kind-folder';
  static bool isFolder(Note n) => isFolderNote(n);

  /// The folder whose notes Board and List show; null means the whole Space.
  String? scopeUid;
  Note? get scope => scopeUid == null ? null : tree.find(scopeUid!)?.note;

  // --- The Notes panel's scope and views ---

  /// True for a note inside the Space's Projects container (a project, a
  /// folder or note in one) and for the container itself.
  bool inProjectsLayer(String uid) => projectIndex.inProjectsLayer(uid);

  // --- Personal layer ---
  //
  // Personal is the individual's own bucket: a folder tagged `kind-personal`
  // (created lazily) plus anything outside the Projects container. The
  // Personal sections (Notes, Tasks, Calendar) read only this layer; the
  // project scope belongs to project pages and does not narrow them.

  Note? get personalContainer {
    Note? oldest;
    for (final n in notes) {
      if (!isPersonalContainer(n)) continue;
      if (oldest == null || NoteTree.byCreated(n, oldest) < 0) oldest = n;
    }
    return oldest;
  }

  /// The Personal container's uid, created when the Space has none. Null in
  /// a read-only Space or when the save fails (the item then stays top
  /// level); concurrent calls share one save, and the oldest container wins.
  Future<String?> ensurePersonalContainer() async {
    if (!editable) return null;
    final src = source;
    while (_personalBusy != null) {
      await _personalBusy;
    }
    if (src != source) return null;
    final existing = personalContainer;
    if (existing != null) return existing.uid;
    final done = Completer<void>();
    _personalBusy = done.future;
    try {
      final n = _newFolder(personalTitle, tags: const [personalTag]);
      if (n == null) return null;
      await _save(n);
      if (src != source || error != null) return null;
      // A sync may have landed a container meanwhile: the oldest wins.
      return personalContainer?.uid ?? tree.find(n.uid)?.note.uid;
    } finally {
      _personalBusy = null;
      done.complete();
    }
  }

  Future<void>? _personalBusy;

  /// The personal notes (folders and views left out), oldest first.
  List<Note> get personalNotes => [
    for (final n in notes)
      if (!isFolder(n) &&
          !isViewNote(n) &&
          !isPersonalContainer(n) &&
          !inProjectsLayer(n.uid))
        n,
  ]..sort(NoteTree.byCreated);

  /// Personal notes after the search and tag filters.
  List<Note> get filteredPersonal => [
    for (final n in notes)
      if (!isFolder(n) &&
          !isPersonalContainer(n) &&
          !inProjectsLayer(n.uid) &&
          matches(n))
        n,
  ]..sort(NoteTree.byCreated);

  /// The whole-Space tree's top rows: the Personal container is hidden and
  /// its children take its place (the Projects layer stays visible here).
  List<NoteNode> get spaceTreeRoots {
    final container = personalContainer;
    final node = container == null ? null : tree.find(container.uid);
    if (container == null || node == null) return tree.roots;
    return [
      for (final r in tree.roots)
        if (r.note.uid == container.uid) ...node.children else r,
    ];
  }

  /// The tree's top rows for Personal: the Personal container's children,
  /// the container itself hidden, plus top-level items outside it.
  List<NoteNode> get personalTreeRoots {
    final container = personalContainer;
    if (container == null) {
      return [
        for (final r in tree.roots)
          if (!inProjectsLayer(r.note.uid) && !isProjectsContainer(r.note)) r,
      ];
    }
    final inside = tree.find(container.uid)?.children ?? const <NoteNode>[];
    final top = [
      for (final r in tree.roots)
        if (r.note.uid != container.uid &&
            !isPersonalContainer(r.note) &&
            !inProjectsLayer(r.note.uid))
          r,
    ];
    return [...inside, ...top];
  }

  /// The folders Personal can drop into: the container's child folders, or
  /// the loose top-level folders when there is no container.
  List<Note> get personalSubFolders {
    final container = personalContainer;
    if (container == null) {
      return [
        for (final r in tree.roots)
          if (isFolder(r.note) &&
              !isProjectsContainer(r.note) &&
              !inProjectsLayer(r.note.uid))
            r.note,
      ];
    }
    return [
      for (final c in tree.find(container.uid)?.children ?? const <NoteNode>[])
        if (isFolder(c.note)) c.note,
    ];
  }

  /// The folder a personal note is grouped under (the container itself is
  /// hidden), or null for a note directly in Personal or at the top level.
  Note? personalGroupOf(String uid) {
    final container = personalContainer?.uid;
    var p = tree.find(uid)?.note.parentUid;
    Note? group;
    while (p != null) {
      final n = tree.find(p)?.note;
      if (n == null || p == container || isPersonalContainer(n)) break;
      group = n;
      p = n.parentUid;
    }
    return group;
  }

  /// Open personal tasks (outside the projects layer), in task order.
  List<Task> personalOpenTasks([DateTime? now]) {
    final n = now ?? DateTime.now();
    return [
      for (final t in tasks)
        if (!t.isClosed && !inProjectsLayer(t.uid)) t,
    ]..sort((a, b) => compareTasks(a, b, n));
  }

  /// Personal tasks after the tag filter (status is the panel's own filter).
  List<Task> get filteredPersonalTasks => [
    for (final t in tasks)
      if ((taskTagFilter == null || t.categories.contains(taskTagFilter)) &&
          !inProjectsLayer(t.uid))
        t,
  ];

  /// Personal events after the tag filter.
  List<Event> get filteredPersonalEvents => [
    for (final e in events)
      if ((eventTagFilter == null || e.categories.contains(eventTagFilter)) &&
          !inProjectsLayer(e.uid))
        e,
  ];

  List<AgendaGroup> upcomingPersonalOccurrences(DateTime from, int days) =>
      upcomingGroups(filteredPersonalEvents, from, days);

  List<EventOccurrence> pastPersonalOccurrences(
    DateTime from, [
    int days = 30,
  ]) => pastAgenda(filteredPersonalEvents, from, days);

  /// The notes the Notes panel lists: [scopeUid]'s subtree in a project
  /// scope, and the Space's own (loose) notes in Personal scope. Folders are
  /// not notes here; the tree shows those.
  List<Note> get notesInScope {
    final scope = scopeUid;
    if (scope != null) {
      return [
        for (final n in tree.descendants(scope))
          if (!isFolderNote(n)) n,
      ];
    }
    return [
      for (final n in notes)
        if (!isFolderNote(n) && !inProjectsLayer(n.uid)) n,
    ];
  }

  /// The folder a note is grouped under in the Notes list: the folder just
  /// below the open scope, or null for a note directly in it (Personal: the
  /// top folder, or none for a loose note).
  Note? notesGroupOf(String uid) {
    var p = tree.find(uid)?.note.parentUid;
    Note? group;
    while (p != null) {
      final n = tree.find(p)?.note;
      if (n == null || p == scopeUid) break;
      group = n;
      p = n.parentUid;
    }
    return group;
  }

  /// The folders directly in the current scope: what the Tree view can show
  /// and what the folder drops accept. Personal scope leaves out the Projects
  /// container (it is the project layer, not a folder of notes).
  List<Note> get subFolders {
    final scope = scopeUid;
    if (scope != null) {
      return [
        for (final c in tree.find(scope)?.children ?? const <NoteNode>[])
          if (isFolderNote(c.note)) c.note,
      ];
    }
    return [
      for (final r in tree.roots)
        if (isFolderNote(r.note) && !inProjectsLayer(r.note.uid)) r.note,
    ];
  }

  /// The tree's top rows for the current scope: the scope folder's children,
  /// or the loose roots (the projects layer is shown in the Projects panel).
  List<NoteNode> get noteTreeRoots {
    final scope = scopeUid;
    if (scope != null) return tree.find(scope)?.children ?? const [];
    return [
      for (final r in tree.roots)
        if (!inProjectsLayer(r.note.uid)) r,
    ];
  }

  static const _notesViewKey = 'davdart.notesview.v1';

  /// How the Notes panel shows the scope: the plain list (default) or the
  /// tree. Trees without sub-folders fall back to the list.
  NotesView notesView = NotesView.list;

  void setNotesView(NotesView v) {
    if (notesView == v) return;
    notesView = v;
    prefs?.write(_notesViewKey, v.name);
    notifyListeners();
  }

  /// Shows only what is inside folder [uid] (null: the whole Space). The
  /// scope is kept per Space, and a project opened this way is remembered as
  /// a recent one.
  void openFolder(String? uid) {
    scopeUid = uid;
    _persistScope();
    if (uid != null) {
      // A project, or a folder inside one, makes that project recent.
      final ix = projectIndex;
      final project = ix.isProject(uid) ? uid : ix.projectOf(uid)?.uid;
      if (project != null) _rememberProject(project);
    }
    final a = _activeViewTab;
    if (a != null && a.kind == TabKind.note) _activeViewTab = null;
    notifyListeners();
  }

  static const _scopeKey = 'davdart.scope.v1';
  static const _recentsKey = 'davdart.recents.v1';

  /// How many projects a Space remembers as recent.
  static const recentsLimit = 5;

  /// The saved folder scope per Space id.
  final Map<String, String> _scopes = {};

  /// The projects opened most recently per Space id, newest first.
  final Map<String, List<String>> _recents = {};

  /// Set on app start and on a Space switch: the next load brings back that
  /// Space's saved scope. A plain reload leaves the scope alone.
  bool _restoreScopePending = true;

  /// The tab a project's page opens on, remembered per project (Overview by
  /// default). Stored per Space, so the same projects in another Space do not
  /// share it.
  ProjectTab projectTab(String uid) =>
      switch (prefs?.read('davdart.proj.tab.v1.$_spaceKey.$uid')) {
        'board' => ProjectTab.board,
        'notes' => ProjectTab.notes,
        'calendar' => ProjectTab.calendar,
        _ => ProjectTab.overview,
      };

  void setProjectTab(String uid, ProjectTab tab) {
    if (projectTab(uid) == tab) return;
    prefs?.write('davdart.proj.tab.v1.$_spaceKey.$uid', tab.name);
    notifyListeners();
  }

  /// The view Home opens on, remembered per Space (Overview by default), the
  /// way a project's page remembers its tab.
  HomeView get homeView =>
      prefs?.read('davdart.home.view.v1.$_spaceKey') == 'calendar'
      ? HomeView.calendar
      : HomeView.overview;

  void setHomeView(HomeView view) {
    if (homeView == view) return;
    prefs?.write('davdart.home.view.v1.$_spaceKey', view.name);
    notifyListeners();
  }

  /// The day Home's calendar has picked (a plain UTC-flagged date), shared by
  /// the grid, which circles it, and the Calendar panel, which pins that
  /// day's items at its top. Null until a day is picked: the grid shows today
  /// and the panel keeps its usual shape. Reset on a Space switch, like the
  /// grid's own view state.
  DateTime? homeDay;

  /// While [homeDay] is picked: the Calendar panel's agenda sections a hand
  /// toggle has opened or shut (id -> collapsed). Layered over the saved
  /// per-section prefs, which are never written from here; cleared by every
  /// day pick, so the next pick puts the sections back where a pick leaves
  /// them.
  Map<String, bool> calendarSectionCollapsed = const {};

  void setCalendarSectionCollapsed(String id, bool collapsed) {
    if (calendarSectionCollapsed[id] == collapsed) return;
    calendarSectionCollapsed = {...calendarSectionCollapsed, id: collapsed};
    notifyListeners();
  }

  /// Picks [day] on Home's calendar and brings the Calendar panel up beside
  /// it: a folded panel, or one on another section, opens on Calendar (which
  /// unfolds it); a panel already there is left alone, so a press never folds
  /// it. The main area stays where it is (Home). A pick collapses the panel's
  /// other agenda sections (see [calendarSectionCollapsed]).
  void selectHomeDay(DateTime day) {
    calendarSectionCollapsed = const {};
    setHomeDay(day);
    if (section != Section.events || sidebarCollapsed) {
      setSection(Section.events);
    }
  }

  /// Moves the picked day without touching the panel: the grid's month arrows
  /// keep the selection inside the month they show.
  void setHomeDay(DateTime day) {
    final d = wallDay(day);
    if (homeDay == d) return;
    homeDay = d;
    notifyListeners();
  }

  /// The tasks under project [uid] at any depth (no scope or filter applied);
  /// grouped once in the project index.
  List<Task> projectTasks(String uid) => projectIndex.tasksOf(uid);

  /// The tasks of project [uid] counted for progress: canceled tasks left
  /// out; `done` versus the total, open, overdue, and a count per canonical
  /// status (blocked and unknown words are kept in their own map entries and
  /// the page folds them into the fixed bar).
  ({int total, int done, int open, int overdue, Map<String, int> byStatus})
  projectTaskCounts(String uid, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final by = <String, int>{};
    var total = 0, done = 0, open = 0, overdue = 0;
    for (final t in projectTasks(uid)) {
      final status = canonicalStatus(t.boardStatus) ?? t.boardStatus;
      if (status == 'canceled') continue;
      total++;
      by[status] = (by[status] ?? 0) + 1;
      if (status == 'done') {
        done++;
      } else {
        open++;
      }
      if (!t.isClosed && isTaskOverdue(t, n)) overdue++;
    }
    return (
      total: total,
      done: done,
      open: open,
      overdue: overdue,
      byStatus: by,
    );
  }

  /// When the project last changed: the newest modification stamp of its
  /// notes, tasks and events (the folder itself included), or null. Computed
  /// once in the project index.
  DateTime? projectLastChanged(String uid) => projectIndex.lastChangedOf(uid);

  /// The Space's projects, the ones opened most recently first: the scope
  /// picker and the palette list them in this order.
  List<Note> get projectsByRecent {
    final rest = [...projectIndex.projects()];
    final recent = <Note>[];
    for (final uid in recentProjects) {
      final i = rest.indexWhere((p) => p.uid == uid);
      if (i >= 0) recent.add(rest.removeAt(i));
    }
    return [...recent, ...rest];
  }

  /// The project uids opened most recently in this Space, newest first (at
  /// most [recentsLimit]); the scope picker lists them first. Projects that
  /// were deleted or are no longer projects are left out.
  List<String> get recentProjects {
    final live = _liveProjects;
    return List.unmodifiable([
      for (final uid in _recents[_spaceKey] ?? const <String>[])
        if (live.contains(uid)) uid,
    ]);
  }

  /// The Space id the per-Space prefs are keyed by ('default' without a
  /// catalog: folders, tags, Home focus and the scope share it).
  String get _spaceKey => catalog?.current ?? 'default';

  void _readScopePrefs() {
    final scopes = _jsonMap(prefs?.read(_scopeKey));
    _scopes
      ..clear()
      ..addAll({for (final e in scopes.entries) e.key: '${e.value}'});
    _recents.clear();
    for (final e in _jsonMap(prefs?.read(_recentsKey)).entries) {
      final v = e.value;
      if (v is! List) continue;
      _recents[e.key] = [
        for (final u in v)
          if (u is String && u.isNotEmpty) u,
      ];
    }
  }

  static Map<String, Object?> _jsonMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final m = jsonDecode(raw);
      return m is Map
          ? {for (final e in m.entries) '${e.key}': e.value}
          : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Writes this Space's folder scope (nothing when it is the whole Space).
  void _persistScope() {
    final uid = scopeUid;
    final key = _spaceKey;
    if (uid == null) {
      if (_scopes.remove(key) != null) {
        prefs?.write(_scopeKey, jsonEncode(_scopes));
      }
      return;
    }
    if (_scopes[key] == uid) return;
    _scopes[key] = uid;
    prefs?.write(_scopeKey, jsonEncode(_scopes));
  }

  /// Sets the scope to what [page] last showed; a page's first visit keeps
  /// the scope the user already has. Home is personal: it brings back its own
  /// loose folder scope, never a project scope (a project page owns that).
  void _scopeToPage(DocTab? page) {
    if (!_pageScope.containsKey(page)) return;
    final want = _pageScope[page];
    // A scope whose folder or project is gone falls back to the page's own:
    // the project of a project page, else none.
    if (want != null && tree.find(want) == null) {
      _scopeTo(page != null && page.kind == TabKind.project ? page.id : null);
      return;
    }
    if (page == null && want != null && projectIndex.projectOf(want) != null) {
      _scopeTo(null);
      return;
    }
    _scopeTo(want);
  }

  /// Sets the scope to [uid] and saves it, doing nothing when it already is
  /// the scope. A page's own scope goes through here.
  void _scopeTo(String? uid) {
    if (uid == scopeUid) return;
    scopeUid = uid;
    _persistScope();
  }

  /// Makes the scope follow the active tab: the project page's project, or
  /// none for Home and the other pages.
  void _syncScopeToTab() {
    final project = mainProjectUid;
    if (scopeUid == project) return;
    scopeUid = project;
    _persistScope();
  }

  /// Brings back the Space's saved folder scope once its notes are loaded:
  /// the saved folder when it is still there, else Everything (null) for this
  /// session. A saved folder that is only missing because the Space is empty
  /// or offline stays saved, so a later load with it back restores it.
  void _restoreScope() {
    final saved = _scopes[_spaceKey];
    if (scopeUid != null && tree.find(scopeUid!) != null) {
      if (saved != scopeUid) _persistScope();
      return;
    }
    scopeUid = saved != null && tree.find(saved) != null ? saved : null;
  }

  /// The projects of this Space, by uid.
  Set<String> get _liveProjects => {
    for (final p in projectIndex.projects()) p.uid,
  };

  void _rememberProject(String uid) {
    // Projects that are gone or no longer projects give up their slot.
    final live = _liveProjects;
    final list = [
      for (final u in _recents[_spaceKey] ?? const <String>[])
        if (u != uid && live.contains(u)) u,
    ];
    list.insert(0, uid);
    _recents[_spaceKey] = list.take(recentsLimit).toList();
    prefs?.write(_recentsKey, jsonEncode(_recents));
  }

  /// Moves note, task or event [uid] and everything under it to Space [targetId],
  /// at its top level. Under a note go its sub-notes and every task whose
  /// parent chain leads to it; under a task go its sub-tasks. The items are
  /// copied into the other Space first, checked, and removed here only after
  /// that worked, so a failure leaves a duplicate, never a loss. The copies
  /// get new ids; earlier versions stay behind. A server Space syncs the new
  /// items the next time it is opened. Returns how many items moved, or null
  /// with [error] set. A repeating task or event with per-occurrence
  /// overrides is not moved (the overrides carry the old id). Tasks under an
  /// event go with it.
  Future<int?> moveToSpace(String uid, String targetId) async {
    final c = catalog;
    final src = source;
    final node = tree.find(uid);
    final rootTask = node == null ? _taskById(uid) : null;
    final rootEvent = node == null && rootTask == null ? _eventById(uid) : null;
    if (c == null || (node == null && rootTask == null && rootEvent == null)) {
      return null;
    }
    if (src is! EditableNoteSource) return null;
    if (targetId == c.current || !c.spaces.any((s) => s.id == targetId)) {
      return null;
    }
    final noteGroup = node == null
        ? <Note>[]
        : [node.note, ...tree.descendants(uid)];
    // Tasks under the group, parents before children.
    final ids = {
      for (final n in noteGroup) n.uid,
      ?rootTask?.uid,
      ?rootEvent?.uid,
    };
    final taskGroup = <Task>[?rootTask];
    for (var grew = true; grew;) {
      grew = false;
      for (final t in tasks) {
        if (ids.contains(t.uid) || !ids.contains(t.parentUid)) continue;
        ids.add(t.uid);
        taskGroup.add(t);
        grew = true;
      }
    }
    if ((taskGroup.isNotEmpty || rootEvent != null) &&
        src is! SpaceNoteSource) {
      return null;
    }
    if (rootEvent != null && rootEvent.siblingLines.isNotEmpty) {
      error = 'A repeating event with changed occurrences cannot be moved yet.';
      notifyListeners();
      return null;
    }
    if (taskGroup.any((t) => t.siblingLines.isNotEmpty)) {
      error = 'A repeating task with changed occurrences cannot be moved yet.';
      notifyListeners();
      return null;
    }
    final target = c.sourceFor(targetId);
    final count =
        noteGroup.length + taskGroup.length + (rootEvent == null ? 0 : 1);
    // Unsaved edits would be lost with the old items: settle them first.
    if (!await _settleDrafts([...ids])) return null;
    final fresh = <String, String>{for (final u in ids) u: newUid()};
    try {
      for (final n in noteGroup) {
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
      if (rootEvent != null) {
        await target.saveEvent(
          Event(
            uid: fresh[rootEvent.uid]!,
            summary: rootEvent.summary,
            description: rootEvent.description,
            location: rootEvent.location,
            categories: List.of(rootEvent.categories),
            status: rootEvent.status,
            dtstart: rootEvent.dtstart,
            dtend: rootEvent.dtend,
            duration: rootEvent.duration,
            rrule: rootEvent.rrule,
            exdates: List.of(rootEvent.exdates),
            rdates: List.of(rootEvent.rdates),
            created: rootEvent.created,
            lastModified: DateTime.now().toUtc(),
            extraLines: List.of(rootEvent.extraLines),
            calendarLines: List.of(rootEvent.calendarLines),
            propertyParams: Map.of(rootEvent.propertyParams),
          ),
        );
      }
      for (final t in taskGroup) {
        await target.saveTask(
          Task(
            uid: fresh[t.uid]!,
            summary: t.summary,
            description: t.description,
            categories: List.of(t.categories),
            status: t.status,
            percentComplete: t.percentComplete,
            priority: t.priority,
            due: t.due,
            dtstart: t.dtstart,
            completed: t.completed,
            rrule: t.rrule,
            parentUid: t.uid == uid ? null : fresh[t.parentUid],
            created: t.created,
            lastModified: DateTime.now().toUtc(),
            extraLines: List.of(t.extraLines),
            calendarLines: List.of(t.calendarLines),
            propertyParams: Map.of(t.propertyParams),
          ),
        );
      }
      // Something may have changed the items while they were being copied
      // (an edit, a sync). Keep the originals then; nothing is lost.
      final current = {for (final n in await src.load()) n.uid: n};
      final currentTasks = taskGroup.isEmpty
          ? const <String, Task>{}
          : {
              for (final t in await (src as SpaceNoteSource).loadTasks())
                t.uid: t,
            };
      var changed = false;
      if (rootEvent != null) {
        final now = (await (src as SpaceNoteSource).loadEvents())
            .where((e) => e.uid == rootEvent.uid)
            .firstOrNull;
        if (now == null ||
            now.summary != rootEvent.summary ||
            now.description != rootEvent.description ||
            now.location != rootEvent.location ||
            now.lastModified != rootEvent.lastModified ||
            now.status != rootEvent.status ||
            now.dtstart != rootEvent.dtstart ||
            now.dtend != rootEvent.dtend ||
            now.rrule != rootEvent.rrule ||
            now.categories.join('\n') != rootEvent.categories.join('\n')) {
          changed = true;
        }
      }
      for (final n in noteGroup) {
        final now = current[n.uid];
        if (now == null ||
            now.summary != n.summary ||
            now.description != n.description ||
            now.lastModified != n.lastModified ||
            now.parentUid != n.parentUid) {
          changed = true;
        }
      }
      for (final t in taskGroup) {
        final now = currentTasks[t.uid];
        if (now == null ||
            now.summary != t.summary ||
            now.description != t.description ||
            now.lastModified != t.lastModified ||
            now.parentUid != t.parentUid ||
            now.status != t.status ||
            now.due != t.due ||
            now.categories.join('\n') != t.categories.join('\n')) {
          changed = true;
        }
      }
      if (changed) {
        if (src == source) {
          error =
              'An item changed while moving. The copies are in the other '
              'space; the originals were kept.';
          notifyListeners();
        }
        return null;
      }
      for (final t in taskGroup.reversed) {
        await (src as SpaceNoteSource).deleteTask(t.uid);
      }
      if (rootEvent != null) {
        await (src as SpaceNoteSource).deleteEvent(rootEvent.uid);
      }
      for (final n in noteGroup.reversed) {
        await src.delete(n.uid);
      }
      if (src != source) return count;
      final loaded = await src.load();
      if (src != source) return count;
      _setNotes(loaded);
      if (src is SpaceNoteSource) {
        _setTasks(await src.loadTasks());
        _setEvents(await src.loadEvents());
      }
      if (src != source) return count;
      if (peekUid != null && findItem(peekUid!) == null) {
        _setPeek(null);
      }
      _drafts.removeWhere((u, d) => !d.dirty && tree.find(u) == null);
      error = null;
      notifyListeners();
      if (connected) sync();
      return count;
    } catch (e) {
      if (src == source) {
        // Some originals may already be gone: show what is really there.
        try {
          _setNotes(await src.load());
          if (src is SpaceNoteSource) {
            _setTasks(await src.loadTasks());
            _setEvents(await src.loadEvents());
          }
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
    final n = _newFolder(title, parentUid: parentUid, text: text);
    if (n == null) return;
    await _save(n);
    if (error == null) openFolder(n.uid);
  }

  Note? _newFolder(
    String title, {
    String? parentUid,
    String text = '',
    List<String> tags = const [],
  }) {
    final t = title.trim();
    if (t.isEmpty) return null;
    final now = DateTime.now().toUtc();
    return Note(
      uid: newUid(),
      summary: t,
      description: text.trim(),
      categories: [folderTag, ...tags],
      parentUid: parentUid,
      created: now,
      lastModified: now,
    );
  }

  // --- Projects ---
  //
  // A project is a folder directly under a Projects container (a folder
  // tagged `kind-folder` and `kind-projects`). Derived from location; see
  // [ProjectIndex]. Opening a project is the ordinary folder scope.

  /// Projects, counts and progress of the open Space, derived on demand.
  ///
  /// Cached until the next notification, so a rebuild reads it once.
  ProjectIndex get projectIndex =>
      _projectIndexCache ??= ProjectIndex(notes, tasks, events);
  ProjectIndex? _projectIndexCache;

  void _dropCaches() {
    _projectIndexCache = null;
  }

  @override
  void notifyListeners() {
    _dropCaches();
    super.notifyListeners();
  }

  /// Adds a project folder under the Space's Projects container and opens
  /// it. The container (title "Projects") is created first when the Space
  /// has none; with several, the oldest is used. Returns the new project's
  /// uid, or null (empty title, read-only Space, failure).
  Future<String?> addProject(String title) async {
    if (title.trim().isEmpty || !editable) return null;
    final src = source;
    // A second call while one is running waits for it and re-reads the containers, so a
    // double submit never creates two containers.
    while (_projectsBusy != null) {
      await _projectsBusy;
    }
    if (src != source) return null;
    final done = Completer<void>();
    _projectsBusy = done.future;
    try {
      var container = projectIndex.containers().firstOrNull;
      if (container == null) {
        final c = _newFolder(projectsTitle, tags: [projectsTag])!;
        await _save(c);
        if (src != source || error != null) return null;
        // A sync may have landed a container meanwhile: the oldest wins.
        container =
            projectIndex.containers().firstOrNull ?? tree.find(c.uid)?.note;
        if (container == null) return null;
      }
      final n = _newFolder(title, parentUid: container.uid)!;
      await _save(n);
      if (src != source || error != null) return null;
      openFolder(n.uid);
      return n.uid;
    } finally {
      _projectsBusy = null;
      done.complete();
    }
  }

  Future<void>? _projectsBusy;

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
    if (old != null && old != uid && !_tabs.contains(_tabOf(old))) {
      _drafts.remove(old);
      _taskDrafts.remove(old);
      _eventDrafts.remove(old);
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
      await _checkHeld(src);
      if (src != source) return;
      // A section the collection cannot hold is never loaded or synced.
      section = _supportedSection(section);
      var loaded = supportsNotes ? await src.load() : <Note>[];
      if (src != source) return; // another Space was opened meanwhile
      _setNotes(loaded);
      await _loadTasks(src);
      if (src != source) return;
      await _loadEvents(src);
      if (src != source) return;
      if (src is EditableNoteSource && supportsNotes) {
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
      _taskTagsOpen = prefs?.read(_taskTagsOpenKey) == 'true';
      _eventTagsOpen = prefs?.read(_eventTagsOpenKey) == 'true';
      _restoreTabs();
      if (_restoreScopePending) {
        _restoreScopePending = false;
        _restoreScope();
        // The active tab owns the scope: a project page reads its project,
        // Home has none. A stale project scope is dropped, while a loose
        // folder scope (the panels' own) stays saved.
        final activeProject = mainProjectUid;
        final savedScope = scopeUid;
        final staleProject =
            activeProject == null &&
            savedScope != null &&
            projectIndex.projectOf(savedScope) != null;
        if (activeProject != null && savedScope != activeProject) {
          scopeUid = activeProject;
          _persistScope();
        } else if (staleProject) {
          scopeUid = null;
          _persistScope();
        }
        // A restored view tab shows its view, not just its name in the strip.
        final at = activeTab;
        final saved = at != null && at.kind == TabKind.view
            ? _viewByUid(at.id)
            : null;
        if (saved != null) applyView(saved);
        // Home's own scope for this session: the loose folder scope coming
        // back with it, never a restored project page's project.
        _pageScope[null] = activeTab == null ? scopeUid : null;
        if (at != null) _pageScope[at] = scopeUid;
      }
    } catch (e) {
      if (src != source) return;
      error = '$e';
    }
    loading = false;
    notifyListeners();
    if (error == null && connected) sync();
  }

  /// Note actions (and saved views, which are notes) are off in a Space
  /// whose collection takes no VJOURNAL.
  bool get editable => source is EditableNoteSource && supportsNotes;

  /// Which sections the current Space's collection supports (VJOURNAL,
  /// VTODO, VEVENT); all of them without a catalog or for local Spaces.
  bool get supportsNotes => catalog?.currentInfo?.notes ?? true;

  ///
  /// A type also counts when the Space already holds items of it (a
  /// collection that does not advertise it but has some).
  bool get supportsTasks => (catalog?.currentInfo?.tasks ?? true) || _heldTasks;
  bool get supportsEvents =>
      (catalog?.currentInfo?.events ?? true) || _heldEvents;
  bool _heldTasks = false, _heldEvents = false;

  /// Notes the items stored locally for a type the collection does not
  /// advertise, so the type stays usable.
  Future<void> _checkHeld(NoteSource src) async {
    _heldTasks = false;
    _heldEvents = false;
    if (src is! SpaceNoteSource) return;
    final info = catalog?.currentInfo;
    if (info == null) return;
    try {
      if (!info.tasks) _heldTasks = (await src.loadTasks()).isNotEmpty;
      if (!info.events) _heldEvents = (await src.loadEvents()).isNotEmpty;
    } catch (_) {}
  }

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
    var message = syncMessage;
    // Notes, tasks and events sync in the same pass, each isolated from the
    // others: a failing task or event sync leaves the notes (and their
    // message) alone and the other way round.
    try {
      final r = supportsNotes ? await s.sync() : null;
      if (s != _space) return;
      message = !supportsNotes
          ? 'Synced ${_clock()}'
          : r == null
          ? null
          : r.errors.isNotEmpty
          ? 'Sync problem: ${r.errors.first}'
          : r.conflicts.isNotEmpty
          ? 'Synced; ${r.conflicts.length} overlapping edit(s) resolved, older text kept in history'
          : 'Synced ${_clock()}';
      final loaded = supportsNotes ? await s.load() : <Note>[];
      if (s != _space) return;
      _setNotes(loaded);
      _rebaseDrafts();
    } catch (e) {
      if (s != _space) return;
      message = 'Sync failed: $e';
    }
    String? taskProblem;
    try {
      final tr = supportsTasks ? await s.syncTasks() : null;
      if (s != _space) return;
      if (tr != null && tr.errors.isNotEmpty) {
        taskProblem = 'Tasks: sync problem: ${tr.errors.first}';
      }
    } catch (e) {
      if (s != _space) return;
      taskProblem = 'Tasks: sync failed: $e';
    }
    try {
      final loaded = supportsTasks ? await s.loadTasks() : <Task>[];
      if (s != _space) return;
      _setTasks(loaded);
      _rebaseTaskDrafts();
    } catch (e) {
      if (s != _space) return;
      taskProblem ??= 'Tasks could not be read: $e';
    }
    if (s != _space) return;
    String? eventProblem;
    try {
      final er = supportsEvents ? await s.syncEvents() : null;
      if (s != _space) return;
      if (er != null && er.errors.isNotEmpty) {
        eventProblem = 'Calendar: sync problem: ${er.errors.first}';
      }
    } catch (e) {
      if (s != _space) return;
      eventProblem = 'Calendar: sync failed: $e';
    }
    try {
      final loaded = supportsEvents ? await s.loadEvents() : <Event>[];
      if (s != _space) return;
      _setEvents(loaded);
      _rebaseEventDrafts();
    } catch (e) {
      if (s != _space) return;
      eventProblem ??= 'Calendar could not be read: $e';
    }
    if (s != _space) return;
    taskError = taskProblem;
    eventError = eventProblem;
    for (final p in [?taskProblem, ?eventProblem]) {
      message = message == null ? p : '$message. $p';
    }
    syncMessage = message;
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
    String? notSaved;
    try {
      try {
        await change(src);
      } on StorageWriteException catch (e) {
        // Kept in memory but not on disk: show it, and reload as usual.
        notSaved = '$e';
      }
      final loaded = await src.load();
      if (src != source) return;
      _setNotes(loaded);
      error = notSaved;
    } catch (e) {
      if (src != source) return;
      error = 'Save failed: $e';
    }
    notifyListeners();
    if (error == null && connected) sync();
  }

  /// Moves a note to another status (keeps the header and status tag in step).
  /// A null [status] clears it (removes the status line and tag).
  Future<void> setStatus(
    String uid,
    String? status, {
    bool undoable = true,
  }) async {
    final n = tree.find(uid)?.note;
    if (n == null) return;
    final before = PlanItem.fromNote(n).status;
    final copy = n.copyWith();
    final p = PlanItem.fromNote(copy);
    if (status == null) {
      p.clearStatus();
    } else {
      p.setStatus(status);
    }
    await _save(p.apply());
    if (undoable && error == null && before != status) {
      _postUndo(
        status == null
            ? 'Cleared status of "${n.summary}"'
            : 'Moved "${n.summary}" to $status',
        () => _restoreItem(uid, setStatus: true, status: before),
      );
    }
  }

  /// Sets a note's priority (`high`, `medium`, `low`; null clears it) in its
  /// body header; the other header lines stay.
  Future<void> setNotePriority(
    String uid,
    String? priority, {
    bool undoable = true,
  }) async {
    final n = tree.find(uid)?.note;
    if (n == null) return;
    final before = PlanItem.fromNote(n).fields['priority'];
    final beforeWord = PlanItem.fromNote(n).priorityWord;
    final copy = n.copyWith();
    final p = PlanItem.fromNote(copy)..setPriority(priority);
    await _save(p.apply());
    if (undoable && error == null && beforeWord != priority) {
      _postUndo(
        _priorityLabel(n.summary, priority),
        () => _restoreItem(uid, setPriority: true, priorityRaw: before),
      );
    }
  }

  /// The one change Undo would revert, shown as a toast by the app shell.
  /// A newer change replaces it.
  BoardUndo? pendingUndo;

  /// Set by the app shell: shows [u] as a toast with an Undo action.
  void Function(BoardUndo u)? onBoardUndo;

  void _postUndo(String label, Future<void> Function() undo) {
    final u = BoardUndo(label, undo);
    pendingUndo = u;
    onBoardUndo?.call(u);
  }

  /// Runs [u] only while it is still the latest change.
  Future<void> undoBoard(BoardUndo u) async {
    if (!identical(pendingUndo, u)) return;
    pendingUndo = null;
    await u.undo();
  }

  static String _priorityLabel(String title, String? word) => word == null
      ? 'Priority of "$title" cleared'
      : 'Priority of "$title" set to ${word[0].toUpperCase()}${word.substring(1)}';

  /// Puts back only the status, priority, due date, start, parent, labels
  /// and/or rank of a note or task; its other fields stay as they are now.
  Future<void> _restoreItem(
    String uid, {
    bool setStatus = false,
    String? status,
    bool setPriority = false,
    String? priorityRaw,
    int? priorityInt,
    _TaskStatusState? taskState,
    bool setRank = false,
    double? rank,
    bool setDue = false,
    ICalDate? due,
    bool setStart = false,
    ICalDate? start,
    bool setParent = false,
    String? parentUid,
    bool setTags = false,
    List<String>? tags,
  }) async {
    final t = _taskById(uid);
    if (t != null) {
      final copy = t.copyWith(
        priority: setPriority ? priorityInt : null,
        clearPriority: setPriority && priorityInt == null,
        due: setDue ? due : null,
        clearDue: setDue && due == null,
        dtstart: setStart ? start : null,
        clearStart: setStart && start == null,
        parentUid: setParent ? parentUid : null,
        clearParent: setParent && parentUid == null,
      );
      if (setTags) {
        copy.categories = [
          ...t.categories.where(
            (c) => c.startsWith('status-') || c.startsWith('kind-'),
          ),
          ..._plainTags(tags ?? const []),
        ];
      }
      if (setStatus && taskState != null) {
        taskState.applyTo(copy);
        if (taskState.status == 'COMPLETED') {
          final blocker = taskCompletionBlocker(copy);
          if (blocker != null) {
            error = blocker;
            notifyListeners();
            return;
          }
        }
      }
      if (setRank) copy.rank = rank;
      await _taskEdit((src) => src.saveTask(copy));
      return;
    }
    final n = tree.find(uid)?.note;
    if (n == null) return;
    var copy = n.copyWith();
    final p = PlanItem.fromNote(copy);
    if (setStatus) {
      if (status == null) {
        p.clearStatus();
      } else {
        p.setStatus(status);
      }
    }
    if (setPriority) _setRawPriority(p, priorityRaw);
    copy = p.apply();
    if (setRank) copy.rank = rank;
    await _save(copy);
  }

  /// Puts the `priority` header line back to its exact raw text [raw] (null
  /// removes it), at its old place among the header lines.
  static void _setRawPriority(PlanItem p, String? raw) {
    final keys = p.fields.keys.toList();
    final had = p.fields.containsKey('priority');
    if (raw == null) {
      p.fields.remove('priority');
      return;
    }
    p.fields['priority'] = raw;
    if (!had) return;
    final copy = Map<String, String>.of(p.fields);
    p.fields
      ..clear()
      ..addAll({for (final k in keys) k: copy[k]!});
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

  /// Sets the note body text of [uid] (its header fields stay), for the inline
  /// text of a project's About. False when the write did not go through (the
  /// reason is [error]), so the field can show it.
  Future<bool> setNoteText(String uid, String text) async {
    final n = tree.find(uid)?.note;
    if (n == null || !editable) return false;
    error = null;
    await updateNote(uid, text: text);
    return error == null;
  }

  /// Sets (or, with an empty [value], removes) the header field [key] of note
  /// [uid]: the project details (lead, team, start, due, members). False when
  /// the write did not go through (the reason is [error]).
  Future<bool> setNoteField(String uid, String key, String? value) async {
    final n = tree.find(uid)?.note;
    if (n == null || !editable) return false;
    final copy = n.copyWith();
    final p = PlanItem.fromNote(copy);
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      p.fields.remove(key);
    } else {
      p.setField(key, v);
    }
    error = null;
    await _save(p.apply());
    return error == null;
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

  /// Deletes project [uid]. Its notes, tasks and events are kept: they move
  /// to the Personal container (a visible home, unlike the hidden Projects
  /// container the plain note delete would leave them in). Not a project:
  /// the plain [deleteNote]. Undo puts the folder back with its children
  /// under it again.
  Future<void> deleteProject(String uid) async {
    if (!projectIndex.isProject(uid)) return deleteNote(uid);
    final project = tree.find(uid)?.note.copyWith();
    if (project == null) return;
    final home = await ensurePersonalContainer();
    // No Personal container (e.g. the Space changed under us): keep the
    // project and its children rather than orphan them.
    if (home == null) return;
    error = null;
    final kidNotes = [
      for (final n in notes)
        if (n.parentUid == uid) n.copyWith(parentUid: home),
    ];
    final kidTasks = [
      for (final k in tasks)
        if (k.parentUid == uid) k.copyWith(parentUid: home),
    ];
    final kidEvents = [
      for (final k in events)
        if (k.parentUid == uid) k.copyWith(parentUid: home),
    ];
    if (kidNotes.isNotEmpty) {
      await _edit((src) async {
        for (final k in kidNotes) {
          await src.save(k);
        }
      });
      if (error != null) return;
    }
    if (kidTasks.isNotEmpty) {
      await _taskEdit((src) async {
        for (final k in kidTasks) {
          await src.saveTask(k);
        }
      });
      if (error != null) return;
    }
    if (kidEvents.isNotEmpty) {
      await _eventEdit((src) async {
        for (final k in kidEvents) {
          await src.saveEvent(k);
        }
      });
      if (error != null) return;
    }
    await deleteNote(uid);
    if (error != null) return;
    // One Undo puts the folder and everything that was under it back. The
    // children went to Personal, so they are saved again under the project
    // rather than left there.
    // Only children still sitting under Personal come back, and as they are
    // now: a later edit, delete or move is left alone.
    final noteIds = {for (final k in kidNotes) k.uid};
    final taskIds = {for (final k in kidTasks) k.uid};
    final eventIds = {for (final k in kidEvents) k.uid};
    _postUndo('Deleted "${project.summary}"', () async {
      final backNotes = [
        for (final n in notes)
          if (noteIds.contains(n.uid) && n.parentUid == home) n,
      ];
      await _edit((src) async {
        if (tree.find(uid) == null) await src.save(project);
        for (final k in backNotes) {
          await src.save(k.copyWith(parentUid: uid));
        }
      });
      if (error != null) return;
      final backTasks = [
        for (final k in tasks)
          if (taskIds.contains(k.uid) && k.parentUid == home) k,
      ];
      if (backTasks.isNotEmpty) {
        await _taskEdit((src) async {
          for (final k in backTasks) {
            await src.saveTask(k.copyWith(parentUid: uid));
          }
        });
        if (error != null) return;
      }
      final backEvents = [
        for (final k in events)
          if (eventIds.contains(k.uid) && k.parentUid == home) k,
      ];
      if (backEvents.isNotEmpty) {
        await _eventEdit((src) async {
          for (final k in backEvents) {
            await src.saveEvent(k.copyWith(parentUid: uid));
          }
        });
      }
    });
  }

  /// Adds a note (a child of [parentUid] if given) and selects it.
  Future<void> addNote(
    String title, {
    String? parentUid,
    String? status,
    bool inTab = false,
    bool personal = false,
  }) async {
    final t = title.trim();
    if (t.isEmpty) return;
    final now = DateTime.now().toUtc();
    // Personal items go under the Personal container (created on demand).
    if (personal && parentUid == null) {
      parentUid = await ensurePersonalContainer();
    }
    // Nothing loose under a Projects container (same rule as tasks/events).
    final pn = parentUid == null ? null : tree.find(parentUid)?.note;
    final n = Note(
      uid: newUid(),
      summary: t,
      parentUid: pn != null && isProjectsContainer(pn) ? null : parentUid,
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

  // --- Tasks ---
  //
  // Tasks (VTODO) live in the same server collection as the notes of a Space
  // but in their own store and sync engine. They load with the notes, sync in
  // the same pass ([sync]) and fail separately: a task problem is shown in
  // [taskError] and the sync message, never as [error], and never touches
  // the notes. A Space with no tasks behaves exactly as before.

  /// The open Space's tasks (all, including completed and cancelled).
  List<Task> tasks = [];

  /// A non-fatal task problem (unreadable store, failed task sync); null
  /// when fine. Notes are unaffected by it.
  String? taskError;

  /// Tasks view filters (not saved): which tasks and a tag. The folder is
  /// the one Home scope ([scopeUid]), shared with notes, Day and Today.
  TaskFilter taskFilter = TaskFilter.open;
  String? taskTagFilter;

  void setTaskFilter(TaskFilter f) {
    taskFilter = f;
    notifyListeners();
  }

  void setTaskTagFilter(String? tag) {
    taskTagFilter = taskTagFilter == tag ? null : tag;
    notifyListeners();
  }

  /// True when [t] sits under [uid] (a folder, note or task) at any depth.
  bool taskIsUnder(Task t, String uid) =>
      projectIndex.isUnder(t.parentUid, uid);

  /// True when [e] sits under [uid] (a folder, note or task) at any depth.
  bool eventIsUnder(Event e, String uid) =>
      projectIndex.isUnder(e.parentUid, uid);

  /// Whether task [t] is in the open scope. With no scope (Personal) that is
  /// the loose, individual tasks only: nothing inside a project, and only
  /// those [isMine] says are the user's (project tasks join Personal later,
  /// when they are specifically assigned to the user).
  bool taskInScope(Task t) => scopeUid == null
      ? (!inProjectsLayer(t.uid) && isMine(t))
      : taskIsUnder(t, scopeUid!);

  /// Whether event [e] is in the open scope; Personal means loose events
  /// only, as for [taskInScope].
  bool eventInScope(Event e) => scopeUid == null
      ? (!inProjectsLayer(e.uid) && isMine(e))
      : eventIsUnder(e, scopeUid!);

  /// The events in the open scope, for Home Day and the Today cards.
  List<Event> get scopedEvents => [
    for (final e in events)
      if (eventInScope(e)) e,
  ];

  /// Tasks in the open scope, whatever the tag and status filters say (the
  /// project Overview counts and lists them).
  List<Task> get scopedTasks => [
    for (final t in tasks)
      if (taskInScope(t)) t,
  ];

  /// Tasks completed this week (from Monday; a cancelled one is not done):
  /// the Overview's done tile.
  List<Task> doneThisWeek([DateTime? now]) => doneThisWeekIn(scopeUid, now);

  /// Tasks completed this week in [scope] (a folder at any depth; null means
  /// the whole Space). The one counting rule behind the Overview's done tile
  /// and Home's Space-wide one.
  List<Task> doneThisWeekIn(String? scope, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = wallDay(wallNow(n));
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return [
      for (final t in tasks)
        if ((scope == null || taskIsUnder(t, scope)) &&
            t.isCompleted &&
            t.completed != null &&
            !wallDay(wallNow(t.completed!)).isBefore(monday))
          t,
    ];
  }

  /// Tasks after the Tasks view's tag filter and the open scope (status
  /// filter not applied; see [taskFilter]).
  List<Task> get filteredTasks => [
    for (final t in tasks)
      if ((taskTagFilter == null || t.categories.contains(taskTagFilter)) &&
          taskInScope(t))
        t,
  ];

  /// The task a search hit asked for.
  String? selectedTaskUid;

  /// Tasks can be written only in a Space (the read-only dev feed rejects).
  bool get tasksEditable => source is SpaceNoteSource && supportsTasks;

  Future<void> _loadTasks(NoteSource src) async {
    if (src is! SpaceNoteSource || !supportsTasks) {
      tasks = [];
      return;
    }
    try {
      final loaded = await src.loadTasks();
      if (src != source) return;
      _setTasks(loaded);
      taskError = null;
    } catch (e) {
      if (src != source) return;
      tasks = [];
      _dropCaches();
      taskError = 'Tasks could not be read: $e';
    }
  }

  void _setTasks(List<Task> loaded) {
    tasks = List.unmodifiable(loaded);
    _dropCaches();
    _taskDrafts.removeWhere((u, _) => !tasks.any((t) => t.uid == u));
    if (selectedTaskUid != null && _taskById(selectedTaskUid!) == null) {
      selectedTaskUid = null;
    }
    if (peekUid != null && findItem(peekUid!) == null) _setPeek(null);
    if (_tabsLoaded) _pruneTabs();
    if (taskTagFilter != null && !taskTags.contains(taskTagFilter)) {
      taskTagFilter = null;
    }
    if (scopeUid != null && tree.find(scopeUid!) == null) scopeUid = null;
  }

  Task? _taskById(String uid) {
    for (final t in tasks) {
      if (t.uid == uid) return t;
    }
    return null;
  }

  Task? taskById(String uid) => _taskById(uid);

  Set<String> _allDraftUids() => {
    ..._drafts.keys,
    ..._taskDrafts.keys,
    ..._eventDrafts.keys,
  };

  /// The item (a [Note], a [Task] or an [Event]) with this uid, or null.
  /// Parents of tasks may be any of them.
  Object? findItem(String uid) =>
      tree.find(uid)?.note ?? _taskById(uid) ?? _eventById(uid);

  /// The one "is this mine" seam Home reads for its personal lists. Today
  /// everything in the Space is the user's own (true for every item); later
  /// this reads an assignee or owner tag (a missing owner means everyone, so
  /// stored data needs no migration). No other multi-user filter exists.
  bool isMine(Object item) => true;

  // Selectors. [now] defaults to the current time (tests pass their own).

  /// Open tasks (not completed, not cancelled) in the open scope: overdue
  /// first, then by due date, priority, title.
  List<Task> openTasks([DateTime? now]) => scopeUid == null
      ? [
          for (final t in openTasksIn(null, now))
            if (taskInScope(t)) t,
        ]
      : openTasksIn(scopeUid, now);

  /// Open tasks in [scope] (a folder at any depth; null means the whole
  /// Space), ordered as [openTasks]. The one counting rule behind the
  /// Overview's tiles and Home's Space-wide ones.
  List<Task> openTasksIn(String? scope, [DateTime? now]) {
    final n = now ?? DateTime.now();
    return [
      for (final t in tasks)
        if (!t.isClosed && (scope == null || taskIsUnder(t, scope))) t,
    ]..sort((a, b) => compareTasks(a, b, n));
  }

  /// Open tasks past due in [scope] (a folder at any depth; null means the
  /// whole Space), in [openTasksIn] order. One rule for the Overview, Home
  /// and the project page.
  List<Task> overdueIn(String? scope, [DateTime? now]) {
    final n = now ?? DateTime.now();
    return [
      for (final t in openTasksIn(scope, n))
        if (isTaskOverdue(t, n)) t,
    ];
  }

  /// Open tasks past due in the open scope (see [isTaskOverdue] for how zoned
  /// times are treated), most overdue first.
  List<Task> overdueTasks([DateTime? now]) {
    final n = now ?? DateTime.now();
    return [
      for (final t in openTasks(n))
        if (isTaskOverdue(t, n)) t,
    ];
  }

  /// Open tasks due on the user's current day, not yet past due.
  List<Task> dueTodayTasks([DateTime? now]) {
    final n = now ?? DateTime.now();
    return [
      for (final t in openTasks(n))
        if (isTaskDueToday(t, n) && !isTaskOverdue(t, n)) t,
    ];
  }

  /// Completed tasks, latest completion first.
  List<Task> completedTasks() =>
      [
        for (final t in tasks)
          if (t.isCompleted) t,
      ]..sort(
        (a, b) => (b.completed ?? b.lastModified ?? DateTime(0)).compareTo(
          a.completed ?? a.lastModified ?? DateTime(0),
        ),
      );

  /// Tasks directly under [parentUid] (a note or a task). Null gives the top
  /// level: no parent, or a parent that does not exist (a missing parent
  /// falls back to the top level, as for notes). Open tasks first.
  List<Task> tasksByParent(String? parentUid, [DateTime? now]) {
    final n = now ?? DateTime.now();
    bool top(Task t) => t.parentUid == null || findItem(t.parentUid!) == null;
    return [
      for (final t in tasks)
        if (parentUid == null ? top(t) : t.parentUid == parentUid) t,
    ]..sort((a, b) {
      if (a.isClosed != b.isClosed) return a.isClosed ? 1 : -1;
      return compareTasks(a, b, n);
    });
  }

  /// Tags used on tasks (without the `status-`/`kind-` markers), sorted.
  List<String> get taskTags => ({
    for (final t in tasks)
      for (final c in t.categories)
        if (!c.startsWith('status-') && !c.startsWith('kind-')) c,
  }.toList()..sort());

  /// The user-facing tags of [t] (no `status-`/`kind-` markers).
  List<String> taskTagsOf(Task t) => _plainTags(t.categories);

  /// The user-facing tags of [n] (no `status-`/`kind-` markers).
  List<String> noteTagsOf(Note n) => _plainTags(n.categories);

  /// Sets a note's labels, with Undo (the board card's labels picker).
  Future<bool> updateNoteTags(String uid, List<String> tags) async {
    final n = tree.find(uid)?.note;
    if (n == null || !editable) return false;
    final before = _plainTags(n.categories);
    await updateNote(uid, tags: tags);
    if (error != null) return false;
    if (!listEquals(before, _plainTags(tags))) {
      _postUndo(
        'Labels of "${n.summary}" changed',
        () => _restoreNoteTags(uid, before),
      );
    }
    return true;
  }

  Future<void> _restoreNoteTags(String uid, List<String> tags) async {
    final n = tree.find(uid)?.note;
    if (n == null) return;
    await updateNote(uid, tags: tags);
  }

  /// Title of the nearest folder above item [uid], or null at the top level.
  String? folderNameOf(String uid) {
    var cur = switch (findItem(uid)) {
      Task t => t.parentUid,
      Note n => n.parentUid,
      _ => null,
    };
    for (var i = 0; cur != null && i <= tasks.length + notes.length; i++) {
      final item = findItem(cur);
      if (item is Note && AppState.isFolder(item)) return item.summary;
      cur = item is Task
          ? item.parentUid
          : item is Note
          ? item.parentUid
          : null;
    }
    return null;
  }

  bool isOverdue(Task t, [DateTime? now]) =>
      isTaskOverdue(t, now ?? DateTime.now());

  /// Why task [uid] cannot be completed, or null when it can.
  String? taskCompletionBlockerFor(String uid) {
    final t = _taskById(uid);
    return t == null ? null : taskCompletionBlocker(t);
  }

  /// True when task [uid] may sit under [parentUid] (null: the top level):
  /// the parent exists as a note or a task and is not the task itself or
  /// one of its descendants.
  bool canMoveTask(String uid, String? parentUid) {
    if (_taskById(uid) == null) return false;
    if (parentUid == null) return true;
    if (parentUid == uid || findItem(parentUid) == null) return false;
    // Walk up from the new parent through tasks and notes: meeting the task
    // itself would make a loop.
    var cur = parentUid;
    for (var i = 0; i <= tasks.length + notes.length; i++) {
      if (cur == uid) return false;
      final t = _taskById(cur);
      final next = t != null ? t.parentUid : tree.find(cur)?.note.parentUid;
      if (next == null) return true;
      cur = next;
    }
    return false;
  }

  /// Saves, reloads the tasks and syncs. False (with [error] set when the
  /// cause is the Space) if nothing was saved.
  Future<bool> _taskEdit(
    Future<void> Function(SpaceNoteSource src) change,
  ) async {
    final src = source;
    if (src is! SpaceNoteSource) {
      error = 'This space is read-only.';
      notifyListeners();
      return false;
    }
    String? notSaved;
    try {
      try {
        await change(src);
      } on StorageWriteException catch (e) {
        notSaved = '$e';
      }
      final loaded = await src.loadTasks();
      if (src != source) return true;
      _setTasks(loaded);
      error = notSaved;
    } catch (e) {
      if (src != source) return false;
      error = 'Save failed: $e';
      notifyListeners();
      return false;
    }
    notifyListeners();
    if (connected) sync();
    return true;
  }

  /// Adds a task and returns its uid, or null (empty title, read-only Space,
  /// failure). [tags] never carry `status-`/`kind-` markers.
  Future<String?> addTask(
    String title, {
    String? description,
    String? parentUid,
    ICalDate? due,
    int? priority,
    List<String> tags = const [],
    bool personal = false,
  }) async {
    final t = title.trim();
    if (t.isEmpty) return null;
    final now = DateTime.now().toUtc();
    final parent = personal && parentUid == null
        ? await ensurePersonalContainer()
        : _parentOrScope(parentUid);
    final task = Task(
      uid: newUid(),
      summary: t,
      description: description ?? '',
      status: 'NEEDS-ACTION',
      due: due,
      priority: priority,
      parentUid: parent,
      categories: _plainTags(tags),
      created: now,
      lastModified: now,
    );
    return await _taskEdit((src) => src.saveTask(task)) ? task.uid : null;
  }

  /// [parentUid] when it exists, else the open scope folder (new items go
  /// under the scope, so a project's items stay in the project).
  String? _parentOrScope(String? parentUid) {
    if (parentUid != null && findItem(parentUid) != null) return parentUid;
    if (parentUid == null && scopeUid != null) {
      final sc = tree.find(scopeUid!)?.note;
      // A Projects container is no place for loose items: they would be
      // invisible on the Projects panel. Treat it as no scope.
      if (sc != null && !isProjectsContainer(sc)) return scopeUid;
    }
    return null;
  }

  static List<String> _plainTags(Iterable<String> tags) => [
    for (final c in tags)
      if (c.trim().isNotEmpty &&
          !c.startsWith('status-') &&
          !c.startsWith('kind-'))
        c.trim(),
  ];

  /// Changes a task. Only what is passed changes; [setParent], [setDue],
  /// [setStart] and [setPriority] say that a null value means "clear". A
  /// parent move that is not valid (see [canMoveTask]) is dropped and the rest
  /// saves. Returns false when nothing was saved.
  Future<bool> updateTask(
    String uid, {
    String? title,
    String? description,
    List<String>? tags,
    bool setParent = false,
    String? parentUid,
    bool setDue = false,
    ICalDate? due,
    bool setStart = false,
    ICalDate? start,
    bool setPriority = false,
    int? priority,
  }) async {
    final t = _taskById(uid);
    if (t == null) return false;
    final sum = title?.trim();
    if (sum != null && sum.isEmpty) return false;
    final move = setParent && canMoveTask(uid, parentUid);
    final copy = t.copyWith(
      summary: sum,
      description: description,
      parentUid: move ? parentUid : null,
      clearParent: move && parentUid == null,
      due: setDue ? due : null,
      clearDue: setDue && due == null,
      dtstart: setStart ? start : null,
      clearStart: setStart && start == null,
      priority: setPriority ? priority : null,
      clearPriority: setPriority && priority == null,
    );
    if (tags != null) {
      copy.categories = [
        ...t.categories.where(
          (c) => c.startsWith('status-') || c.startsWith('kind-'),
        ),
        ..._plainTags(tags),
      ];
    }
    return _taskEdit((src) => src.saveTask(copy));
  }

  /// Completes ([done] true) or reopens task [uid]. A repeating task cannot
  /// be completed yet ([taskCompletionBlockerFor] says why): this returns
  /// false and changes nothing. Reopening is always allowed.
  Future<bool> setTaskDone(String uid, bool done) async {
    final t = _taskById(uid);
    if (t == null) return false;
    if (done && taskCompletionBlocker(t) != null) return false;
    // Reopening also applies to a cancelled task.
    if (done ? t.isCompleted : !t.isClosed) return false;
    final copy = t.copyWith();
    if (done) {
      copy.complete(DateTime.now());
    } else {
      copy.reopen();
    }
    return _taskEdit((src) => src.saveTask(copy));
  }

  /// Flips completion: complete an open task, reopen a closed one.
  Future<bool> toggleTask(String uid) async {
    final t = _taskById(uid);
    return t == null ? false : setTaskDone(uid, !t.isClosed);
  }

  /// Moves a task to a board status word (`todo`, `doing`, `done`, ...);
  /// `done` follows the same repeating-task rule as [setTaskDone].
  Future<bool> setTaskStatus(
    String uid,
    String word, {
    bool undoable = true,
  }) async {
    final t = _taskById(uid);
    if (t == null) return false;
    if (word == 'done' && taskCompletionBlocker(t) != null) return false;
    final before = t.boardStatus;
    final beforeState = _TaskStatusState(t);
    final title = t.summary;
    final copy = t.copyWith()..setBoardStatus(word, DateTime.now());
    final ok = await _taskEdit((src) => src.saveTask(copy));
    if (ok && undoable && before != word) {
      _postUndo(
        'Moved "$title" to $word',
        () => _restoreItem(uid, setStatus: true, taskState: beforeState),
      );
    }
    return ok;
  }

  /// Sets a task's priority (a [priority] of null clears it), with Undo.
  Future<bool> setTaskPriority(String uid, int? priority) async {
    final t = _taskById(uid);
    if (t == null) return false;
    final before = t.priority;
    final title = t.summary;
    final ok = await updateTask(uid, setPriority: true, priority: priority);
    if (ok && before != priority) {
      _postUndo(
        _priorityLabel(title, _priorityWordOf(priority)),
        () => _restoreItem(uid, setPriority: true, priorityInt: before),
      );
    }
    return ok;
  }

  static String? _priorityWordOf(int? p) {
    if (p == null || p <= 0) return null;
    return p <= 4
        ? 'high'
        : p == 5
        ? 'medium'
        : 'low';
  }

  /// Sets a task's due date (null clears it), with Undo.
  Future<bool> setTaskDue(String uid, ICalDate? due) async {
    final t = _taskById(uid);
    if (t == null) return false;
    final before = t.due;
    final title = t.summary;
    final ok = await updateTask(uid, setDue: true, due: due);
    if (ok && before != due) {
      _postUndo(
        due == null
            ? 'Due date of "$title" cleared'
            : 'Due date of "$title" changed',
        () => _restoreItem(uid, setDue: true, due: before),
      );
    }
    return ok;
  }

  /// Sets when a task starts (null clears it), with Undo.
  Future<bool> setTaskStart(String uid, ICalDate? start) async {
    final t = _taskById(uid);
    if (t == null) return false;
    final before = t.dtstart;
    final title = t.summary;
    final ok = await updateTask(uid, setStart: true, start: start);
    if (ok && before != start) {
      _postUndo(
        start == null
            ? 'Start date of "$title" cleared'
            : 'Start date of "$title" changed',
        () => _restoreItem(uid, setStart: true, start: before),
      );
    }
    return ok;
  }

  /// Moves a task under another note or task (null is the top level), with
  /// Undo. A move [canMoveTask] rejects changes nothing and returns false.
  Future<bool> setTaskParent(String uid, String? parentUid) async {
    final t = _taskById(uid);
    if (t == null) return false;
    if (!canMoveTask(uid, parentUid)) return false;
    final before = t.parentUid;
    final title = t.summary;
    final ok = await updateTask(uid, setParent: true, parentUid: parentUid);
    if (ok && before != parentUid) {
      _postUndo(
        parentUid == null
            ? 'Moved "$title" to the top level'
            : 'Moved "$title"',
        () => _restoreItem(uid, setParent: true, parentUid: before),
      );
    }
    return ok;
  }

  /// Sets a task's labels, with Undo.
  Future<bool> setTaskTags(String uid, List<String> tags) async {
    final t = _taskById(uid);
    if (t == null) return false;
    final before = _plainTags(t.categories);
    final title = t.summary;
    final ok = await updateTask(uid, tags: tags);
    if (ok && !listEquals(before, _plainTags(tags))) {
      _postUndo(
        'Labels of "$title" changed',
        () => _restoreItem(uid, setTags: true, tags: before),
      );
    }
    return ok;
  }

  /// Drops a Home board card into [column]. With [index] (the insertion
  /// point among the column's other cards, in shown order) the card is placed
  /// there by writing a manual rank ([planRanks]: normally one write; more
  /// only when ranks must be given to unranked cards above or the column is
  /// re-spread). Without it only the status changes and the card's old rank
  /// is dropped so it does not jump to an arbitrary place. A card already in
  /// [column] with no [index] is left alone.
  Future<void> placeBoardItem(String uid, String column, {int? index}) async {
    String? from;
    final others = <(String, double?)>[];
    final byUid = <String, BoardItem>{};
    for (final (name, items) in homeColumns(all: true)) {
      for (final i in items) {
        byUid[i.uid] = i;
        if (i.uid == uid) from = name;
        if (name == column && i.uid != uid) others.add((i.uid, i.rank));
      }
    }
    final moved = byUid[uid];
    if (moved == null) return;
    final plan = index == null
        ? const <String, double>{}
        : planRanks(others, index, uid);
    final changed = from != column;
    if (!changed && index == null) return;
    final now = DateTime.now();
    final title = moved.isTask ? moved.task!.summary : moved.note!.summary;
    final beforeStatus = moved.isTask
        ? moved.task!.boardStatus
        : PlanItem.fromNote(moved.note!).status;
    final beforeState = moved.isTask ? _TaskStatusState(moved.task!) : null;
    final beforeRanks = <String, double?>{
      for (final id in {uid, ...plan.keys})
        if (byUid[id] != null) id: byUid[id]!.rank,
    };
    final noteSaves = <Note>[], taskSaves = <Task>[];
    for (final id in {uid, ...plan.keys}) {
      final item = byUid[id];
      if (item == null) continue;
      final status = id == uid && changed;
      final double? rank = plan.containsKey(id)
          ? plan[id]
          : (status ? null : item.rank);
      if (item.isTask) {
        final copy = item.task!.copyWith();
        if (status) {
          if (column == 'done' && taskCompletionBlocker(copy) != null) return;
          copy.setBoardStatus(column, now);
        }
        copy.rank = rank;
        taskSaves.add(copy);
      } else {
        var copy = item.note!.copyWith();
        if (status) copy = (PlanItem.fromNote(copy)..setStatus(column)).apply();
        copy.rank = rank;
        noteSaves.add(copy);
      }
    }
    if (noteSaves.isNotEmpty) {
      await _edit((src) async {
        for (final n in noteSaves) {
          await src.save(n);
        }
      });
    }
    if (taskSaves.isNotEmpty) {
      await _taskEdit((src) async {
        for (final t in taskSaves) {
          await src.saveTask(t);
        }
      });
    }
    if (error == null) {
      _postUndo(
        changed ? 'Moved "$title" to $column' : 'Moved "$title" in $column',
        () => _restorePlacement(
          uid,
          changed: changed,
          status: beforeStatus,
          taskState: beforeState,
          ranks: beforeRanks,
        ),
      );
    }
  }

  /// Undo of [placeBoardItem]: the moved card's status and the rank of every
  /// card the drop wrote. Cards deleted meanwhile are skipped.
  Future<void> _restorePlacement(
    String uid, {
    required bool changed,
    required String? status,
    required _TaskStatusState? taskState,
    required Map<String, double?> ranks,
  }) async {
    final noteSaves = <Note>[], taskSaves = <Task>[];
    for (final e in ranks.entries) {
      final id = e.key;
      final isMoved = id == uid;
      final t = _taskById(id);
      if (t != null) {
        final copy = t.copyWith();
        if (isMoved && changed && taskState != null) {
          taskState.applyTo(copy);
          if (taskState.status == 'COMPLETED' &&
              taskCompletionBlocker(copy) != null) {
            error = taskCompletionBlocker(copy);
            notifyListeners();
            return;
          }
        }
        copy.rank = e.value;
        taskSaves.add(copy);
        continue;
      }
      final n = tree.find(id)?.note;
      if (n == null) continue;
      var copy = n.copyWith();
      if (isMoved && changed) {
        final p = PlanItem.fromNote(copy);
        if (status == null) {
          p.clearStatus();
        } else {
          p.setStatus(status);
        }
        copy = p.apply();
      }
      copy.rank = e.value;
      noteSaves.add(copy);
    }
    if (noteSaves.isNotEmpty) {
      await _edit((src) async {
        for (final n in noteSaves) {
          await src.save(n);
        }
      });
    }
    if (taskSaves.isNotEmpty) {
      await _taskEdit((src) async {
        for (final t in taskSaves) {
          await src.saveTask(t);
        }
      });
    }
  }

  /// Deletes a task; its sub-tasks and sub-notes move up to its parent so
  /// none are lost.
  Future<bool> deleteTask(String uid) async {
    final t = _taskById(uid);
    if (t == null) return false;
    final parent = t.parentUid;
    final kidTasks = [
      for (final k in tasks)
        if (k.parentUid == uid) k.copyWith(),
    ];
    final kidNotes = [
      for (final n in notes)
        if (n.parentUid == uid) n.copyWith(),
    ];
    final ok = await _taskEdit((src) async {
      for (final k in kidTasks) {
        await src.saveTask(
          parent == null
              ? k.copyWith(clearParent: true)
              : k.copyWith(parentUid: parent),
        );
      }
      for (final k in kidNotes) {
        await src.save(
          parent == null
              ? k.copyWith(clearParent: true)
              : k.copyWith(parentUid: parent),
        );
      }
      await src.deleteTask(uid);
    });
    if (ok) {
      _taskDrafts.remove(uid);
      if (kidNotes.isNotEmpty && source is SpaceNoteSource) {
        try {
          _setNotes(await (source as SpaceNoteSource).load());
        } catch (_) {}
      }
      notifyListeners();
    }
    return ok;
  }

  // Task drafts: one per task being edited, like the note drafts.

  final Map<String, TaskDraft> _taskDrafts = {};

  List<TaskDraft> get taskDrafts => List.unmodifiable(_taskDrafts.values);
  TaskDraft? taskDraftFor(String uid) => _taskDrafts[uid];
  bool dirtyTaskFor(String uid) => _taskDrafts[uid]?.dirty ?? false;

  /// Gives the area showing [uid] the focus, so the edit keys act on it.
  void _focusEditor(String uid) =>
      nav.focusArea(uid == mainItemUid ? NavArea.main : NavArea.peek);

  /// Opens the text buffer of task [uid] (no-op if read-only or unknown) and
  /// focuses one of its inline fields: the title, or the description with
  /// [focusBody] (a tap on the value it edits). It stays open until the page
  /// leaves it, so typing survives a sync; [saveTaskDraft] keeps its text.
  /// Edit keys act on the focused area: the area that shows [uid] takes the
  /// focus when its edit starts.
  void startTaskEdit(String uid, {bool focusBody = false}) {
    final t = _taskById(uid);
    if (t == null || !tasksEditable) return;
    if (!_taskDrafts.containsKey(uid)) {
      final d = TaskDraft(uid: uid, title: t.summary, body: t.description);
      _taskDrafts[uid] = d;
      _watchDraft(uid, d);
    }
    // The field the page builds next opens and takes the focus (a tap on the
    // value, or `e` on the item).
    taskTextIntent = (uid: uid, body: focusBody);
    _focusEditor(uid);
    notifyListeners();
  }

  /// The task text field a tap on a value (or `e`) asked to open, waiting for
  /// the page to build it; null when none is waiting.
  ({String uid, bool body})? taskTextIntent;

  /// Whether the field of task [uid] is the one the last tap asked for.
  bool taskTextTargets(String uid, {required bool body}) =>
      taskTextIntent?.uid == uid && taskTextIntent!.body == body;

  /// The field the intent named has opened: the next build does not open it
  /// again.
  void clearTaskTextIntent() => taskTextIntent = null;

  /// Saves the open text buffer of task [uid] (the typing pause, a blur, a
  /// picker opening, the page going away) and says why when it cannot.
  Future<bool> commitTaskText(String uid) async {
    final ok = await flushEdit(uid);
    if (!ok) reportNotSaved(_notSavedReason(uid));
    return ok;
  }

  /// Saves the text buffer of task [uid]: only the field that changed, so a
  /// value written elsewhere (a pick, an undo, a sync) is never put back by
  /// this save. Text typed while the save runs stays as the draft, still
  /// dirty. False if nothing was saved.
  Future<bool> saveTaskDraft(String uid, {bool stay = false}) async {
    final d = _taskDrafts[uid];
    if (d == null || d.titleEmpty) return false;
    final title = d.titleDirty ? d.titleController.text : null;
    final body = d.bodyDirty ? d.bodyController.text : null;
    if (title == null && body == null) {
      if (!stay) _taskDrafts.remove(uid);
      notifyListeners();
      return true;
    }
    final ok = await updateTask(uid, title: title, description: body);
    if (!ok) return false;
    if (_taskDrafts[uid] == d) {
      d.markSaved(title: title, body: body);
      if (!d.dirty && !stay) _taskDrafts.remove(uid);
    }
    notifyListeners();
    return true;
  }

  // --- Events ---
  //
  // Events (VEVENT) live in the same server collection as the notes and tasks
  // of a Space, sync in the same pass ([sync]) and fail separately: an event
  // problem is shown in [eventError] and the sync message, never as [error],
  // and never touches notes or tasks. Times are wall-clock fields (no time
  // zone database): "now" is the user's local clock read the same way. A
  // Space with no events behaves exactly as before.

  /// The open Space's events.
  List<Event> events = [];

  /// A non-fatal event problem (unreadable store, failed event sync); null
  /// when fine.
  String? eventError;

  /// Events can be written only in a Space (the read-only dev feed rejects).
  bool get eventsEditable => source is SpaceNoteSource && supportsEvents;

  Future<void> _loadEvents(NoteSource src) async {
    if (src is! SpaceNoteSource || !supportsEvents) {
      events = [];
      return;
    }
    try {
      final loaded = await src.loadEvents();
      if (src != source) return;
      _setEvents(loaded);
      eventError = null;
    } catch (e) {
      if (src != source) return;
      events = [];
      _dropCaches();
      eventError = 'Calendar could not be read: $e';
    }
  }

  void _setEvents(List<Event> loaded) {
    events = List.unmodifiable(loaded);
    _dropCaches();
    if (eventTagFilter != null && !eventTags.contains(eventTagFilter)) {
      eventTagFilter = null;
    }
    // An edit with unsaved text outlives its event (deleted elsewhere, e.g.
    // by a sync): it stays, and [orphanDraftNotice] says so.
    _eventDrafts.removeWhere(
      (u, d) => !d.dirty && !events.any((e) => e.uid == u),
    );
    if (peekUid != null && findItem(peekUid!) == null) _setPeek(null);
    if (_tabsLoaded) _pruneTabs();
  }

  static const _goneNote =
      'This note was deleted elsewhere. Your edit is kept.';

  bool _noteGone(NoteDraft d) => tree.find(d.uid) == null;
  bool _eventGone(EventDraft d) => !events.any((e) => e.uid == d.uid);

  /// Dirty note and event edits whose item is gone (deleted elsewhere, e.g.
  /// by a sync). They are kept so the text is not lost; saving one returns
  /// false and [discardOrphanDrafts] drops them.
  int get orphanDraftCount =>
      _drafts.values.where((d) => d.dirty && _noteGone(d)).length +
      _eventDrafts.values.where((d) => d.dirty && _eventGone(d)).length;

  /// A notice while [orphanDraftCount] is above zero; null otherwise.
  String? get orphanDraftNotice {
    final n = orphanDraftCount;
    if (n == 0) return null;
    return n == 1
        ? 'An item you are editing was deleted elsewhere. Your unsaved edit is kept.'
        : '$n items you are editing were deleted elsewhere. Your unsaved edits are kept.';
  }

  /// Drops the kept edits of deleted items.
  void discardOrphanDrafts() {
    _drafts.removeWhere((_, d) => _noteGone(d));
    _eventDrafts.removeWhere((_, d) => _eventGone(d));
    if (error == _goneNote) error = null;
    notifyListeners();
  }

  Event? _eventById(String uid) {
    for (final e in events) {
      if (e.uid == uid) return e;
    }
    return null;
  }

  Event? eventById(String uid) => _eventById(uid);

  /// Tags used on events (without the `status-`/`kind-` markers), sorted.
  List<String> get eventTags =>
      ({for (final e in events) ..._plainTags(e.categories)}.toList()..sort());

  List<String> eventTagsOf(Event e) => _plainTags(e.categories);

  /// Events panel tag filter (not saved); null shows every event.
  String? eventTagFilter;

  void setEventTagFilter(String? tag) {
    eventTagFilter = eventTagFilter == tag ? null : tag;
    notifyListeners();
  }

  /// Events after the folder scope and tag filter, for the agenda (past
  /// included).
  List<Event> get filteredEvents => [
    for (final e in events)
      if (eventInScope(e) &&
          (eventTagFilter == null || e.categories.contains(eventTagFilter)))
        e,
  ];

  /// Agenda groups from the day of [from] for [days] days: Today, Tomorrow,
  /// This week, Later (empty groups left out). Recurring events are expanded;
  /// see [upcomingGroups].
  List<AgendaGroup> upcomingOccurrences(DateTime from, int days) =>
      upcomingGroups(filteredEvents, from, days);

  /// Occurrences that ended before the day of [from], within the last [days]
  /// days, latest first.
  List<EventOccurrence> pastOccurrences(DateTime from, [int days = 30]) =>
      pastAgenda(filteredEvents, from, days);

  /// Saves, reloads the events and syncs. False (with [error] set when the
  /// cause is the Space) if nothing was saved.
  Future<bool> _eventEdit(
    Future<void> Function(SpaceNoteSource src) change,
  ) async {
    final src = source;
    if (src is! SpaceNoteSource) {
      error = 'This space is read-only.';
      notifyListeners();
      return false;
    }
    String? notSaved;
    try {
      try {
        await change(src);
      } on StorageWriteException catch (e) {
        notSaved = '$e';
      }
      final loaded = await src.loadEvents();
      if (src != source) return true;
      _setEvents(loaded);
      error = notSaved;
    } catch (e) {
      if (src != source) return false;
      error = 'Save failed: $e';
      notifyListeners();
      return false;
    }
    notifyListeners();
    if (connected) sync();
    return true;
  }

  /// Adds an event and returns its uid, or null (empty title, read-only
  /// Space, failure). [start] and [end] are wall-clock fields; for an
  /// [allDay] event only their dates count and [end] is the last day,
  /// inclusive (default: [start]'s day). A timed event without [end] has no
  /// end. A new timed event is a floating time (no zone).
  Future<String?> addEvent(
    String title, {
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String location = '',
    String? description,
    List<String> tags = const [],
    bool personal = false,
  }) async {
    final t = title.trim();
    if (t.isEmpty) return null;
    final now = DateTime.now().toUtc();
    final first = allDay ? wallDay(start) : start;
    ICalDate? last;
    if (allDay) {
      final day = end == null ? first : wallDay(end);
      last = eventDate(
        (day.isBefore(first) ? first : day).add(const Duration(days: 1)),
        allDay: true,
      );
    } else if (end != null && end.isAfter(start)) {
      last = eventDate(end);
    }
    final event = Event(
      uid: newUid(),
      summary: t,
      description: description ?? '',
      location: location.trim(),
      categories: _plainTags(tags),
      parentUid: personal
          ? await ensurePersonalContainer()
          : _parentOrScope(null),
      dtstart: eventDate(first, allDay: allDay),
      dtend: last,
      created: now,
      lastModified: now,
    );
    return await _eventEdit((src) => src.saveEvent(event)) ? event.uid : null;
  }

  /// Changes an event (a recurring one: the whole series; overrides, EXDATEs
  /// and other lines follow a changed start). Only what is passed changes;
  /// [setStatus] says that a null [status] means "clear"; [setWhen] applies
  /// [allDay], [start] and [end] (all-day end inclusive, see [addEvent]) and
  /// keeps the zone flavour of the old value (a UTC event is written back as UTC;
  /// [start] and [end] are local). A new start moves EXDATE, RDATE and the
  /// overrides by the same amount. Returns false when nothing was
  /// saved.
  Future<bool> updateEvent(
    String uid, {
    String? title,
    String? description,
    String? location,
    List<String>? tags,
    bool setStatus = false,
    String? status,
    bool setWhen = false,
    bool allDay = false,
    DateTime? start,
    DateTime? end,
    bool setRrule = false,
    String? rrule,
  }) async {
    final e = _eventById(uid);
    if (e == null) return false;
    final sum = title?.trim();
    if (sum != null && sum.isEmpty) return false;
    var copy = e.copyWith(
      summary: sum,
      description: description,
      location: location?.trim(),
      status: setStatus ? status : null,
      clearStatus: setStatus && status == null,
      rrule: setRrule ? rrule : null,
      clearRrule: setRrule && (rrule == null || rrule.isEmpty),
      // No rule left: its exceptions and changed occurrences go with it.
      exdates: setRrule && (rrule == null || rrule.isEmpty) ? [] : null,
      rdates: setRrule && (rrule == null || rrule.isEmpty) ? [] : null,
      siblingLines: setRrule && (rrule == null || rrule.isEmpty) ? [] : null,
    );
    if (setWhen && start != null) {
      final first = allDay ? wallDay(start) : start;
      var last = end ?? first;
      if (last.isBefore(first)) last = first;
      final from = eventDate(first, allDay: allDay, like: e.dtstart);
      final old = e.startWall;
      final hasExtras =
          copy.exdates.isNotEmpty ||
          copy.rdates.isNotEmpty ||
          copy.siblingLines.isNotEmpty;
      if (hasExtras && old != null) {
        if (allDay != e.allDay) {
          error =
              'A repeating event with excluded or changed occurrences '
              'cannot switch between all day and timed.';
          notifyListeners();
          return false;
        }
        // Keep EXDATE, RDATE and the overrides on the same instances: move
        // them by the same amount as the start (their lengths stay).
        final delta = first.difference(old);
        if (delta != Duration.zero) {
          copy = copy.copyWith(
            exdates: [for (final l in copy.exdates) shiftDateLine(l, delta)],
            rdates: [for (final l in copy.rdates) shiftDateLine(l, delta)],
            siblingLines: shiftSiblingLines(copy.siblingLines, delta),
          );
        }
      }
      if (allDay) {
        copy = copy.copyWith(
          dtstart: from,
          dtend: eventDate(
            wallDay(last).add(const Duration(days: 1)),
            allDay: true,
          ),
          clearDuration: true,
        );
      } else if (last == first) {
        copy = copy.copyWith(
          dtstart: from,
          clearEnd: true,
          clearDuration: true,
        );
      } else {
        copy = copy.copyWith(
          dtstart: from,
          dtend: eventDate(last, like: e.dtend ?? e.dtstart),
          clearDuration: true,
        );
      }
    }
    if (tags != null) {
      copy.categories = [
        ...e.categories.where(
          (c) => c.startsWith('status-') || c.startsWith('kind-'),
        ),
        ..._plainTags(tags),
      ];
    }
    return _eventEdit((src) => src.saveEvent(copy));
  }

  /// Deletes an event (the whole series); tasks under it move up to its
  /// parent so none are lost.
  Future<bool> deleteEvent(String uid) async {
    final e = _eventById(uid);
    if (e == null) return false;
    final parent = e.parentUid;
    final kidTasks = [
      for (final k in tasks)
        if (k.parentUid == uid) k.copyWith(),
    ];
    final ok = await _eventEdit((src) async {
      for (final k in kidTasks) {
        await src.saveTask(
          parent == null
              ? k.copyWith(clearParent: true)
              : k.copyWith(parentUid: parent),
        );
      }
      await src.deleteEvent(uid);
    });
    if (ok) {
      _eventDrafts.remove(uid);
      if (kidTasks.isNotEmpty && source is SpaceNoteSource) {
        try {
          _setTasks(await (source as SpaceNoteSource).loadTasks());
        } catch (_) {}
      }
      notifyListeners();
    }
    return ok;
  }

  // Event drafts: one per event being edited, like the task drafts.

  final Map<String, EventDraft> _eventDrafts = {};

  List<EventDraft> get eventDrafts => List.unmodifiable(_eventDrafts.values);
  EventDraft? eventDraftFor(String uid) => _eventDrafts[uid];
  bool dirtyEventFor(String uid) => _eventDrafts[uid]?.dirty ?? false;

  /// The all-day flag, start and end an event edit shows (for an all-day
  /// event the end is the last day, inclusive).
  EventWhen _eventWhen(Event e) => eventWhenOf(e);

  /// The text field of an event a tap (or `e`) asks to open.
  void startEventEdit(
    String uid, {
    bool focusBody = false,
    bool focusLocation = false,
  }) {
    final e = _eventById(uid);
    if (e == null || !eventsEditable) return;
    if (!_eventDrafts.containsKey(uid)) {
      final d = EventDraft(
        uid: uid,
        title: e.summary,
        location: e.location,
        body: e.description,
      );
      _eventDrafts[uid] = d;
      _watchDraft(uid, d);
    }
    eventTextIntent = (uid: uid, body: focusBody, location: focusLocation);
    _focusEditor(uid);
    notifyListeners();
  }

  /// The event text field a tap on a value (or `e`) asked to open, waiting for
  /// the page to build it; null when none is waiting.
  ({String uid, bool body, bool location})? eventTextIntent;

  /// Whether the field of event [uid] is the one the last tap asked for.
  bool eventTextTargets(
    String uid, {
    bool body = false,
    bool location = false,
  }) {
    final intent = eventTextIntent;
    if (intent == null || intent.uid != uid || intent.body != body) {
      return false;
    }
    return intent.location == location;
  }

  /// The field the intent named has opened: the next build does not open it
  /// again.
  void clearEventTextIntent() => eventTextIntent = null;

  /// Saves the open text buffer of event [uid] (the typing pause, a blur, a
  /// picker opening, the page going away) and says why when it cannot.
  Future<bool> commitEventText(String uid) async {
    final ok = await flushEdit(uid);
    if (!ok) reportNotSaved(_notSavedReason(uid));
    return ok;
  }

  /// Saves the text buffer of event [uid]: only the field that changed, so a
  /// value written elsewhere (a pick, an undo, a sync) is never put back by
  /// this save. Text typed while the save runs stays as the draft, still
  /// dirty. False if nothing was saved.
  Future<bool> saveEventDraft(String uid, {bool stay = false}) async {
    const gone = 'This event was deleted elsewhere. Your edit is kept.';
    final d = _eventDrafts[uid];
    if (d == null || d.titleEmpty) return false;
    // The event is gone (deleted meanwhile, e.g. by a sync): nothing to save
    // to. The draft stays, so the text is not lost.
    if (_eventGone(d)) {
      error = gone;
      notifyListeners();
      return false;
    }
    final title = d.titleDirty ? d.titleController.text : null;
    final location = d.locationDirty ? d.locationController.text : null;
    final body = d.bodyDirty ? d.bodyController.text : null;
    if (title == null && location == null && body == null) {
      if (!stay) _eventDrafts.remove(uid);
      notifyListeners();
      return true;
    }
    final ok = await updateEvent(
      uid,
      title: title,
      location: location,
      description: body,
    );
    if (!ok) return false;
    // Deleted while this save ran: the reload has no event, so nothing was
    // written. Keep the draft, so the text is not lost.
    if (_eventGone(d)) {
      error = gone;
      notifyListeners();
      return false;
    }
    if (_eventDrafts[uid] == d) {
      d.markSaved(title: title, location: location, body: body);
      if (!d.dirty && !stay) _eventDrafts.remove(uid);
    }
    notifyListeners();
    return true;
  }

  /// Sets an event's status (null clears it), with Undo.
  Future<bool> setEventStatus(String uid, String? status) async {
    final e = _eventById(uid);
    if (e == null) return false;
    final before = e;
    final ok = await updateEvent(uid, setStatus: true, status: status);
    if (ok && before.status != status) {
      _postUndo(
        status == null
            ? 'Status of "${before.summary}" cleared'
            : 'Status of "${before.summary}" set to '
                  '${eventStatusName(status)}',
        () => _restoreEvent(before, status: true),
      );
    }
    return ok;
  }

  /// Moves an event under another note, folder or project (null: the top
  /// level), with Undo.
  Future<bool> setEventParent(String uid, String? parentUid) async {
    final e = _eventById(uid);
    if (e == null) return false;
    if (parentUid != null && findItem(parentUid) == null) return false;
    final before = e;
    final ok = await _eventEdit(
      (src) => src.saveEvent(
        e.copyWith(parentUid: parentUid, clearParent: parentUid == null),
      ),
    );
    if (ok && before.parentUid != parentUid) {
      _postUndo(
        parentUid == null
            ? 'Moved "${before.summary}" to the top level'
            : 'Moved "${before.summary}"',
        () => _restoreEvent(before, parent: true),
      );
    }
    return ok;
  }

  /// Sets an event's labels, with Undo.
  Future<bool> setEventTags(String uid, List<String> tags) async {
    final e = _eventById(uid);
    if (e == null) return false;
    final before = e;
    final beforeTags = _plainTags(e.categories);
    final ok = await updateEvent(uid, tags: tags);
    if (ok && !listEquals(beforeTags, _plainTags(tags))) {
      _postUndo(
        'Labels of "${before.summary}" changed',
        () => _restoreEvent(before, tags: true),
      );
    }
    return ok;
  }

  /// Moves an event to [when] (all day, start and end), with Undo. The guard
  /// on a repeating event whose occurrences were changed separately stays: it
  /// cannot switch between all day and timed.
  Future<bool> setEventWhen(
    String uid,
    EventWhen when, {
    bool undoable = true,
  }) async {
    final e = _eventById(uid);
    if (e == null) return false;
    final before = e;
    final had = _eventWhen(e);
    if (had == when) return true;
    final ok = await updateEvent(
      uid,
      setWhen: true,
      allDay: when.allDay,
      start: when.start,
      end: when.end,
    );
    if (ok && undoable) {
      _postUndo(
        'When of "${before.summary}" changed',
        () => _restoreEvent(before, when: true),
      );
    }
    return ok;
  }

  /// Sets an event's repeat rule (null: no repeat), with Undo. Clearing a rule
  /// also drops its excluded and changed occurrences, which the Undo puts
  /// back.
  Future<bool> setEventRrule(String uid, String? rrule) async {
    final e = _eventById(uid);
    if (e == null) return false;
    final before = e;
    final had = before.rrule ?? '';
    final next = rrule ?? '';
    if (had == next) return true;
    final ok = await updateEvent(uid, setRrule: true, rrule: rrule);
    if (ok) {
      _postUndo(
        next.isEmpty
            ? 'Repeat of "${before.summary}" cleared'
            : 'Repeat of "${before.summary}" changed',
        () => _restoreEvent(before, rrule: true),
      );
    }
    return ok;
  }

  /// Puts back the picked fields of event [before]: its status, labels, when
  /// (start, end and the occurrences moved with them) or its repeat rule
  /// (with the occurrences it had). The event's text and its other fields
  /// stay as they are now.
  Future<void> _restoreEvent(
    Event before, {
    bool status = false,
    bool tags = false,
    bool when = false,
    bool rrule = false,
    bool parent = false,
  }) async {
    final now = _eventById(before.uid);
    if (now == null) return;
    var copy = now.copyWith(
      status: status ? before.status : null,
      clearStatus: status && before.status == null,
      parentUid: parent ? before.parentUid : null,
      clearParent: parent && before.parentUid == null,
      rrule: rrule ? before.rrule : null,
      clearRrule: rrule && (before.rrule == null || before.rrule!.isEmpty),
      exdates: when || rrule ? before.exdates : null,
      rdates: when || rrule ? before.rdates : null,
      siblingLines: when || rrule ? List.of(before.siblingLines) : null,
    );
    if (when) {
      copy = copy.copyWith(
        dtstart: before.dtstart,
        clearStart: before.dtstart == null,
        dtend: before.dtend,
        clearEnd: before.dtend == null,
        duration: before.duration,
        clearDuration: before.duration == null,
      );
    }
    if (tags) {
      copy.categories = [
        ...now.categories.where(
          (c) => c.startsWith('status-') || c.startsWith('kind-'),
        ),
        ..._plainTags(_plainTags(before.categories)),
      ];
    }
    await _eventEdit((src) => src.saveEvent(copy));
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

  /// The task the main pane shows full page, when its tab is a task tab.
  String? get mainTaskUid {
    final t = activeTab;
    return t != null && t.kind == TabKind.task && _taskById(t.id) != null
        ? t.id
        : null;
  }

  /// The event the main pane shows full page, when its tab is an event tab.
  String? get mainEventUid {
    final t = activeTab;
    return t != null && t.kind == TabKind.event && _eventById(t.id) != null
        ? t.id
        : null;
  }

  /// The project whose page fills the main pane, when its tab is one.
  String? get mainProjectUid {
    final t = activeTab;
    return t != null &&
            t.kind == TabKind.project &&
            projectIndex.isProject(t.id)
        ? t.id
        : null;
  }

  /// The tab the open project page shows, if a project tab is active.
  ProjectTab? get mainProjectTab {
    final p = mainProjectUid;
    return p == null ? null : projectTab(p);
  }

  /// The note, task or event the main pane shows full page, if any.
  String? get mainItemUid => mainNoteUid ?? mainTaskUid ?? mainEventUid;

  /// The title of the page the main pane shows: Home, a note, a saved view
  /// or a project. The phone bar names it.
  String get mainPageTitle {
    final t = activeTab;
    if (t == null) return 'Home';
    final title = tabTitle(t);
    return title.isEmpty ? 'Untitled' : title;
  }

  /// Something other than Home or a view fills the main pane: a note, task
  /// or event page.
  bool get mainIsPage => mainItemUid != null;

  String get _tabsKey => 'davdart.tabs.v1.$_spaceKey';
  String get _activeTabKey => 'davdart.activetab.v1.$_spaceKey';

  void _saveTabs() {
    if (!_tabsLoaded) return;
    if (_tabs.tabs.isEmpty) {
      prefs?.remove(_tabsKey);
    } else {
      prefs?.write(_tabsKey, _tabs.encode());
    }
    final a = activeTab;
    if (a == null) {
      prefs?.remove(_activeTabKey);
    } else {
      prefs?.write(_activeTabKey, a.code);
    }
  }

  void _resetTabs() {
    _tabsLoaded = false;
    _tabs.tabs.clear();
    _activeViewTab = null;
    peekCollapsed = false;
    _pageScope.clear();
  }

  /// A tab stays while its kind's list cannot vouch for it: a task or event
  /// load that failed says nothing about which items exist, and so does an
  /// empty list on the first restore of an offline or empty Space. Pruning
  /// then would drop and save the user's tabs for good.
  bool _tabExists(DocTab t) => _tabUnverified(t) || _tabFound(t);

  bool _restoringTabs = false;

  bool _tabUnverified(DocTab t) => switch (t.kind) {
    TabKind.note ||
    TabKind.view ||
    TabKind.project => _restoringTabs && notes.isEmpty,
    TabKind.task => taskError != null || (_restoringTabs && tasks.isEmpty),
    TabKind.event => eventError != null || (_restoringTabs && events.isEmpty),
  };

  bool _tabFound(DocTab t) => switch (t.kind) {
    TabKind.note => tree.find(t.id) != null,
    TabKind.view => _viewNotes.containsKey(t.id),
    TabKind.task => _taskById(t.id) != null,
    TabKind.event => _eventById(t.id) != null,
    TabKind.project => projectIndex.isProject(t.id),
  };

  void _pruneTabs() {
    final wasActive = _activeViewTab;
    if (_tabs.retain(_tabExists)) _saveTabs();
    if (wasActive != null && !_tabs.contains(wasActive)) {
      _activeViewTab = null;
      _pageScope.remove(wasActive);
      // The project page went away: its scope goes with it, and Home starts
      // from what is left.
      if (_pageScope.containsKey(null)) {
        _scopeToPage(null);
      } else {
        _syncScopeToTab();
      }
      _pageScope[null] = scopeUid;
    }
  }

  /// Brings back the tabs saved for this Space, dropping any whose note or
  /// view is gone. The saved active tab takes focus again (Home if none).
  void _restoreTabs() {
    _tabs.decode(prefs?.read(_tabsKey));
    _tabsLoaded = true;
    _restoringTabs = true;
    try {
      _pruneTabs();
    } finally {
      _restoringTabs = false;
    }
    final active = DocTab.parse(prefs?.read(_activeTabKey) ?? '');
    if (active != null && _tabs.contains(active)) _activeViewTab = active;
    _saveTabs();
  }

  /// Opens (or focuses) the main tab of task [uid].
  void openTaskTab(String uid) {
    if (_taskById(uid) == null) return;
    final t = DocTab.task(uid);
    if (_tabs.add(t)) _saveTabs();
    _show(t);
  }

  /// Opens (or focuses) the tab of project [uid]. Projects always open in a
  /// tab (never the peek).
  void openProjectTab(String uid) {
    if (!projectIndex.isProject(uid)) return;
    final t = DocTab.project(uid);
    if (_tabs.add(t)) _saveTabs();
    _show(t);
  }

  /// Opens (or focuses) the main tab of event [uid].
  void openEventTab(String uid) {
    if (_eventById(uid) == null) return;
    final t = DocTab.event(uid);
    if (_tabs.add(t)) _saveTabs();
    _show(t);
  }

  /// Narrow: opens the side menu (set by the shell), the only place the
  /// panels show there.
  VoidCallback? openMenu;

  /// Shows [s] in the side panel; on the phone it opens the side menu too,
  /// the only place the panels show there.
  void openPanel(Section s) {
    setSection(s);
    if (narrow) openMenu?.call();
  }

  void openTasksPanel() => openPanel(Section.tasks);
  void openEventsPanel() => openPanel(Section.events);
  void openSearchPanel() => openPanel(Section.search);

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
    if (uid == null || findItem(uid) == null) return;
    _openTab(uid);
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
    TabKind.task => _taskById(t.id)?.summary ?? '',
    TabKind.event => _eventById(t.id)?.summary ?? '',
    TabKind.project => tree.find(t.id)?.note.summary ?? '',
  };

  bool tabIsFolder(DocTab t) =>
      t.kind == TabKind.note &&
      tree.find(t.id) != null &&
      isFolder(tree.find(t.id)!.note);

  /// Whether the tab's note has unsaved edits.
  bool tabDirty(DocTab t) => switch (t.kind) {
    TabKind.note => dirtyFor(t.id),
    TabKind.task => dirtyTaskFor(t.id),
    TabKind.event => dirtyEventFor(t.id),
    _ => false,
  };

  SavedView? _viewByUid(String uid) {
    for (final v in savedViews) {
      if (v.uid == uid) return v;
    }
    return null;
  }

  /// The scope each page last showed: Home under the null key, a tab under
  /// itself. Leaving a page books its scope, showing it restores it, so a
  /// loose folder scope set on Home survives a trip through a note tab and
  /// closing an unrelated tab changes nothing.
  final Map<DocTab?, String?> _pageScope = {};

  /// Shows [t] (null: home) in the main pane, leaving the active page's scope
  /// behind for its next visit.
  void _show(DocTab? t) => _showFrom(activeTab, t);

  void _showFrom(DocTab? from, DocTab? t) {
    if (from != t) _pageScope[from] = scopeUid;
    _showPage(t);
  }

  /// Shows [t] (null: home) in the main pane without asking about edits.
  void _showPage(DocTab? t) {
    // Narrow: leaving an item saves its pending edit.
    final leaving = activeTab;
    if (narrow && leaving != null && leaving != t && isEditing(leaving.id)) {
      final id = leaving.id;
      unawaited(
        flushEdit(id).then((ok) {
          // The edit stays open in memory; say it is not stored yet.
          if (!ok && isEditing(id) && dirtyItem(id)) {
            onNotSaved?.call(_notSavedReason(id));
          }
        }),
      );
    }
    if (t == null) {
      _activeViewTab = null;
      // Home keeps the scope Home showed before (a project page owns its
      // project, so this is the loose folder scope or none).
      _scopeToPage(null);
      _saveTabs();
      notifyListeners();
    } else if (t.kind == TabKind.note) {
      if (tree.find(t.id) == null) return;
      _activeViewTab = t;
      _scopeToPage(t);
      if (peekUid == t.id) _setPeek(null);
      _saveTabs();
      notifyListeners();
    } else if (t.kind == TabKind.task) {
      if (_taskById(t.id) == null) return;
      _activeViewTab = t;
      _scopeToPage(t);
      if (peekUid == t.id) _setPeek(null);
      _saveTabs();
      notifyListeners();
    } else if (t.kind == TabKind.event) {
      if (_eventById(t.id) == null) return;
      _activeViewTab = t;
      _scopeToPage(t);
      if (peekUid == t.id) _setPeek(null);
      _saveTabs();
      notifyListeners();
    } else if (t.kind == TabKind.project) {
      if (!projectIndex.isProject(t.id)) return;
      _activeViewTab = t;
      _scopeTo(t.id);
      _rememberProject(t.id);
      if (peekUid == t.id) _setPeek(null);
      _saveTabs();
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
      if (t.kind == TabKind.task && peekUid != t.id) _taskDrafts.remove(t.id);
      if (t.kind == TabKind.event && peekUid != t.id) {
        _eventDrafts.remove(t.id);
      }
      _saveTabs();
      // The next page brings back its own scope, booked from the page that
      // was closed: only that page's scope goes with it, so closing any
      // other tab leaves the loose folder scope alone.
      if (wasActive) {
        final visited = _pageScope.containsKey(next);
        _showFrom(t, next);
        // A page never shown keeps no scope of its own to bring back: it
        // reads the one its tab implies, so a closed project's scope goes.
        if (!visited && scopeUid != null && tree.find(scopeUid!) != null) {
          if (projectIndex.isProject(scopeUid!) ||
              projectIndex.projectOf(scopeUid!) != null) {
            _syncScopeToTab();
          }
        } else if (!visited) {
          _syncScopeToTab();
        }
      }
      _pageScope.remove(t);
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
      if (t == keep) continue;
      await closeTab(t);
      if (_tabs.contains(t)) return; // the unsaved-changes prompt cancelled
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
      if (_tabs.contains(t)) return; // the unsaved-changes prompt cancelled
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
      originalPriority: p.priorityWord,
    );
    final d = _drafts[uid]!;
    _watchDraft(uid, d, () => (d.parent, d.status, d.priority));
    _focusEditor(uid);
    notifyListeners();
  }

  /// Saves the edit of note [uid] (the peek note by default) through
  /// [updateNote] (and [setStatus] when the status changed). False if
  /// nothing was saved (empty title, failure).
  Future<bool> saveDraft([String? uid, bool stay = false]) async {
    final key = uid ?? peekUid;
    final d = key == null ? null : _drafts[key];
    if (d == null || d.titleEmpty) return false;
    // The note is gone (deleted meanwhile, e.g. by a sync): nothing to save
    // to. The draft stays, so the text is not lost.
    if (tree.find(d.uid) == null) {
      error = _goneNote;
      notifyListeners();
      return false;
    }
    // What this save sends; text typed while it runs is newer than this.
    final title = d.titleController.text;
    final body = d.bodyController.text;
    final tagText = d.tagsController.text;
    final parent = d.parent;
    final status = d.status;
    final priority = d.priority;
    await updateNote(
      d.uid,
      title: title,
      text: body,
      tags: d.tagList,
      setParent: parent != d.originalParent,
      parentUid: parent,
    );
    if (error == null && status != null && status != d.originalStatus) {
      await setStatus(d.uid, status, undoable: false);
    }
    if (error == null && priority != d.originalPriority) {
      await setNotePriority(d.uid, priority, undoable: false);
    }
    if (error != null) return false;
    // Deleted while this save ran: updateNote did nothing. Keep the draft.
    if (tree.find(d.uid) == null) {
      _drafts[key!] = d;
      error = _goneNote;
      notifyListeners();
      return false;
    }
    if (error == _goneNote) error = null;
    if (_drafts[key] == d) {
      d.markSaved(
        title: title,
        body: body,
        tags: tagText,
        parent: parent,
        status: status ?? d.originalStatus,
        priority: priority,
      );
      // Nothing typed meanwhile: the edit is done. Otherwise the newer text
      // stays as the draft, still dirty.
      if (!d.dirty && !stay) _drafts.remove(key);
    }
    notifyListeners();
    return true;
  }

  // --- Autosave (narrow) ---
  //
  // On the narrow layout an open edit saves itself: a pause in typing saves
  // after [autosaveDelay], a change of a selector at once, and leaving the
  // item, closing it, toggling to preview or pausing the app flush what is
  // pending. Saves go through the same path as the Save button (a local save,
  // then a sync that merges with the server and keeps overlapping text in the
  // history), one at a time per item. The wide layout keeps explicit Save.

  /// How long typing must pause before the edit saves itself.
  Duration autosaveDelay = const Duration(milliseconds: 1500);

  final Map<String, Timer> _autosaveTimers = {};
  final Map<String, Future<bool>> _flushing = {};

  /// Whether the open edit of item [uid] (note, task or event) has unsaved
  /// changes.
  bool dirtyItem(String uid) => _taskDrafts.containsKey(uid)
      ? dirtyTaskFor(uid)
      : _eventDrafts.containsKey(uid)
      ? dirtyEventFor(uid)
      : dirtyFor(uid);

  /// Whether the open edit of [uid] cannot be saved as it is (empty title,
  /// event end before start).
  bool editBlocked(String uid) {
    final n = _drafts[uid], k = _taskDrafts[uid], e = _eventDrafts[uid];
    if (e != null) return e.titleEmpty;
    if (k != null) return k.titleEmpty;
    if (n != null) return n.titleEmpty;
    return false;
  }

  /// Saves [uid] when [draft] changes (narrow only): at once when [choices]
  /// (the selector values) changed, else after the typing pause. A task's
  /// buffer has no selector, so it always takes the pause.
  void _watchDraft(String uid, Listenable draft, [Object Function()? choices]) {
    var last = choices?.call();
    draft.addListener(() {
      if (!narrow || !isEditing(uid)) return;
      final now = choices?.call();
      final picked = choices != null && now != last;
      last = now;
      _autosaveTimers.remove(uid)?.cancel();
      if (!dirtyItem(uid)) return;
      if (picked) {
        unawaited(flushEdit(uid));
      } else {
        _autosaveTimers[uid] = Timer(autosaveDelay, () {
          _autosaveTimers.remove(uid);
          unawaited(flushEdit(uid));
        });
      }
    });
  }

  /// Saves the edit of [uid] now if anything is pending, staying in edit
  /// mode. Runs after a save already in flight. False when nothing was saved
  /// (empty title, failure).
  Future<bool> flushEdit(String uid) {
    _autosaveTimers.remove(uid)?.cancel();
    final running = _flushing[uid];
    if (running != null) return running.then((_) => flushEdit(uid));
    final f = saveEdit(uid).whenComplete(() {
      _flushing.remove(uid);
      notifyListeners();
    });
    _flushing[uid] = f;
    // Shows "Saving" while the save runs.
    if (dirtyItem(uid)) notifyListeners();
    return f;
  }

  /// Set by the shell: shows why an edit left behind could not be saved.
  void Function(String reason)? onNotSaved;

  /// Shows the shell's "Not saved" notice for [reason] (a pick or an inline
  /// text commit that did not go through).
  void reportNotSaved(String reason) => onNotSaved?.call(reason);

  String _notSavedReason(String uid) {
    final empty = _taskDrafts.containsKey(uid)
        ? _taskDrafts[uid]!.titleEmpty
        : _eventDrafts.containsKey(uid)
        ? _eventDrafts[uid]!.titleEmpty
        : _drafts[uid]?.titleEmpty ?? false;
    return empty ? 'a title is required' : (error ?? 'could not save');
  }

  /// Flushes every pending edit (the app is going to the background): the
  /// narrow layout's drafts save themselves, and inline text (a task's or an
  /// event's) does on both layouts.
  Future<void> flushAllEdits() => Future.wait([
    for (final u in _allDraftUids())
      if (dirtyItem(u) && (narrow || isTextBuffer(u))) flushEdit(u),
  ]);

  /// Whether a save of [uid] is waiting for its typing pause or running.
  bool autosavePending(String uid) =>
      _autosaveTimers.containsKey(uid) || _flushing.containsKey(uid);

  /// After a sync: an edit with nothing typed takes the merged text, so the
  /// next autosave does not send back a stale copy over a remote change.
  void _rebaseDrafts() {
    if (!narrow) return;
    for (final d in _drafts.values) {
      final n = tree.find(d.uid)?.note;
      if (n == null || d.dirty) continue;
      final p = PlanItem.fromNote(n);
      // Ignore trailing whitespace: the store may normalise it.
      if (n.summary.trim() == d.originalTitle.trim() &&
          p.text.trimRight() == d.originalBody.trimRight()) {
        continue;
      }
      d.rebase(title: n.summary, body: p.text);
    }
  }

  /// Like [_rebaseDrafts] for tasks: a buffer with nothing typed takes the
  /// text a sync brought, a buffer with typed text is left alone. The task
  /// text buffer exists on both layouts, so this runs always.
  void _rebaseTaskDrafts() {
    for (final d in _taskDrafts.values) {
      final t = _taskById(d.uid);
      if (t == null || d.dirty) continue;
      if (t.summary.trim() == d.originalTitle.trim() &&
          t.description.trimRight() == d.originalBody.trimRight()) {
        continue;
      }
      d.rebase(title: t.summary, body: t.description);
    }
  }

  /// Like [_rebaseDrafts] for events: a buffer with nothing typed takes the
  /// text a sync brought, a buffer with typed text is left alone.
  void _rebaseEventDrafts() {
    for (final d in _eventDrafts.values) {
      final e = _eventById(d.uid);
      if (e == null || d.dirty) continue;
      if (e.summary.trim() == d.originalTitle.trim() &&
          e.location.trim() == d.originalLocation.trim() &&
          e.description.trimRight() == d.originalBody.trimRight()) {
        continue;
      }
      d.rebase(title: e.summary, location: e.location, body: e.description);
    }
  }

  /// Whether [uid] is a task or event whose text is edited in place: it has
  /// no edit mode to leave, only a buffer whose text commits itself.
  bool isTextBuffer(String uid) =>
      _taskDrafts.containsKey(uid) || _eventDrafts.containsKey(uid);

  /// Commits the text buffer of [uid] (task or event) and says why when it
  /// cannot.
  Future<bool> commitTextBuffer(String uid) =>
      _taskDrafts.containsKey(uid) ? commitTaskText(uid) : commitEventText(uid);

  /// Whether item [uid] (note, task or event) is open in edit mode.
  bool isEditing(String uid) =>
      _drafts.containsKey(uid) ||
      _taskDrafts.containsKey(uid) ||
      _eventDrafts.containsKey(uid);

  void _dropDraft(String uid) {
    _drafts.remove(uid);
    _taskDrafts.remove(uid);
    _eventDrafts.remove(uid);
    // Leaving the edit of a note deleted elsewhere clears that notice.
    if (error == _goneNote) error = null;
    notifyListeners();
  }

  /// Leaves edit mode for [uid] (Esc, Cancel): a clean edit just closes; a
  /// dirty one asks first (save, discard or keep editing). A task's text
  /// buffer has no edit mode to leave: its text is committed and the buffer
  /// closes. False when the user keeps editing.
  Future<bool> leaveEdit(String uid) async {
    if (!isEditing(uid)) return true;
    if (isTextBuffer(uid)) {
      await commitTextBuffer(uid);
      if (!dirtyItem(uid)) _dropDraft(uid);
      return true;
    }
    if (!await _settleDrafts([uid])) return false;
    if (isEditing(uid)) _dropDraft(uid);
    return true;
  }

  /// Saves the edit of [uid] and stays in edit mode (`:w` in the Vim
  /// editor). A clean edit does nothing. False when nothing was saved.
  Future<bool> saveEdit(String uid) async {
    if (!isEditing(uid)) return true;
    if (_taskDrafts.containsKey(uid)) {
      return dirtyTaskFor(uid) ? saveTaskDraft(uid, stay: true) : true;
    }
    if (_eventDrafts.containsKey(uid)) {
      return dirtyEventFor(uid) ? saveEventDraft(uid, stay: true) : true;
    }
    return dirtyFor(uid) ? saveDraft(uid, true) : true;
  }

  /// Leaves edit mode for [uid] and drops the unsaved changes without asking
  /// (`:q!` in the Vim editor).
  void discardEdit(String uid) {
    if (isEditing(uid)) _dropDraft(uid);
  }

  /// Saves the edit of [uid] and leaves edit mode (Ctrl/Cmd+Enter, the Save
  /// icon). A clean edit just closes. False when nothing was saved (empty
  /// title, failure): edit mode stays.
  Future<bool> saveAndLeave(String uid) async {
    if (!isEditing(uid)) return true;
    // A task's or event's text is inline: saving it closes the buffer and
    // there is nothing else to leave.
    if (isTextBuffer(uid)) {
      final saved = await commitTextBuffer(uid);
      if (saved && !dirtyItem(uid)) _dropDraft(uid);
      return saved;
    }
    // Narrow: through the autosave queue, so it waits for a save in flight
    // (and drops the pending timer) instead of racing it.
    if (narrow) {
      await flushEdit(uid);
      if (!isEditing(uid)) return true;
    }
    if (!dirtyItem(uid)) {
      _dropDraft(uid);
      return true;
    }
    return saveDraft(uid);
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
      final isTask = _taskDrafts.containsKey(u);
      final isEvent = _eventDrafts.containsKey(u);
      final dirty = isTask
          ? dirtyTaskFor(u)
          : isEvent
          ? dirtyEventFor(u)
          : dirtyFor(u);
      if (!dirty) {
        // A clean buffer on the way out is closed; nothing is lost.
        if (isTask) _taskDrafts.remove(u);
        if (isEvent) _eventDrafts.remove(u);
        continue;
      }
      // A task's or an event's text commits itself (a failed write keeps the
      // buffer); narrow edits save themselves too; the dialog is the fallback
      // when the save cannot go through (empty title, error).
      if (isTask || isEvent) {
        await commitTextBuffer(u);
        if (!dirtyItem(u)) {
          if (isTask) _taskDrafts.remove(u);
          if (isEvent) _eventDrafts.remove(u);
        }
        continue;
      }
      if (narrow && await flushEdit(u)) continue;
      if (g == null) continue;
      switch (await g()) {
        case DraftChoice.keep:
          return false;
        case DraftChoice.save:
          final saved = isTask
              ? await saveTaskDraft(u)
              : isEvent
              ? await saveEventDraft(u)
              : await saveDraft(u);
          if (!saved) return false;
        case DraftChoice.discard:
          if (isTask) {
            _taskDrafts.remove(u);
          } else if (isEvent) {
            _eventDrafts.remove(u);
          } else {
            _drafts.remove(u);
          }
      }
    }
    return true;
  }

  Note? get peek => peekUid == null ? null : tree.find(peekUid!)?.note;

  /// The task shown in the peek, if the peek holds a task.
  Task? get peekTask => peekUid == null ? null : _taskById(peekUid!);

  /// The event shown in the peek, if the peek holds an event.
  Event? get peekEvent => peekUid == null ? null : _eventById(peekUid!);

  /// The peek holds a note, a task or an event.
  bool get hasPeek => peek != null || peekTask != null || peekEvent != null;

  /// Shows note [uid] in the peek (null closes it). A note that has a main
  /// tab is focused there instead: it lives in one place.
  void select(String? uid) {
    if (uid != null && _tabs.contains(_tabOf(uid))) {
      _show(_tabOf(uid));
      return;
    }
    // Showing a note outside the open folder leaves the folder. Narrow keeps
    // it: the pill still names the project and Back or Home returns to it,
    // while the item shows as the page it is.
    if (!narrow &&
        uid != null &&
        !_isTask(uid) &&
        !_isEvent(uid) &&
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

  /// Clears the search text (and its field), leaving tag and folder alone.
  void clearSearch() {
    searchController.clear();
    setQuery('');
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

  /// Collapses every folder that has children, or expands all when none is
  /// open (the side menu's fold button).
  void toggleAllFolders() {
    final parents = <String>[];
    void walk(List<NoteNode> nodes) {
      for (final n in nodes) {
        if (n.children.isNotEmpty) parents.add(n.note.uid);
        walk(n.children);
      }
    }

    walk(tree.roots);
    final anyOpen = parents.any((u) => !collapsed.contains(u));
    collapsed.clear();
    if (anyOpen) collapsed.addAll(parents);
    _saveCollapsed();
    notifyListeners();
  }

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

  /// Whether the user left the Notes tags list open in this Space.
  bool get tagsOpen => _tagsOpen;
  bool _tagsOpen = false;

  /// The tags list shows open while a tag filter is active, so the active
  /// tag stays visible.
  bool get tagsExpanded => tagsOpen || tag != null;

  bool _taskTagsOpen = false;
  bool _eventTagsOpen = false;

  /// Tags drawer open flags of the Tasks and Events panels (per Space,
  /// saved); each shows open while its tag filter is active.
  bool get taskTagsExpanded => _taskTagsOpen || taskTagFilter != null;
  bool get eventTagsExpanded => _eventTagsOpen || eventTagFilter != null;
  String get _taskTagsOpenKey => 'davdart.tasktags.open.v1.$_spaceKey';
  String get _eventTagsOpenKey => 'davdart.eventtags.open.v1.$_spaceKey';

  // ---- The selected day and the Home Board's kinds ----

  /// The old Home focus pref (Day | Board). Nothing sets it any more; a saved
  /// 'tasks' still means the Tasks kind until a kind is chosen.
  String get _legacyFocusKey => 'davdart.home.focus.v1.$_spaceKey';
  String get _homeCalKey => 'davdart.home.cal.open.v1.$_spaceKey';

  String get _homeKindKey => 'davdart.home.kind.v1.$_spaceKey';

  /// Which kinds the Home Board shows, remembered per Space; All by default.
  /// Tasks fall back to All in a Space without tasks, Notes in one without notes. A legacy 'tasks' focus
  /// pref with no kind pref loads as Tasks.
  HomeKind get homeKind {
    final saved = prefs?.read(_homeKindKey);
    final kind = switch (saved) {
      'notes' => HomeKind.notes,
      'tasks' => HomeKind.tasks,
      'all' => HomeKind.all,
      _ =>
        prefs?.read(_legacyFocusKey) == 'tasks' ? HomeKind.tasks : HomeKind.all,
    };
    if (kind == HomeKind.tasks && !supportsTasks) return HomeKind.all;
    if (kind == HomeKind.notes && !supportsNotes) return HomeKind.all;
    return kind;
  }

  void setHomeKind(HomeKind k) {
    if (k == homeKind) return;
    // All is the default, but a legacy 'tasks' focus pref needs it written.
    if (k == HomeKind.all && prefs?.read(_legacyFocusKey) != 'tasks') {
      prefs?.remove(_homeKindKey);
    } else {
      prefs?.write(_homeKindKey, k.name);
    }
    nav.boardOpen.remove('done#all');
    notifyListeners();
  }

  String get _homeHiddenKey => 'davdart.home.hidden.v1.board.$_spaceKey';
  String get _legacyTasksHiddenKey => 'davdart.home.hidden.v1.tasks.$_spaceKey';

  /// Status columns hidden on the Home Board (per Space, saved). The old
  /// Tasks view's hidden set is used until the first change when the board
  /// has none and the Tasks kind is chosen.
  Set<String> homeHiddenCols() {
    var raw = prefs?.read(_homeHiddenKey);
    if (raw == null && homeKind == HomeKind.tasks) {
      raw = prefs?.read(_legacyTasksHiddenKey);
    }
    return {...?raw?.split(',').where((c) => c.isNotEmpty)};
  }

  /// The Columns menu: every column now present, then saved hidden names that
  /// are absent (so they can be shown again), and which of them are hidden.
  /// Hidden is empty when everything would be (the board then shows all). The
  /// third set is every name shown unchecked: those hidden on the board plus
  /// absent saved ones (for the check marks and label).
  (List<String>, Set<String>, Set<String>) homeColumnChoices() {
    final present = [for (final c in homeColumns(all: true)) c.$1];
    final saved = homeHiddenCols();
    final names = [
      ...present,
      ...(saved.where((c) => !present.contains(c)).toList()..sort()),
    ];
    final hidden = saved.intersection(present.toSet());
    final effective = hidden.length >= present.length ? <String>{} : hidden;
    return (
      names,
      effective,
      {...effective, ...saved.where((c) => !present.contains(c))},
    );
  }

  /// Shows or hides a column; the last visible column cannot be hidden.
  void toggleHomeCol(String name) {
    final saved = homeHiddenCols();
    if (!saved.remove(name)) {
      final (names, hidden, _) = homeColumnChoices();
      final present = [for (final c in homeColumns(all: true)) c.$1];
      if (names.contains(name) &&
          present.every((c) => c == name || hidden.contains(c))) {
        return;
      }
      saved.add(name);
    }
    if (saved.isEmpty) {
      // Explicit empty so a legacy tasks set does not come back.
      prefs?.remove(_homeHiddenKey);
      prefs?.remove(_legacyTasksHiddenKey);
    } else {
      prefs?.write(_homeHiddenKey, (saved.toList()..sort()).join(','));
    }
    nav.boardOpen.remove('done#all');
    notifyListeners();
  }

  /// The narrow Home calendar is expanded to the month grid (per Space).
  bool get homeCalOpen => prefs?.read(_homeCalKey) == 'true';

  void setHomeCalOpen(bool open) {
    if (open == homeCalOpen) return;
    if (open) {
      prefs?.write(_homeCalKey, 'true');
    } else {
      prefs?.remove(_homeCalKey);
    }
    notifyListeners();
  }

  String _homeCardKey(String slug) =>
      'davdart.home.card.collapsed.v1.$slug.$_spaceKey';

  /// A Home day card (`tasks`, `events`) is collapsed (per Space).
  bool homeCardCollapsed(String slug) =>
      prefs?.read(_homeCardKey(slug)) == 'true';

  void setHomeCardCollapsed(String slug, bool c) {
    if (c == homeCardCollapsed(slug)) return;
    if (c) {
      prefs?.write(_homeCardKey(slug), 'true');
    } else {
      prefs?.remove(_homeCardKey(slug));
    }
    notifyListeners();
  }

  void setTaskTagsOpen(bool v) {
    _taskTagsOpen = v;
    _flag(_taskTagsOpenKey, v);
    notifyListeners();
  }

  void setEventTagsOpen(bool v) {
    _eventTagsOpen = v;
    _flag(_eventTagsOpenKey, v);
    notifyListeners();
  }

  void _flag(String key, bool v) {
    if (v) {
      prefs?.write(key, 'true');
    } else {
      prefs?.remove(key);
    }
  }

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

  /// The Home Board's cards: notes and tasks that have a status, under the
  /// folder scope, the tag filters and the search, narrowed by [homeKind].
  List<BoardItem> get homeItems {
    final kind = homeKind;
    final q = query.trim().toLowerCase();
    return [
      if (kind != HomeKind.tasks)
        for (final n in filtered)
          if (PlanItem.fromNote(n).status != null) BoardItem.note(n),
      if (kind != HomeKind.notes && supportsTasks)
        for (final t in filteredTasks)
          if ((tag == null || t.categories.contains(tag)) &&
              (q.isEmpty ||
                  t.summary.toLowerCase().contains(q) ||
                  t.description.toLowerCase().contains(q)))
            BoardItem.task(t),
    ];
  }

  /// Home board columns in board order: the fixed statuses in use, then
  /// Other. With the Tasks kind todo, doing and done always show. Canceled
  /// has its own column (its cards are dimmed). Each column is sorted by
  /// [compareBoardItems]; the hidden columns are applied, [all] keeps them
  /// (the toggle's list).
  List<(String, List<BoardItem>)> homeColumns({bool all = false}) {
    final by = <String, List<BoardItem>>{
      if (homeKind == HomeKind.tasks) ...{'todo': [], 'doing': [], 'done': []},
    };
    for (final i in homeItems) {
      final raw = i.isTask
          ? i.task!.boardStatus
          : PlanItem.fromNote(i.note!).status!;
      (by[statusColumn(canonicalStatus(raw) ?? raw)] ??= []).add(i);
    }
    const always = ['todo', 'doing', 'done'];
    final keys = [
      ...boardOrder.where(by.containsKey),
      if (by.containsKey(otherColumn)) otherColumn,
    ];
    final cols = [
      for (final k in keys)
        if (by[k]!.isNotEmpty ||
            (homeKind == HomeKind.tasks && always.contains(k)))
          (k, by[k]!..sort(compareBoardItems)),
    ];
    return all ? cols : _visibleCols(cols);
  }

  List<(String, List<T>)> _visibleCols<T>(List<(String, List<T>)> cols) {
    final hidden = homeHiddenCols();
    final shown = [
      for (final c in cols)
        if (!hidden.contains(c.$1)) c,
    ];
    return shown.isEmpty ? cols : shown;
  }

  /// Board columns in a stable order: the fixed statuses that are in use,
  /// then Other (words outside the set), then notes with no status, which are
  /// left out when [includeNoStatus] is false (Home shows work items only).
  /// Within a column notes sort by priority (high first, none last), then
  /// creation.
  List<(String, List<Note>)> columns({bool includeNoStatus = true}) {
    final by = <String, List<Note>>{};
    for (final n in filtered) {
      final s = PlanItem.fromNote(n).status;
      if (s == null && !includeNoStatus) continue;
      (by[s == null ? 'notes' : statusColumn(s)] ??= []).add(n);
    }
    final keys = [
      ...boardOrder.where(by.containsKey),
      if (by.containsKey(otherColumn)) otherColumn,
      if (by.containsKey('notes')) 'notes',
    ];
    return [
      for (final k in keys) (k, [...by[k]!]..sort(byPriority)),
    ];
  }

  /// Priority first (high, medium, low, none), then creation: the order of a
  /// note column.
  static int byPriority(Note a, Note b) {
    int rank(Note n) => PlanItem.fromNote(n).priority ?? 10;
    final c = rank(a).compareTo(rank(b));
    return c != 0 ? c : NoteTree.byCreated(a, b);
  }
}
