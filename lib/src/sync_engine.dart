import 'caldav.dart';
import 'merge.dart';
import 'note.dart';
import 'store.dart';

/// What one [SyncEngine.sync] run did.
class SyncReport {
  int pulled = 0;
  int pushed = 0;
  int deleted = 0;
  int merged = 0;
  final conflicts = <MergeConflict>[];
  final errors = <String>[];

  @override
  String toString() => 'pulled $pulled, pushed $pushed, deleted $deleted, '
      'merged $merged, conflicts ${conflicts.length}, errors ${errors.length}';
}

/// Offline-first sync between a [NoteStore] and one CalDAV collection.
///
/// Edit through [save] and [delete]; they only touch the store. [sync] pulls
/// server changes (incrementally when the server supports sync tokens),
/// merges them with local edits against the last-synced copy, then pushes
/// what is left. A true conflict never creates a duplicate note: the later
/// edit wins that value, and the earlier local text is kept as a [Revision].
class SyncEngine {
  SyncEngine(this.client, this.store, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final CalDavClient client;
  final NoteStore store;
  final DateTime Function() _now;

  /// Saves [note] locally (new or edited) and marks it for the next sync.
  Future<Note> save(Note note) async {
    final existing = await store.get(note.uid);
    final local = note.copyWith(lastModified: _now().toUtc());
    local.href = existing?.base?.href ?? existing?.local.href ?? note.href;
    local.etag = existing?.base?.etag;
    await store.put(
        note.uid,
        StoredNote(
            local: local, base: existing?.base, dirty: true, deleted: false));
    return local;
  }

  /// Deletes locally; the server copy goes at the next sync.
  Future<void> delete(String uid) async {
    final s = await store.get(uid);
    if (s == null) return;
    if (s.base == null) {
      await store.remove(uid);
    } else {
      s.deleted = true;
      s.dirty = true;
      await store.put(uid, s);
    }
  }

  /// Notes to show: everything not deleted locally.
  Future<List<Note>> notes() async => [
        for (final s in await store.all())
          if (!s.deleted) s.local
      ];

  String _path(String href) => client.collection.resolve(href).path;

  Future<SyncReport> sync() async {
    final report = SyncReport();
    await _pull(report);
    await _push(report);
    return report;
  }

  Future<void> _pull(SyncReport report) async {
    var token = await store.getSyncToken();
    SyncResult res;
    try {
      res = await client.sync(syncToken: token);
    } on SyncTokenInvalid {
      token = null;
      res = await client.sync();
    }
    for (final r in res.changed) {
      await _applyRemote(r, report);
    }
    final all = await store.all();
    if (token == null || token.isEmpty) {
      // Full listing: anything synced before that the server no longer has
      // was deleted there.
      final present = {for (final r in res.changed) _path(r.href ?? '')};
      for (final s in all) {
        final href = s.base?.href;
        if (href != null && !present.contains(_path(href))) {
          await _remoteDeleted(s);
        }
      }
    } else {
      final gone = res.deletedHrefs.map(_path).toSet();
      for (final s in all) {
        final href = s.base?.href ?? s.local.href;
        if (href != null && gone.contains(_path(href))) {
          await _remoteDeleted(s);
        }
      }
    }
    await store.setSyncToken(res.syncToken);
  }

  Future<void> _remoteDeleted(StoredNote s) async {
    final uid = s.local.uid;
    if (!s.dirty || s.deleted) {
      await store.remove(uid);
    } else {
      // Edited here, deleted there: keep the edit and recreate it on push.
      s.base = null;
      s.local.etag = null;
      await store.put(uid, s);
    }
  }

  bool _sameContent(Note a, Note b) =>
      a.summary == b.summary &&
      a.description == b.description &&
      a.status == b.status &&
      a.categories.length == b.categories.length &&
      a.categories.toSet().containsAll(b.categories);

  Future<void> _applyRemote(Note r, SyncReport report) async {
    final s = await store.get(r.uid);
    if (s == null) {
      await store.put(r.uid, StoredNote(local: r, base: r));
      report.pulled++;
      return;
    }
    if (r.etag != null && s.base?.etag == r.etag) return; // our own push
    if (!s.dirty || s.deleted) {
      await store.put(r.uid, StoredNote(local: r, base: r));
      report.pulled++;
      return;
    }
    final base = s.base ?? Note(uid: r.uid);
    final m = mergeNotes(base, s.local, r);
    if (m.hadConflict) {
      report.conflicts.addAll(m.conflicts);
      await store.addRevision(Revision(
        uid: r.uid,
        at: _now().toUtc(),
        reason: 'merge conflict: ${m.conflicts.map((c) => c.what).join(", ")}',
        summary: s.local.summary,
        body: s.local.description,
      ));
    }
    report.merged++;
    await store.put(r.uid,
        StoredNote(local: m.note, base: r, dirty: !_sameContent(m.note, r)));
  }

  Future<void> _push(SyncReport report) async {
    for (final first in await store.all()) {
      if (!first.dirty) continue;
      final uid = first.local.uid;
      for (var attempt = 0; attempt < 3; attempt++) {
        final s = await store.get(uid);
        if (s == null || !s.dirty) break;
        try {
          if (s.deleted) {
            await client.deleteNote(s.base!);
            await store.remove(uid);
            report.deleted++;
          } else {
            final stored = await client.putNote(s.local.copyWith()
              ..href = s.local.href
              ..etag = s.local.etag);
            await store.put(
                uid, StoredNote(local: stored, base: stored.copyWith()));
            report.pushed++;
          }
          break;
        } on ConflictException {
          await _refetch(s, report);
        } on CalDavException catch (e) {
          report.errors.add('$uid: $e');
          break;
        }
        if (attempt == 2) report.errors.add('$uid: still conflicting');
      }
    }
  }

  /// After a 412: pull the server copy of [s] and merge, so the next push
  /// carries the current etag.
  Future<void> _refetch(StoredNote s, SyncReport report) async {
    final href = s.base?.href ?? s.local.href ?? '${s.local.uid}.ics';
    try {
      await _applyRemote(await client.getNote(href), report);
    } on CalDavException catch (e) {
      if (e.statusCode != 404) rethrow;
      // Gone from the server: a deletion is done, an edit is recreated.
      if (s.deleted) {
        await store.remove(s.local.uid);
      } else {
        s.base = null;
        s.local.etag = null;
        await store.put(s.local.uid, s);
      }
    }
  }
}
