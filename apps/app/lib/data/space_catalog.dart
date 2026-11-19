import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;

import 'key_value_storage.dart';
import 'note_source.dart';
import 'persistent_store.dart';

class SpaceInfo {
  const SpaceInfo(this.id, this.name);
  final String id;
  final String name;
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
  }

  final KeyValueStorage storage;
  final NoteSource? planningSeed;
  final Uri? davBase;
  final http.Client? httpClient;

  static const planningId = 'planning';
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
            spaces.add(SpaceInfo(j['id'] as String, j['name'] as String));
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
        for (final s in spaces) {'id': s.id, 'name': s.name},
      ]),
    );
    storage.write(_currentKey, current);
  }

  SpaceInfo get currentInfo => spaces.firstWhere((s) => s.id == current);

  /// Adds a local Space named [name] and returns it.
  SpaceInfo add(String name) {
    var n = name.trim();
    final base = n;
    for (var i = 2; spaces.any((s) => s.name == n); i++) {
      n = '$base $i';
    }
    final info = SpaceInfo('sp-${DateTime.now().microsecondsSinceEpoch}', n);
    spaces.add(info);
    _save();
    return info;
  }

  /// Renames Space [id]; blank or already-used names are refused (false).
  bool rename(String id, String name) {
    final n = name.trim();
    final i = spaces.indexWhere((s) => s.id == id);
    if (i < 0 || n.isEmpty) return false;
    if (spaces.any((s) => s.id != id && s.name == n)) return false;
    spaces[i] = SpaceInfo(id, n);
    _save();
    return true;
  }

  /// Deletes a local Space and everything stored for it. The Planning Space
  /// cannot be deleted. If it was open, Planning opens instead.
  bool remove(String id) {
    if (id == planningId || !spaces.any((s) => s.id == id)) return false;
    _deleted.add(id);
    final scoped = PrefixedStorage(storage, 'sp.$id.');
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
      flags: scoped,
      davBase: davBase,
      httpClient: httpClient,
    );
  }
}
