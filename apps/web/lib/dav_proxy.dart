import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

const _methods = {
  'OPTIONS', 'PROPFIND', 'REPORT', 'GET', 'PUT', 'DELETE', 'MKCALENDAR', //
};

/// Notes are small; this only stops runaway uploads.
const _maxBody = 2 * 1024 * 1024;
const _forwardRequest = {
  'authorization', 'content-type', 'depth', 'if-match', 'if-none-match',
  'accept', //
};
const _forwardResponse = {
  'content-type', 'etag', 'dav', 'allow', 'location', 'www-authenticate',
  'content-location', //
};

/// Passes CalDAV requests under `/dav/` to a Radicale at [upstream], so the
/// browser app (a different origin) needs no CORS. It adds no credentials:
/// the browser's own Authorization header goes through, so a caller needs a
/// login Radicale accepts. Only the methods the app uses are allowed, and
/// paths are kept under `/dav`. The prefix is stripped upstream and sent as
/// X-Script-Name so Radicale writes hrefs that come back through here.
Handler davProxy(Uri upstream, {http.Client? client}) {
  final c = client ?? http.Client();
  return (Request req) async {
    if (!_methods.contains(req.method)) {
      return Response(405, body: 'method not allowed');
    }
    final rest = req.url.path.startsWith('dav/')
        ? req.url.path.substring(4)
        : req.url.path.replaceFirst(RegExp(r'^dav$'), '');
    // Uri parsing already resolves literal dot segments; refuse encoded ones
    // (and bad escapes) so nothing climbs out of the upstream root.
    final List<String> segs;
    try {
      segs = [for (final s in rest.split('/')) Uri.decodeComponent(s)];
    } on FormatException {
      return Response(400, body: 'bad path');
    }
    if (segs.contains('..') ||
        segs.contains('.') ||
        segs.any((s) => s.contains('/'))) {
      return Response(400, body: 'bad path');
    }
    // The /dav prefix is stripped; X-Script-Name tells Radicale it is served
    // under /dav, so the hrefs it returns work through this proxy.
    final target = upstream.replace(
      path: '/${rest.isEmpty ? '' : rest}',
      query: req.url.query.isEmpty ? null : req.url.query,
    );
    final out = http.Request(req.method, target)
      ..followRedirects = false
      ..headers['X-Script-Name'] = '/dav';
    req.headers.forEach((k, v) {
      if (_forwardRequest.contains(k.toLowerCase())) out.headers[k] = v;
    });
    final declared = req.contentLength;
    if (declared != null && declared > _maxBody) {
      return Response(413, body: 'too large');
    }
    final body = <int>[];
    await for (final chunk in req.read()) {
      body.addAll(chunk);
      if (body.length > _maxBody) return Response(413, body: 'too large');
    }
    out.bodyBytes = Uint8List.fromList(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await c.send(out).timeout(const Duration(seconds: 30)),
      );
    } on TimeoutException {
      return Response(504, body: 'upstream timed out');
    }
    return Response(
      res.statusCode,
      body: res.bodyBytes,
      headers: {
        for (final e in res.headers.entries)
          if (_forwardResponse.contains(e.key.toLowerCase())) e.key: e.value,
        'cache-control': 'no-store',
      },
    );
  };
}
