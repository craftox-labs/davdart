import 'dart:convert';
import 'dart:io';

import 'event_store.dart';

/// A [MemoryEventStore] saved to one JSON file after every change (written to a
/// temporary file first, then renamed). Not available on the web; use
/// [MemoryEventStore.toJson] with browser storage there.
class FileEventStore extends MemoryEventStore {
  FileEventStore._(this.path);
  final String path;

  static Future<FileEventStore> open(String path) async {
    final store = FileEventStore._(path);
    final f = File(path);
    if (f.existsSync()) {
      try {
        store.loadJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      } on FormatException {
        // Truncated or damaged: keep it for inspection and start over, so the
        // next sync repopulates from the server.
        f.renameSync('$path.corrupt-${DateTime.now().millisecondsSinceEpoch}');
        return FileEventStore._(path);
      }
    }
    return store;
  }

  @override
  void changed() {
    final tmp = File('$path.$pid.tmp');
    tmp.parent.createSync(recursive: true);
    tmp.writeAsStringSync(jsonEncode(toJson()));
    tmp.renameSync(path);
  }
}
