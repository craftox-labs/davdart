import 'event.dart';
import 'ical.dart';
import 'store.dart' show Revision;

/// An event as the app holds it: the working copy, the copy last synced with
/// the server (the merge base), and what is waiting to be sent.
class StoredEvent {
  StoredEvent({
    required this.local,
    this.base,
    this.dirty = false,
    this.deleted = false,
  });

  Event local;
  Event? base;
  bool dirty;
  bool deleted;
}

/// Where events, sync state and revisions live between syncs; see TaskStore.
abstract class EventStore {
  Future<StoredEvent?> get(String uid);
  Future<List<StoredEvent>> all();
  Future<void> put(String uid, StoredEvent s);
  Future<void> remove(String uid);
  Future<String?> getSyncToken();
  Future<void> setSyncToken(String? token);
  Future<void> addRevision(Revision r);
  Future<List<Revision>> revisions(String uid);
}

Event _clone(Event n) => n.copyWith();

StoredEvent _cloneStored(StoredEvent s) => StoredEvent(
      local: _clone(s.local),
      base: s.base == null ? null : _clone(s.base!),
      dirty: s.dirty,
      deleted: s.deleted,
    );

class MemoryEventStore implements EventStore {
  final Map<String, StoredEvent> _events = {};
  final List<Revision> _revisions = [];
  String? _token;

  /// Called after every change; [FileEventStore] persists here.
  void changed() {}

  @override
  Future<StoredEvent?> get(String uid) async {
    final s = _events[uid];
    return s == null ? null : _cloneStored(s);
  }

  @override
  Future<List<StoredEvent>> all() async =>
      [for (final s in _events.values) _cloneStored(s)];

  @override
  Future<void> put(String uid, StoredEvent s) async {
    _events[uid] = _cloneStored(s);
    changed();
  }

  @override
  Future<void> remove(String uid) async {
    _events.remove(uid);
    changed();
  }

  @override
  Future<String?> getSyncToken() async => _token;

  @override
  Future<void> setSyncToken(String? token) async {
    _token = token;
    changed();
  }

  @override
  Future<void> addRevision(Revision r) async {
    _revisions.add(r);
    changed();
  }

  @override
  Future<List<Revision>> revisions(String uid) async =>
      _revisions.where((r) => r.uid == uid).toList();

  static Map<String, Object?> _encode(Event n) =>
      {'ics': serializeEvent(n), 'href': n.href, 'etag': n.etag};

  static Event _decode(Map<String, dynamic> m) => parseEvent(m['ics'] as String)
    ..href = m['href'] as String?
    ..etag = m['etag'] as String?;

  /// The whole store as a JSON-ready map; events are kept as iCalendar text.
  Map<String, Object?> toJson() => {
        'syncToken': _token,
        'events': {
          for (final e in _events.entries)
            e.key: {
              'local': _encode(e.value.local),
              'base': e.value.base == null ? null : _encode(e.value.base!),
              'dirty': e.value.dirty,
              'deleted': e.value.deleted,
            }
        },
        'revisions': [
          for (final r in _revisions)
            {
              'uid': r.uid,
              'at': r.at.toIso8601String(),
              'reason': r.reason,
              'summary': r.summary,
              'body': r.body,
            }
        ],
      };

  /// Replaces the contents with a map from [toJson].
  void loadJson(Map<String, dynamic> j) {
    _events.clear();
    _revisions.clear();
    _token = j['syncToken'] as String?;
    for (final e in (j['events'] as Map<String, dynamic>).entries) {
      final m = e.value as Map<String, dynamic>;
      _events[e.key] = StoredEvent(
        local: _decode(m['local'] as Map<String, dynamic>),
        base: m['base'] == null
            ? null
            : _decode(m['base'] as Map<String, dynamic>),
        dirty: m['dirty'] as bool,
        deleted: m['deleted'] as bool,
      );
    }
    for (final r in j['revisions'] as List<dynamic>) {
      final m = r as Map<String, dynamic>;
      _revisions.add(Revision(
        uid: m['uid'] as String,
        at: DateTime.parse(m['at'] as String),
        reason: m['reason'] as String,
        summary: m['summary'] as String,
        body: m['body'] as String,
      ));
    }
  }
}
