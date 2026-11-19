import 'dart:convert';

import 'package:davdart/davdart.dart';

import 'key_value_storage.dart';

/// A [MemoryNoteStore] that saves itself to [storage] after every change and
/// loads what is there on creation. A damaged saved value is ignored (the
/// store starts empty) rather than blocking the app.
class PersistentNoteStore extends MemoryNoteStore {
  PersistentNoteStore(this.storage, {this.key = 'davdart.space.v1'}) {
    final raw = storage.read(key);
    if (raw == null) return;
    try {
      loadJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Start empty; the next change overwrites the damaged value.
      loadJson({'notes': <String, dynamic>{}, 'revisions': <dynamic>[]});
    }
  }

  final KeyValueStorage storage;
  final String key;

  @override
  void changed() => storage.write(key, jsonEncode(toJson()));
}
