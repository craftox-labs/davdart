import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart_web/web_app.dart';
import 'package:shelf/shelf_io.dart' as io;

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
  final server =
      await io.serve(buildHandler(load), InternetAddress.loopbackIPv4, port);
  stdout.writeln('davdart board on http://127.0.0.1:${server.port}/');
}
