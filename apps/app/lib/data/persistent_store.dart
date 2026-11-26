import 'dart:convert';

import 'package:davdart/davdart.dart';

import 'key_value_storage.dart';

/// A [MemoryNoteStore] that saves itself to [storage] after every change and
/// loads what is there on creation. A damaged saved value is kept under
/// `<key>.unreadable` and the store starts empty rather than blocking the app.
/// A refused write throws [StorageWriteException] after the change is made.
class PersistentNoteStore extends MemoryNoteStore {
  PersistentNoteStore(this.storage, {this.key = 'davdart.space.v1'}) {
    final raw = storage.read(key);
    if (raw == null || raw.isEmpty) return;
    try {
      loadJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Keep the damaged value for recovery, then start empty.
      storage.write('$key.unreadable', raw);
      loadJson({'notes': <String, dynamic>{}, 'revisions': <dynamic>[]});
    }
  }

  final KeyValueStorage storage;
  final String key;

  @override
  void changed() => writeOrThrow(storage, key, jsonEncode(toJson()));
}
