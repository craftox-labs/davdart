import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;

import 'key_value_storage.dart';
import 'note_source.dart';
import 'persistent_store.dart';

class SpaceInfo {
  const SpaceInfo(this.id, this.name, {this.collection});
  final String id;
  final String name;

  /// The server collection (path under /dav/) of an account Space; null for
  /// a local Space.
  final String? collection;
  bool get onServer => collection != null;
}

/// Storage whose keys all start with [prefix].
class PrefixedStorage implements KeyValueStorage {
  PrefixedStorage(this.inner, this.prefix, {this.dead});
  final KeyValueStorage inner;
  final String prefix;

  /// When this returns true the storage ignores writes (its Space was
  /// deleted while a save or sync was still running).
  final bool Function()? dead;
  @override
  String? read(String key) => inner.read('$prefix$key');
  @override
  void write(String key, String value) {
    if (dead?.call() ?? false) return;
    inner.write('$prefix$key', value);
  }

  @override
  void remove(String key) => inner.remove('$prefix$key');
  @override
  Iterable<String> get keys => [
    for (final k in inner.keys)
      if (k.startsWith(prefix)) k.substring(prefix.length),
  ];
}

/// The Spaces on this device and which one is open. The first, `planning`,
/// keeps its original storage keys (and is seeded from the board feed once);
/// every other Space is local, empty to start, and has its own keys.
class SpaceCatalog {
  SpaceCatalog(
    this.storage, {
    this.planningSeed,
    this.davBase,
    this.httpClient,
  }) {
    _load();
    _loadAccount();
  }

  final KeyValueStorage storage;
  final NoteSource? planningSeed;
  final Uri? davBase;
  final http.Client? httpClient;

  static const planningId = 'planning';
  static const _accountKey = 'davdart.account.v1';

  /// The signed-in server account, if any. Its collections are the account
  /// Spaces; its password lives here once, not in every Space.
  Account? account;

  void _loadAccount() {
    try {
      final raw = storage.read(_accountKey);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      account = Account(j['user'] as String, j['password'] as String);
    } catch (_) {
      account = null;
    }
  }

  Uri get _davBase => davBase ?? Uri.base.resolve('/dav/');
  static const _listKey = 'davdart.spaces.v1';
  static const _currentKey = 'davdart.currentspace.v1';

  final List<SpaceInfo> spaces = [];
  final Set<String> _deleted = {};
  String current = planningId;

  void _load() {
    try {
      final raw = storage.read(_listKey);
      if (raw != null && raw.isNotEmpty) {
        for (final j in jsonDecode(raw) as List<dynamic>) {
          if (j is Map && j['id'] is String && j['name'] is String) {
            spaces.add(
              SpaceInfo(
                j['id'] as String,
                j['name'] as String,
                collection: j['collection'] is String
                    ? j['collection'] as String
                    : null,
              ),
            );
          }
        }
      }
    } catch (_) {
      // Keep the unreadable value for recovery instead of overwriting it.
      final raw = storage.read(_listKey);
      if (raw != null) storage.write('$_listKey.unreadable', raw);
      spaces.clear();
    }
    if (!spaces.any((s) => s.id == planningId)) {
      spaces.insert(0, const SpaceInfo(planningId, 'Planning'));
    }
    final c = storage.read(_currentKey);
    if (c != null && spaces.any((s) => s.id == c)) current = c;
  }

  void _save() {
    storage.write(
      _listKey,
      jsonEncode([
        for (final s in spaces)
          {
            'id': s.id,
            'name': s.name,
            if (s.collection != null) 'collection': s.collection,
          },
      ]),
    );
    storage.write(_currentKey, current);
  }

  SpaceInfo get currentInfo => spaces.firstWhere((s) => s.id == current);

  String _unique(String name) {
    var n = name.trim();
    final base = n;
    for (var i = 2; spaces.any((s) => s.name == n); i++) {
      n = '$base $i';
    }
    return n;
  }

  /// Adds a local Space named [name] and returns it.
  SpaceInfo add(String name) {
    final info = SpaceInfo(
      'sp-${DateTime.now().microsecondsSinceEpoch}',
      _unique(name),
    );
    spaces.add(info);
    _save();
    return info;
  }

  /// Checks the login, remembers it, and adds a Space for every note
  /// collection the user has that is not here yet. Returns how many were
  /// added. Throws, changing nothing, if the server refuses.
  Future<int> signIn(String user, String password) async {
    final cur = account;
    if (cur != null && cur.user != user) {
      throw StateError('Sign out of ${cur.user} first');
    }
    final found = await _discover(user, password);
    account = Account(user, password);
    storage.write(
      _accountKey,
      jsonEncode({'user': user, 'password': password}),
    );
    return _addFound(found);
  }

  /// Finds collections created elsewhere since sign-in.
  Future<int> refresh() async {
    final a = account;
    if (a == null) return 0;
    return _addFound(await _discover(a.user, a.password));
  }

  Future<List<FoundCollection>> _discover(String user, String password) async {
    final found = await CalDavClient.discover(
      _davBase.resolve('${Uri.encodeComponent(user)}/'),
      username: user,
      password: password,
      client: httpClient,
    );
    return [
      for (final c in found)
        if (c.holdsNotes) FoundCollection(c.name, davPath(_davBase, c.href)),
    ];
  }

  static String _norm(String p) {
    var n = p.replaceAll(RegExp('^/+'), '').replaceAll(RegExp('/+\$'), '');
    try {
      n = Uri.decodeFull(n); // 'a%20b' and 'a b' name the same collection
    } catch (_) {}
    return n;
  }

  KeyValueStorage _scoped(String id) =>
      id == planningId ? storage : PrefixedStorage(storage, 'sp.$id.');

  /// The collection path a local Space was connected to by hand, if any.
  String? _connectedPath(String id) {
    try {
      final raw = _scoped(id).read(SpaceNoteSource.loginKey);
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return j['path'] is String ? _norm(j['path'] as String) : null;
    } catch (_) {
      return null;
    }
  }

  /// The server's display name wins; a name another Space already uses stays.
  void _applyName(int i, String serverName) {
    final n = serverName.trim();
    final s = spaces[i];
    if (n.isEmpty || n == s.name) return;
    if (spaces.any((o) => o.id != s.id && o.name == n)) return;
    spaces[i] = SpaceInfo(s.id, n, collection: s.collection);
  }

  int _addFound(List<FoundCollection> found) {
    var added = 0;
    for (final f in found) {
      final id = 'srv-${Uri.encodeComponent(f.path)}';
      _deleted.remove(id); // a Space removed earlier may come back
      final have = spaces.indexWhere((s) => s.collection == f.path);
      if (have >= 0) {
        _applyName(have, f.name);
        continue;
      }
      // A local copy left by an earlier sign-out, or a Space connected to
      // this collection by hand: link it instead of adding a duplicate.
      var at = spaces.indexWhere((s) => s.id == id);
      if (at < 0) {
        at = spaces.indexWhere(
          (s) => s.collection == null && _connectedPath(s.id) == _norm(f.path),
        );
        if (at >= 0) _adoptLogin(spaces[at].id);
      }
      if (at >= 0) {
        spaces[at] = SpaceInfo(
          spaces[at].id,
          spaces[at].name,
          collection: f.path,
        );
        _applyName(at, f.name);
        added++;
        continue;
      }
      spaces.add(SpaceInfo(id, _unique(f.name), collection: f.path));
      added++;
    }
    _save();
    return added;
  }

  /// Rewrites a hand-made login so the Space uses the account's password.
  void _adoptLogin(String id) {
    final a = account;
    if (a == null) return;
    final own = _scoped(id);
    try {
      final j = jsonDecode(
        own.read(SpaceNoteSource.loginKey)!,
      ) as Map<String, dynamic>;
      own.write(
        SpaceNoteSource.loginKey,
        jsonEncode({'path': j['path'], 'user': a.user, 'account': true}),
      );
    } catch (_) {}
  }

  /// Renames Space [id]. For an account Space the server's display name is
  /// changed first, so other apps see it; null means done, else the reason.
  Future<String?> renameSpace(String id, String name) async {
    final n = name.trim();
    final i = spaces.indexWhere((s) => s.id == id);
    if (i < 0) return 'No such space';
    if (n.isEmpty) return 'Enter a name';
    if (spaces.any((s) => s.id != id && s.name == n)) {
      return 'Another space already has that name';
    }
    final a = account;
    final path = spaces[i].collection;
    if (path != null && a != null) {
      try {
        await CalDavClient.renameCollection(
          _davBase.resolve(path),
          n,
          username: a.user,
          password: a.password,
          client: httpClient,
        );
      } catch (e) {
        return 'Could not rename on the server: $e';
      }
    }
    // The list may have changed while the server answered.
    final j = spaces.indexWhere((s) => s.id == id);
    if (j < 0) return null;
    if (spaces.any((s) => s.id != id && s.name == n)) {
      return 'Another space took that name meanwhile';
    }
    spaces[j] = SpaceInfo(id, n, collection: spaces[j].collection);
    _save();
    return null;
  }

  /// Creates a new collection on the server and a Space for it.
  Future<SpaceInfo> addOnServer(String name) async {
    final a = account;
    if (a == null) throw StateError('Not signed in');
    final shown = _unique(name);
    final url = await CalDavClient.createCollection(
      _davBase.resolve('${Uri.encodeComponent(a.user)}/'),
      shown,
      username: a.user,
      password: a.password,
      client: httpClient,
    );
    final path = davPath(_davBase, url);
    final info = SpaceInfo(
      'srv-${Uri.encodeComponent(path)}',
      shown,
      collection: path,
    );
    _deleted.remove(info.id);
    spaces.add(info);
    _save();
    return info;
  }

  /// Signs out. Account Spaces stay on this device as local copies.
  void signOut() {
    account = null;
    storage.write(_accountKey, '');
    for (var i = 0; i < spaces.length; i++) {
      final s = spaces[i];
      if (s.collection == null) continue;
      spaces[i] = SpaceInfo(s.id, s.name);
      // It is a plain local copy now: forget the sync bases, so signing in
      // again merges by note id and never replays local deletes to the server.
      final own = _scoped(s.id);
      own.write(SpaceNoteSource.lastServerKey, '');
      own.write(SpaceNoteSource.loginKey, '');
    }
    _save();
  }

  /// Deletes a local Space and everything stored for it. The Planning Space
  /// cannot be deleted. If it was open, Planning opens instead.
  bool remove(String id) {
    if (id == planningId || !spaces.any((s) => s.id == id)) return false;
    _deleted.add(id);
    final scoped = PrefixedStorage(storage, 'sp.$id.'); // never Planning
    for (final k in scoped.keys.toList()) {
      scoped.remove(k);
    }
    spaces.removeWhere((s) => s.id == id);
    if (current == id) current = planningId;
    _save();
    return true;
  }

  void select(String id) {
    if (!spaces.any((s) => s.id == id)) return;
    current = id;
    _save();
  }

  /// The note source for Space [id].
  SpaceNoteSource sourceFor(String id) {
    final info = spaces.firstWhere((s) => s.id == id);
    final scoped = id == planningId
        ? storage
        : PrefixedStorage(
            storage,
            'sp.$id.',
            dead: () => _deleted.contains(id),
          );
    return SpaceNoteSource(
      Space(SpaceConfig(id: id, name: info.name), PersistentNoteStore(scoped)),
      seed: id == planningId ? planningSeed : null,
      account: info.onServer ? account : null,
      pendingPath: info.collection,
      flags: scoped,
      davBase: davBase,
      httpClient: httpClient,
    );
  }
}
