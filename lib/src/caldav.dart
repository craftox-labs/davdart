import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'ical.dart';
import 'note.dart';

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

  static const _reportBody = '''<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR">
    <c:comp-filter name="VJOURNAL"/>
  </c:comp-filter></c:filter>
</c:calendar-query>''';

  /// Lists every note in the collection, with href and etag set.
  Future<List<Note>> listNotes() async {
    final r = await _send('REPORT', collection,
        headers: {
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        body: _reportBody);
    if (r.statusCode != 207) {
      throw CalDavException(r.statusCode, 'REPORT failed');
    }
    return parseMultistatus(utf8.decode(r.bodyBytes), onError: onResourceError);
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
