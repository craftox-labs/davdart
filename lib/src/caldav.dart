import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'event.dart';
import 'ical.dart';
import 'note.dart';
import 'task.dart';

class CalDavException implements Exception {
  CalDavException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'CalDavException($statusCode): $message';
}

/// Thrown when an If-Match / If-None-Match precondition fails (HTTP 412).
class ConflictException extends CalDavException {
  ConflictException(String message) : super(412, message);
}

/// Thrown by [CalDavClient.sync] when the server rejects the sync token
/// (RFC 6578 valid-sync-token). Callers should fall back to a full sync.
class SyncTokenInvalid extends CalDavException {
  SyncTokenInvalid(super.statusCode, super.message);
}

/// Result of [CalDavClient.sync].
class SyncResult {
  SyncResult(this.changed, this.deletedHrefs, this.syncToken,
      [this.unparsableHrefs = const []]);
  final List<Note> changed;
  final List<String> deletedHrefs;

  /// Resources that are on the server but could not be parsed. They are not
  /// in [changed], yet they must not count as deleted.
  final List<String> unparsableHrefs;
  final String? syncToken;
}

/// Result of [CalDavClient.syncTasks].
class TaskSyncResult {
  TaskSyncResult(this.changed, this.deletedHrefs, this.syncToken,
      [this.unparsableHrefs = const []]);
  final List<Task> changed;
  final List<String> deletedHrefs;

  /// Resources on the server that could not be parsed; see [SyncResult].
  final List<String> unparsableHrefs;
  final String? syncToken;
}

/// Result of [CalDavClient.syncEvents].
class EventSyncResult {
  EventSyncResult(this.changed, this.deletedHrefs, this.syncToken,
      [this.unparsableHrefs = const []]);
  final List<Event> changed;
  final List<String> deletedHrefs;

  /// Resources on the server that could not be parsed; see [SyncResult].
  final List<String> unparsableHrefs;
  final String? syncToken;
}

/// A calendar collection found under a user's home.
class CollectionInfo {
  const CollectionInfo(this.href, this.name,
      {this.holdsNotes = true,
      this.holdsTasks = true,
      this.holdsEvents = true});

  /// Absolute URL of the collection.
  final Uri href;

  /// The display name, or the last path segment when there is none.
  final String name;

  /// False when the server says the collection takes only events or tasks.
  final bool holdsNotes;

  /// False when the server says the collection takes no VTODO.
  final bool holdsTasks;

  /// False when the server says the collection takes no VEVENT.
  final bool holdsEvents;
}

/// A resource as the server lists it: href, etag and raw calendar-data
/// (null when missing or empty).
class RawResource {
  RawResource(this.href, this.etag, this.data);
  final String href;
  final String? etag;
  final String? data;
}

/// CalDAV client for one collection that holds VJOURNAL resources.
class CalDavClient {
  CalDavClient({
    required Uri collection,
    required this.username,
    required this.password,
    http.Client? client,
    this.onResourceError,
  })  : collection = _withSlash(collection),
        _http = client ?? http.Client();

  final Uri collection;
  final String username;
  final String password;
  final http.Client _http;

  /// Called for a resource that cannot be parsed. [listNotes] skips it instead
  /// of failing the whole listing.
  final void Function(String? href, Object error)? onResourceError;

  static Uri _withSlash(Uri u) =>
      u.path.endsWith('/') ? u : u.replace(path: '${u.path}/');

  Map<String, String> get _auth => {
        'Authorization':
            'Basic ${base64.encode(utf8.encode('$username:$password'))}',
      };

  static const _discoverBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:displayname/><d:resourcetype/>
  <c:supported-calendar-component-set/></d:prop>
</d:propfind>''';

  /// Lists the calendar collections one level below [home] (a user's home
  /// URL, for example `/dav/bot/`), so a person can pick by name instead of
  /// typing a collection id.
  static Future<List<CollectionInfo>> discover(
    Uri home, {
    required String username,
    required String password,
    http.Client? client,
  }) async {
    final h = _withSlash(home);
    final c = CalDavClient(
        collection: h, username: username, password: password, client: client);
    final r = await c._send('PROPFIND', h,
        headers: {
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: _discoverBody);
    if (r.statusCode != 207) {
      throw CalDavException(r.statusCode, 'PROPFIND failed');
    }
    final out = <CollectionInfo>[];
    for (final resp in XmlDocument.parse(utf8.decode(r.bodyBytes))
        .descendantElements
        .where((e) => e.name.local == 'response')) {
      XmlElement? find(String name) => resp.descendantElements
          .where((e) => e.name.local == name)
          .firstOrNull;
      final href = find('href')?.innerText.trim();
      if (href == null || find('calendar') == null) continue;
      final url = h.resolve(href);
      if (url.path == h.path) continue;
      final comps = resp.descendantElements
          .where((e) => e.name.local == 'comp')
          .map((e) => e.getAttribute('name'))
          .toList();
      final dn = find('displayname')?.innerText.trim() ?? '';
      final segs = url.pathSegments.where((s) => s.isNotEmpty);
      out.add(CollectionInfo(
        _withSlash(url),
        dn.isEmpty ? (segs.isEmpty ? url.path : segs.last) : dn,
        holdsNotes: comps.isEmpty || comps.contains('VJOURNAL'),
        holdsTasks: comps.isEmpty || comps.contains('VTODO'),
        holdsEvents: comps.isEmpty || comps.contains('VEVENT'),
      ));
    }
    return out;
  }

  /// Creates a new collection for notes under [home] (a user's home URL),
  /// named [name], and returns its URL. The id in the path is random; the
  /// name lives in the display name, so renaming never moves anything.
  static Future<Uri> createCollection(
    Uri home,
    String name, {
    required String username,
    required String password,
    http.Client? client,
    String? id,
    List<String> components = const ['VJOURNAL', 'VTODO', 'VEVENT'],
  }) async {
    final h = _withSlash(home);
    final c = CalDavClient(
        collection: h, username: username, password: password, client: client);
    final rnd = Random.secure();
    final cid = id ??
        List.generate(
                16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join();
    final url = h.resolve('$cid/');
    final b = XmlBuilder();
    b.element('c:mkcalendar', nest: () {
      b.namespace('DAV:', 'd');
      b.namespace('urn:ietf:params:xml:ns:caldav', 'c');
      b.element('d:set', nest: () {
        b.element('d:prop', nest: () {
          b.element('d:displayname', nest: name);
          b.element('c:supported-calendar-component-set', nest: () {
            for (final c in components) {
              b.element('c:comp', attributes: {'name': c});
            }
          });
        });
      });
    });
    final r = await c._send('MKCALENDAR', url,
        headers: {'Content-Type': 'application/xml; charset=utf-8'},
        body: b.buildDocument().toXmlString());
    if (r.statusCode != 201) {
      throw CalDavException(r.statusCode, 'MKCALENDAR failed');
    }
    return url;
  }

  /// Sets the display name of the collection at [url] (PROPPATCH).
  static Future<void> renameCollection(
    Uri url,
    String name, {
    required String username,
    required String password,
    http.Client? client,
  }) async {
    final u = _withSlash(url);
    final c = CalDavClient(
        collection: u, username: username, password: password, client: client);
    final b = XmlBuilder();
    b.element('d:propertyupdate', nest: () {
      b.namespace('DAV:', 'd');
      b.element('d:set', nest: () {
        b.element('d:prop', nest: () {
          b.element('d:displayname', nest: name);
        });
      });
    });
    final r = await c._send('PROPPATCH', u,
        headers: {'Content-Type': 'application/xml; charset=utf-8'},
        body: b.buildDocument().toXmlString());
    if (r.statusCode != 207 && r.statusCode != 200 && r.statusCode != 204) {
      throw CalDavException(r.statusCode, 'PROPPATCH failed');
    }
    if (r.statusCode == 207) {
      final bad = XmlDocument.parse(utf8.decode(r.bodyBytes))
          .descendantElements
          .where((e) => e.name.local == 'status')
          .where((e) => !e.innerText.contains(' 200'));
      if (bad.isNotEmpty) {
        throw CalDavException(403, 'rename refused: ${bad.first.innerText}');
      }
    }
  }

  /// Deletes the whole collection at [url] with everything in it (DELETE).
  /// CalDAV has no trash: callers must back up first (see
  /// `CollectionService.delete`).
  static Future<void> deleteCollection(
    Uri url, {
    required String username,
    required String password,
    http.Client? client,
  }) async {
    final u = _withSlash(url);
    final c = CalDavClient(
        collection: u, username: username, password: password, client: client);
    final r = await c._send('DELETE', u);
    if (r.statusCode != 200 && r.statusCode != 204) {
      throw CalDavException(r.statusCode, 'DELETE collection failed');
    }
  }

  /// Sends a raw request with this client's credentials, for capability
  /// probes. Not for item writes.
  Future<http.Response> sendRaw(String method, Uri url,
          {Map<String, String> headers = const {}, String? body}) =>
      _send(method, url, headers: headers, body: body);

  Uri _resolve(String href) => collection.resolve(href);

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final req = http.Request(method, url)
      ..headers.addAll(_auth)
      ..headers.addAll(headers);
    if (body != null) req.body = body;
    return http.Response.fromStream(await _http.send(req));
  }

  static String _reportBody(String? comp) =>
      '''<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR">
    ${comp == null ? '' : '<c:comp-filter name="$comp"/>'}
  </c:comp-filter></c:filter>
</c:calendar-query>''';

  /// Lists every resource in the collection whatever its component type,
  /// with the raw calendar-data when the server returned any. Used to check
  /// that typed listings did not silently drop anything.
  Future<List<RawResource>> listRaw() async {
    final r = await _send('REPORT', collection,
        headers: {
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: _reportBody(null));
    if (r.statusCode != 207) {
      throw CalDavException(r.statusCode, 'REPORT failed');
    }
    final doc = XmlDocument.parse(utf8.decode(r.bodyBytes));
    final out = <RawResource>[];
    for (final resp
        in doc.descendantElements.where((e) => e.localName == 'response')) {
      String? text(String name) => resp.descendantElements
          .where((e) => e.localName == name)
          .map((e) => e.innerText)
          .firstOrNull;
      final href = text('href');
      if (href == null) continue;
      if (_resolve(href).path == collection.path) continue;
      final data = text('calendar-data');
      out.add(RawResource(href, text('getetag'),
          data == null || data.trim().isEmpty ? null : data));
    }
    return out;
  }

  /// Fetches the raw body of the resource at [href].
  Future<List<int>> getRawBytes(String href) async {
    final r = await _send('GET', _resolve(href));
    if (r.statusCode != 200) {
      throw CalDavException(r.statusCode, 'GET failed for $href');
    }
    return r.bodyBytes;
  }

  /// Absolute path of [href] as this collection sees it.
  String pathOf(String href) => _resolve(href).path;

  /// Lists every note in the collection, with href and etag set.
  Future<List<Note>> listNotes() async {
    final r = await _send('REPORT', collection,
        headers: {
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: _reportBody('VJOURNAL'));
    if (r.statusCode != 207) {
      throw CalDavException(r.statusCode, 'REPORT failed');
    }
    return parseMultistatus(utf8.decode(r.bodyBytes), onError: onResourceError);
  }

  /// Incremental sync (RFC 6578 sync-collection). A null or empty [syncToken]
  /// is an initial sync. Throws [SyncTokenInvalid] if the server rejects the
  /// token; fall back to `sync()` without a token then.
  Future<SyncResult> sync({String? syncToken}) async {
    final r = await _syncGeneric<Note>(syncToken,
        parse: parseNote,
        missing: 'no VJOURNAL found',
        get: getNote,
        setMeta: (n, href, etag) => n
          ..href = href
          ..etag = etag);
    return SyncResult(r.$1, r.$2, r.$3, r.$4);
  }

  /// Like [sync], for the VTODO resources of the collection. The server
  /// answers sync-collection for every component, so notes, tasks and events
  /// arrive together; each caller keeps its own type and skips the rest.
  Future<TaskSyncResult> syncTasks({String? syncToken}) async {
    final r = await _syncGeneric<Task>(syncToken,
        parse: parseTask,
        missing: 'no VTODO found',
        get: getTask,
        setMeta: (t, href, etag) => t
          ..href = href
          ..etag = etag);
    return TaskSyncResult(r.$1, r.$2, r.$3, r.$4);
  }

  /// Like [sync], for the VEVENT resources of the collection.
  Future<EventSyncResult> syncEvents({String? syncToken}) async {
    final r = await _syncGeneric<Event>(syncToken,
        parse: parseEvent,
        missing: 'no VEVENT found',
        get: getEvent,
        setMeta: (e, href, etag) => e
          ..href = href
          ..etag = etag);
    return EventSyncResult(r.$1, r.$2, r.$3, r.$4);
  }

  Future<(List<T>, List<String>, String?, List<String>)> _syncGeneric<T>(
    String? syncToken, {
    required T Function(String) parse,
    required String missing,
    required Future<T> Function(String href) get,
    required T Function(T, String href, String? etag) setMeta,
  }) async {
    final token =
        const HtmlEscape(HtmlEscapeMode.element).convert(syncToken ?? '');
    final body = '''<?xml version="1.0" encoding="utf-8"?>
<d:sync-collection xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:sync-token>$token</d:sync-token>
  <d:sync-level>1</d:sync-level>
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
</d:sync-collection>''';
    final r = await _send('REPORT', collection,
        headers: {
          'Depth': '0',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: body);
    final text = utf8.decode(r.bodyBytes, allowMalformed: true);
    if ({403, 409, 412}.contains(r.statusCode) &&
        text.contains('valid-sync-token')) {
      throw SyncTokenInvalid(r.statusCode, 'sync token rejected');
    }
    if (r.statusCode != 207) {
      throw CalDavException(r.statusCode, 'sync REPORT failed');
    }
    final doc = XmlDocument.parse(text);
    final changed = <T>[];
    final deleted = <String>[];
    final unparsable = <String>[];
    String? newToken;
    for (final e in doc.descendantElements) {
      if (e.localName == 'sync-token' &&
          e.parentElement?.localName == 'multistatus') {
        newToken = e.innerText.trim();
      }
    }
    for (final resp
        in doc.descendantElements.where((e) => e.localName == 'response')) {
      String? first(String name) => resp.descendantElements
          .where((e) => e.localName == name)
          .map((e) => e.innerText)
          .firstOrNull;
      final href = first('href')?.trim();
      if (href == null || href.isEmpty) continue;
      final respStatus = resp.childElements
          .where((e) => e.localName == 'status')
          .map((e) => e.innerText)
          .firstOrNull;
      final propStatuses = resp.descendantElements
          .where((e) => e.localName == 'propstat')
          .expand((p) => p.childElements.where((e) => e.localName == 'status'))
          .map((e) => e.innerText)
          .toList();
      bool is404(String s) => RegExp(r'\s404(\s|$)').hasMatch(s);
      bool ok(String s) => RegExp(r'\s2\d\d(\s|$)').hasMatch(s);
      if ((respStatus != null && is404(respStatus)) ||
          (propStatuses.isNotEmpty &&
              !propStatuses.any(ok) &&
              propStatuses.every(is404))) {
        deleted.add(href);
        continue;
      }
      if (_resolve(href).path == collection.path) continue;
      final etag = first('getetag');
      var data = first('calendar-data');
      try {
        T n;
        if (data == null || data.trim().isEmpty) {
          n = await get(href);
        } else {
          n = setMeta(parse(data), href, etag);
        }
        changed.add(n);
      } on ICalException catch (e) {
        if (e.message != missing) {
          unparsable.add(href);
          onResourceError?.call(href, e);
        }
      }
      // A failed fetch (CalDavException, network error) is not caught: the
      // whole sync fails, so the caller keeps its old token and retries.
    }
    return (changed, deleted, newToken, unparsable);
  }

  /// Fetches one note by href (absolute or relative to the collection).
  Future<Note> getNote(String href) async {
    final r = await _send('GET', _resolve(href));
    if (r.statusCode != 200) throw CalDavException(r.statusCode, 'GET failed');
    final n = parseNote(utf8.decode(r.bodyBytes));
    n.href = href;
    n.etag = r.headers['etag'];
    return n;
  }

  /// Creates or updates [note]. A note with an etag is updated only if the
  /// server copy is unchanged; a note without one is created only if absent.
  /// DTSTAMP and LAST-MODIFIED are set to now ([touch], default) so other
  /// clients see the change. Returns the stored note with fresh href and etag.
  ///
  /// The etag goes into If-Match as given, so a weak etag (`W/"..."`) will be
  /// refused by the server (RFC 7232 strong comparison); Radicale sends strong
  /// ones.
  Future<Note> putNote(Note note, {bool touch = true}) async {
    if (touch) {
      final now = DateTime.now().toUtc();
      note
        ..lastModified = now
        ..dtstamp = now;
    }
    final href = note.href ?? '${Uri.encodeComponent(note.uid)}.ics';
    final r = await _send('PUT', _resolve(href),
        headers: {
          'Content-Type': 'text/calendar; charset=utf-8',
          if (note.etag != null)
            'If-Match': note.etag!
          else
            'If-None-Match': '*',
        },
        body: serializeNote(note));
    if (r.statusCode == 412) {
      throw ConflictException('${note.uid} changed on the server');
    }
    if (r.statusCode != 200 && r.statusCode != 201 && r.statusCode != 204) {
      throw CalDavException(r.statusCode, 'PUT failed');
    }
    final stored = note.copyWith();
    stored.href = href;
    stored.etag = r.headers['etag'] ?? (await getNote(href)).etag;
    return stored;
  }

  /// Deletes [note]; with an etag the delete is conditional.
  Future<void> deleteNote(Note note) async {
    final href = note.href;
    if (href == null) throw ArgumentError('note has no href');
    final r = await _send('DELETE', _resolve(href),
        headers: {if (note.etag != null) 'If-Match': note.etag!});
    if (r.statusCode == 412) {
      throw ConflictException('${note.uid} changed on the server');
    }
    if (r.statusCode != 200 && r.statusCode != 204 && r.statusCode != 404) {
      throw CalDavException(r.statusCode, 'DELETE failed');
    }
  }

  // ---- Tasks (VTODO) ----

  /// Lists every task in the collection, with href and etag set.
  Future<List<Task>> listTasks() async {
    final r = await _send('REPORT', collection,
        headers: {
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: _reportBody('VTODO'));
    if (r.statusCode != 207) {
      throw CalDavException(r.statusCode, 'REPORT failed');
    }
    return parseTaskMultistatus(utf8.decode(r.bodyBytes),
        onError: onResourceError);
  }

  /// Fetches one task by href (absolute or relative to the collection).
  Future<Task> getTask(String href) async {
    final r = await _send('GET', _resolve(href));
    if (r.statusCode != 200) throw CalDavException(r.statusCode, 'GET failed');
    final t = parseTask(utf8.decode(r.bodyBytes));
    t.href = href;
    t.etag = r.headers['etag'];
    return t;
  }

  /// Creates or updates [task], like [putNote]: conditional on the etag, or
  /// create-only without one. Returns the stored task with fresh href, etag.
  Future<Task> putTask(Task task, {bool touch = true}) async {
    if (touch) {
      final now = DateTime.now().toUtc();
      task
        ..lastModified = now
        ..dtstamp = now;
    }
    final href = task.href ?? '${Uri.encodeComponent(task.uid)}.ics';
    final r = await _send('PUT', _resolve(href),
        headers: {
          'Content-Type': 'text/calendar; charset=utf-8',
          if (task.etag != null)
            'If-Match': task.etag!
          else
            'If-None-Match': '*',
        },
        body: serializeTask(task));
    if (r.statusCode == 412) {
      throw ConflictException('${task.uid} changed on the server');
    }
    if (r.statusCode != 200 && r.statusCode != 201 && r.statusCode != 204) {
      throw CalDavException(r.statusCode, 'PUT failed');
    }
    final stored = task.copyWith();
    stored.href = href;
    stored.etag = r.headers['etag'] ?? (await getTask(href)).etag;
    return stored;
  }

  /// Deletes [task]; with an etag the delete is conditional.
  Future<void> deleteTask(Task task) async {
    final href = task.href;
    if (href == null) throw ArgumentError('task has no href');
    final r = await _send('DELETE', _resolve(href),
        headers: {if (task.etag != null) 'If-Match': task.etag!});
    if (r.statusCode == 412) {
      throw ConflictException('${task.uid} changed on the server');
    }
    if (r.statusCode != 200 && r.statusCode != 204 && r.statusCode != 404) {
      throw CalDavException(r.statusCode, 'DELETE failed');
    }
  }

  // ---- Events (VEVENT) ----

  /// Lists every event in the collection, with href and etag set.
  Future<List<Event>> listEvents() async {
    final r = await _send('REPORT', collection,
        headers: {
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: _reportBody('VEVENT'));
    if (r.statusCode != 207) {
      throw CalDavException(r.statusCode, 'REPORT failed');
    }
    return parseEventMultistatus(utf8.decode(r.bodyBytes),
        onError: onResourceError);
  }

  /// Fetches one event by href (absolute or relative to the collection).
  Future<Event> getEvent(String href) async {
    final r = await _send('GET', _resolve(href));
    if (r.statusCode != 200) throw CalDavException(r.statusCode, 'GET failed');
    final e = parseEvent(utf8.decode(r.bodyBytes));
    e.href = href;
    e.etag = r.headers['etag'];
    return e;
  }

  /// Creates or updates [event], like [putNote]: conditional on the etag, or
  /// create-only without one. Returns the stored event with fresh href, etag.
  Future<Event> putEvent(Event event, {bool touch = true}) async {
    if (touch) {
      final now = DateTime.now().toUtc();
      event
        ..lastModified = now
        ..dtstamp = now;
    }
    final href = event.href ?? '${Uri.encodeComponent(event.uid)}.ics';
    final r = await _send('PUT', _resolve(href),
        headers: {
          'Content-Type': 'text/calendar; charset=utf-8',
          if (event.etag != null)
            'If-Match': event.etag!
          else
            'If-None-Match': '*',
        },
        body: serializeEvent(event));
    if (r.statusCode == 412) {
      throw ConflictException('${event.uid} changed on the server');
    }
    if (r.statusCode != 200 && r.statusCode != 201 && r.statusCode != 204) {
      throw CalDavException(r.statusCode, 'PUT failed');
    }
    final stored = event.copyWith();
    stored.href = href;
    stored.etag = r.headers['etag'] ?? (await getEvent(href)).etag;
    return stored;
  }

  /// Deletes [event]; with an etag the delete is conditional.
  Future<void> deleteEvent(Event event) async {
    final href = event.href;
    if (href == null) throw ArgumentError('event has no href');
    final r = await _send('DELETE', _resolve(href),
        headers: {if (event.etag != null) 'If-Match': event.etag!});
    if (r.statusCode == 412) {
      throw ConflictException('${event.uid} changed on the server');
    }
    if (r.statusCode != 200 && r.statusCode != 204 && r.statusCode != 404) {
      throw CalDavException(r.statusCode, 'DELETE failed');
    }
  }

  void close() => _http.close();
}

/// Parses a WebDAV 207 multistatus body into notes with href and etag.
///
/// A resource that fails to parse is reported to [onError] and skipped.
List<Note> parseMultistatus(String body,
    {void Function(String? href, Object error)? onError}) {
  final doc = XmlDocument.parse(body);
  final notes = <Note>[];
  for (final resp
      in doc.descendantElements.where((e) => e.localName == 'response')) {
    String? text(String name) => resp.descendantElements
        .where((e) => e.localName == name)
        .map((e) => e.innerText)
        .firstOrNull;
    final data = text('calendar-data');
    if (data == null || data.trim().isEmpty) continue;
    final href = text('href');
    final etag = text('getetag');
    try {
      final n = parseNote(data);
      n.href = href;
      n.etag = etag;
      notes.add(n);
    } on ICalException catch (e) {
      if (e.message != 'no VJOURNAL found') onError?.call(href, e);
    }
  }
  return notes;
}

/// Parses a WebDAV 207 multistatus body into tasks with href and etag.
/// Resources without a VTODO are skipped; unparsable ones go to [onError].
List<Task> parseTaskMultistatus(String body,
    {void Function(String? href, Object error)? onError}) {
  final doc = XmlDocument.parse(body);
  final tasks = <Task>[];
  for (final resp
      in doc.descendantElements.where((e) => e.localName == 'response')) {
    String? text(String name) => resp.descendantElements
        .where((e) => e.localName == name)
        .map((e) => e.innerText)
        .firstOrNull;
    final data = text('calendar-data');
    if (data == null || data.trim().isEmpty) continue;
    final href = text('href');
    try {
      tasks.add(parseTask(data)
        ..href = href
        ..etag = text('getetag'));
    } on ICalException catch (e) {
      if (e.message != 'no VTODO found') onError?.call(href, e);
    }
  }
  return tasks;
}

/// Parses a WebDAV 207 multistatus body into events with href and etag.
/// Resources without a VEVENT are skipped; unparsable ones go to [onError].
List<Event> parseEventMultistatus(String body,
    {void Function(String? href, Object error)? onError}) {
  final doc = XmlDocument.parse(body);
  final events = <Event>[];
  for (final resp
      in doc.descendantElements.where((e) => e.localName == 'response')) {
    String? text(String name) => resp.descendantElements
        .where((e) => e.localName == name)
        .map((e) => e.innerText)
        .firstOrNull;
    final data = text('calendar-data');
    if (data == null || data.trim().isEmpty) continue;
    final href = text('href');
    try {
      events.add(parseEvent(data)
        ..href = href
        ..etag = text('getetag'));
    } on ICalException catch (e) {
      if (e.message != 'no VEVENT found') onError?.call(href, e);
    }
  }
  return events;
}
