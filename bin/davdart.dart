import 'dart:io';
import 'dart:math';

import 'package:davdart/davdart.dart';

/// Minimal CLI. Config from env: DAVDART_URL (collection), DAVDART_USER,
/// DAVDART_PASSWORD. Commands: list, add TITLE [BODY], rm UID.
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final url = env['DAVDART_URL'];
  final user = env['DAVDART_USER'];
  final pass = env['DAVDART_PASSWORD'];
  if (args.isEmpty || url == null || user == null || pass == null) {
    stderr.writeln('usage: davdart list | add <title> [body] | rm <uid>\n'
        'env: DAVDART_URL DAVDART_USER DAVDART_PASSWORD');
    exit(2);
  }
  final c =
      CalDavClient(collection: Uri.parse(url), username: user, password: pass);
  try {
    switch (args.first) {
      case 'list':
        for (final n in await c.listNotes()) {
          stdout.writeln('${n.uid}\t${n.categories.join(",")}\t${n.summary}');
        }
      case 'add':
        if (args.length < 2) {
          stderr.writeln('add needs a title');
          exit(2);
        }
        final now = DateTime.now();
        final n = await c.putNote(Note(
          uid:
              '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}@davdart',
          summary: args[1],
          description: args.length > 2 ? args[2] : '',
          created: now,
          lastModified: now,
        ));
        stdout.writeln('created ${n.uid}');
      case 'rm':
        if (args.length < 2) {
          stderr.writeln('rm needs a uid');
          exit(2);
        }
        final all = await c.listNotes();
        final hit = all.where((n) => n.uid == args[1]).firstOrNull;
        if (hit == null) {
          stderr.writeln('no note ${args[1]}');
          exit(1);
        }
        await c.deleteNote(hit);
        stdout.writeln('deleted ${hit.uid}');
      default:
        stderr.writeln('unknown command ${args.first}');
        exit(2);
    }
  } finally {
    c.close();
  }
}
