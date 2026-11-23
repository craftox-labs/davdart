import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'caldav.dart';
import 'collection_backup_stub.dart'
    if (dart.library.io) 'collection_backup_io.dart';
import 'ical.dart';

/// Stores a backup: [files] maps each .ics file name to its text, [dir] is
/// the target folder. The default writes to disk (not available on web).
/// Writes the backup files; returns how many it wrote, or null when it
/// cannot tell (a browser download).
typedef BackupWriter = int? Function(String dir, Map<String, String> files);

/// A refused collection operation (wrong confirmation, not empty, unknown).
class CollectionSafetyException implements Exception {
  CollectionSafetyException(this.message);
  final String message;
  @override
  String toString() => 'CollectionSafetyException: $message';
}

/// What a server was seen to support for one collection. A null value means
/// "could not be determined"; the reason is in [undetermined].
class CollectionCapabilities {
  CollectionCapabilities({
    this.syncCollection,
    this.ctag,
    this.mkcalendar,
    this.proppatch,
    this.components,
    this.vjournal,
    this.vtodo,
    this.vevent,
    this.davClasses = const [],
    this.undetermined = const {},
  });

  /// RFC 6578 sync-collection listed in supported-report-set.
  final bool? syncCollection;

  /// A getctag or sync-token property exists, so change detection can fall
  /// back to it when sync-collection is absent.
  final bool? ctag;

  /// MKCALENDAR / PROPPATCH advertised in the Allow header of the collection.
  final bool? mkcalendar;
  final bool? proppatch;

  /// supported-calendar-component-set (for example VJOURNAL, VTODO, VEVENT);
  /// null when the server does not say (then all are assumed).
  final List<String>? components;
  final bool? vjournal;
  final bool? vtodo;
  final bool? vevent;
  final List<String> davClasses;

  /// Capability name to the reason it could not be determined.
  final Map<String, String> undetermined;

  Map<String, Object?> toJson() => {
        'syncCollection': syncCollection,
        'ctag': ctag,
        'mkcalendar': mkcalendar,
        'proppatch': proppatch,
        'components': components,
        'vjournal': vjournal,
        'vtodo': vtodo,
        'vevent': vevent,
        'dav': davClasses,
        'undetermined': undetermined,
      };
}

/// Outcome of a collection write. With [dryRun] nothing was changed.
class CollectionChange {
  const CollectionChange(this.action, this.dryRun, this.changes,
      {this.href, this.backupPath, this.itemCount});
  final String action;
  final bool dryRun;
  final List<String> changes;
  final Uri? href;

  /// Directory the ICS snapshot was (or would be) written to, for delete.
  final String? backupPath;
  final int? itemCount;
  Map<String, Object?> toJson() => {
        'action': action,
        'dryRun': dryRun,
        'changes': changes,
        if (href != null) 'href': href.toString(),
        if (backupPath != null) 'backup': backupPath,
        if (itemCount != null) 'items': itemCount,
      };
}

/// Collection management under one calendar home: list, create, rename,
/// delete (with the safety rules), and a capability probe. Safety lives here
/// so every front-end gets it.
class CollectionService {
  CollectionService({
    required Uri home,
    required this.username,
    required this.password,
    this.httpClient,
    DateTime Function()? now,
  })  : home = home.path.endsWith('/')
            ? home
            : home.replace(path: '${home.path}/'),
        _now = now ?? DateTime.now;

  final Uri home;
  final String username;
  final String password;
  final http.Client? httpClient;
  final DateTime Function() _now;

  CalDavClient _client(Uri collection) => CalDavClient(
      collection: collection,
      username: username,
      password: password,
      client: httpClient);

  Future<List<CollectionInfo>> list() => CalDavClient.discover(home,
      username: username, password: password, client: httpClient);

  Future<CollectionInfo> _info(Uri href) async {
    final h =
        href.path.endsWith('/') ? href : href.replace(path: '${href.path}/');
    final all = await list();
    final hit = all.where((c) => c.href.path == h.path).firstOrNull;
    if (hit == null) {
      throw CollectionSafetyException('no collection at ${h.path}');
    }
    return hit;
  }

  /// Creates a collection named [name]; returns its URL in the result.
  Future<CollectionChange> create(String name,
      {List<String> components = const ['VJOURNAL', 'VTODO', 'VEVENT'],
      bool dryRun = false}) async {
    if (name.trim().isEmpty) {
      throw CollectionSafetyException('collection name is empty');
    }
    final desc = ['create collection "$name" (${components.join(', ')})'];
    if (dryRun) return CollectionChange('create', true, desc);
    final url = await CalDavClient.createCollection(home, name,
        username: username,
        password: password,
        client: httpClient,
        components: components);
    return CollectionChange('create', false, desc, href: url);
  }

  /// Renames (display name) the collection at [href].
  Future<CollectionChange> rename(Uri href, String name,
      {bool dryRun = false}) async {
    if (name.trim().isEmpty) {
      throw CollectionSafetyException('collection name is empty');
    }
    final info = await _info(href);
    final desc = ['rename "${info.name}" -> "$name"'];
    if (!dryRun) {
      await CalDavClient.renameCollection(info.href, name,
          username: username, password: password, client: httpClient);
    }
    return CollectionChange('rename', dryRun, desc, href: info.href);
  }

  /// Deletes the collection at [href]. Refused unless [confirmName] equals
  /// the collection's name exactly, and unless it is empty or
  /// [allowNonEmpty] is set. Before deleting, every resource is written as an
  /// .ics file into a new folder under [backupDir]; its path is returned.
  /// Resources that cannot be read as notes, tasks or events (parse failure,
  /// no calendar-data, anything listed but not returned as an item) abort the
  /// delete unless [allowUnreadable] is set; then their raw bodies are backed
  /// up too. The delete is also aborted when the collection's resources
  /// changed between the backup and the DELETE. A dry run reports the same
  /// plan (and the same refusals) without writing or deleting anything.
  Future<CollectionChange> delete(
    Uri href, {
    required String confirmName,
    required String backupDir,
    bool allowNonEmpty = false,
    bool allowUnreadable = false,
    bool dryRun = false,
    BackupWriter? backupWriter,
  }) async {
    final info = await _info(href);
    if (confirmName != info.name) {
      throw CollectionSafetyException(
          'confirmation "$confirmName" does not match the collection name '
          '"${info.name}"');
    }
    final errors = <String?>[];
    final c = CalDavClient(
        collection: info.href,
        username: username,
        password: password,
        client: httpClient,
        onResourceError: (h, _) => errors.add(h));
    try {
      final raw = await c.listRaw();
      final notes = await c.listNotes();
      final tasks = await c.listTasks();
      final events = await c.listEvents();
      // Every item with the raw body it came from (null href: no raw body).
      final items = <(String? href, String uid, String Function() text)>[
        for (final n in notes) (n.href, n.uid, () => serializeNote(n)),
        for (final t in tasks) (t.href, t.uid, () => serializeTask(t)),
        for (final e in events) (e.href, e.uid, () => serializeEvent(e)),
      ];
      final seen = <String>{
        for (final i in items)
          if (i.$1 != null) c.pathOf(i.$1!),
      };
      final unreadable = <RawResource>[
        for (final r in raw)
          if (!seen.contains(c.pathOf(r.href))) r,
      ];
      final count = items.length + unreadable.length;
      if (unreadable.isNotEmpty && !allowUnreadable) {
        throw CollectionSafetyException(
            '"${info.name}" holds ${unreadable.length} unreadable '
            'resource(s) that cannot be parsed as notes, tasks or events '
            '(${unreadable.map((r) => r.href).take(5).join(', ')}'
            '${unreadable.length > 5 ? ', ...' : ''}); nothing was deleted. '
            'Set allowUnreadable to back up their raw bodies and delete anyway');
      }
      if (count > 0 && !allowNonEmpty) {
        throw CollectionSafetyException(
            '"${info.name}" holds $count items; set allowNonEmpty to delete it');
      }
      final stamp = _now()
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '')
          .replaceAll('-', '');
      final id = info.href.pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
          'collection';
      final dir = '$backupDir/${Uri.encodeComponent(id)}-$stamp';
      final desc = [
        if (count > 0) 'back up $count items to $dir',
        if (unreadable.isNotEmpty)
          'includes ${unreadable.length} unreadable resource(s), raw',
        'delete collection "${info.name}"',
      ];
      if (dryRun) {
        return CollectionChange('delete', true, desc,
            href: info.href,
            backupPath: count > 0 ? dir : null,
            itemCount: count);
      }
      if (count > 0) {
        final rawByPath = {for (final r in raw) c.pathOf(r.href): r};
        final width = '$count'.length;
        final files = <String, String>{};
        String name(int i, String label) {
          final safe = label
              .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
              .replaceAll(RegExp(r'^\.+'), '_');
          final clipped = safe.length > 80 ? safe.substring(0, 80) : safe;
          return '${'${i + 1}'.padLeft(width, '0')}-$clipped.ics';
        }

        var i = 0;
        for (final it in items) {
          final r = it.$1 == null ? null : rawByPath[c.pathOf(it.$1!)];
          final body = r?.data ?? it.$3();
          final label = it.$1 == null
              ? it.$2
              : c.pathOf(it.$1!).split('/').where((x) => x.isNotEmpty).last;
          files[name(i++, label)] = body;
        }
        for (final r in unreadable) {
          final bytes = await c.getRawBytes(r.href);
          final label =
              c.pathOf(r.href).split('/').where((x) => x.isNotEmpty).last;
          files[name(i++, label)] = utf8.decode(bytes, allowMalformed: true);
        }
        if (files.length != count) {
          throw CollectionSafetyException(
              'backup would hold ${files.length} files for $count items; '
              'nothing was deleted');
        }
        final written = (backupWriter ?? writeBackupFiles)(dir, files);
        if (written != null && written != files.length) {
          throw CollectionSafetyException(
              'backup wrote $written of ${files.length} files; nothing was '
              'deleted');
        }
      }
      // Anything created or changed since the listing was not backed up.
      final again = await c.listRaw();
      String sig(List<RawResource> l) =>
          (l.map((r) => '${c.pathOf(r.href)}|${r.etag ?? ''}').toList()..sort())
              .join('\n');
      if (sig(again) != sig(raw)) {
        throw CollectionSafetyException(
            '"${info.name}" changed while it was being backed up; nothing '
            'was deleted. Run the delete again');
      }
      await CalDavClient.deleteCollection(info.href,
          username: username, password: password, client: httpClient);
      return CollectionChange('delete', false, desc,
          href: info.href,
          backupPath: count > 0 ? dir : null,
          itemCount: count);
    } finally {
      // The client wraps the caller's http client (or its own): leave a
      // caller-supplied one open.
      if (httpClient == null) c.close();
    }
  }

  static const _probeBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"
    xmlns:cs="http://calendarserver.org/ns/">
  <d:prop><d:supported-report-set/><c:supported-calendar-component-set/>
  <cs:getctag/><d:sync-token/></d:prop>
</d:propfind>''';

  /// Asks the server what it supports for the collection at [href]. Never
  /// throws on a server answer: what could not be found out is null in the
  /// result, with the reason in `undetermined`.
  Future<CollectionCapabilities> probe(Uri href) async {
    final url =
        href.path.endsWith('/') ? href : href.replace(path: '${href.path}/');
    final c = _client(url);
    final why = <String, String>{};
    bool? mk, pp, sync, ctag, vj, vt, ve;
    List<String>? comps;
    var dav = <String>[];
    try {
      try {
        final r = await c.sendRaw('OPTIONS', url);
        final allow = r.headers['allow'];
        dav = (r.headers['dav'] ?? '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (r.statusCode >= 400) {
          why['mkcalendar'] = why['proppatch'] = 'OPTIONS ${r.statusCode}';
        } else if (allow == null) {
          why['mkcalendar'] = why['proppatch'] = 'no Allow header';
        } else {
          final ms = allow.toUpperCase().split(RegExp(r'[,\s]+'));
          mk = ms.contains('MKCALENDAR');
          pp = ms.contains('PROPPATCH');
        }
      } catch (e) {
        why['mkcalendar'] = why['proppatch'] = 'OPTIONS failed: $e';
      }
      try {
        final r = await c.sendRaw('PROPFIND', url,
            headers: {
              'Depth': '0',
              'Content-Type': 'application/xml; charset=utf-8',
            },
            body: _probeBody);
        if (r.statusCode != 207) {
          for (final k in ['syncCollection', 'ctag', 'components']) {
            why[k] = 'PROPFIND ${r.statusCode}';
          }
        } else {
          final doc = XmlDocument.parse(utf8.decode(r.bodyBytes));
          // Properties the server answered with 200.
          Iterable<XmlElement> okProps(String name) => doc.descendantElements
              .where((p) => p.localName == 'propstat')
              .where((p) => p.childElements.any((s) =>
                  s.localName == 'status' && s.innerText.contains(' 200')))
              .expand((p) => p.descendantElements)
              .where((e) => e.localName == name);
          final reports = okProps('supported-report-set').toList();
          if (reports.isEmpty) {
            why['syncCollection'] = 'supported-report-set not returned';
          } else {
            sync = reports.first.descendantElements
                .any((e) => e.localName == 'sync-collection');
          }
          final cs = okProps('getctag').toList();
          final st = okProps('sync-token').toList();
          ctag = cs.isNotEmpty || st.isNotEmpty ? true : null;
          if (ctag == null) why['ctag'] = 'no getctag or sync-token property';
          final set = okProps('supported-calendar-component-set').toList();
          if (set.isEmpty) {
            why['components'] = 'supported-calendar-component-set not returned';
          } else {
            comps = [
              for (final e in set.first.descendantElements)
                if (e.localName == 'comp') e.getAttribute('name') ?? ''
            ]..removeWhere((s) => s.isEmpty);
            vj = comps.contains('VJOURNAL');
            vt = comps.contains('VTODO');
            ve = comps.contains('VEVENT');
          }
        }
      } catch (e) {
        for (final k in ['syncCollection', 'ctag', 'components']) {
          why.putIfAbsent(k, () => 'PROPFIND failed: $e');
        }
      }
    } finally {
      if (httpClient == null) c.close();
    }
    return CollectionCapabilities(
        syncCollection: sync,
        ctag: ctag,
        mkcalendar: mk,
        proppatch: pp,
        components: comps,
        vjournal: vj,
        vtodo: vt,
        vevent: ve,
        davClasses: dav,
        undetermined: why);
  }
}
