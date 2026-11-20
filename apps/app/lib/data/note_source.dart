import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;

import 'key_value_storage.dart';

/// Where the app gets notes from. The dev build reads the board server's
/// read-only feed; the real app will read a local Space.
abstract class NoteSource {
  Future<List<Note>> load();
}

/// Notes from the JSON feed at `/api/notes` on the same origin.
class ApiNoteSource implements NoteSource {
  ApiNoteSource({Uri? url, http.Client? client})
    : url = url ?? Uri.base.resolve('/api/notes'),
      _client = client ?? http.Client();

  final Uri url;
  final http.Client _client;

  @override
  Future<List<Note>> load() async {
    final r = await _client.get(url);
    if (r.statusCode != 200) {
      throw Exception('Notes feed answered ${r.statusCode}');
    }
    return parseNotesJson(utf8.decode(r.bodyBytes));
  }
}

/// Reads the feed, skipping entries that are not usable (no uid, bad date)
/// instead of failing the whole load.
List<Note> parseNotesJson(String body) {
  DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;
  final out = <Note>[];
  final seen = <String>{};
  for (final j in jsonDecode(body) as List<dynamic>) {
    if (j is! Map<String, dynamic>) continue;
    final uid = j['uid'];
    if (uid is! String || uid.isEmpty || !seen.add(uid)) continue;
    out.add(
      Note(
        uid: uid,
        summary: (j['title'] as String?) ?? '',
        description: (j['body'] as String?) ?? '',
        categories: [for (final t in (j['tags'] as List<dynamic>? ?? [])) '$t'],
        status: j['status'] as String?,
        parentUid: j['parent'] as String?,
        created: date(j['created']),
        lastModified: date(j['modified']),
      ),
    );
  }
  return out;
}

/// The source of an app with no Space open: no notes, read-only.
class EmptyNoteSource implements NoteSource {
  const EmptyNoteSource();
  @override
  Future<List<Note>> load() async => const [];
}

/// A source the app can also write to.
abstract class EditableNoteSource implements NoteSource {
  Future<Note> save(Note note);
  Future<void> delete(String uid);
}

/// Notes held in a local [Space]. Edits go through the Space (and so the sync
/// engine), never to the network, until a server is connected. The first time
/// the Space is empty and a [seed] source is given, its notes are copied in
/// once; [flags] remembers that (and the server login) across restarts, so
/// deleting every note does not bring the seed back.
/// The server login shared by every account Space on this device.
class Account {
  const Account(this.user, this.password);
  final String user;
  final String password;
}

/// [href] as a path relative to the proxy root [base], the form
/// [SpaceNoteSource.connect] accepts.
String davPath(Uri base, Uri href) => href.path.startsWith(base.path)
    ? href.path.substring(base.path.length)
    : href.path.replaceFirst(RegExp('^/+'), '');

/// A collection offered in the Connect dialog.
class FoundCollection {
  const FoundCollection(
    this.name,
    this.path, {
    this.notes = true,
    this.tasks = true,
    this.events = true,
  });
  final String name;
  final String path;

  /// Which components (VJOURNAL, VTODO, VEVENT) the server collection takes.
  final bool notes, tasks, events;
}

class SpaceNoteSource implements EditableNoteSource {
  SpaceNoteSource(
    this.space, {
    this.seed,
    this.flags,
    Uri? davBase,
    this.httpClient,
    this.account,
    this.pendingPath,
    TaskStore? taskStore,
    EventStore? eventStore,
  }) : davBase = davBase ?? Uri.base.resolve('/dav/'),
       taskStore = taskStore ?? MemoryTaskStore(),
       eventStore = eventStore ?? MemoryEventStore() {
    final saved = flags?.read(loginKey);
    if (saved != null && saved.isNotEmpty) {
      try {
        final j = jsonDecode(saved) as Map<String, dynamic>;
        // An account Space keeps no password of its own: it borrows the
        // account's, and goes back to local when that is signed out.
        final pw = j['account'] == true
            ? account!.password
            : j['password'] as String;
        final user = j['account'] == true ? account!.user : j['user'] as String;
        _login = (j['path'] as String, user);
        final client = _clientFor(j['path'] as String, user, pw);
        space.connectExisting(client);
        _useTaskClient(client);
        _useEventClient(client);
      } catch (_) {
        flags?.write(loginKey, '');
      }
    }
  }

  final Space space;

  /// The Space's tasks (VTODO in the same collection as its notes).
  final TaskStore taskStore;
  TaskSyncEngine? _taskEngine;
  CalDavClient? _taskClient;

  void _useTaskClient(CalDavClient? c) {
    _taskClient = c;
    _taskEngine = null;
  }

  // Local edits never touch the network, so the offline engine's client is
  // a placeholder (same as Space does for notes).
  TaskSyncEngine get _tasks => _taskEngine ??= TaskSyncEngine(
    _taskClient ??
        CalDavClient(
          collection: Uri.parse('http://localhost/'),
          username: '',
          password: '',
        ),
    taskStore,
  );

  Future<List<Task>> loadTasks() => _tasks.tasks();
  Future<Task> saveTask(Task t) => _tasks.save(t);
  Future<void> deleteTask(String uid) => _tasks.delete(uid);

  /// Syncs the tasks with the server; null for a local Space. Independent of
  /// the notes' [sync]: callers run both and treat a task failure as
  /// non-fatal.
  Future<SyncReport?> syncTasks() async {
    if (_taskClient == null) return null;
    return _tasks.sync();
  }

  Future<List<Revision>> taskRevisions(String uid) => taskStore.revisions(uid);

  // Writes only when there is something to clear, so a Space without tasks
  // never gets a tasks key.
  Future<void> _clearTaskToken() async {
    if (await taskStore.getSyncToken() != null) {
      await taskStore.setSyncToken(null);
    }
  }

  /// Like [Space.attach] for tasks: every task counts as not yet on the
  /// server, so the first sync sends them and merges by UID.
  Future<void> _attachTasks() async {
    for (final s in await taskStore.all()) {
      s.base = null;
      s.local.href = null;
      s.local.etag = null;
      s.dirty = !s.deleted;
      if (s.deleted) {
        await taskStore.remove(s.local.uid);
      } else {
        await taskStore.put(s.local.uid, s);
      }
    }
    await _clearTaskToken();
  }

  /// The Space's events (VEVENT in the same collection as its notes).
  final EventStore eventStore;
  EventSyncEngine? _eventEngine;
  CalDavClient? _eventClient;

  void _useEventClient(CalDavClient? c) {
    _eventClient = c;
    _eventEngine = null;
  }

  EventSyncEngine get _events => _eventEngine ??= EventSyncEngine(
    _eventClient ??
        CalDavClient(
          collection: Uri.parse('http://localhost/'),
          username: '',
          password: '',
        ),
    eventStore,
  );

  Future<List<Event>> loadEvents() => _events.events();
  Future<Event> saveEvent(Event e) => _events.save(e);
  Future<void> deleteEvent(String uid) => _events.delete(uid);

  /// Syncs the events with the server; null for a local Space. Independent of
  /// the notes' and tasks' sync: a failure here is non-fatal for them.
  Future<SyncReport?> syncEvents() async {
    if (_eventClient == null) return null;
    return _events.sync();
  }

  Future<List<Revision>> eventRevisions(String uid) =>
      eventStore.revisions(uid);

  Future<void> _clearEventToken() async {
    if (await eventStore.getSyncToken() != null) {
      await eventStore.setSyncToken(null);
    }
  }

  /// Like [Space.attach] for events: every event counts as not yet on the
  /// server, so the first sync sends them and merges by UID.
  Future<void> _attachEvents() async {
    for (final s in await eventStore.all()) {
      s.base = null;
      s.local.href = null;
      s.local.etag = null;
      s.dirty = !s.deleted;
      if (s.deleted) {
        await eventStore.remove(s.local.uid);
      } else {
        await eventStore.put(s.local.uid, s);
      }
    }
    await _clearEventToken();
  }

  /// Set for a Space that belongs to the signed-in account.
  final Account? account;

  /// The collection an account Space syncs with, before its first connect.
  final String? pendingPath;
  final NoteSource? seed;
  final KeyValueStorage? flags;

  /// For tests: the HTTP client the server connection uses.
  final http.Client? httpClient;

  /// Where the board server's `/dav/` proxy lives (same origin as the app).
  final Uri davBase;
  bool _seeded = false;
  (String, String)? _login;

  static const _seededKey = 'davdart.seeded.v1';
  static const loginKey = 'davdart.server.v1';
  static const lastServerKey = 'davdart.lastserver.v1';

  bool get connected => _login != null;

  /// An account Space that has not synced yet and must attach first.
  bool get needsFirstConnect =>
      _login == null && account != null && pendingPath != null;

  Future<void> connectAccount() =>
      connect(pendingPath!, account!.user, account!.password, viaAccount: true);

  /// The server collection path and user, when connected.
  String? get serverLabel =>
      _login == null ? null : '${_login!.$2} @ ${_login!.$1}';

  CalDavClient _clientFor(String path, String user, String password) =>
      CalDavClient(
        collection: davBase.resolve(path.replaceFirst(RegExp('^/+'), '')),
        username: user,
        password: password,
        client: httpClient,
      );

  /// Collections the login can see, by name, as paths [connect] accepts.
  Future<List<FoundCollection>> discover(String user, String password) async {
    final found = await CalDavClient.discover(
      davBase.resolve('${Uri.encodeComponent(user)}/'),
      username: user,
      password: password,
      client: httpClient,
    );
    return [
      for (final c in found)
        if (c.holdsNotes || c.holdsTasks || c.holdsEvents)
          FoundCollection(
            c.name,
            davPath(davBase, c.href),
            notes: c.holdsNotes,
            tasks: c.holdsTasks,
            events: c.holdsEvents,
          ),
    ];
  }

  /// Checks the login against the server, then attaches this Space to it.
  /// Throws (and changes nothing) if the server refuses.
  ///
  /// With [replaceLocal] the local notes are dropped first, so the Space
  /// becomes a copy of the server's (nothing local is sent).
  Future<void> connect(
    String path,
    String user,
    String password, {
    bool replaceLocal = false,
    bool viaAccount = false,
  }) async {
    final client = _clientFor(path, user, password);
    await client.listNotes();
    if (replaceLocal) {
      for (final n in await space.store.all()) {
        await space.store.remove(n.local.uid);
      }
      for (final t in await taskStore.all()) {
        await taskStore.remove(t.local.uid);
      }
      await _clearTaskToken();
      for (final e in await eventStore.all()) {
        await eventStore.remove(e.local.uid);
      }
      await _clearEventToken();
      _markSeeded();
    }
    // Reconnecting to the collection this Space last synced with keeps the
    // sync bases, so notes deleted on the server meanwhile are removed here
    // instead of being sent back, and edits made while offline merge normally.
    final same =
        !replaceLocal &&
        flags?.read(lastServerKey) == client.collection.toString();
    if (same) {
      space.connectExisting(client);
    } else {
      await space.attach(client);
      await _attachTasks();
      await _attachEvents();
    }
    _useTaskClient(client);
    _useEventClient(client);
    flags?.write(lastServerKey, client.collection.toString());
    _login = (path, user);
    flags?.write(
      loginKey,
      jsonEncode(
        viaAccount
            ? {'path': path, 'user': user, 'account': true}
            : {'path': path, 'user': user, 'password': password},
      ),
    );
  }

  Future<void> disconnect() async {
    await space.detach();
    _useTaskClient(null);
    await _clearTaskToken();
    _useEventClient(null);
    await _clearEventToken();
    _login = null;
    flags?.write(loginKey, '');
  }

  Future<SyncReport?> sync() => space.sync();

  bool get _wasSeeded => _seeded || flags?.read(_seededKey) == '1';

  void _markSeeded() {
    _seeded = true;
    flags?.write(_seededKey, '1');
  }

  @override
  Future<List<Note>> load() async {
    var notes = await space.notes();
    if (notes.isNotEmpty) {
      _markSeeded();
    } else if (seed != null && !_wasSeeded) {
      for (final n in await seed!.load()) {
        await space.save(n);
      }
      _markSeeded();
      notes = await space.notes();
    }
    return notes;
  }

  @override
  Future<Note> save(Note note) => space.save(note);

  @override
  Future<void> delete(String uid) => space.delete(uid);

  /// How many notes have local changes the server has not received yet
  /// (0 when not connected: a local Space has no server copy to lag behind).
  Future<int> unsyncedCount() async {
    if (!connected) return 0;
    var n = 0;
    for (final e in await space.store.all()) {
      if (e.dirty || e.deleted) n++;
    }
    for (final e in await taskStore.all()) {
      if (e.dirty || e.deleted) n++;
    }
    for (final e in await eventStore.all()) {
      if (e.dirty || e.deleted) n++;
    }
    return n;
  }

  /// Earlier versions kept when a sync merge had to pick a winner.
  Future<List<Revision>> revisions(String uid) => space.store.revisions(uid);
}
