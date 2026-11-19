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
  PrefixedStorage(this.inner, this.prefix);
  final KeyValueStorage inner;
  final String prefix;
  @override
  String? read(String key) => inner.read('$prefix$key');
  @override
  void write(String key, String value) => inner.write('$prefix$key', value);
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
        : PrefixedStorage(storage, 'sp.$id.');
    return SpaceNoteSource(
      Space(SpaceConfig(id: id, name: info.name), PersistentNoteStore(scoped)),
      seed: id == planningId ? planningSeed : null,
      flags: scoped,
      davBase: davBase,
      httpClient: httpClient,
    );
  }
}
