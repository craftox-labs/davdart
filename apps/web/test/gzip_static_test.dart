import 'dart:convert';
import 'dart:io' show gzip;

import 'package:davdart_web/gzip_static.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final body = 'x' * 5000;
  var hits = 0;
  Response inner(Request r) {
    hits++;
    return Response.ok(body, headers: {
      'content-type':
          r.url.path.endsWith('.png') ? 'image/png' : 'text/javascript',
      'etag': 'W/"1"',
    });
  }

  final h = const Pipeline().addMiddleware(gzipStatic()).addHandler(inner);
  Request get(String path, {String? enc, String method = 'GET'}) => Request(
        method,
        Uri.parse('http://x/$path'),
        headers: {if (enc != null) 'accept-encoding': enc},
      );

  test('gzips for a client that accepts it, round trips, sets headers',
      () async {
    final r = await h(get('a.js', enc: 'gzip, br'));
    expect(r.headers['content-encoding'], 'gzip');
    expect(r.headers['vary'], 'Accept-Encoding');
    final bytes = await r.read().expand((c) => c).toList();
    expect(int.parse(r.headers['content-length']!), bytes.length);
    expect(utf8.decode(gzip.decode(bytes)), body);
    expect(bytes.length, lessThan(body.length));
  });

  test('plain without accept-encoding, for images and for non-GET', () async {
    expect((await h(get('a.js'))).headers['content-encoding'], isNull);
    expect((await h(get('a.png', enc: 'gzip'))).headers['content-encoding'],
        isNull);
    expect(
        (await h(get('a.js', enc: 'gzip', method: 'HEAD')))
            .headers['content-encoding'],
        isNull);
  });

  test('a second request for the same tag reuses the compressed body',
      () async {
    final one = await h(get('b.js', enc: 'gzip'));
    await one.read().drain<void>();
    final before = hits;
    final two = await h(get('b.js', enc: 'gzip'));
    final bytes = await two.read().expand((c) => c).toList();
    expect(utf8.decode(gzip.decode(bytes)), body);
    expect(hits, before + 1); // the inner handler runs, compression does not
  });
}
