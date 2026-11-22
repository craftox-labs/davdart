import 'dart:io';
import 'dart:math';

import 'package:davdart/davdart.dart';
import 'package:davdart/io.dart';

/// Minimal CLI. Config: a key=value file (url, user, password) or DAVDART_*
/// environment variables, which win. Commands: list, add TITLE [BODY], rm UID.
Future<void> main(List<String> args) async {
  final cfg = loadConfig();
  final url = cfg['url'];
  final user = cfg['user'];
  final pass = cfg['password'];
  if (args.isEmpty || url == null || user == null || pass == null) {
    stderr.writeln(
        'usage: davdart list [--status S] [--tag T] | board | show TEXT | add TITLE [BODY] | new TITLE [--id I --status S --owner O --decided-by D --github-ref R --tags a,b] (body on stdin) | set-status MATCH STATUS | append MATCH (text on stdin) | task TITLE [--tags a,b --status S] (description on stdin) | folder TITLE [--under MATCH] (text on stdin) | move MATCH TARGET|top | export DIR | rm UID\n'
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
          if (isViewNote(n)) continue; // saved views are not items
          final p = PlanItem.fromNote(n);
          if (status != null && p.status != status) continue;
          if (!tags.every(n.categories.contains)) continue;
          stdout.writeln(
              '${n.uid}\t${p.status ?? "-"}\t${n.categories.join(",")}\t${n.summary}');
        }
      case 'board':
        final cols = <String, List<PlanItem>>{};
        for (final n in await c.listNotes()) {
          if (isStructuralNote(n)) continue; // folders and saved views
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
      case 'export':
        if (args.length < 2) {
          stderr.writeln('export needs a directory');
          exit(2);
        }
        Directory(args[1]).createSync(recursive: true);
        var count = 0;
        for (final n in await c.listNotes()) {
          File('${args[1]}/${Uri.encodeComponent(n.uid)}.ics')
              .writeAsStringSync(serializeNote(n));
          count++;
        }
        stdout.writeln('exported $count notes to ${args[1]}');
      case 'set-status':
        if (args.length < 3) {
          stderr.writeln('set-status needs MATCH and STATUS');
          exit(2);
        }
        final n = await _one(c, args[1]);
        final p = PlanItem.fromNote(n)
          ..setStatus(args[2])
          ..setField('updated', _today());
        p.apply();
        await c.putNote(n);
        stdout.writeln('${n.summary}: status ${args[2]}');
      case 'append':
        if (args.length < 2) {
          stderr.writeln('append needs MATCH; text on stdin');
          exit(2);
        }
        final text =
            (await stdin.transform(const SystemEncoding().decoder).join())
                .trim();
        final n = await _one(c, args[1]);
        final p = PlanItem.fromNote(n);
        p.text = p.text.trimRight().isEmpty
            ? text
            : '${p.text.trimRight()}\n\n$text';
        if (p.fields.isNotEmpty) p.setField('updated', _today());
        p.apply();
        await c.putNote(n);
        stdout.writeln('${n.summary}: appended ${text.length} chars');
      case 'new':
        if (args.length < 2) {
          stderr.writeln('new needs a TITLE; body on stdin');
          exit(2);
        }
        String? opt(String k) {
          final i = args.indexOf('--$k');
          return i > 0 && i + 1 < args.length ? args[i + 1] : null;
        }

        final body =
            (await stdin.transform(const SystemEncoding().decoder).join())
                .trim();
        final now = DateTime.now();
        final status = opt('status');
        final parent =
            opt('under') == null ? null : await _one(c, opt('under')!);
        final note = Note(
          parentUid: parent?.uid,
          uid:
              '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}@davdart',
          summary: args[1],
          categories: [
            ...(opt('tags') ?? '').split(',').where((t) => t.isNotEmpty),
            if (status != null) 'status-$status',
          ],
          created: now,
          lastModified: now,
        );
        final p = PlanItem.fromNote(note);
        if (opt('id') != null) {
          p
            ..setField('item_id', opt('id')!)
            ..setField('status', status ?? 'backlog')
            ..setField('owner', opt('owner') ?? '')
            ..setField('decided_by', opt('decided-by') ?? '')
            ..setField('github_ref', opt('github-ref') ?? '(none)')
            ..setField('created', _today())
            ..setField('updated', _today());
        }
        p.text = body;
        p.apply();
        final saved = await c.putNote(note);
        stdout.writeln('created ${saved.uid}');
      case 'task':
        if (args.length < 2) {
          stderr.writeln('task needs a TITLE; description on stdin');
          exit(2);
        }
        String? topt(String k) {
          final i = args.indexOf('--$k');
          return i > 0 && i + 1 < args.length ? args[i + 1] : null;
        }

        final desc =
            (await stdin.transform(const SystemEncoding().decoder).join())
                .trim();
        final tnow = DateTime.now();
        final tstatus = topt('status');
        final task = await c.putTask(Task(
          uid:
              '${tnow.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}@davdart',
          summary: args[1],
          description: desc,
          categories: [
            ...(topt('tags') ?? '').split(',').where((t) => t.isNotEmpty),
            if (tstatus != null) 'status-$tstatus',
          ],
          status: 'NEEDS-ACTION',
          created: tnow,
          lastModified: tnow,
        ));
        stdout.writeln('created task ${task.uid}');
      case 'folder':
        if (args.length < 2) {
          stderr.writeln('folder needs a TITLE; text on stdin');
          exit(2);
        }
        final ftext =
            (await stdin.transform(const SystemEncoding().decoder).join())
                .trim();
        final fi = args.indexOf('--under');
        final fparent =
            fi > 0 && fi + 1 < args.length ? await _one(c, args[fi + 1]) : null;
        final fnow = DateTime.now();
        final folder = Note(
          uid:
              '${fnow.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}@davdart',
          summary: args[1],
          description: ftext,
          categories: ['kind-folder'],
          parentUid: fparent?.uid,
          created: fnow,
          lastModified: fnow,
        );
        final fsaved = await c.putNote(folder);
        stdout.writeln('folder ${fsaved.uid}');
      case 'move':
        if (args.length < 3) {
          stderr.writeln('move needs MATCH and TARGET (a note, or "top")');
          exit(2);
        }
        final mv = await _one(c, args[1]);
        final target = args[2] == 'top' ? null : await _one(c, args[2]);
        final tree = NoteTree.build(await c.listNotes());
        if (!tree.canMove(mv.uid, target?.uid)) {
          stderr.writeln('cannot move ${mv.summary} there');
          exit(1);
        }
        final moved = mv.copyWith(
          parentUid: target?.uid,
          clearParent: target == null,
        );
        await c.putNote(moved);
        stdout.writeln('${mv.summary}: now under ${target?.summary ?? 'top'}');
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

String _today() {
  final d = DateTime.now();
  String t(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${t(d.month)}-${t(d.day)}';
}

/// The one note whose uid equals [q] or whose title contains it (case-blind).
Future<Note> _one(CalDavClient c, String q) async {
  final low = q.toLowerCase();
  final hits = (await c.listNotes())
      .where((n) =>
          n.uid == q ||
          PlanItem.fromNote(n).itemId == q ||
          n.summary.toLowerCase().contains(low))
      .toList();
  if (hits.length != 1) {
    stderr.writeln(hits.isEmpty
        ? 'no note matches "$q"'
        : '${hits.length} notes match "$q": ${hits.map((n) => n.summary).join(' | ')}');
    exit(1);
  }
  return hits.single;
}
