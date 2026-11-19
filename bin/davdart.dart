import 'dart:io';
import 'dart:math';

import 'package:davdart/davdart.dart';

/// Minimal CLI. Config: a key=value file (url, user, password) or DAVDART_*
/// environment variables, which win. Commands: list, add TITLE [BODY], rm UID.
Future<void> main(List<String> args) async {
  final cfg = loadConfig();
  final url = cfg['url'];
  final user = cfg['user'];
  final pass = cfg['password'];
  if (args.isEmpty || url == null || user == null || pass == null) {
    stderr.writeln(
        'usage: davdart list [--status S] [--tag T] | board | show TEXT | add TITLE [BODY] | rm UID\n'
        'config: url, user, password in ~/.config/davdart/credentials '
        '(key=value lines) or DAVDART_URL, DAVDART_USER, DAVDART_PASSWORD');
    exit(2);
  }
  final c =
      CalDavClient(collection: Uri.parse(url), username: user, password: pass);
  try {
    switch (args.first) {
      case 'list':
        // Optional filters: --status WORD, --tag TAG (repeatable).
        String? status;
        final tags = <String>[];
        for (var i = 1; i < args.length - 1; i++) {
          if (args[i] == '--status') status = args[++i].toLowerCase();
          if (args[i] == '--tag') tags.add(args[++i]);
        }
        for (final n in await c.listNotes()) {
          final p = PlanItem.fromNote(n);
          if (status != null && p.status != status) continue;
          if (!tags.every(n.categories.contains)) continue;
          stdout.writeln(
              '${n.uid}\t${p.status ?? "-"}\t${n.categories.join(",")}\t${n.summary}');
        }
      case 'board':
        final cols = <String, List<PlanItem>>{};
        for (final n in await c.listNotes()) {
          final p = PlanItem.fromNote(n);
          (cols[p.status ?? 'no status'] ??= []).add(p);
        }
        const order = ['backlog', 'todo', 'doing', 'blocked', 'done'];
        final keys = [
          ...order.where(cols.containsKey),
          ...cols.keys.where((k) => !order.contains(k)),
        ];
        for (final k in keys) {
          stdout.writeln('\n== $k (${cols[k]!.length})');
          for (final p in cols[k]!) {
            final who = p.owner == null ? '' : '  [${p.owner}]';
            stdout.writeln('  ${p.itemId ?? p.title}$who');
          }
        }
      case 'show':
        if (args.length < 2) {
          stderr.writeln('show needs a uid or title text');
          exit(2);
        }
        final q = args[1].toLowerCase();
        final hits = (await c.listNotes()).where(
            (n) => n.uid == args[1] || n.summary.toLowerCase().contains(q));
        for (final n in hits) {
          stdout.writeln('# ${n.summary}');
          stdout.writeln('uid: ${n.uid}');
          stdout.writeln('categories: ${n.categories.join(", ")}');
          if (n.status != null) stdout.writeln('status: ${n.status}');
          stdout.writeln('\n${n.description}\n');
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
