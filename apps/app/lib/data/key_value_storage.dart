/// A tiny string store the app can keep its Space in. The browser build uses
/// localStorage; tests and other platforms use memory.
abstract class KeyValueStorage {
  String? read(String key);

  /// Stores [value]; false when the store refused it (full or blocked).
  bool write(String key, String value);
  void remove(String key);

  /// Every key currently stored.
  Iterable<String> get keys;
}

/// Thrown by a persistent store when its write was refused, so the edit is
/// kept for this session only and would be gone on reload.
class StorageWriteException implements Exception {
  const StorageWriteException(this.key);
  final String key;
  @override
  String toString() =>
      'Not saved: browser storage is full or blocked, so this change will be '
      'lost on reload';
}

/// Writes [value] to [storage] or throws [StorageWriteException].
void writeOrThrow(KeyValueStorage storage, String key, String value) {
  if (!storage.write(key, value)) throw StorageWriteException(key);
}

class MemoryStorage implements KeyValueStorage {
  final Map<String, String> data = {};
  @override
  String? read(String key) => data[key];
  @override
  bool write(String key, String value) {
    data[key] = value;
    return true;
  }

  @override
  void remove(String key) => data.remove(key);
  @override
  Iterable<String> get keys => data.keys.toList();
}
