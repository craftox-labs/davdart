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
class SpaceNoteSource implements EditableNoteSource {
  SpaceNoteSource(
    this.space, {
    this.seed,
    this.flags,
    Uri? davBase,
    this.httpClient,
  }) : davBase = davBase ?? Uri.base.resolve('/dav/') {
    final saved = flags?.read(_loginKey);
    if (saved != null && saved.isNotEmpty) {
      try {
        final j = jsonDecode(saved) as Map<String, dynamic>;
        _login = (j['path'] as String, j['user'] as String);
        space.connectExisting(
          _clientFor(
            j['path'] as String,
            j['user'] as String,
            j['password'] as String,
          ),
        );
      } catch (_) {
        flags?.write(_loginKey, '');
      }
    }
  }

  final Space space;
  final NoteSource? seed;
  final KeyValueStorage? flags;

  /// For tests: the HTTP client the server connection uses.
  final http.Client? httpClient;

  /// Where the board server's `/dav/` proxy lives (same origin as the app).
  final Uri davBase;
  bool _seeded = false;
  (String, String)? _login;

  static const _seededKey = 'davdart.seeded.v1';
  static const _loginKey = 'davdart.server.v1';

  bool get connected => _login != null;

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

  /// Checks the login against the server, then attaches this Space to it.
  /// Throws (and changes nothing) if the server refuses.
  Future<void> connect(String path, String user, String password) async {
    final client = _clientFor(path, user, password);
    await client.listNotes();
    await space.attach(client);
    _login = (path, user);
    flags?.write(
      _loginKey,
      jsonEncode({'path': path, 'user': user, 'password': password}),
    );
  }

  Future<void> disconnect() async {
    await space.detach();
    _login = null;
    flags?.write(_loginKey, '');
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
}
