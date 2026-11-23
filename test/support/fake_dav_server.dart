import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_caldav.dart';

/// Wraps [fake] so PROPFIND on `/dav/` lists the one collection `/dav/c/`
/// (named [name]); everything else goes to the fake collection.
http.Client withHome(FakeCalDav fake, {String name = 'Work'}) =>
    MockClient((r) async {
      if (r.method == 'PROPFIND' && r.url.path == '/dav/') {
        return http.Response(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" '
            'xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response>'
            '<d:href>/dav/c/</d:href><d:propstat><d:prop>'
            '<d:displayname>$name</d:displayname><d:resourcetype>'
            '<d:collection/><c:calendar/></d:resourcetype></d:prop>'
            '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>'
            '</d:multistatus>',
            207);
      }
      return fake.respond(r);
    });

/// A real localhost HTTP server (ephemeral port) answering with [client], so a
/// spawned process can talk to the fake. Collection URL: `$base/dav/c`.
class FakeDavServer {
  FakeDavServer._(this._server, this.client);
  final HttpServer _server;
  final http.Client client;

  static Future<FakeDavServer> start(http.Client client) async {
    final s = await HttpServer.bind('127.0.0.1', 0);
    final self = FakeDavServer._(s, client);
    s.listen(self._handle);
    return self;
  }

  String get collectionUrl => 'http://127.0.0.1:${_server.port}/dav/c';

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decodeStream(req);
    final r = http.Request(req.method, req.requestedUri)..body = body;
    req.headers.forEach((k, v) => r.headers[k] = v.join(','));
    final res = await http.Response.fromStream(await client.send(r));
    req.response.statusCode = res.statusCode;
    res.headers.forEach((k, v) {
      if (k != 'content-length' && k != 'transfer-encoding') {
        req.response.headers.set(k, v);
      }
    });
    req.response.add(res.bodyBytes);
    await req.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
