import 'dart:convert';
import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart/io.dart';
import 'package:http/http.dart' as http;

/// Thin command-line front-end over [ItemService] and [CollectionService].
/// Config: a key=value file (url, user, password) or DAVDART_* environment
/// variables, which win.
Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}

const usageText = '''usage: davdart COMMAND [ARGS] [OPTIONS]
generic commands (a "kind" is note, task or event; ID is a uid, href or exact title):
  overview [--depth N] [--under ID]          compact tree and counts
  list [--kind K|all] [--tag T]... [--status S] [--under ID] [--no-folders] [--limit N] [--offset N]
  get ID [--kind K]
  create TITLE --kind K [--body TEXT|--stdin] [--tags a,b] [--status S] [--under ID] [--folder]
         [--due DATE] [--priority 0-9] [--start WHEN] [--end WHEN] [--location TEXT]
  update ID [--kind K] [--title T] [--body TEXT|--stdin] [--location L] [--start W] [--end W]
  move ID TARGET|top
  move-to ID --to-collection HREF|NAME --backup-dir DIR --allow-admin [--under FOLDER] [--no-subtree]
          [--allow-unreadable]   (copy to another collection, verify, delete originals; use --dry-run first)
  tag ID [--add a,b] [--remove a,b] [--set a,b]
  status ID STATUS|none
  due ID DATE|none            (tasks)
  priority ID N|none          (tasks and notes; notes: high|medium|low or 1/5/9)
  delete ID [--kind K] [--no-adopt]
  collections list | probe [ID] | create NAME [--components VJOURNAL,VTODO,VEVENT]
              | rename ID NAME | delete ID --confirm NAME [--non-empty] [--allow-unreadable] [--backup-dir DIR]
options: --collection HREF|NAME (item commands: another collection under the home; default the configured one),
  --json (machine output), --dry-run (preview a write), --read-only (refuse item writes;
  also DAVDART_READ_ONLY=1), --allow-admin (needed for collections create, rename, delete)
aliases (old output kept): list, board, show TEXT, add TITLE [BODY], new TITLE [--id I --status S
  --owner O --decided-by D --github-ref R --tags a,b --under ID] (body on stdin), set-status MATCH STATUS,
  append MATCH (text on stdin), task TITLE [--tags a,b --status S] (description on stdin),
  folder TITLE [--under MATCH] (text on stdin), export DIR, rm UID
dates: YYYY-MM-DD or YYYY-MM-DDTHH:MM[:SS][Z]
exit codes: 0 ok, 1 failed, 2 usage, 3 refused by an access flag
config: url (the collection), user, password, optional home (calendar home for collections) in
~/.config/davdart/credentials (key=value lines) or DAVDART_URL, DAVDART_USER, DAVDART_PASSWORD, DAVDART_HOME''';

/// Raised for bad arguments (exit 2).
class UsageError implements Exception {
  UsageError(this.message);
  final String message;
}

/// Raised when an access flag forbids the command (exit 3).
class RefusedError implements Exception {
  RefusedError(this.message);
  final String message;
}

const _boolFlags = {
  'json',
  'dry-run',
  'read-only',
  'allow-admin',
  'folder',
  'stdin',
  'no-folders',
  'no-adopt',
  'non-empty',
  'allow-unreadable',
  'no-subtree',
};

/// Parsed command line: positionals, value options (repeatable) and flags.
class Parsed {
  Parsed(this.positional, this.opts, this.flags);
  final List<String> positional;
  final Map<String, List<String>> opts;
  final Set<String> flags;

  String? opt(String k) => opts[k]?.last;
  List<String> all(String k) => opts[k] ?? const [];
  bool flag(String k) => flags.contains(k);

  static Parsed parse(List<String> args) {
    final pos = <String>[];
    final opts = <String, List<String>>{};
    final flags = <String>{};
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a.startsWith('--') && a.length > 2) {
        var k = a.substring(2);
        String? v;
        final eq = k.indexOf('=');
        if (eq > 0) {
          v = k.substring(eq + 1);
          k = k.substring(0, eq);
        }
        if (_boolFlags.contains(k)) {
          if (v != null) throw UsageError('--$k takes no value');
          flags.add(k);
        } else {
          if (v == null) {
            if (i + 1 >= args.length) throw UsageError('--$k needs a value');
            v = args[++i];
          }
          (opts[k] ??= []).add(v);
        }
      } else {
        pos.add(a);
      }
    }
    return Parsed(pos, opts, flags);
  }
}

List<String> _csv(String? s) => (s ?? '')
    .split(',')
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toList();

const _itemWrites = {
  'create', 'update', 'move', 'move-to', 'tag', 'status', 'due', 'priority',
  'delete',
  // aliases
  'add', 'new', 'set-status', 'append', 'task', 'folder', 'rm',
};

/// Runs the CLI and returns the exit code. [config], [env], [out], [err],
/// [readStdin] and [httpClient] are injectable for tests.
Future<int> runCli(
  List<String> args, {
  Map<String, String>? config,
  Map<String, String>? env,
  StringSink? out,
  StringSink? err,
  Future<String> Function()? readStdin,
  http.Client? httpClient,
  String? defaultBackupDir,
}) async {
  final o = out ?? stdout;
  final e = err ?? stderr;
  final environ = env ?? Platform.environment;
  Parsed p;
  try {
    p = Parsed.parse(args);
  } on UsageError catch (x) {
    e.writeln(x.message);
    return 2;
  }
  final json = p.flag('json');
  int fail(int code, String msg) {
    e.writeln(json ? jsonEncode({'error': msg}) : msg);
    return code;
  }

  if (p.positional.isEmpty) {
    e.writeln(usageText);
    return 2;
  }
  final cmd = p.positional.first;
  final rest = p.positional.sublist(1);
  const known = {
    'overview',
    'list',
    'get',
    'collections',
    'board',
    'show',
    'export',
    ..._itemWrites,
  };
  if (!known.contains(cmd)) {
    e.writeln('unknown command $cmd\n$usageText');
    return 2;
  }

  // Access gates, before any network use.
  final ro = p.flag('read-only') ||
      const {'1', 'true', 'yes'}
          .contains((environ['DAVDART_READ_ONLY'] ?? '').toLowerCase());
  final sub = rest.isEmpty ? '' : rest.first;
  final isAdmin = (cmd == 'collections' &&
          const {'create', 'rename', 'delete'}.contains(sub)) ||
      cmd == 'move-to';
  if (_itemWrites.contains(cmd) && ro) {
    return fail(3,
        'refused: read-only mode (--read-only or DAVDART_READ_ONLY=1) forbids "$cmd"');
  }
  if (isAdmin) {
    if (ro) {
      return fail(3, 'refused: read-only mode forbids "$cmd"');
    }
    if (!p.flag('allow-admin')) {
      return fail(3, 'refused: "$cmd" needs --allow-admin');
    }
  }

  final cfg = config ?? loadConfig();
  final url = cfg['url'], user = cfg['user'], pass = cfg['password'];
  if (url == null || user == null || pass == null) {
    e.writeln('$usageText\nmissing url, user or password in the config');
    return 2;
  }

  /// Resolves a collection href or exact name under the home; only a
  /// collection the home lists is reachable.
  Future<Uri> resolveCollection(String want) async {
    final h = cfg['home'] ?? environ['DAVDART_HOME'];
    final base = Uri.parse(url);
    final segs = base.pathSegments.where((s) => s.isNotEmpty).toList();
    final home = h != null && h.isNotEmpty
        ? Uri.parse(h)
        : base.replace(
            path: '/${segs.take(segs.length - 1).join('/')}/', query: null);
    final cs = CollectionService(
        home: home, username: user, password: pass, httpClient: httpClient);
    String sl(String x) => x.endsWith('/') ? x : '$x/';
    final u = cs.home.resolve(want.trim());
    final all = await cs.list();
    var hits = all
        .where((c) =>
            c.href.host == u.host &&
            c.href.port == u.port &&
            sl(c.href.path) == sl(u.path))
        .toList();
    if (hits.isEmpty) hits = all.where((c) => c.name == want.trim()).toList();
    if (hits.isEmpty) {
      throw ItemServiceException(
          'no collection "$want" under the home (see: collections list)');
    }
    if (hits.length > 1) {
      throw ItemServiceException(
          '${hits.length} collections are named "$want"; pass the href');
    }
    return hits.single.href;
  }

  var target = Uri.parse(url);
  final want = p.opt('collection');
  Uri? moveTarget;
  try {
    if (want != null && cmd != 'collections') {
      target = await resolveCollection(want);
    }
    if (cmd == 'move-to') {
      final to = p.opt('to-collection');
      if (to == null) throw UsageError('move-to needs --to-collection');
      moveTarget = await resolveCollection(to);
    }
  } on ItemServiceException catch (x) {
    return fail(1, x.message);
  } on UsageError catch (x) {
    return fail(2, x.message);
  } on CalDavException catch (x) {
    return fail(1, 'server: $x');
  }
  final client = CalDavClient(
      collection: target, username: user, password: pass, client: httpClient);
  final svc = ItemService(client);
  final ctx = _Ctx(
    p: p,
    o: o,
    e: e,
    svc: svc,
    json: json,
    dry: p.flag('dry-run'),
    readStdin: readStdin ??
        () async =>
            (await stdin.transform(const SystemEncoding().decoder).join())
                .trim(),
    client: client,
    cfg: cfg,
    env: environ,
    httpClient: httpClient,
    defaultBackupDir: defaultBackupDir,
    moveTarget: moveTarget,
  );
  try {
    await ctx.run(cmd, rest);
    return 0;
  } on UsageError catch (x) {
    return fail(2, x.message);
  } on RefusedError catch (x) {
    return fail(3, x.message);
  } on ItemServiceException catch (x) {
    return fail(1, x.message);
  } on CollectionSafetyException catch (x) {
    return fail(1, x.message);
  } on CalDavException catch (x) {
    return fail(1, 'server: $x');
  } on FormatException catch (x) {
    return fail(2, x.message);
  } finally {
    // A caller-supplied http client stays open.
    if (httpClient == null) client.close();
  }
}

class _Ctx {
  _Ctx({
    required this.p,
    required this.o,
    required this.e,
    required this.svc,
    required this.json,
    required this.dry,
    required this.readStdin,
    required this.client,
    required this.cfg,
    required this.env,
    required this.httpClient,
    required this.defaultBackupDir,
    this.moveTarget,
  });
  final Parsed p;
  final StringSink o;
  final StringSink e;
  final ItemService svc;
  final bool json;
  final bool dry;
  final Future<String> Function() readStdin;
  final CalDavClient client;
  final Map<String, String> cfg;
  final Map<String, String> env;
  final http.Client? httpClient;
  final String? defaultBackupDir;
  final Uri? moveTarget;

  ItemKind? get kind => p.opt('kind') == null || p.opt('kind') == 'all'
      ? null
      : ItemKind.parse(p.opt('kind')!);

  void emit(Object? j) => o.writeln(jsonEncode(j));

  String _need(List<String> rest, int i, String what) {
    if (rest.length <= i) throw UsageError('${p.positional.first} needs $what');
    return rest[i];
  }

  int _int(String? s, int def, String name) {
    if (s == null) return def;
    return int.tryParse(s) ?? (throw UsageError('--$name needs a number'));
  }

  Future<String?> _body() async {
    if (p.flag('stdin')) return readStdin();
    return p.opt('body');
  }

  /// Resolves [q] to one item: exact uid, href or title through the service,
  /// else (the old CLI habit) a unique title substring or plan item id.
  Future<ItemData> resolve(String q, {ItemKind? kind}) async {
    try {
      return await svc.get(q, kind: kind);
    } on ItemServiceException catch (x) {
      if (!x.message.startsWith('no item matches')) rethrow;
    }
    final low = q.toLowerCase();
    final page = await svc.list(kind: kind, includeFolders: true, limit: 500);
    final hits = page.items.where((i) {
      if (i.title.toLowerCase().contains(low)) return true;
      if (i.kind != ItemKind.note) return false;
      return PlanItem.fromNote(Note(
                  uid: i.uid,
                  summary: i.title,
                  description: i.body,
                  categories: i.tags))
              .itemId ==
          q;
    }).toList();
    if (hits.isEmpty) throw ItemServiceException('no item matches "$q"');
    if (hits.length > 1) {
      throw ItemServiceException(
          '${hits.length} items match "$q": ${hits.map((h) => h.title).join(' | ')}');
    }
    return hits.single;
  }

  /// Prints a write result: JSON, or [text] (plain) / a change summary.
  void done(ItemChange c, String text) {
    if (json) {
      emit(c.toJson());
    } else if (c.dryRun) {
      o.writeln('dry run, nothing changed:');
      for (final ch in c.changes) {
        o.writeln('  $ch');
      }
    } else {
      o.writeln(text);
    }
  }

  String listLine(ItemData i, {required bool withKind}) => [
        i.uid,
        if (withKind) i.kind.name,
        i.status ?? '-',
        i.tags.join(','),
        i.title
      ].join('\t');

  void showItem(ItemData i) {
    o.writeln('# ${i.title}');
    o.writeln('uid: ${i.uid}');
    o.writeln('kind: ${i.kind.name}');
    o.writeln('categories: ${i.tags.join(", ")}');
    if (i.status != null) o.writeln('status: ${i.status}');
    if (i.parentUid != null) o.writeln('parent: ${i.parentUid}');
    if (i.due != null) o.writeln('due: ${i.due}');
    if (i.priority != null) o.writeln('priority: ${i.priority}');
    if (i.start != null) o.writeln('start: ${i.start}');
    if (i.end != null) o.writeln('end: ${i.end}');
    if (i.location != null && i.location!.isNotEmpty) {
      o.writeln('location: ${i.location}');
    }
    o.writeln('\n${i.body}\n');
  }

  void tree(List<OverviewNode> nodes, int depth) {
    for (final n in nodes) {
      final tag = n.folder ? '[folder] ' : '';
      final st = n.status == null ? '' : ' (${n.status})';
      o.writeln(
          '${'  ' * depth}$tag${n.title}$st  ${n.kind.name} ${n.uid}${n.hiddenChildren > 0 ? '  +${n.hiddenChildren} more' : ''}');
      tree(n.children, depth + 1);
    }
  }

  static String _today() {
    final d = DateTime.now();
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${t(d.day)}';
  }

  /// Old plan-item behaviour: bump the `updated` header after a change.
  Future<void> bumpUpdated(ItemData i) async {
    if (i.kind != ItemKind.note || dry) return;
    final fresh = await svc.get(i.uid, kind: ItemKind.note);
    final n = Note(
        uid: fresh.uid,
        summary: fresh.title,
        description: fresh.body,
        categories: List.of(fresh.tags));
    final pi = PlanItem.fromNote(n);
    if (pi.fields.isEmpty) return;
    pi.setField('updated', _today());
    pi.apply();
    if (n.description != fresh.body) {
      await svc.update(fresh.uid, kind: ItemKind.note, body: n.description);
    }
  }

  Future<void> run(String cmd, List<String> rest) async {
    switch (cmd) {
      case 'overview':
        final ov = await svc.overview(
            maxDepth: _int(p.opt('depth'), 2, 'depth'), under: p.opt('under'));
        if (json) {
          emit(ov.toJson());
        } else {
          o.writeln(
              '${ov.total} items  kinds ${ov.byKind}  status ${ov.byStatus}');
          if (ov.byTag.isNotEmpty) o.writeln('tags ${ov.byTag}');
          tree(ov.roots, 0);
        }
      case 'list':
        // Old default: notes only, folders included.
        final noKind = p.opt('kind') == null;
        final k = noKind ? ItemKind.note : kind;
        final tags = p.all('tag');
        final page = await svc.list(
            kind: k,
            tag: tags.isEmpty ? null : tags.first,
            status: p.opt('status'),
            under: p.opt('under'),
            includeFolders: !p.flag('no-folders'),
            limit: _int(p.opt('limit'), 50, 'limit'),
            offset: _int(p.opt('offset'), 0, 'offset'));
        // More than one --tag: all must match (filtered after paging is
        // wrong, so re-query unpaged).
        var shown = page;
        if (tags.length > 1) {
          final big = await svc.list(
              kind: k,
              tag: tags.first,
              status: p.opt('status'),
              under: p.opt('under'),
              includeFolders: !p.flag('no-folders'),
              limit: 500);
          final items =
              big.items.where((i) => tags.every(i.tags.contains)).toList();
          final off = _int(p.opt('offset'), 0, 'offset');
          final lim = _int(p.opt('limit'), 50, 'limit');
          shown = ItemPage(
              items.skip(off).take(lim).toList(), items.length, off, lim);
        }
        if (json) {
          emit(shown.toJson());
        } else {
          for (final i in shown.items) {
            o.writeln(listLine(i, withKind: k != ItemKind.note));
          }
          if (shown.hasMore) {
            e.writeln(
                '# ${shown.total - shown.offset - shown.items.length} more: use --offset ${shown.offset + shown.items.length}');
          }
        }
      case 'get':
        final it = await resolve(_need(rest, 0, 'an ID'), kind: kind);
        if (json) {
          emit(it.toJson());
        } else {
          showItem(it);
        }
      case 'show':
        final q = _need(rest, 0, 'a uid or title text').toLowerCase();
        final page = await svc.list(
            kind: ItemKind.note, includeFolders: true, limit: 500);
        final hits = page.items
            .where((i) => i.uid == rest[0] || i.title.toLowerCase().contains(q))
            .toList();
        if (json) {
          emit([for (final h in hits) h.toJson()]);
        } else {
          hits.forEach(showItem);
        }
      case 'create':
        final title = _need(rest, 0, 'a TITLE');
        final k = p.opt('kind') == null
            ? (p.flag('folder') ? ItemKind.note : null)
            : kind;
        if (k == null) throw UsageError('create needs --kind note|task|event');
        final c = await svc.create(k, title,
            body: await _body() ?? '',
            tags: _csv(p.opt('tags')),
            status: p.opt('status'),
            parent: p.opt('under'),
            folder: p.flag('folder'),
            due: p.opt('due'),
            priority: p.opt('priority') == null
                ? null
                : _int(p.opt('priority'), 0, 'priority'),
            start: p.opt('start'),
            end: p.opt('end'),
            location: p.opt('location'),
            dryRun: dry);
        done(c, 'created ${c.item.kind.name} ${c.item.uid}');
      case 'update':
        final it = await resolve(_need(rest, 0, 'an ID'), kind: kind);
        final c = await svc.update(it.uid,
            kind: it.kind,
            title: p.opt('title'),
            body: await _body(),
            location: p.opt('location'),
            start: p.opt('start'),
            end: p.opt('end'),
            dryRun: dry);
        done(c, c.changes.isEmpty ? 'no change' : 'updated ${c.item.uid}');
      case 'move':
        final it = await resolve(_need(rest, 0, 'an ID'), kind: kind);
        final t = _need(rest, 1, 'a TARGET (an item, or "top")');
        final target = t == 'top' ? null : await resolve(t);
        final c = await svc.move(it.uid, target?.uid, dryRun: dry);
        done(c, '${it.title}: now under ${target?.title ?? 'top'}');
      case 'move-to':
        final id = _need(rest, 0, 'an ID');
        final dir = p.opt('backup-dir');
        if (!dry && (dir == null || dir.isEmpty)) {
          throw UsageError('move-to needs --backup-dir DIR');
        }
        final tsvc = ItemService(CalDavClient(
            collection: moveTarget!,
            username: cfg['user']!,
            password: cfg['password']!,
            client: httpClient));
        try {
          final r = await svc.moveToCollection(tsvc, id,
              under: p.opt('under'),
              subtree: !p.flag('no-subtree'),
              backupDir: dir,
              allowUnreadable: p.flag('allow-unreadable'),
              dryRun: dry);
          if (json) {
            emit(r.toJson());
          } else {
            if (r.dryRun) o.writeln('dry run, nothing changed:');
            for (final l in r.plan) {
              o.writeln('  $l');
            }
            if (!r.dryRun) {
              o.writeln('moved ${r.entries.length} item(s); backup: '
                  '${r.backupPath}');
              o.writeln('old uid\tnew uid');
              for (final x in r.entries) {
                o.writeln('${x.oldUid}\t${x.newUid}');
              }
            }
          }
        } finally {
          if (httpClient == null) tsvc.client.close();
        }
      case 'tag':
        final it = await resolve(_need(rest, 0, 'an ID'), kind: kind);
        final c = await svc.setTags(it.uid,
            kind: it.kind,
            set: p.opt('set') == null ? null : _csv(p.opt('set')),
            add: _csv(p.opt('add')),
            remove: _csv(p.opt('remove')),
            dryRun: dry);
        done(c, 'tags: ${c.item.tags.join(',')}');
      case 'status':
        final it = await resolve(_need(rest, 0, 'an ID'), kind: kind);
        final w = _need(rest, 1, 'a STATUS (or "none")');
        final c = await svc.setStatus(it.uid, w == 'none' ? null : w,
            kind: it.kind, dryRun: dry);
        done(c, '${it.title}: status ${c.item.status ?? '-'}');
      case 'set-status':
        final it = await resolve(_need(rest, 0, 'MATCH'));
        final w = _need(rest, 1, 'STATUS');
        final c = await svc.setStatus(it.uid, w, kind: it.kind, dryRun: dry);
        if (!dry) await bumpUpdated(it);
        done(c, '${it.title}: status $w');
      case 'due':
        final it = await resolve(_need(rest, 0, 'an ID'), kind: ItemKind.task);
        final v = _need(rest, 1, 'a DATE (or "none")');
        final c = await svc.setDue(it.uid, v == 'none' ? null : v, dryRun: dry);
        done(c, '${it.title}: due ${c.item.due ?? '-'}');
      case 'priority':
        final it = await resolve(_need(rest, 0, 'an ID'), kind: kind);
        final v = _need(rest, 1, 'a number 0-9, high|medium|low (or "none")');
        final c = await svc.setPriority(
            it.uid,
            v == 'none'
                ? null
                : (notePriorities[v.toLowerCase()] ?? _int(v, 0, 'priority')),
            kind: it.kind,
            dryRun: dry);
        done(c, '${it.title}: priority ${c.item.priority ?? '-'}');
      case 'delete':
        final it = await resolve(_need(rest, 0, 'an ID'), kind: kind);
        final c = await svc.delete(it.uid,
            kind: it.kind, adoptChildren: !p.flag('no-adopt'), dryRun: dry);
        done(c, 'deleted ${it.uid}');
      case 'rm':
        final uid = _need(rest, 0, 'a uid');
        final hit = (await svc.list(
                kind: ItemKind.note, includeFolders: true, limit: 500))
            .items
            .where((i) => i.uid == uid)
            .firstOrNull;
        if (hit == null) throw ItemServiceException('no note $uid');
        final c = await svc.delete(uid,
            kind: ItemKind.note, adoptChildren: false, dryRun: dry);
        done(c, 'deleted $uid');
      case 'add':
        final c = await svc.create(ItemKind.note, _need(rest, 0, 'a title'),
            body: rest.length > 1 ? rest[1] : '', dryRun: dry);
        done(c, 'created ${c.item.uid}');
      case 'new':
        final body = await readStdin();
        final rawStatus = p.opt('status');
        final status = rawStatus == null ? null : canonicalStatus(rawStatus);
        if (rawStatus != null && status == null) {
          throw ItemServiceException('unknown status "$rawStatus"; '
              'allowed: ${allowedStatuses.join(', ')}');
        }
        final under = p.opt('under');
        final parent = under == null ? null : (await resolve(under)).uid;
        final tmp =
            Note(uid: 'tmp', summary: _need(rest, 0, 'a TITLE'), categories: [
          ..._csv(p.opt('tags')),
          if (status != null) 'status-$status',
        ]);
        final pi = PlanItem.fromNote(tmp);
        if (p.opt('id') != null) {
          pi
            ..setField('item_id', p.opt('id')!)
            ..setField('status', status ?? 'backlog')
            ..setField('owner', p.opt('owner') ?? '')
            ..setField('decided_by', p.opt('decided-by') ?? '')
            ..setField('github_ref', p.opt('github-ref') ?? '(none)')
            ..setField('created', _today())
            ..setField('updated', _today());
        }
        pi.text = body;
        pi.apply();
        final c = await svc.create(ItemKind.note, tmp.summary,
            body: tmp.description,
            tags: tmp.categories,
            parent: parent,
            dryRun: dry);
        done(c, 'created ${c.item.uid}');
      case 'append':
        final it = await resolve(_need(rest, 0, 'MATCH'));
        final text = await readStdin();
        final n = Note(
            uid: it.uid,
            summary: it.title,
            description: it.body,
            categories: List.of(it.tags));
        final pi = PlanItem.fromNote(n);
        pi.text = pi.text.trimRight().isEmpty
            ? text
            : '${pi.text.trimRight()}\n\n$text';
        if (pi.fields.isNotEmpty) pi.setField('updated', _today());
        pi.apply();
        final c = await svc.update(it.uid,
            kind: it.kind, body: n.description, dryRun: dry);
        done(c, '${it.title}: appended ${text.length} chars');
      case 'task':
        if (rest.isEmpty || rest.first.startsWith('--')) {
          throw UsageError('task needs a TITLE first; description on stdin');
        }
        final c = await svc.create(ItemKind.task, rest.first,
            body: await readStdin(),
            tags: _csv(p.opt('tags')),
            status: p.opt('status'),
            dryRun: dry);
        done(c, 'created task ${c.item.uid}');
      case 'folder':
        final text = await readStdin();
        final c = await svc.create(ItemKind.note, _need(rest, 0, 'a TITLE'),
            body: text,
            folder: true,
            parent: p.opt('under') == null
                ? null
                : (await resolve(p.opt('under')!)).uid,
            dryRun: dry);
        done(c, 'folder ${c.item.uid}');
      case 'board':
        final page = await svc.list(
            kind: ItemKind.note, includeFolders: false, limit: 500);
        final cols = <String, List<PlanItem>>{};
        for (final i in page.items) {
          final pi = PlanItem.fromNote(Note(
              uid: i.uid,
              summary: i.title,
              description: i.body,
              categories: List.of(i.tags)));
          (cols[pi.status ?? 'no status'] ??= []).add(pi);
        }
        const order = allowedStatuses;
        final keys = [
          ...order.where(cols.containsKey),
          ...cols.keys.where((k) => !order.contains(k)),
        ];
        for (final k in keys) {
          o.writeln('\n== $k (${cols[k]!.length})');
          for (final pi in cols[k]!) {
            final who = pi.owner == null ? '' : '  [${pi.owner}]';
            o.writeln('  ${pi.itemId ?? pi.title}$who');
          }
        }
      case 'export':
        final dir = _need(rest, 0, 'a directory');
        Directory(dir).createSync(recursive: true);
        var count = 0;
        for (final n in await client.listNotes()) {
          File('$dir/${Uri.encodeComponent(n.uid)}.ics')
              .writeAsStringSync(serializeNote(n));
          count++;
        }
        o.writeln('exported $count notes to $dir');
      case 'collections':
        await collections(rest);
    }
  }

  Uri get _home {
    final h = cfg['home'] ?? env['DAVDART_HOME'];
    if (h != null && h.isNotEmpty) return Uri.parse(h);
    final base = Uri.parse(cfg['url']!);
    final segs = base.pathSegments.where((s) => s.isNotEmpty).toList();
    return base.replace(
        path: '/${segs.take(segs.length - 1).join('/')}/', query: null);
  }

  Future<void> collections(List<String> rest) async {
    final sub = rest.isEmpty ? 'list' : rest.first;
    final cs = CollectionService(
        home: _home,
        username: cfg['user']!,
        password: cfg['password']!,
        httpClient: httpClient);
    Future<CollectionInfo> find(String q) async {
      final all = await cs.list();
      String id(CollectionInfo c) =>
          c.href.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
      final hits = all
          .where((c) => id(c) == q || c.href.toString() == q || c.name == q)
          .toList();
      if (hits.isEmpty) throw ItemServiceException('no collection "$q"');
      if (hits.length > 1) {
        throw ItemServiceException(
            '${hits.length} collections match "$q"; use the id');
      }
      return hits.single;
    }

    void change(CollectionChange c, String text) {
      if (json) {
        emit(c.toJson());
      } else if (c.dryRun) {
        o.writeln('dry run, nothing changed:');
        for (final ch in c.changes) {
          o.writeln('  $ch');
        }
      } else {
        o.writeln(text);
      }
    }

    switch (sub) {
      case 'list':
        final all = await cs.list();
        if (json) {
          emit([
            for (final c in all)
              {
                'id': c.href.pathSegments.where((s) => s.isNotEmpty).last,
                'name': c.name,
                'href': c.href.toString(),
                'notes': c.holdsNotes,
                'tasks': c.holdsTasks,
                'events': c.holdsEvents,
              }
          ]);
        } else {
          for (final c in all) {
            o.writeln(
                '${c.href.pathSegments.where((s) => s.isNotEmpty).last}\t${c.name}');
          }
        }
      case 'probe':
        final href = rest.length > 1
            ? (await find(rest[1])).href
            : Uri.parse(cfg['url']!);
        final cap = await cs.probe(href);
        if (json) {
          emit(cap.toJson());
        } else {
          cap.toJson().forEach((k, v) => o.writeln('$k: $v'));
        }
      case 'create':
        final name = _need(rest, 1, 'a NAME');
        final comps = p.opt('components') == null
            ? const ['VJOURNAL', 'VTODO', 'VEVENT']
            : _csv(p.opt('components')).map((s) => s.toUpperCase()).toList();
        final c = await cs.create(name, components: comps, dryRun: dry);
        change(c, 'created collection ${c.href}');
      case 'rename':
        final info = await find(_need(rest, 1, 'a collection ID'));
        final c = await cs.rename(info.href, _need(rest, 2, 'a new NAME'),
            dryRun: dry);
        change(c, 'renamed ${info.name}');
      case 'delete':
        final info = await find(_need(rest, 1, 'a collection ID'));
        final confirm = p.opt('confirm');
        if (confirm == null) {
          throw UsageError(
              'collections delete needs --confirm "<exact collection name>"');
        }
        final dir = p.opt('backup-dir') ??
            env['DAVDART_BACKUP_DIR'] ??
            defaultBackupDir ??
            '${env['HOME']}/.local/share/davdart/backups';
        final c = await cs.delete(info.href,
            confirmName: confirm,
            backupDir: dir,
            allowNonEmpty: p.flag('non-empty'),
            allowUnreadable: p.flag('allow-unreadable'),
            dryRun: dry);
        change(
            c,
            'deleted collection ${info.name}'
            '${c.backupPath == null ? '' : ' (backup: ${c.backupPath})'}');
      default:
        throw UsageError('collections: unknown subcommand "$sub"');
    }
  }
}
