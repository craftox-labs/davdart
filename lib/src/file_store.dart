import 'dart:convert';
import 'dart:io';

import 'store.dart';

/// A [MemoryNoteStore] saved to one JSON file after every change (written to a
/// temporary file first, then renamed). Not available on the web; use
/// [MemoryNoteStore.toJson] with browser storage there.
class FileNoteStore extends MemoryNoteStore {
  FileNoteStore._(this.path);
  final String path;

  static Future<FileNoteStore> open(String path) async {
    final store = FileNoteStore._(path);
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
        return FileNoteStore._(path);
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
