import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart_web/dav_proxy.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Live check of the proxy against a real Radicale, in process (no server is
/// started). Runs only with DAVDART_TEST_URL, _USER and _PASSWORD set.
void main() {
  final env = Platform.environment;
  final url = env['DAVDART_TEST_URL'];
  test('CalDAV through the proxy: list, put, get, delete',
      skip: url == null || url.isEmpty ? 'DAVDART_TEST_URL not set' : null,
      () async {
    final real = Uri.parse(url!);
    final handler = davProxy(real.replace(path: '/', query: null));
    // Routes the client's requests into the handler as a browser would.
    final bridge = MockClient.streaming((req, body) async {
      final bytes = await body.expand((c) => c).toList();
      final res = await handler(
          Request(req.method, req.url, headers: req.headers, body: bytes));
      return http.StreamedResponse(res.read(), res.statusCode,
          headers: res.headers, request: req);
    });
    final c = CalDavClient(
      collection: Uri.parse('http://app/dav${real.path}'),
      username: env['DAVDART_TEST_USER'] ?? '',
      password: env['DAVDART_TEST_PASSWORD'] ?? '',
      client: bridge,
    );
    final uid = 'davdart-proxy-${DateTime.now().microsecondsSinceEpoch}';
    Note? made;
    try {
      made = await c.putNote(Note(uid: uid, summary: 'via proxy'));
      expect(made.etag, isNotNull);
      expect((await c.listNotes()).map((n) => n.uid), contains(uid));
      expect((await c.getNote(made.href!)).summary, 'via proxy');
      await c.deleteNote(made);
      made = null;
      expect((await c.listNotes()).map((n) => n.uid), isNot(contains(uid)));
    } finally {
      if (made != null) await c.deleteNote(made);
      c.close();
    }
  });
}
