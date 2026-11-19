import 'dart:convert';
import 'dart:io';

import 'caldav.dart';
import 'note.dart';
import 'store.dart';
import 'sync_engine.dart';

/// What a Space is, saved to disk without any password.
class SpaceConfig {
  SpaceConfig({required this.id, required this.name, this.url, this.user});

  final String id;
  String name;

  /// CalDAV collection URL, or null for a local-only Space.
  String? url;
  String? user;

  bool get hasServer => url != null;

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'url': url, 'user': user};

  factory SpaceConfig.fromJson(Map<String, dynamic> j) => SpaceConfig(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String?,
        user: j['user'] as String?,
      );
}

/// One body of notes: a project, an inbox. Always usable offline; a server is
/// optional and can be attached or detached at any time.
class Space {
  Space(this.config, this.store,
      {CalDavClient? client, DateTime Function()? now})
      : _client = client,
        _now = now;

  final SpaceConfig config;
  final NoteStore store;
  CalDavClient? _client;
  final DateTime Function()? _now;
  SyncEngine? _engine;

  /// Set by [SpaceBook] so attach and detach are saved to disk.
  void Function()? onConfigChanged;

  SyncEngine get _sync => _engine ??= SyncEngine(_client!, store, now: _now);

  bool get isLocalOnly => _client == null;

  /// The Space has a server saved but no login in this session.
  bool get needsPassword => config.hasServer && _client == null;

  SyncEngine get _local => SyncEngine(
        // Local edits never touch the network; a throwaway client is not
        // needed because save/delete/notes only use the store.
        CalDavClient(
            collection: Uri.parse('http://localhost/'),
            username: '',
            password: ''),
        store,
        now: _now,
      );

  Future<List<Note>> notes() => (_engine ?? _local).notes();
  Future<Note> save(Note n) => (_engine ?? _local).save(n);
  Future<void> delete(String uid) => (_engine ?? _local).delete(uid);

  /// Syncs with the attached server. Local-only Spaces have nothing to do.
  Future<SyncReport?> sync() async {
    if (needsPassword) {
      throw StateError('${config.name} has a server but no login yet');
    }
    return isLocalOnly ? null : _sync.sync();
  }

  /// Connects this Space to a CalDAV collection. Every note here counts as not
  /// yet on the server, so the first [sync] sends them all and merges with
  /// whatever the server already holds, matching notes by UID.
  Future<void> attach(CalDavClient client, {String? url, String? user}) async {
    _client = client;
    _engine = null;
    config
      ..url = url ?? client.collection.toString()
      ..user = user ?? client.username;
    for (final s in await store.all()) {
      s.base = null;
      s.local.href = null;
      s.local.etag = null;
      s.dirty = !s.deleted;
      if (s.deleted) {
        await store.remove(s.local.uid);
      } else {
        await store.put(s.local.uid, s);
      }
    }
    await store.setSyncToken(null);
    onConfigChanged?.call();
  }

  /// Disconnects from the server and keeps every note locally.
  Future<void> detach() async {
    _client = null;
    _engine = null;
    config
      ..url = null
      ..user = null;
    await store.setSyncToken(null);
    onConfigChanged?.call();
  }
}

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
          password: password);
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
