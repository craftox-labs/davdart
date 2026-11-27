import 'dart:convert';
import 'dart:io';

import 'caldav.dart';
import 'file_store.dart';
import 'space.dart';

/// The list of Spaces on this device, saved as `spaces.json` in [dir], with
/// each Space's notes in its own file beside it.
class SpaceBook {
  SpaceBook._(this.dir, this._configs);
  final String dir;
  final List<SpaceConfig> _configs;

  static Future<SpaceBook> open(String dir) async {
    final f = File('$dir/spaces.json');
    final configs = <SpaceConfig>[];
    if (f.existsSync()) {
      for (final j in jsonDecode(await f.readAsString()) as List<dynamic>) {
        configs.add(SpaceConfig.fromJson(j as Map<String, dynamic>));
      }
    }
    return SpaceBook._(dir, configs);
  }

  List<SpaceConfig> get configs => List.unmodifiable(_configs);

  void _save() {
    Directory(dir).createSync(recursive: true);
    final tmp = File('$dir/spaces.json.$pid.tmp')
      ..writeAsStringSync(jsonEncode([for (final c in _configs) c.toJson()]));
    tmp.renameSync('$dir/spaces.json');
  }

  /// Creates a local-only Space.
  Future<Space> createLocal(String name) async {
    final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
    final config = SpaceConfig(id: id, name: name);
    _configs.add(config);
    _save();
    return Space(config, await FileNoteStore.open('$dir/$id.json'))
      ..onConfigChanged = _save;
  }

  /// Opens a saved Space. Pass [password] to reconnect one that has a server.
  Future<Space> open_(String id, {String? password}) async {
    final c = _configs.firstWhere((c) => c.id == id);
    final store = await FileNoteStore.open('$dir/$id.json');
    CalDavClient? client;
    if (c.hasServer && password != null) {
      client = CalDavClient(
        collection: Uri.parse(c.url!),
        username: c.user ?? '',
        password: password,
      );
    }
    return Space(c, store, client: client)..onConfigChanged = _save;
  }

  /// Removes a Space and its notes from this device. Server content stays.
  Future<void> remove(String id) async {
    _configs.removeWhere((c) => c.id == id);
    _save();
    final f = File('$dir/$id.json');
    if (f.existsSync()) f.deleteSync();
  }
}
