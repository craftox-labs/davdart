import 'dart:convert';

import 'package:davdart/davdart.dart';

import 'key_value_storage.dart';

/// A [MemoryEventStore] that saves itself to [storage] after every change and
/// loads what is there on creation. A damaged saved value is kept under
/// `<key>.unreadable` for recovery and the store starts empty, so events never
/// block the app (or the notes and tasks).
class PersistentEventStore extends MemoryEventStore {
  PersistentEventStore(this.storage, {this.key = 'events.v1'}) {
    final raw = storage.read(key);
    if (raw == null || raw.isEmpty) return;
    try {
      loadJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      storage.write('$key.unreadable', raw);
      loadJson({'events': <String, dynamic>{}, 'revisions': <dynamic>[]});
    }
  }

  final KeyValueStorage storage;
  final String key;

  @override
  void changed() => writeOrThrow(storage, key, jsonEncode(toJson()));
}
