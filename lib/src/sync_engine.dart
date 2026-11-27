import 'caldav.dart';
import 'ical.dart' show ICalException;
import 'merge.dart';
import 'note.dart';
import 'store.dart';

/// What one [SyncEngine.sync] run did.
class SyncReport {
  int pulled = 0;
  int pushed = 0;
  int deleted = 0;
  int merged = 0;

  /// Notes deleted locally but edited on the server, so they came back.
  int restored = 0;
  final conflicts = <MergeConflict>[];
  final errors = <String>[];

  @override
  String toString() => 'pulled $pulled, pushed $pushed, deleted $deleted, '
      'merged $merged, restored $restored, conflicts ${conflicts.length}, errors ${errors.length}';
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
        local: local,
        base: existing?.base,
        dirty: true,
        deleted: false,
      ),
    );
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
          if (!s.deleted) s.local,
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
    for (final h in res.unparsableHrefs) {
      report.errors.add('$h: cannot be read, left as is');
    }
    for (final r in res.changed) {
      await _applyRemote(r, report);
    }
    final all = await store.all();
    if (token == null || token.isEmpty) {
      // Full listing: anything synced before that the server no longer has
      // was deleted there.
      final present = {
        for (final r in res.changed) _path(r.href ?? ''),
        // Present but unreadable: never treated as deleted.
        for (final h in res.unparsableHrefs) _path(h),
      };
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

  bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  bool _sameContent(Note a, Note b) =>
      _sameList(a.extraLines, b.extraLines) &&
      a.propertyParams.length == b.propertyParams.length &&
      a.propertyParams.entries.every(
        (e) => b.propertyParams[e.key] == e.value,
      ) &&
      a.parentUid == b.parentUid &&
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
    if (s.deleted) {
      // Deleted here, edited there: the edit is someone's work, so the note
      // comes back, and the event is recorded rather than silent.
      await store.addRevision(
        Revision(
          uid: r.uid,
          at: _now().toUtc(),
          reason: 'deleted locally, edited on the server; restored',
          summary: s.local.summary,
          body: s.local.description,
        ),
      );
      await store.put(r.uid, StoredNote(local: r, base: r));
      report.restored++;
      return;
    }
    if (!s.dirty) {
      await store.put(r.uid, StoredNote(local: r, base: r));
      report.pulled++;
      return;
    }
    final base = s.base ?? Note(uid: r.uid);
    final m = mergeNotes(base, s.local, r);
    if (m.hadConflict) {
      report.conflicts.addAll(m.conflicts);
      await store.addRevision(
        Revision(
          uid: r.uid,
          at: _now().toUtc(),
          reason:
              'merge conflict: ${m.conflicts.map((c) => c.what).join(", ")}',
          summary: s.local.summary,
          body: s.local.description,
        ),
      );
    }
    report.merged++;
    await store.put(
      r.uid,
      StoredNote(local: m.note, base: r, dirty: !_sameContent(m.note, r)),
    );
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
            final cur = await store.get(uid);
            if (cur != null && !cur.deleted) {
              // Edited again while the delete was in flight: keep the edit
              // and recreate it on the next push.
              cur.base = null;
              cur.local.etag = null;
              cur.dirty = true;
              await store.put(uid, cur);
            } else {
              await store.remove(uid);
            }
            report.deleted++;
          } else {
            final stored = await client.putNote(
              s.local.copyWith()
                ..href = s.local.href
                ..etag = s.local.etag,
            );
            final cur = await store.get(uid);
            if (cur != null &&
                (cur.deleted ||
                    cur.local.lastModified != s.local.lastModified)) {
              // Edited or deleted while the PUT was in flight: keep that
              // change, now on top of what was just stored.
              cur.base = stored.copyWith();
              cur.local.href = stored.href;
              cur.local.etag = stored.etag;
              cur.dirty = true;
              await store.put(uid, cur);
            } else {
              await store.put(
                uid,
                StoredNote(local: stored, base: stored.copyWith()),
              );
            }
            report.pushed++;
          }
          break;
        } on ConflictException {
          if (!await _refetch(s, report)) break;
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
  ///
  /// Returns false when the server copy cannot be parsed: the local item stays
  /// as it is (dirty) and the problem is reported, nothing is deleted.
  Future<bool> _refetch(StoredNote s, SyncReport report) async {
    final href = s.base?.href ?? s.local.href ?? '${s.local.uid}.ics';
    try {
      await _applyRemote(await client.getNote(href), report);
      return true;
    } on ICalException catch (e) {
      report.errors.add('${s.local.uid}: server copy cannot be read ($e)');
      return false;
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
    return true;
  }
}
