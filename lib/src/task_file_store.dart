import 'dart:convert';
import 'dart:io';

import 'task_store.dart';

/// A [MemoryTaskStore] saved to one JSON file after every change (written to a
/// temporary file first, then renamed). Not available on the web; use
/// [MemoryTaskStore.toJson] with browser storage there.
class FileTaskStore extends MemoryTaskStore {
  FileTaskStore._(this.path);
  final String path;

  static Future<FileTaskStore> open(String path) async {
    final store = FileTaskStore._(path);
    final f = File(path);
    if (f.existsSync()) {
      try {
        store.loadJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        );
      } on FormatException {
        // Truncated or damaged: keep it for inspection and start over, so the
        // next sync repopulates from the server.
        f.renameSync('$path.corrupt-${DateTime.now().millisecondsSinceEpoch}');
        return FileTaskStore._(path);
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
