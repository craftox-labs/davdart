import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart/io.dart';
import 'package:davdart_web/dav_proxy.dart';
import 'package:davdart_web/gzip_static.dart';
import 'package:davdart_web/web_app.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';

/// Read-only board. Binds to loopback only. Usage: dart run bin/server.dart [port]
/// (default 8800). Login comes from the davdart config file or environment.
Future<void> main(List<String> args) async {
  final cfg = loadConfig();
  final url = cfg['url'], user = cfg['user'], pass = cfg['password'];
  if (url == null || user == null || pass == null) {
    stderr.writeln(
        'missing url/user/password; see ~/.config/davdart/credentials');
    exit(2);
  }
  final client =
      CalDavClient(collection: Uri.parse(url), username: user, password: pass);
  List<Note>? cache;
  var fetched = DateTime.fromMillisecondsSinceEpoch(0);
  Future<List<Note>> load() async {
    if (cache == null || DateTime.now().difference(fetched).inSeconds > 5) {
      cache = await client.listNotes();
      fetched = DateTime.now();
    }
    return cache!;
  }

  final port = args.isEmpty ? 8800 : int.parse(args.first);
  // The Flutter web build, when present, is served at /app/ (same origin as
  // /api/notes, so the browser needs no cross-origin access).
  final board = buildHandler(load);
  final appDir = Directory('../app/build/web'); // relative to apps/web
  final app = appDir.existsSync()
      ? const Pipeline()
          // no-cache = revalidate (the files carry ETags), so a deploy shows
          // up on the next load instead of after heuristic cache expiry.
          .addMiddleware(createMiddleware(
              responseHandler: (r) =>
                  r.change(headers: {'cache-control': 'no-cache'})))
          .addMiddleware(gzipStatic())
          .addHandler(createStaticHandler(appDir.path,
              defaultDocument: 'index.html'))
      : null;
  // Off unless DAVDART_DAV_UPSTREAM (the Radicale base, e.g.
  // http://127.0.0.1:5232) is set: then /dav/... reaches it for the app's sync.
  final upstreamEnv = Platform.environment['DAVDART_DAV_UPSTREAM'];
  final dav = (upstreamEnv == null || upstreamEnv.isEmpty)
      ? null
      : davProxy(Uri.parse(upstreamEnv));
  Future<Response> handler(Request req) async {
    final path = req.url.path;
    if (dav != null && (path == 'dav' || path.startsWith('dav/'))) {
      return dav(req);
    }
    if (app != null && path == 'app') {
      return Response.found('/app/');
    }
    if (app != null && path.startsWith('app/')) {
      return app(req.change(path: 'app'));
    }
    return board(req);
  }

  final server = await io.serve(handler, InternetAddress.loopbackIPv4, port);
  stdout.writeln('davdart board on http://127.0.0.1:${server.port}/');
}
