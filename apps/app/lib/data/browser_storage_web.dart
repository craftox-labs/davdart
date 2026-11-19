import 'package:web/web.dart' as web;

import 'key_value_storage.dart';

class BrowserStorage implements KeyValueStorage {
  @override
  String? read(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null; // storage blocked: start empty
    }
  }

  @override
  void write(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {
      // Blocked or full: the session keeps working, edits just are not saved.
    }
  }

  @override
  void remove(String key) {
    try {
      web.window.localStorage.removeItem(key);
    } catch (_) {}
  }

  @override
  Iterable<String> get keys {
    try {
      final s = web.window.localStorage;
      return [
        for (var i = 0; i < s.length; i++)
          if (s.key(i) != null) s.key(i)!,
      ];
    } catch (_) {
      return const [];
    }
  }
}

KeyValueStorage defaultStorage() => BrowserStorage();
