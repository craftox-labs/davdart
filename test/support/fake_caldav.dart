import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A small in-memory CalDAV collection for tests: GET, PUT and DELETE with
/// ETag preconditions, calendar-query and sync-collection REPORTs.
class FakeCalDav {
  final Map<String, String> ics = {};
  final Map<String, String> etags = {};
  final Map<String, int> changedAt = {};
  final Map<String, int> deletedAt = {};
  int version = 0;
  int _etagCounter = 0;
  bool rejectTokens = false;
  final List<String> log = [];

  static final collection = Uri.parse('https://fake.test/dav/c');
  late final MockClient client = MockClient(_handle);

  String _name(Uri u) => u.pathSegments.last;
  static const _esc = HtmlEscape(HtmlEscapeMode.element);

  /// Writes a resource as if another client had, bumping version.
  void external(String name, String body) {
    ics[name] = body;
    etags[name] = '"e${++_etagCounter}"';
    changedAt[name] = ++version;
    deletedAt.remove(name);
  }

  void externalDelete(String name) {
    ics.remove(name);
    etags.remove(name);
    deletedAt[name] = ++version;
  }

  String _resp(String name) => '<d:response><d:href>/dav/c/$name</d:href>'
      '<d:propstat><d:prop><d:getetag>${etags[name]}</d:getetag>'
      '<c:calendar-data>${_esc.convert(ics[name]!)}</c:calendar-data>'
      '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
      '</d:response>';

  http.Response _multi(String inner, [String? token]) => http.Response.bytes(
      utf8.encode('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" '
          'xmlns:c="urn:ietf:params:xml:ns:caldav">$inner'
          '${token == null ? '' : '<d:sync-token>$token</d:sync-token>'}'
          '</d:multistatus>'),
      207);

  Future<http.Response> _handle(http.BaseRequest req) async {
    final body = req is http.Request ? req.body : '';
    final name = _name(req.url);
    log.add('${req.method} $name');
    switch (req.method) {
      case 'GET':
        if (!ics.containsKey(name)) return http.Response('', 404);
        return http.Response(ics[name]!, 200, headers: {'etag': etags[name]!});
      case 'PUT':
        final exists = ics.containsKey(name);
        final ifMatch = req.headers['If-Match'];
        if (req.headers['If-None-Match'] == '*' && exists) {
          return http.Response('', 412);
        }
        if (ifMatch != null && (!exists || etags[name] != ifMatch)) {
          return http.Response('', 412);
        }
        external(name, body);
        return http.Response('', exists ? 204 : 201,
            headers: {'etag': etags[name]!});
      case 'DELETE':
        if (!ics.containsKey(name)) return http.Response('', 404);
        final ifMatch = req.headers['If-Match'];
        if (ifMatch != null && etags[name] != ifMatch) {
          return http.Response('', 412);
        }
        externalDelete(name);
        return http.Response('', 204);
      case 'REPORT':
        if (body.contains('sync-collection')) {
          final t = RegExp(r'<d:sync-token>(.*?)</d:sync-token>', dotAll: true)
                  .firstMatch(body)
                  ?.group(1) ??
              '';
          final m = RegExp(r'^v(\d+)$').firstMatch(t);
          if (t.isNotEmpty && (rejectTokens || m == null)) {
            return http.Response(
                '<d:error xmlns:d="DAV:"><d:valid-sync-token/></d:error>', 403);
          }
          final since = m == null ? 0 : int.parse(m.group(1)!);
          final b = StringBuffer();
          for (final e in changedAt.entries) {
            if (e.value > since && ics.containsKey(e.key)) {
              b.write(_resp(e.key));
            }
          }
          for (final e in deletedAt.entries) {
            if (e.value > since && !ics.containsKey(e.key)) {
              b.write('<d:response><d:href>/dav/c/${e.key}</d:href>'
                  '<d:status>HTTP/1.1 404 Not Found</d:status></d:response>');
            }
          }
          return _multi(b.toString(), 'v$version');
        }
        return _multi([for (final n in ics.keys) _resp(n)].join());
    }
    return http.Response('', 405);
  }
}
