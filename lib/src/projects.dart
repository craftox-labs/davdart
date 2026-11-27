import 'event.dart';
import 'note.dart';
import 'note_tree.dart';
import 'plan_item.dart';
import 'saved_view.dart';
import 'status.dart';
import 'task.dart';

/// Tag that, together with [folderTag], marks a Space's Projects container:
/// its direct child folders are the projects. Nothing is stored on a project;
/// project-ness is derived from location.
const projectsTag = 'kind-projects';

/// Default title of a newly created Projects container.
const projectsTitle = 'Projects';

/// True for a folder that is a Projects container.
bool isProjectsContainer(Note n) =>
    isFolderNote(n) && n.categories.contains(projectsTag);

/// Derived counts of one project (or of everything outside any project).
///
/// Counted are tasks and notes that carry a status; events, folders and
/// saved views are not. `canceled` items are left out of every number. [open]
/// is every counted item that is not in review or done (backlog, todo,
/// doing, blocked); [review] and [done] are exact. [total] is
/// `open + review + done`.
class ProjectStats {
  const ProjectStats(this.open, this.review, this.done);
  const ProjectStats.empty() : this(0, 0, 0);

  final int open;
  final int review;
  final int done;

  int get total => open + review + done;

  /// done / total, 0 when there is nothing to count; always in 0..1.
  double get progress => total == 0 ? 0 : done / total;
}

/// Projects of one Space, derived from its notes, tasks and events. Pure and
/// read-only; build a new one after any change. Parent chains are walked
/// across all three kinds of item and are safe against loops and missing
/// parents (an orphan belongs to no project).
class ProjectIndex {
  ProjectIndex(
    Iterable<Note> notes, [
    Iterable<Task> tasks = const [],
    Iterable<Event> events = const [],
  ])  : _notes = notes.toList(),
        _tasks = tasks.toList(),
        _events = events.toList() {
    for (final n in _notes) {
      _parent[n.uid] = n.parentUid;
      _byUid[n.uid] = n;
    }
    for (final t in _tasks) {
      _parent.putIfAbsent(t.uid, () => t.parentUid);
    }
    for (final e in _events) {
      _parent.putIfAbsent(e.uid, () => e.parentUid);
    }
    final all = [..._notes.where(isProjectsContainer)]
      ..sort(NoteTree.byCreated);
    _containers = all;
    final ids = {for (final c in all) c.uid};
    _projects = [
      for (final n in _notes)
        if (isFolderNote(n) &&
            !isProjectsContainer(n) &&
            n.parentUid != null &&
            ids.contains(n.parentUid))
          n,
    ]..sort(NoteTree.byCreated);
    _projectIds = {for (final p in _projects) p.uid};
  }

  final List<Note> _notes;
  final List<Task> _tasks;
  final List<Event> _events;
  final _parent = <String, String?>{};
  final _byUid = <String, Note>{};
  late final List<Note> _containers;
  late final List<Note> _projects;
  late final Set<String> _projectIds;
  final _projectOf = <String, String?>{};
  Map<String, ProjectStats>? _stats;
  ProjectStats _rest = const ProjectStats.empty();

  /// The tasks under project [uid], grouped once for all projects (the panel
  /// and the page ask per project on every build).
  List<Task> tasksOf(String uid) {
    _groupTasks();
    return _tasksOf?[uid] ?? const [];
  }

  Map<String, List<Task>>? _tasksOf;

  void _groupTasks() {
    if (_tasksOf != null) return;
    final map = <String, List<Task>>{};
    for (final t in _tasks) {
      final p = _projectIdOf(t.uid);
      if (p != null) (map[p] ??= []).add(t);
    }
    _tasksOf = map;
  }

  /// The newest modification stamp among project [uid]'s notes, tasks and
  /// events (the folder itself included), or null. Computed once for all
  /// projects, like [statsOf].
  DateTime? lastChangedOf(String uid) {
    _computeLastChanged();
    return _lastChanged?[uid];
  }

  Map<String, DateTime>? _lastChanged;

  /// The projects, most recently changed first: the newest modification
  /// stamp among a project's notes, tasks and events (the folder itself
  /// included). Built once per index, so a page that orders projects on every
  /// rebuild does not walk the Space again.
  List<Note> projectsByLastChanged() {
    _computeLastChanged();
    return _byChange ??= _orderByChange();
  }

  List<Note>? _byChange;

  List<Note> _orderByChange() {
    final at = _lastChanged!;
    final list = [..._projects];
    list.sort((a, b) {
      final x = at[a.uid], y = at[b.uid];
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return List.unmodifiable(list);
  }

  void _computeLastChanged() {
    if (_lastChanged != null) return;
    final map = <String, DateTime>{};
    void touch(String uid, DateTime? at) {
      if (at == null) return;
      final p = _projectIdOf(uid);
      if (p == null) return;
      final cur = map[p];
      if (cur == null || at.isAfter(cur)) map[p] = at;
    }

    for (final n in _notes) {
      touch(n.uid, n.lastModified ?? n.dtstamp);
    }
    for (final t in _tasks) {
      touch(t.uid, t.lastModified ?? t.dtstamp);
    }
    for (final e in _events) {
      touch(e.uid, e.lastModified ?? e.dtstamp);
    }
    _lastChanged = map;
  }

  /// Every Projects container (several can exist, for example synced from
  /// another client), oldest first.
  List<Note> containers() => List.unmodifiable(_containers);

  /// The projects: direct child folders of any container, oldest first. A
  /// folder below a project is a plain folder, not a project.
  List<Note> projects() => List.unmodifiable(_projects);

  bool isProject(String uid) => _projectIds.contains(uid);

  /// The uid of [uid]'s parent (null at a root, or for an unknown uid). The
  /// map is built once for the whole index, so callers never scan a list.
  String? parentOf(String uid) => _parent[uid];

  /// Whether [start] or one of its ancestors is [scope]: one walk of the
  /// parent map with a seen-set, so a parent loop ends instead of spinning.
  /// The new parent wins for notes over tasks over events, as [NoteTree].
  bool isUnder(String? start, String scope) {
    final seen = <String>{};
    var cur = start;
    while (cur != null && seen.add(cur)) {
      if (cur == scope) return true;
      cur = _parent[cur];
    }
    return false;
  }

  /// The project folder whose subtree holds item [uid] (a note, task or
  /// event) at any depth, or the project itself for its own uid; null when
  /// [uid] is outside every project (including the containers, and loose
  /// items directly under a container).
  Note? projectOf(String uid) {
    final id = _projectIdOf(uid);
    return id == null ? null : _byUid[id];
  }

  String? _projectIdOf(String uid) {
    if (_projectOf.containsKey(uid)) return _projectOf[uid];
    final seen = <String>{};
    final path = <String>[];
    String? found;
    String? cur = uid;
    while (cur != null && seen.add(cur)) {
      if (_projectOf.containsKey(cur)) {
        found = _projectOf[cur];
        break;
      }
      path.add(cur);
      if (_projectIds.contains(cur)) {
        found = cur;
        break;
      }
      cur = _parent[cur];
    }
    for (final p in path) {
      _projectOf[p] = found;
    }
    return found;
  }

  /// Whether [uid] belongs to the projects layer: a project, anything under
  /// one, the Projects container itself, or anything directly under it.
  /// Walks the same parent map as [projectOf] (no scans), memoised because
  /// Home asks for every item on each build.
  bool inProjectsLayer(String uid) => _layer[uid] ??= _inLayer(uid);

  final _layer = <String, bool>{};

  bool _inLayer(String uid) {
    if (isProject(uid) || projectOf(uid) != null) return true;
    final seen = <String>{};
    String? cur = uid;
    while (cur != null && seen.add(cur)) {
      final n = _byUid[cur];
      if (n != null && isProjectsContainer(n)) return true;
      cur = _parent[cur];
    }
    return false;
  }

  /// Counts of project [uid] (zeros for an unknown uid).
  ProjectStats statsOf(String uid) {
    _compute();
    return _stats![uid] ?? const ProjectStats.empty();
  }

  /// Counts of the items outside every project ("Everything else").
  ProjectStats get everythingElse {
    _compute();
    return _rest;
  }

  void _compute() {
    if (_stats != null) return;
    final open = <String, int>{},
        review = <String, int>{},
        done = <String, int>{};
    var ro = 0, rr = 0, rd = 0;
    void count(String uid, String? status) {
      if (status == null || status == 'canceled') return;
      final p = _projectIdOf(uid);
      if (p == null) {
        switch (status) {
          case 'review':
            rr++;
          case 'done':
            rd++;
          default:
            ro++;
        }
        return;
      }
      final m = switch (status) {
        'review' => review,
        'done' => done,
        _ => open,
      };
      m[p] = (m[p] ?? 0) + 1;
    }

    for (final t in _tasks) {
      count(t.uid, canonicalStatus(t.boardStatus) ?? 'todo');
    }
    for (final n in _notes) {
      if (isStructuralNote(n)) continue;
      final s = PlanItem.fromNote(n).status;
      count(n.uid, s == null ? null : canonicalStatus(s));
    }
    _stats = {
      for (final p in _projects)
        p.uid: ProjectStats(
          open[p.uid] ?? 0,
          review[p.uid] ?? 0,
          done[p.uid] ?? 0,
        ),
    };
    _rest = ProjectStats(ro, rr, rd);
  }
}
