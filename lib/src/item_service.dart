import 'dart:math';

import 'caldav.dart';
import 'collection_backup_stub.dart'
    if (dart.library.io) 'collection_backup_io.dart';
import 'collection_service.dart' show BackupWriter;
import 'event.dart';
import 'ical.dart' show serializeEvent, serializeNote, serializeTask;
import 'merge.dart';
import 'note.dart';
import 'note_tree.dart';
import 'plan_item.dart';
import 'saved_view.dart';
import 'status.dart';
import 'task.dart';

/// Which resource type an item is stored as.
enum ItemKind {
  note,
  task,
  event;

  static ItemKind parse(String s) => ItemKind.values.firstWhere(
        (k) => k.name == s.toLowerCase().trim(),
        orElse: () => throw ItemServiceException(
            'unknown kind "$s" (expected note, task or event)'),
      );
}

/// A refused or impossible item operation (not found, ambiguous, bad move,
/// wrong kind for the operation).
class ItemServiceException implements Exception {
  ItemServiceException(this.message);
  final String message;
  @override
  String toString() => 'ItemServiceException: $message';
}

/// Plain, JSON-ready view of one item. Dates are raw iCalendar text
/// (`20261225`, `20261225T090000Z`) for due, start and end, ISO 8601 for
/// created and modified.
class ItemData {
  const ItemData({
    required this.kind,
    required this.uid,
    required this.title,
    this.href,
    this.etag,
    this.body = '',
    this.tags = const [],
    this.status,
    this.parentUid,
    this.isFolder = false,
    this.due,
    this.start,
    this.end,
    this.location,
    this.priority,
    this.created,
    this.modified,
    this.writer,
  });

  final ItemKind kind;
  final String uid;
  final String title;
  final String? href;
  final String? etag;
  final String body;
  final List<String> tags;

  /// Board status word (`todo`, `doing`, `done`, ...), or null.
  final String? status;
  final String? parentUid;
  final bool isFolder;
  final String? due;
  final String? start;
  final String? end;
  final String? location;
  final int? priority;
  final DateTime? created;
  final DateTime? modified;

  /// Self-declared name of whoever wrote the item last (its `X-WRITER`
  /// property). Not authentication.
  final String? writer;

  /// [full] false leaves out the body, for lists.
  Map<String, Object?> toJson({bool full = true}) => {
        'kind': kind.name,
        'uid': uid,
        'title': title,
        if (href != null) 'href': href,
        if (etag != null) 'etag': etag,
        if (full) 'body': body,
        'tags': tags,
        if (status != null) 'status': status,
        if (parentUid != null) 'parent': parentUid,
        if (isFolder) 'folder': true,
        if (due != null) 'due': due,
        if (start != null) 'start': start,
        if (end != null) 'end': end,
        if (location != null && location!.isNotEmpty) 'location': location,
        if (priority != null) 'priority': priority,
        if (created != null) 'created': created!.toIso8601String(),
        if (modified != null) 'modified': modified!.toIso8601String(),
        if (writer != null) 'writer': writer,
      };
}

/// One page of [ItemData].
class ItemPage {
  const ItemPage(this.items, this.total, this.offset, this.limit);
  final List<ItemData> items;
  final int total;
  final int offset;
  final int limit;
  bool get hasMore => offset + items.length < total;
  Map<String, Object?> toJson() => {
        'total': total,
        'offset': offset,
        'limit': limit,
        'hasMore': hasMore,
        'items': [for (final i in items) i.toJson(full: false)],
      };
}

/// A node of the compact [Overview] tree.
class OverviewNode {
  OverviewNode(this.kind, this.uid, this.title, this.status, this.folder);
  final ItemKind kind;
  final String uid;
  final String title;
  final String? status;
  final bool folder;
  final List<OverviewNode> children = [];

  /// Children left out because of the depth limit.
  int hiddenChildren = 0;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'uid': uid,
        'title': title,
        if (status != null) 'status': status,
        if (folder) 'folder': true,
        if (children.isNotEmpty)
          'children': [for (final c in children) c.toJson()],
        if (hiddenChildren > 0) 'hidden': hiddenChildren,
      };
}

/// Compact picture of a collection: tree plus counts.
class Overview {
  Overview(this.roots, this.total, this.byKind, this.byStatus, this.byTag);
  final List<OverviewNode> roots;
  final int total;
  final Map<String, int> byKind;
  final Map<String, int> byStatus;
  final Map<String, int> byTag;
  Map<String, Object?> toJson() => {
        'total': total,
        'byKind': byKind,
        'byStatus': byStatus,
        'byTag': byTag,
        'tree': [for (final r in roots) r.toJson()],
      };
}

/// Outcome of a write. With [dryRun] nothing was changed: [item] is what the
/// item would look like and [changes] what would be done.
class ItemChange {
  const ItemChange(this.action, this.dryRun, this.changes, this.item);
  final String action;
  final bool dryRun;
  final List<String> changes;
  final ItemData item;
  Map<String, Object?> toJson() => {
        'action': action,
        'dryRun': dryRun,
        'changes': changes,
        'item': item.toJson(),
      };
}

final _writerLine = RegExp(r'^X-WRITER:(.*)$', caseSensitive: false);

/// A writer label made safe for an iCalendar line: letters, digits and
/// `._@:/ -` only, at most 64 characters; null when nothing is left.
String? cleanWriter(String? name) {
  if (name == null) return null;
  var w = name.replaceAll(RegExp(r'[^A-Za-z0-9._@:/ -]'), '_').trim();
  if (w.length > 64) w = w.substring(0, 64);
  return w.isEmpty ? null : w;
}

// ---- internal: one wrapper over the three resource types ----

class _Ref {
  _Ref(this.raw);
  final Object raw; // Note, Task or Event

  ItemKind get kind => switch (raw) {
        Note() => ItemKind.note,
        Task() => ItemKind.task,
        _ => ItemKind.event,
      };

  String get uid => switch (raw) {
        Note n => n.uid,
        Task t => t.uid,
        Event e => e.uid,
        _ => '',
      };
  String? get href => switch (raw) {
        Note n => n.href,
        Task t => t.href,
        Event e => e.href,
        _ => null,
      };
  String get title => switch (raw) {
        Note n => n.summary,
        Task t => t.summary,
        Event e => e.summary,
        _ => '',
      };
  set title(String v) => switch (raw) {
        Note n => n.summary = v,
        Task t => t.summary = v,
        Event e => e.summary = v,
        _ => null,
      };
  String get body => switch (raw) {
        Note n => n.description,
        Task t => t.description,
        Event e => e.description,
        _ => '',
      };
  set body(String v) => switch (raw) {
        Note n => n.description = v,
        Task t => t.description = v,
        Event e => e.description = v,
        _ => null,
      };
  List<String> get tags => switch (raw) {
        Note n => n.categories,
        Task t => t.categories,
        Event e => e.categories,
        _ => <String>[],
      };
  set tags(List<String> v) => switch (raw) {
        Note n => n.categories = v,
        Task t => t.categories = v,
        Event e => e.categories = v,
        _ => null,
      };
  String? get parentUid => switch (raw) {
        Note n => n.parentUid,
        Task t => t.parentUid,
        Event e => e.parentUid,
        _ => null,
      };
  set parentUid(String? v) => switch (raw) {
        Note n => n.parentUid = v,
        Task t => t.parentUid = v,
        Event e => e.parentUid = v,
        _ => null,
      };
  DateTime? get created => switch (raw) {
        Note n => n.created ?? n.dtstamp,
        Task t => t.created ?? t.dtstamp,
        Event e => e.created ?? e.dtstamp,
        _ => null,
      };

  List<String> get _extra => switch (raw) {
        Note n => n.extraLines,
        Task t => t.extraLines,
        Event e => e.extraLines,
        _ => <String>[],
      };

  /// The `X-WRITER` value, or null.
  String? get writer {
    for (final l in _extra) {
      final m = _writerLine.firstMatch(l);
      if (m != null) return m.group(1);
    }
    return null;
  }

  /// Stamps [name] as the writer (replacing an earlier stamp). A null or
  /// empty name leaves the item untouched, so an existing stamp is kept.
  void stampWriter(String? name) {
    final w = cleanWriter(name);
    if (w == null) return;
    final extra = _extra;
    final at = extra.indexWhere(_writerLine.hasMatch);
    if (at >= 0) {
      extra[at] = 'X-WRITER:$w';
    } else {
      extra.add('X-WRITER:$w');
    }
  }

  String? get etag => switch (raw) {
        Note n => n.etag,
        Task t => t.etag,
        Event e => e.etag,
        _ => null,
      };

  bool get hasSiblings => switch (raw) {
        Note n => n.siblingLines.isNotEmpty,
        Task t => t.siblingLines.isNotEmpty,
        Event e => e.siblingLines.isNotEmpty,
        _ => false,
      };

  /// A copy with a new uid and parent, without href or etag, for creating
  /// the item in another collection.
  _Ref reuid(String uid, String? parent) => _Ref(switch (raw) {
        Note n => Note(
            uid: uid,
            summary: n.summary,
            description: n.description,
            categories: List.of(n.categories),
            status: n.status,
            parentUid: parent,
            created: n.created,
            lastModified: n.lastModified,
            extraLines: List.of(n.extraLines),
            calendarLines: List.of(n.calendarLines),
            propertyParams: Map.of(n.propertyParams)),
        Task t => Task(
            uid: uid,
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
            parentUid: parent,
            created: t.created,
            lastModified: t.lastModified,
            extraLines: List.of(t.extraLines),
            calendarLines: List.of(t.calendarLines),
            propertyParams: Map.of(t.propertyParams)),
        Event e => Event(
            uid: uid,
            summary: e.summary,
            description: e.description,
            location: e.location,
            categories: List.of(e.categories),
            status: e.status,
            dtstart: e.dtstart,
            dtend: e.dtend,
            duration: e.duration,
            rrule: e.rrule,
            exdates: List.of(e.exdates),
            rdates: List.of(e.rdates),
            parentUid: parent,
            created: e.created,
            lastModified: e.lastModified,
            extraLines: List.of(e.extraLines),
            calendarLines: List.of(e.calendarLines),
            propertyParams: Map.of(e.propertyParams)),
        _ => raw,
      });

  /// The item as iCalendar text, for comparing copies.
  String get ics => switch (raw) {
        Note n => serializeNote(n),
        Task t => serializeTask(t),
        _ => serializeEvent(raw as Event),
      };

  /// Content lines (unfolded) without the ones that legitimately change in
  /// a move: uid, stamps, the parent link (checked on its own) and the
  /// writer stamp.
  List<String> get contentLines {
    final text = ics.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    return [
      for (final l in text.split(RegExp(r'\r?\n')))
        if (l.isNotEmpty &&
            !RegExp(r'^(UID|DTSTAMP|CREATED|LAST-MODIFIED|PRODID|X-WRITER)[:;]')
                .hasMatch(l) &&
            !l.startsWith('RELATED-TO;RELTYPE=PARENT:'))
          l
    ];
  }

  /// Creates this item (no etag: only if absent) through [c].
  Future<void> putNew(CalDavClient c) async {
    switch (raw) {
      case Note n:
        await c.putNote(n);
      case Task t:
        await c.putTask(t);
      default:
        await c.putEvent(raw as Event);
    }
  }

  _Ref clone() => _Ref(switch (raw) {
        Note n => n.copyWith(),
        Task t => t.copyWith(),
        Event e => e.copyWith(),
        _ => raw,
      });

  String? get status => switch (raw) {
        Note n => PlanItem.fromNote(n).status,
        Task t => t.boardStatus,
        Event e => e.categories
            .where((c) => c.startsWith('status-'))
            .map((c) => c.substring(7))
            .firstOrNull,
        _ => null,
      };

  /// [base] is the collection URL: a href the server returned relative to it
  /// (after a PUT) is made absolute-path, as list returns it.
  ItemData toData([Uri? base]) {
    final d = _toData();
    final h = d.href;
    if (base == null || h == null || h.startsWith('/')) return d;
    return ItemData(
        kind: d.kind,
        uid: d.uid,
        title: d.title,
        href: base.resolve(h).path,
        etag: d.etag,
        body: d.body,
        tags: d.tags,
        status: d.status,
        parentUid: d.parentUid,
        isFolder: d.isFolder,
        due: d.due,
        start: d.start,
        end: d.end,
        location: d.location,
        priority: d.priority,
        created: d.created,
        modified: d.modified,
        writer: d.writer);
  }

  ItemData _toData() => _withWriter(_toData0());

  ItemData _withWriter(ItemData d) {
    final w = writer;
    if (w == null) return d;
    return ItemData(
        kind: d.kind,
        uid: d.uid,
        title: d.title,
        href: d.href,
        etag: d.etag,
        body: d.body,
        tags: d.tags,
        status: d.status,
        parentUid: d.parentUid,
        isFolder: d.isFolder,
        due: d.due,
        start: d.start,
        end: d.end,
        location: d.location,
        priority: d.priority,
        created: d.created,
        modified: d.modified,
        writer: w);
  }

  ItemData _toData0() {
    switch (raw) {
      case Note n:
        return ItemData(
            kind: ItemKind.note,
            uid: n.uid,
            title: n.summary,
            href: n.href,
            etag: n.etag,
            body: n.description,
            tags: List.of(n.categories),
            status: status,
            parentUid: n.parentUid,
            isFolder: isFolderNote(n),
            priority: PlanItem.fromNote(n).priority,
            created: n.created,
            modified: n.lastModified);
      case Task t:
        return ItemData(
            kind: ItemKind.task,
            uid: t.uid,
            title: t.summary,
            href: t.href,
            etag: t.etag,
            body: t.description,
            tags: List.of(t.categories),
            status: t.boardStatus,
            parentUid: t.parentUid,
            due: t.due?.value,
            start: t.dtstart?.value,
            priority: t.priority,
            created: t.created,
            modified: t.lastModified);
      default:
        final e = raw as Event;
        return ItemData(
            kind: ItemKind.event,
            uid: e.uid,
            title: e.summary,
            href: e.href,
            etag: e.etag,
            body: e.description,
            tags: List.of(e.categories),
            status: status,
            parentUid: e.parentUid,
            start: e.dtstart?.value,
            end: e.dtend?.value,
            location: e.location,
            created: e.created,
            modified: e.lastModified);
    }
  }

  /// PUT through the client. On a 412 the server copy is fetched, merged
  /// three-way against [base] and written once more; a second conflict throws.
  Future<_Ref> put(CalDavClient c, _Ref base) async {
    switch (raw) {
      case Note n:
        try {
          return _Ref(await c.putNote(n));
        } on ConflictException {
          final remote = await c.getNote(n.href!);
          return _Ref(
              await c.putNote(mergeNotes(base.raw as Note, n, remote).note));
        }
      case Task t:
        try {
          return _Ref(await c.putTask(t));
        } on ConflictException {
          final remote = await c.getTask(t.href!);
          return _Ref(
              await c.putTask(mergeTasks(base.raw as Task, t, remote).task));
        }
      default:
        final e = raw as Event;
        try {
          return _Ref(await c.putEvent(e));
        } on ConflictException {
          final remote = await c.getEvent(e.href!);
          return _Ref(await c
              .putEvent(mergeEvents(base.raw as Event, e, remote).event));
        }
    }
  }

  Future<void> delete(CalDavClient c) => switch (raw) {
        Note n => c.deleteNote(n),
        Task t => c.deleteTask(t),
        _ => c.deleteEvent(raw as Event),
      };
}

/// Parses `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM[:SS][Z]` or the compact iCalendar
/// forms into an [ICalDate]. A timed value without Z is floating.
ICalDate parseWhen(String s) {
  final m = RegExp(
          r'^(\d{4})-?(\d{2})-?(\d{2})(?:[T ](\d{2}):?(\d{2})(?::?(\d{2}))?(Z)?)?$')
      .firstMatch(s.trim());
  if (m == null) {
    throw ItemServiceException('cannot read date "$s" (use YYYY-MM-DD or '
        'YYYY-MM-DDTHH:MM[:SS][Z])');
  }
  final y = m.group(1)!, mo = m.group(2)!, d = m.group(3)!;
  if (m.group(4) == null) return ICalDate('$y$mo$d', ';VALUE=DATE');
  return ICalDate('$y$mo${d}T${m.group(4)}${m.group(5)}${m.group(6) ?? '00'}'
      '${m.group(7) ?? ''}');
}

/// Item operations over one CalDAV collection, generic over note, task and
/// event, for any front-end (CLI, MCP, app). Every write goes through
/// [CalDavClient] (ETag preconditions; a lost race is merged and retried once)
/// and has a `dryRun` option that changes nothing.
class ItemService {
  ItemService(this.client, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final CalDavClient client;
  final DateTime Function() _now;

  Future<List<_Ref>> _load([ItemKind? only]) async {
    final out = <_Ref>[];
    if (only == null || only == ItemKind.note) {
      out.addAll((await client.listNotes()).map(_Ref.new));
    }
    if (only == null || only == ItemKind.task) {
      out.addAll((await client.listTasks()).map(_Ref.new));
    }
    if (only == null || only == ItemKind.event) {
      out.addAll((await client.listEvents()).map(_Ref.new));
    }
    return out
        .where((r) => !(r.raw is Note && isViewNote(r.raw as Note)))
        .toList();
  }

  /// Saved-view notes (hidden by [_load]).
  Future<List<_Ref>> _loadViews() async => [
        for (final n in await client.listNotes())
          if (isViewNote(n)) _Ref(n)
      ];

  /// The first difference between two items' content, as "FIELD", or null.
  static String? _contentDiff(_Ref o, _Ref c) {
    final a = o.contentLines, b = c.contentLines;
    String name(String l) => l.split(RegExp(r'[:;]')).first;
    final rest = List.of(b);
    for (final l in a) {
      if (!rest.remove(l)) return name(l);
    }
    if (rest.isNotEmpty) return name(rest.first);
    return null;
  }

  /// One note-shaped proxy per item so [NoteTree] can arrange all kinds.
  NoteTree _tree(List<_Ref> refs) => NoteTree.build([
        for (final r in refs)
          Note(
              uid: r.uid,
              summary: r.title,
              parentUid: r.parentUid,
              created: r.created)
      ]);

  _Ref _find(List<_Ref> refs, String id, {ItemKind? kind}) {
    final low = id.toLowerCase();
    var hits = refs
        .where((r) =>
            (kind == null || r.kind == kind) && (r.uid == id || r.href == id))
        .toList();
    if (hits.isEmpty) {
      hits = refs
          .where((r) =>
              (kind == null || r.kind == kind) && r.title.toLowerCase() == low)
          .toList();
    }
    if (hits.isEmpty) throw ItemServiceException('no item matches "$id"');
    if (hits.length > 1) {
      throw ItemServiceException(
          '${hits.length} items match "$id": ${hits.map((h) => '${h.title} (${h.uid})').join(' | ')}');
    }
    return hits.single;
  }

  /// Compact tree (to [maxDepth] levels, default 2) plus tag and status
  /// counts. [under] limits the tree to one folder or item.
  Future<Overview> overview({int maxDepth = 2, String? under}) async {
    final refs = await _load();
    final tree = _tree(refs);
    final byUid = {for (final r in refs) r.uid: r};
    OverviewNode node(NoteNode n, int depth) {
      final r = byUid[n.note.uid]!;
      final o = OverviewNode(r.kind, r.uid, r.title, r.status,
          r.raw is Note && isFolderNote(r.raw as Note));
      if (depth >= maxDepth) {
        o.hiddenChildren = n.children.length;
      } else {
        for (final c in n.children) {
          o.children.add(node(c, depth + 1));
        }
      }
      return o;
    }

    final List<NoteNode> start;
    if (under == null) {
      start = tree.roots;
    } else {
      start = tree.find(_find(refs, under).uid)!.children;
    }
    final byKind = <String, int>{};
    final byStatus = <String, int>{};
    final byTag = <String, int>{};
    for (final r in refs) {
      byKind[r.kind.name] = (byKind[r.kind.name] ?? 0) + 1;
      final s = r.status;
      if (s != null) byStatus[s] = (byStatus[s] ?? 0) + 1;
      for (final t in r.tags) {
        if (t.startsWith('status-') || t == folderTag) continue;
        byTag[t] = (byTag[t] ?? 0) + 1;
      }
    }
    return Overview([for (final n in start) node(n, 1)], refs.length, byKind,
        byStatus, byTag);
  }

  /// Filtered, paged list without bodies. [under] is a folder (or any item)
  /// uid or title: everything below it. Folders are left out unless
  /// [includeFolders].
  Future<ItemPage> list({
    ItemKind? kind,
    String? tag,
    String? status,
    String? under,
    bool includeFolders = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final refs = await _load(kind);
    Set<String>? below;
    if (under != null) {
      final all = kind == null ? refs : await _load();
      below = _tree(all)
          .descendants(_find(all, under).uid)
          .map((n) => n.uid)
          .toSet();
    }
    final raw = status?.toLowerCase();
    final low = status == null ? null : canonicalStatus(status) ?? raw;
    final hits = refs.where((r) {
      if (!includeFolders && r.raw is Note && isFolderNote(r.raw as Note)) {
        return false;
      }
      if (tag != null && !r.tags.contains(tag)) return false;
      if (low != null && r.status != low && r.status != raw) return false;
      if (below != null && !below.contains(r.uid)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final c = a.created!.compareTo(b.created!);
        return c != 0 ? c : a.title.compareTo(b.title);
      });
    final lim = limit.clamp(1, 500);
    final off = offset < 0 ? 0 : offset;
    return ItemPage([for (final r in hits.skip(off).take(lim)) r.toData()],
        hits.length, off, lim);
  }

  /// One item by uid, href or exact title.
  Future<ItemData> get(String id, {ItemKind? kind}) async =>
      _find(await _load(kind), id, kind: kind).toData();

  String _newUid() =>
      '${_now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}@davdart';

  List<String> _cleanTags(Iterable<String> t) => {
        for (final x in t)
          if (x.trim().isNotEmpty) x.trim().replaceAll(',', '-')
      }.toList();

  /// Creates an item. [due] and [priority] apply to tasks; [start], [end] and
  /// [location] to events (start required); [folder] makes a note a folder.
  Future<ItemChange> create(
    ItemKind kind,
    String title, {
    String body = '',
    List<String> tags = const [],
    String? status,
    String? parent,
    bool folder = false,
    String? due,
    int? priority,
    String? start,
    String? end,
    String? location,
    String? writer,
    bool dryRun = false,
  }) async {
    if (title.trim().isEmpty) throw ItemServiceException('title is empty');
    if (folder && kind != ItemKind.note) {
      throw ItemServiceException('only notes can be folders');
    }
    if (kind != ItemKind.task && due != null) {
      throw ItemServiceException('due applies to tasks only');
    }
    if (kind == ItemKind.event && priority != null) {
      throw ItemServiceException('priority applies to tasks and notes only');
    }
    if (kind != ItemKind.event &&
        (start != null || end != null || location != null)) {
      throw ItemServiceException(
          'start, end and location apply to events only');
    }
    String? parentUid;
    if (parent != null) parentUid = _find(await _load(), parent).uid;
    final now = _now();
    final cats = _cleanTags([...tags, if (folder) folderTag]);
    final uid = _newUid();
    final _Ref ref;
    switch (kind) {
      case ItemKind.note:
        final n = Note(
            uid: uid,
            summary: title,
            description: body,
            categories: cats,
            parentUid: parentUid,
            created: now,
            lastModified: now);
        ref = _Ref(n);
        if (status != null) _setStatus(ref, status, now);
        if (priority != null) _setNotePriority(n, priority);
      case ItemKind.task:
        final t = Task(
            uid: uid,
            summary: title,
            description: body,
            categories: cats,
            status: 'NEEDS-ACTION',
            priority: priority,
            due: due == null ? null : parseWhen(due),
            parentUid: parentUid,
            created: now,
            lastModified: now);
        ref = _Ref(t);
        if (status != null) _setStatus(ref, status, now);
      case ItemKind.event:
        if (start == null) throw ItemServiceException('an event needs a start');
        final e = Event(
            uid: uid,
            summary: title,
            description: body,
            location: location ?? '',
            categories: cats,
            dtstart: parseWhen(start),
            dtend: end == null ? null : parseWhen(end),
            parentUid: parentUid,
            created: now,
            lastModified: now);
        ref = _Ref(e);
        if (status != null) _setStatus(ref, status, now);
    }
    ref.stampWriter(writer);
    final desc = ['create ${folder ? 'folder' : kind.name} "$title"'];
    if (dryRun) return ItemChange('create', true, desc, ref.toData());
    return ItemChange('create', false, desc,
        (await ref.put(client, ref)).toData(client.collection));
  }

  Future<ItemChange> _edit(
    String id,
    String action,
    ItemKind? kind,
    bool dryRun,
    List<String> Function(_Ref edit, List<_Ref> all) apply, [
    String? writer,
  ]) async {
    final all = await _load(kind);
    final base = _find(all, id, kind: kind);
    final edit = base.clone();
    final changes = apply(edit, all);
    edit.stampWriter(writer);
    if (changes.isEmpty || dryRun) {
      return ItemChange(action, dryRun, changes, edit.toData());
    }
    return ItemChange(action, false, changes,
        (await edit.put(client, base)).toData(client.collection));
  }

  /// Changes title, body, location (events) or start and end (events).
  /// Null leaves a field as it is.
  Future<ItemChange> update(
    String id, {
    ItemKind? kind,
    String? title,
    String? body,
    String? location,
    String? start,
    String? end,
    String? writer,
    bool dryRun = false,
  }) =>
      _edit(id, 'update', kind, dryRun, (e, _) {
        final ch = <String>[];
        if (title != null && title != e.title) {
          ch.add('title: "${e.title}" -> "$title"');
          e.title = title;
        }
        if (body != null && body != e.body) {
          ch.add('body: ${e.body.length} -> ${body.length} chars');
          e.body = body;
        }
        final raw = e.raw;
        if (location != null || start != null || end != null) {
          if (raw is! Event) {
            throw ItemServiceException(
                'location, start and end apply to events only');
          }
          if (location != null && location != raw.location) {
            ch.add('location: "${raw.location}" -> "$location"');
            raw.location = location;
          }
          if (start != null) {
            ch.add('start: ${raw.dtstart?.value} -> $start');
            raw.dtstart = parseWhen(start);
          }
          if (end != null) {
            ch.add('end: ${raw.dtend?.value} -> $end');
            raw.dtend = parseWhen(end);
            raw.duration = null;
          }
        }
        return ch;
      }, writer);

  /// Moves an item under [parent] (uid or title), or to the top level when
  /// [parent] is null. Refuses a move that would make a loop.
  Future<ItemChange> move(String id, String? parent,
          {String? writer, bool dryRun = false}) =>
      _edit(id, 'move', null, dryRun, (e, all) {
        final target = parent == null ? null : _find(all, parent);
        if (!_tree(all).canMove(e.uid, target?.uid)) {
          throw ItemServiceException(
              'cannot move "${e.title}" under "${target?.title}"');
        }
        if (e.parentUid == target?.uid) return [];
        final from = e.parentUid;
        e.parentUid = target?.uid;
        return ['parent: ${from ?? 'top'} -> ${target?.uid ?? 'top'}'];
      }, writer);

  /// Replaces ([set]), adds to ([add]) or removes from ([remove]) the tags.
  /// Status tags are managed by [setStatus]; this leaves them alone unless
  /// named explicitly.
  Future<ItemChange> setTags(String id,
          {List<String>? set,
          List<String> add = const [],
          List<String> remove = const [],
          ItemKind? kind,
          String? writer,
          bool dryRun = false}) =>
      _edit(id, 'tags', kind, dryRun, (e, _) {
        final before = List.of(e.tags);
        var t = set == null
            ? List.of(before)
            : [
                ..._cleanTags(set),
                ...before
                    .where((x) => x.startsWith('status-') || x == folderTag)
              ];
        for (final a in _cleanTags(add)) {
          if (!t.contains(a)) t.add(a);
        }
        t.removeWhere(remove.contains);
        t = t.toSet().toList();
        if (_same(t, before)) return [];
        e.tags = t;
        return ['tags: ${before.join(',')} -> ${t.join(',')}'];
      }, writer);

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  void _setStatus(_Ref e, String? word, DateTime now) {
    var w = word?.trim().toLowerCase();
    if (w != null && w.isNotEmpty) {
      w = canonicalStatus(w);
      if (w == null) {
        throw ItemServiceException('unknown status "${word!.trim()}"; '
            'allowed: ${allowedStatuses.join(', ')}');
      }
    }
    switch (e.raw) {
      case Task t:
        if (w == null || w.isEmpty) {
          throw ItemServiceException('a task always has a status');
        }
        t.setBoardStatus(w, now);
      case Note n:
        final p = PlanItem.fromNote(n);
        if (w == null || w.isEmpty) {
          p.clearStatus();
        } else if (p.statusLine != null) {
          p.setStatus(w);
        } else {
          n.categories
            ..removeWhere((c) => c.startsWith('status-'))
            ..add('status-$w');
        }
        p.apply();
      default:
        final ev = e.raw as Event;
        ev.categories.removeWhere((c) => c.startsWith('status-'));
        if (w != null && w.isNotEmpty) ev.categories.add('status-$w');
    }
  }

  /// Sets the board status word. Tasks keep STATUS, percent and completion
  /// in step (via [Task.setBoardStatus]); notes and events use `status-*`
  /// tags (and the body header of a plan note). A null [status] clears it
  /// (not for tasks).
  Future<ItemChange> setStatus(String id, String? status,
          {ItemKind? kind, String? writer, bool dryRun = false}) =>
      _edit(id, 'status', kind, dryRun, (e, _) {
        final before = e.status;
        _setStatus(e, status, _now());
        final after = e.status;
        return before == after
            ? []
            : ['status: ${before ?? '-'} -> ${after ?? '-'}'];
      }, writer);

  /// Sets the due date of a task ([due] null clears it).
  Future<ItemChange> setDue(String id, String? due,
          {String? writer, bool dryRun = false}) =>
      _edit(id, 'due', ItemKind.task, dryRun, (e, _) {
        final t = e.raw as Task;
        final nd = due == null ? null : parseWhen(due);
        if (nd == t.due) return [];
        final ch = ['due: ${t.due?.value ?? '-'} -> ${nd?.value ?? '-'}'];
        t.due = nd;
        return ch;
      }, writer);

  /// Sets a note's `priority` body field from a task-style number (1-4 high,
  /// 5 medium, 6-9 low; null or 0 clears it).
  static void _setNotePriority(Note n, int? priority) {
    final p = PlanItem.fromNote(n)..setPriority(priorityWordOf(priority));
    p.apply();
  }

  /// Sets the priority of a task or note (1 highest .. 9 lowest; null clears
  /// it). A note keeps it as a `priority: high|medium|low` body line (1-4 high,
  /// 5 medium, 6-9 low; 1, 5 and 9 are what it reads back as).
  Future<ItemChange> setPriority(String id, int? priority,
      {ItemKind? kind, String? writer, bool dryRun = false}) {
    if (priority != null && (priority < 0 || priority > 9)) {
      throw ItemServiceException('priority is 0..9');
    }
    return _edit(id, 'priority', kind, dryRun, (e, _) {
      switch (e.raw) {
        case Task t:
          if (t.priority == priority) return [];
          final ch = ['priority: ${t.priority ?? '-'} -> ${priority ?? '-'}'];
          t.priority = priority;
          return ch;
        case Note n:
          final before = PlanItem.fromNote(n).priority;
          final after = notePriorities[priorityWordOf(priority)];
          if (before == after) return [];
          _setNotePriority(n, priority);
          return ['priority: ${before ?? '-'} -> ${after ?? '-'}'];
        default:
          throw ItemServiceException(
              'priority applies to tasks and notes only; "${e.title}" is an event');
      }
    }, writer);
  }

  /// Deletes an item. With [adoptChildren] (default) its children move up to
  /// its own parent first, so none are left dangling.
  Future<ItemChange> delete(String id,
      {ItemKind? kind,
      bool adoptChildren = true,
      String? writer,
      bool dryRun = false}) async {
    final all = await _load();
    final ref = _find(all, id, kind: kind);
    final kids = adoptChildren
        ? all.where((r) => r.parentUid == ref.uid).toList()
        : <_Ref>[];
    final changes = [
      'delete ${ref.kind.name} "${ref.title}"',
      for (final k in kids) 'move "${k.title}" to ${ref.parentUid ?? 'top'}',
    ];
    if (!dryRun) {
      for (final k in kids) {
        final edit = k.clone()..parentUid = ref.parentUid;
        edit.stampWriter(writer);
        await edit.put(client, k);
      }
      await ref.delete(client);
    }
    return ItemChange('delete', dryRun, changes, ref.toData());
  }

  /// Moves an item, and with [subtree] (default) everything below it, into
  /// the collection served by [target]. Copies get new uids; parent links are
  /// remapped inside the moved set; the moved root becomes top level in the
  /// target, or goes under [under] (uid, href or title there).
  ///
  /// Order: plan, raw ICS backup of the source set into [backupDir] (required
  /// unless [dryRun]), copy everything, read the target back and check every
  /// copy (kind, title, tags, status, parent), check the originals did not
  /// change, and only then delete the originals. Any failure before the
  /// delete leaves the originals untouched (copies already made stay in the
  /// target and are named in the error). Recurring items with per-occurrence
  /// overrides are refused. A collection holding unreadable resources is
  /// refused unless [allowUnreadable] (they are never moved or deleted).
  /// Without [subtree], children left behind move up to the moved item's
  /// own parent.
  Future<MoveResult> moveToCollection(
    ItemService target,
    String id, {
    String? under,
    bool subtree = true,
    String? backupDir,
    bool allowUnreadable = false,
    bool dryRun = false,
    String? writer,
    BackupWriter? backupWriter,
  }) async {
    String norm(Uri u) =>
        '${u.host}:${u.port}${u.path.endsWith('/') ? u.path : '${u.path}/'}';
    if (norm(client.collection) == norm(target.client.collection)) {
      throw ItemServiceException('source and target are the same collection');
    }
    if (!dryRun && (backupDir == null || backupDir.isEmpty)) {
      throw ItemServiceException('a move needs a backup directory');
    }
    final all = await _load();
    final root = _find(all, id);
    final byUid = {for (final r in all) r.uid: r};
    final tree = _tree(all);
    final set = <_Ref>[
      root,
      if (subtree)
        for (final n in tree.descendants(root.uid)) byUid[n.uid]!,
    ];
    final inSet = {for (final r in set) r.uid};
    for (final r in set) {
      if (r.hasSiblings) {
        throw ItemServiceException('"${r.title}" is a repeating item with '
            'changed occurrences; it cannot be moved');
      }
    }
    // Unreadable resources in the source.
    final raw = await client.listRaw();
    final readable = <String>{
      for (final n in await client.listNotes())
        if (n.href != null) client.pathOf(n.href!),
      for (final t in await client.listTasks())
        if (t.href != null) client.pathOf(t.href!),
      for (final e in await client.listEvents())
        if (e.href != null) client.pathOf(e.href!),
    };
    final unreadable = [
      for (final r in raw)
        if (!readable.contains(client.pathOf(r.href))) r.href
    ];
    if (unreadable.isNotEmpty && !allowUnreadable) {
      throw ItemServiceException('the source holds ${unreadable.length} '
          'unreadable resource(s) (${unreadable.take(5).join(', ')}); nothing '
          'was moved. Allow unreadable to move anyway (they stay untouched)');
    }
    final tAll = await target._load();
    final under0 = under == null ? null : target._find(tAll, under);
    if (under0 != null &&
        !(under0.raw is Note && isFolderNote(under0.raw as Note))) {
      throw ItemServiceException('--under "${under0.title}" is not a folder '
          'in the target collection; nothing was moved');
    }
    final views = [
      for (final v in await _loadViews())
        if (inSet.contains(v.parentUid)) v
    ];
    final fresh = {for (final r in set) r.uid: target._newUid()};
    final kids =
        subtree ? <_Ref>[] : all.where((r) => r.parentUid == root.uid).toList();
    final entries = [
      for (final r in set)
        MoveEntry(
            r.kind,
            r.uid,
            fresh[r.uid]!,
            r.title,
            r.uid == root.uid
                ? under0?.uid
                : (inSet.contains(r.parentUid) ? fresh[r.parentUid] : null)),
    ];
    final stamp = _now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '')
        .replaceAll('-', '');
    final dir = backupDir == null ? null : '$backupDir/move-$stamp';
    final plan = [
      'move ${set.length} item(s) from ${client.collection.path} to '
          '${target.client.collection.path}'
          '${under0 == null ? '' : ' under "${under0.title}"'}',
      if (dir != null) 'back up ${set.length} source item(s) to $dir',
      for (final x in entries)
        '${x.kind.name} "${x.title}" ${x.oldUid} -> ${x.newUid}'
            '${x.newParent == null ? ' (top)' : ' (parent ${x.newParent})'}',
      for (final k in kids)
        'children left behind: "${k.title}" moves to '
            '${root.parentUid ?? 'top'}',
      if (views.isNotEmpty)
        'left behind, ${views.length} view notes: they are re-parented to '
            '${root.parentUid ?? 'top level'}, not moved',
      if (unreadable.isNotEmpty)
        '${unreadable.length} unreadable resource(s) stay untouched',
      'delete the ${set.length} original(s) after every copy is verified',
    ];
    if (dryRun) {
      return MoveResult(true, plan, entries, dir, false, views.length);
    }

    // Backup of the raw source set.
    final rawByPath = {for (final r in raw) client.pathOf(r.href): r};
    final files = <String, String>{};
    final width = '${set.length}'.length;
    var i = 0;
    for (final r in set) {
      final h = r.href;
      final body = h == null ? null : rawByPath[client.pathOf(h)]?.data;
      if (h == null || body == null || body.trim().isEmpty) {
        throw ItemServiceException(
            'cannot back up "${r.title}": no raw copy or it is empty; '
            'nothing was moved');
      }
      final label = client.pathOf(h).split('/').where((x) => x.isNotEmpty).last;
      final safe = label
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
          .replaceAll(RegExp(r'^\.+'), '_');
      files['${'${++i}'.padLeft(width, '0')}-$safe'
          '${safe.endsWith('.ics') ? '' : '.ics'}'] = body;
    }
    if (files.length != set.length ||
        files.values.any((t) => t.trim().isEmpty)) {
      throw ItemServiceException(
          'backup set is incomplete (${files.length} of ${set.length}, or an '
          'empty file); nothing was moved');
    }
    final written = (backupWriter ?? writeBackupFiles)(dir!, files);
    if (written != null && written != files.length) {
      throw ItemServiceException(
          'backup wrote $written of ${files.length} files; nothing was moved');
    }

    // Copy everything first.
    final made = <String>[];
    String madeText() => made.isEmpty
        ? 'no copies were made'
        : 'copies already in the target: ${made.join(', ')}';
    try {
      for (final x in entries) {
        final copy = byUid[x.oldUid]!.reuid(x.newUid, x.newParent);
        copy.stampWriter(writer);
        await copy.putNew(target.client);
        made.add(x.newUid);
      }
    } catch (e) {
      throw ItemServiceException('copy failed ($e); the originals were kept; '
          '${madeText()}');
    }
    // Read the target back and check every copy.
    final back = {for (final r in await target._load()) r.uid: r};
    for (final x in entries) {
      final o = byUid[x.oldUid]!, c = back[x.newUid];
      String? bad;
      if (c == null) {
        bad = 'missing';
      } else if (c.kind != o.kind) {
        bad = 'wrong kind';
      } else if (c.title != o.title) {
        bad = 'title differs';
      } else if (c.parentUid != x.newParent) {
        bad = 'parent differs';
      } else if (c.status != o.status) {
        bad = 'status differs';
      } else if (!_same((List.of(c.tags)..sort()), (List.of(o.tags)..sort()))) {
        bad = 'tags differ';
      } else {
        final f = _contentDiff(o, c);
        if (f != null) bad = 'field $f differs';
      }
      if (bad != null) {
        throw ItemServiceException('verification failed for "${x.title}" '
            '(${x.newUid}): $bad; the originals were kept; ${madeText()}');
      }
    }
    if (made.length != set.length) {
      throw ItemServiceException('verification failed: ${made.length} copies '
          'for ${set.length} items; the originals were kept; ${madeText()}');
    }
    // The originals must be unchanged since they were read.
    final now = {for (final r in await _load()) r.uid: r};
    for (final r in set) {
      final n = now[r.uid];
      if (n == null || n.etag != r.etag) {
        throw ItemServiceException('"${r.title}" changed while moving; the '
            'originals were kept; ${madeText()}');
      }
    }
    // Re-parent what stays behind, then delete originals, children first.
    // On failure, list every copy whose original is still there.
    var deleted = 0;
    String pending() {
      final left = entries.reversed.skip(deleted);
      return 'copied but not cleaned up (old uid, new uid, new href): '
          '${left.map((x) => '${x.oldUid} -> ${x.newUid} ${back[x.newUid]?.href}').join('; ')}. '
          'To resolve: check the copies in the target, then delete the '
          'listed originals (or, to undo, the listed copies); the backup is '
          'at $dir. Nothing was auto-deleted beyond $deleted original(s)';
    }

    try {
      for (final k in [...kids, ...views]) {
        final edit = k.clone()..parentUid = root.parentUid;
        edit.stampWriter(writer);
        await edit.put(client, k);
      }
    } catch (e) {
      throw ItemServiceException('re-parenting failed ($e); no original was '
          'deleted; ${pending()}');
    }
    try {
      for (final r in set.reversed) {
        await r.delete(client);
        deleted++;
      }
    } catch (e) {
      throw ItemServiceException('delete failed after $deleted of '
          '${set.length} originals ($e); ${pending()}');
    }
    return MoveResult(false, plan, entries, dir, true, views.length);
  }
}

/// One item of a cross-collection move: kind, old and new uid, title and the
/// new parent uid (null: top level).
class MoveEntry {
  const MoveEntry(
      this.kind, this.oldUid, this.newUid, this.title, this.newParent);
  final ItemKind kind;
  final String oldUid, newUid, title;
  final String? newParent;
  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'title': title,
        'old_uid': oldUid,
        'new_uid': newUid,
        'parent': newParent,
      };
}

/// Outcome of [ItemService.moveToCollection]. With [dryRun] nothing was
/// written; [deleted] says the originals are gone.
class MoveResult {
  const MoveResult(
      this.dryRun, this.plan, this.entries, this.backupPath, this.deleted,
      [this.viewNotesLeft = 0]);
  final bool dryRun;
  final List<String> plan;
  final List<MoveEntry> entries;
  final String? backupPath;
  final bool deleted;

  /// View notes under the moved set, left in the source and re-parented.
  final int viewNotesLeft;
  Map<String, Object?> toJson() => {
        'action': 'move-to-collection',
        'view_notes_left_behind': viewNotesLeft,
        'dryRun': dryRun,
        'deleted': deleted,
        'backup': backupPath,
        'plan': plan,
        'items': [for (final e in entries) e.toJson()],
      };
}
