import 'dart:convert';
import 'dart:io';

import 'ical.dart';
import 'note.dart';

/// A note as the app holds it: the working copy, the copy last synced with the
/// server (the merge base), and what is waiting to be sent.
class StoredNote {
  StoredNote({
    required this.local,
    this.base,
    this.dirty = false,
    this.deleted = false,
  });

  /// What the user sees and edits.
  Note local;

  /// The server copy as of the last sync; null if never synced.
  Note? base;

  /// Local changes not yet pushed.
  bool dirty;

  /// Deleted locally, delete not yet pushed.
  bool deleted;
}

/// An earlier version of a note, kept when a merge had to pick a winner, so a
/// resolved conflict never needs a duplicate note.
class Revision {
  Revision({
    required this.uid,
    required this.at,
    required this.reason,
    required this.summary,
    required this.body,
  });
  final String uid;
  final DateTime at;
  final String reason;
  final String summary;
  final String body;
}

/// Where notes, sync state and revisions live between syncs. Flutter apps can
/// provide a drift/SQLite implementation; [MemoryNoteStore] and
/// [FileNoteStore] cover tests, the CLI and quick use.
abstract class NoteStore {
  Future<StoredNote?> get(String uid);
  Future<List<StoredNote>> all();
  Future<void> put(String uid, StoredNote s);
  Future<void> remove(String uid);
  Future<String?> getSyncToken();
  Future<void> setSyncToken(String? token);
  Future<void> addRevision(Revision r);
  Future<List<Revision>> revisions(String uid);
}

Note _clone(Note n) => n.copyWith();

StoredNote _cloneStored(StoredNote s) => StoredNote(
      local: _clone(s.local),
      base: s.base == null ? null : _clone(s.base!),
      dirty: s.dirty,
      deleted: s.deleted,
    );

class MemoryNoteStore implements NoteStore {
  final Map<String, StoredNote> _notes = {};
  final List<Revision> _revisions = [];
  String? _token;

  /// Called after every change; [FileNoteStore] persists here.
  void changed() {}

  @override
  Future<StoredNote?> get(String uid) async {
    final s = _notes[uid];
    return s == null ? null : _cloneStored(s);
  }

  @override
  Future<List<StoredNote>> all() async =>
      [for (final s in _notes.values) _cloneStored(s)];

  @override
  Future<void> put(String uid, StoredNote s) async {
    _notes[uid] = _cloneStored(s);
    changed();
  }

  @override
  Future<void> remove(String uid) async {
    _notes.remove(uid);
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
}

/// A [MemoryNoteStore] saved to one JSON file after every change (written to a
/// temporary file first, then renamed). Notes are stored as iCalendar text, so
/// nothing a server sent is lost.
class FileNoteStore extends MemoryNoteStore {
  FileNoteStore._(this.path);
  final String path;

  static Future<FileNoteStore> open(String path) async {
    final store = FileNoteStore._(path);
    final f = File(path);
    if (f.existsSync()) {
      Map<String, dynamic> j;
      try {
        j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      } on FormatException {
        // Truncated or damaged: keep it for inspection and start over, so the
        // next sync repopulates from the server.
        f.renameSync('$path.corrupt-${DateTime.now().millisecondsSinceEpoch}');
        return store;
      }
      store._token = j['syncToken'] as String?;
      for (final e in (j['notes'] as Map<String, dynamic>).entries) {
        final m = e.value as Map<String, dynamic>;
        store._notes[e.key] = StoredNote(
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
        store._revisions.add(Revision(
          uid: m['uid'] as String,
          at: DateTime.parse(m['at'] as String),
          reason: m['reason'] as String,
          summary: m['summary'] as String,
          body: m['body'] as String,
        ));
      }
    }
    return store;
  }

  static Map<String, Object?> _encode(Note n) =>
      {'ics': serializeNote(n), 'href': n.href, 'etag': n.etag};

  static Note _decode(Map<String, dynamic> m) => parseNote(m['ics'] as String)
    ..href = m['href'] as String?
    ..etag = m['etag'] as String?;

  @override
  void changed() {
    final tmp = File('$path.$pid.tmp');
    tmp.parent.createSync(recursive: true);
    tmp.writeAsStringSync(jsonEncode({
      'syncToken': _token,
      'notes': {
        for (final e in _notes.entries)
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
    }));
    tmp.renameSync(path);
  }
}
