import 'dart:io' show gzip;

import 'package:shelf/shelf.dart';

/// Content types worth compressing (the web build's script, markup, fonts and
/// wasm). Images and already-compressed formats are left alone.
bool _compressible(String? type) {
  if (type == null) return false;
  final t = type.split(';').first.trim().toLowerCase();
  return t.startsWith('text/') ||
      t.contains('javascript') ||
      t.contains('json') ||
      t.contains('wasm') ||
      t.contains('font') ||
      t.contains('opentype') ||
      t.contains('svg') ||
      t.contains('xml');
}

/// Gzips successful GET responses for clients that accept it, keeping each
/// compressed body in memory keyed by the response's ETag (the static
/// handler's tag changes with the file), so a large file such as main.dart.js
/// is compressed once, not per request.
Middleware gzipStatic() {
  final cache = <String, List<int>>{};
  return (inner) => (request) async {
    final res = await inner(request);
    final accept = request.headers['accept-encoding'] ?? '';
    if (request.method != 'GET' ||
        res.statusCode != 200 ||
        !accept.contains('gzip') ||
        res.headers.containsKey('content-encoding') ||
        !_compressible(res.headers['content-type'])) {
      return res;
    }
    final etag = res.headers['etag'];
    final key = etag == null ? null : '${request.url.path}|$etag';
    var bytes = key == null ? null : cache[key];
    if (bytes == null) {
      final raw = <int>[];
      await for (final c in res.read()) {
        raw.addAll(c);
      }
      bytes = gzip.encode(raw);
      if (key != null) cache[key] = bytes;
    }
    return res.change(
      body: bytes,
      headers: {
        'content-encoding': 'gzip',
        'content-length': '${bytes.length}',
        'vary': 'Accept-Encoding',
      },
    );
  };
}
