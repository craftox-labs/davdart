/// A tiny string store the app can keep its Space in. The browser build uses
/// localStorage; tests and other platforms use memory.
abstract class KeyValueStorage {
  String? read(String key);
  void write(String key, String value);
}

class MemoryStorage implements KeyValueStorage {
  final Map<String, String> data = {};
  @override
  String? read(String key) => data[key];
  @override
  void write(String key, String value) => data[key] = value;
}
