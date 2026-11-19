/// A tiny string store the app can keep its Space in. The browser build uses
/// localStorage; tests and other platforms use memory.
abstract class KeyValueStorage {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);

  /// Every key currently stored.
  Iterable<String> get keys;
}

class MemoryStorage implements KeyValueStorage {
  final Map<String, String> data = {};
  @override
  String? read(String key) => data[key];
  @override
  void write(String key, String value) => data[key] = value;
  @override
  void remove(String key) => data.remove(key);
  @override
  Iterable<String> get keys => data.keys.toList();
}
