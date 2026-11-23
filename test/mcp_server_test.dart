import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart/mcp_server.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'support/fake_caldav.dart';
import 'support/fake_dav_server.dart';

const _token = 'tok-secret-123';

class _Env {
  _Env(this.fake) {
    final http = withHome(fake);
    items = ItemService(CalDavClient(
        collection: FakeCalDav.collection,
        username: 'u',
        password: 'p',
        client: http));
    collections = CollectionService(
        home: Uri.parse('https://fake.test/dav/'),
        username: 'u',
        password: 'p',
        httpClient: http);
  }
  final FakeCalDav fake;
  late final ItemService items;
  late final CollectionService collections;

  McpServer server(Set<ToolGroup> g, {String? backup}) => buildMcpServer(
      items: items, collections: collections, groups: g, backupDir: backup);
}

/// Connects a client to [server] over in-memory pipes.
Future<McpClient> connect(McpServer server) async {
  final c2s = StreamController<List<int>>();
  final s2c = StreamController<List<int>>();
  await server.connect(IOStreamTransport(stream: c2s.stream, sink: s2c.sink));
  final client = McpClient(const Implementation(name: 't', version: '1'));
  await client.connect(IOStreamTransport(stream: s2c.stream, sink: c2s.sink));
  addTearDown(() async {
    await client.close();
    await server.close();
  });
  return client;
}

Future<List<String>> toolNames(McpClient c) async =>
    ((await c.listTools()).tools.map((t) => t.name).toList()..sort());

Future<(bool, dynamic)> call(McpClient c, String name,
    [Map<String, dynamic> args = const {}]) async {
  final r = await c.callTool(CallToolRequest(name: name, arguments: args));
  final text = (r.content.single as TextContent).text;
  return (r.isError, r.isError ? text : jsonDecode(text));
}

void main() {
  late _Env env;
  setUp(() => env = _Env(FakeCalDav()));

  group('tool listing', () {
    test('read group', () async {
      final c = await connect(env.server({ToolGroup.read}));
      expect(await toolNames(c), ['collections', 'get', 'list', 'overview']);
    });
    test('write group', () async {
      final c = await connect(env.server({ToolGroup.write}));
      expect(await toolNames(c), ['create', 'move', 'update']);
    });
    test('delete group is only delete', () async {
      final c = await connect(env.server({ToolGroup.delete}));
      expect(await toolNames(c), ['delete']);
    });
    test('read,write cannot delete', () async {
      final c = await connect(env.server({ToolGroup.read, ToolGroup.write}));
      expect(await toolNames(c), [
        'collections',
        'create',
        'get',
        'list',
        'move',
        'overview',
        'update'
      ]);
      await expectLater(call(c, 'delete', {'id': 'x'}), throwsA(anything));
    });
    test('history tool only with a history log', () async {
      final f =
          File('${Directory.systemTemp.createTempSync('h').path}/h.jsonl');
      final c = await connect(buildMcpServer(
          items: env.items,
          groups: {ToolGroup.read},
          history: HistoryLog(f.path)));
      expect(await toolNames(c),
          ['collections', 'get', 'history', 'list', 'overview']);
      expect(f.existsSync(), isTrue);
    });
    test('admin group needs a backup dir', () {
      expect(() => env.server({ToolGroup.admin}), throwsArgumentError);
      expect(() => env.server({ToolGroup.admin}, backup: '/tmp/x'),
          returnsNormally);
    });
    test('all groups give eight tools', () async {
      final c = await connect(env.server(ToolGroup.values.toSet(),
          backup: Directory.systemTemp.path));
      expect(await toolNames(c), [
        'collections',
        'create',
        'delete',
        'get',
        'list',
        'move',
        'overview',
        'update'
      ]);
    });
    test('group parsing', () {
      expect(ToolGroup.parse('read, write'), {ToolGroup.read, ToolGroup.write});
      expect(ToolGroup.parse('read,write,delete'),
          {ToolGroup.read, ToolGroup.write, ToolGroup.delete});
      expect(() => ToolGroup.parse('root'), throwsFormatException);
    });
  });

  group('collection argument', () {
    late FakeCalDav other;
    late McpServer Function(Set<ToolGroup>) make;
    setUp(() {
      other = FakeCalDav();
      final h = multiHome(env.fake, other);
      final items = ItemService(CalDavClient(
          collection: FakeCalDav.collection,
          username: 'u',
          password: 'p',
          client: h));
      final cs = CollectionService(
          home: Uri.parse('https://fake.test/dav/'),
          username: 'u',
          password: 'p',
          httpClient: h);
      make = (g) => buildMcpServer(items: items, collections: cs, groups: g);
    });

    test('omitted: the configured collection, unchanged', () async {
      final c = await connect(
          make({ToolGroup.read, ToolGroup.write, ToolGroup.delete}));
      final (e, _) = await call(c, 'create', {'kind': 'note', 'title': 'A'});
      expect(e, isFalse);
      expect(env.fake.ics, hasLength(1));
      expect(other.ics, isEmpty);
      final (_, l) = await call(c, 'list');
      expect(l['items'], hasLength(1));
    });

    test('a second collection by name and by href', () async {
      final c = await connect(
          make({ToolGroup.read, ToolGroup.write, ToolGroup.delete}));
      var (e, r) = await call(
          c, 'create', {'collection': 'Other', 'kind': 'note', 'title': 'B'});
      expect(e, isFalse, reason: '$r');
      expect(other.ics, hasLength(1));
      expect(env.fake.ics, isEmpty);
      (e, r) = await call(c, 'list', {'collection': '/dav/d/'});
      expect(e, isFalse, reason: '$r');
      expect(r['items'].single['title'], 'B');
      (e, r) = await call(c, 'list', {'collection': 'https://fake.test/dav/d'});
      expect(r['items'], hasLength(1));
      (e, r) = await call(c, 'overview', {'collection': 'Other'});
      expect(e, isFalse, reason: '$r');
      (e, r) = await call(c, 'get', {'collection': 'Other', 'id': 'B'});
      expect(r['title'], 'B');
      (e, r) = await call(c, 'update', {
        'collection': 'Other',
        'id': 'B',
        'tags_add': ['x']
      });
      expect(e, isFalse, reason: '$r');
      (e, r) = await call(c, 'move', {'collection': 'Other', 'id': 'B'});
      expect(e, isFalse, reason: '$r');
      (e, r) = await call(c, 'delete', {'collection': 'Other', 'id': 'B'});
      expect(e, isFalse, reason: '$r');
      expect(other.ics, isEmpty);
    });

    test('the configured collection by name reaches the same data', () async {
      final c = await connect(
          make({ToolGroup.read, ToolGroup.write, ToolGroup.delete}));
      await call(c, 'create', {'kind': 'note', 'title': 'A'});
      final (_, l) = await call(c, 'list', {'collection': 'Work'});
      expect(l['items'], hasLength(1));
    });

    test('unknown or escaping collections are refused', () async {
      final c = await connect(
          make({ToolGroup.read, ToolGroup.write, ToolGroup.delete}));
      for (final bad in [
        'Nope',
        'other',
        '/dav/x/',
        '../etc/',
        '/dav/d/../x/',
        'https://evil.test/dav/d/',
        'http://fake.test:8080/dav/d/',
        '//evil.test/dav/d/',
      ]) {
        final (e, m) = await call(c, 'list', {'collection': bad});
        expect(e, isTrue, reason: bad);
        expect(m, contains('no collection'), reason: bad);
      }
      final (e, _) = await call(
          c, 'create', {'collection': 'Nope', 'kind': 'note', 'title': 'x'});
      expect(e, isTrue);
      expect(env.fake.ics, isEmpty);
      expect(other.ics, isEmpty);
    });

    test('a collection that does not hold the kind gives a clear error',
        () async {
      final c = await connect(
          make({ToolGroup.read, ToolGroup.write, ToolGroup.delete}));
      final (e, m) = await call(c, 'create', {
        'collection': 'Todos',
        'kind': 'event',
        'title': 'x',
        'start': '2026-01-01'
      });
      expect(e, isTrue);
      expect(m, contains('does not hold events'));
      expect(m, contains('tasks'));
      expect(other.ics, isEmpty);
    });

    test('read-only and tool groups are unaffected', () async {
      final c = await connect(make({ToolGroup.read}));
      expect(await toolNames(c), ['collections', 'get', 'list', 'overview']);
      await expectLater(
          call(c, 'create',
              {'collection': 'Other', 'kind': 'note', 'title': 'x'}),
          throwsA(anything));
      expect(other.ics, isEmpty);
      final tools = (await c.listTools()).tools;
      for (final t in tools.where((t) => t.name != 'collections')) {
        expect(t.inputSchema.toJson()['properties'], contains('collection'));
        expect(t.description, contains('collections tool'));
      }
    });
  });

  group('read-only refusal', () {
    late McpClient c;
    setUp(() async => c = await connect(env.server({ToolGroup.read})));

    test('write tools are not served', () async {
      await expectLater(
          call(c, 'create', {'kind': 'note', 'title': 'x'}), throwsA(anything));
      expect(env.fake.ics, isEmpty);
    });
    test('collections admin actions are refused with a clear message',
        () async {
      for (final a in ['create', 'rename', 'delete']) {
        final (err, msg) = await call(c, 'collections',
            {'action': a, 'name': 'n', 'href': 'c/', 'new_name': 'n'});
        expect(err, isTrue);
        expect(msg, contains('not enabled'));
      }
      expect(env.fake.log.where((l) => l.startsWith('DELETE')), isEmpty);
    });
    test('collections list works', () async {
      final (err, out) = await call(c, 'collections', {'action': 'list'});
      expect(err, isFalse);
      expect(out['collections'].single['name'], 'Work');
    });
  });

  group('tools end to end', () {
    late McpClient c;
    setUp(() async => c = await connect(env.server({
          ToolGroup.read,
          ToolGroup.write,
          ToolGroup.delete,
        })));

    test('create, list, get, update, move, delete', () async {
      var (err, f) = await call(
          c, 'create', {'kind': 'note', 'title': 'Folder', 'folder': true});
      expect(err, isFalse, reason: '$f');
      (err, _) = await call(c, 'create', {
        'kind': 'task',
        'title': 'Do it',
        'tags': ['a'],
        'parent': 'Folder'
      });
      expect(err, isFalse);
      var (_, page) = await call(c, 'list', {'kind': 'task'});
      expect(page['total'], 1);
      expect(page['items'].single.containsKey('body'), isFalse);

      (err, _) = await call(c, 'update', {
        'id': 'Do it',
        'status': 'doing',
        'tags_add': ['b'],
        'due': '2026-12-24',
        'priority': 2,
        'body': 'details',
      });
      expect(err, isFalse);
      var (_, t) = await call(c, 'get', {'id': 'Do it'});
      expect(t['status'], 'doing');
      expect(t['tags'], containsAll(['a', 'b']));
      expect(t['due'], '20261224');
      expect(t['priority'], 2);
      expect(t['body'], 'details');

      (err, _) = await call(c, 'move', {'id': 'Do it', 'parent': 'top'});
      expect(err, isFalse);
      (_, t) = await call(c, 'get', {'id': 'Do it'});
      expect(t.containsKey('parent'), isFalse);

      var (_, o) = await call(c, 'overview');
      expect(o['total'], 2);

      var (_, d) = await call(c, 'delete', {'id': 'Do it', 'dry_run': true});
      expect(d['dryRun'], isTrue);
      (_, d) = await call(c, 'delete', {'id': 'Do it'});
      expect(d['dryRun'], isFalse);
      (_, page) = await call(c, 'list', {'kind': 'task'});
      expect(page['total'], 0);
    });

    test('pagination', () async {
      for (var i = 0; i < 3; i++) {
        await call(c, 'create', {'kind': 'note', 'title': 'n$i'});
      }
      final (_, p) = await call(c, 'list', {'limit': 2});
      expect(p['items'], hasLength(2));
      expect(p['hasMore'], isTrue);
      final (_, q) = await call(c, 'list', {'limit': 2, 'offset': 2});
      expect(q['items'], hasLength(1));
      expect(q['hasMore'], isFalse);
    });

    test('clear errors', () async {
      var (err, m) = await call(c, 'get', {'id': 'nope'});
      expect(err, isTrue);
      expect(m, contains('no item matches "nope"'));
      (err, m) = await call(c, 'list', {'kind': 'memo'});
      expect(m, contains('kind'));
      (err, m) = await call(c, 'create', {'kind': 'note', 'title': 'N'});
      (err, m) = await call(c, 'update', {'id': 'N', 'due': '2026-01-01'});
      expect(err, isTrue);
      expect(m, contains('tasks only'));
      (err, m) = await call(c, 'update', {'id': 'N', 'priority': 'high'});
      expect(m, contains('priority'));
    });
  });

  group('collections admin', () {
    late Directory backup;
    late McpClient c;
    setUp(() async {
      backup = Directory.systemTemp.createTempSync('davdart-mcp-');
      addTearDown(() => backup.deleteSync(recursive: true));
      c = await connect(
          env.server({ToolGroup.read, ToolGroup.admin}, backup: backup.path));
    });

    test('delete needs the exact name', () async {
      final (err, m) = await call(c, 'collections', {
        'action': 'delete',
        'href': 'https://fake.test/dav/c/',
        'confirm': 'wrong',
      });
      expect(err, isTrue);
      expect(m, contains('does not match'));
      expect(env.fake.log.any((l) => l.startsWith('DELETE')), isFalse);
    });

    test('delete refuses a non-empty collection, dry run previews', () async {
      env.fake.external(
          'n1.ics',
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VJOURNAL\r\nUID:n1\r\n'
              'DTSTAMP:20260101T000000Z\r\nSUMMARY:N\r\nEND:VJOURNAL\r\n'
              'END:VCALENDAR\r\n');
      final args = {
        'action': 'delete',
        'href': 'https://fake.test/dav/c/',
        'confirm': 'Work',
      };
      var (err, m) = await call(c, 'collections', args);
      expect(err, isTrue);
      expect(m, contains('allow_non_empty'));
      var (_, d) = await call(c, 'collections',
          {...args, 'allow_non_empty': true, 'dry_run': true});
      expect(d['dryRun'], isTrue);
      expect(d['items'], 1);
      expect(backup.listSync(), isEmpty, reason: 'dry run writes nothing');
    });
  });

  group('writer and history', () {
    late Directory dir;
    late File file;
    late McpClient c;
    Future<McpClient> start({String? defaultWriter, bool del = true}) async {
      c = await connect(buildMcpServer(
          items: env.items,
          collections: env.collections,
          groups: {ToolGroup.read, ToolGroup.write, if (del) ToolGroup.delete},
          history: HistoryLog(file.path),
          defaultWriter: defaultWriter));
      return c;
    }

    List<Map<String, dynamic>> lines() => [
          for (final l in file.readAsLinesSync())
            if (l.isNotEmpty) jsonDecode(l) as Map<String, dynamic>
        ];

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hist');
      file = File('${dir.path}/h.jsonl');
    });

    test('writer is stored as X-WRITER, shown by get, kept on update',
        () async {
      await start();
      var (e, r) = await call(c, 'create',
          {'kind': 'note', 'title': 'A', 'writer': 'bot-a', 'body': 'x'});
      expect(e, isFalse, reason: '$r');
      expect(r['item']['writer'], 'bot-a');
      expect(env.fake.ics.values.single, contains('X-WRITER:bot-a'));
      // an update without a writer keeps the stamp
      (e, r) = await call(c, 'update', {'id': 'A', 'body': 'y'});
      expect(e, isFalse, reason: '$r');
      expect(env.fake.ics.values.single, contains('X-WRITER:bot-a'));
      expect((await call(c, 'get', {'id': 'A'})).$2['writer'], 'bot-a');
      // another writer replaces it, one line only
      await call(c, 'update', {
        'id': 'A',
        'tags_add': ['t'],
        'writer': 'bot-b'
      });
      final ics = env.fake.ics.values.single;
      expect(RegExp('X-WRITER').allMatches(ics), hasLength(1));
      expect(ics, contains('X-WRITER:bot-b'));
      // move and the other kinds take it too
      await call(
          c, 'create', {'kind': 'task', 'title': 'T', 'writer': 'bot-t'});
      await call(c, 'move', {'id': 'T', 'parent': 'A', 'writer': 'bot-m'});
      expect((await call(c, 'get', {'id': 'T'})).$2['writer'], 'bot-m');
    });

    test('writer is sanitised and the default writer applies', () async {
      await start(defaultWriter: 'default-bot');
      await call(c, 'create', {'kind': 'note', 'title': 'A'});
      expect(env.fake.ics.values.single, contains('X-WRITER:default-bot'));
      await call(c, 'update',
          {'id': 'A', 'body': 'z', 'writer': 'evil\r\nATTENDEE:x;y,z'});
      final ics = env.fake.ics.values.single;
      expect(ics, isNot(contains('\nATTENDEE')));
      expect(ics, contains('X-WRITER:evil__ATTENDEE:x_y_z'));
    });

    test('history records writes with BEFORE snapshots, not dry runs',
        () async {
      await start();
      await call(c, 'create',
          {'kind': 'note', 'title': 'A', 'body': 'one', 'writer': 'w1'});
      await call(c, 'update',
          {'id': 'A', 'body': 'two', 'writer': 'w2', 'dry_run': true});
      expect(lines(), hasLength(1));
      await call(c, 'update', {'id': 'A', 'body': 'two', 'writer': 'w2'});
      await call(c, 'delete', {'id': 'A', 'writer': 'w3'});
      final l = lines();
      expect(l.map((e) => e['tool']), ['create', 'update', 'delete']);
      expect(l[0]['before'], isNull);
      expect(l[1]['writer'], 'w2');
      expect(l[1]['before'].single, contains('DESCRIPTION:one'));
      expect(l[2]['before'].single, contains('DESCRIPTION:two'));
      expect(l[2]['before'].single, contains('X-WRITER:w2'));
      expect(l[2]['uid'], l[0]['uid']);
      expect(l[0]['collection'], '/dav/c/');
      expect(
          l.every((e) => e['time'] is String && e['kind'] == 'note'), isTrue);
      expect(env.fake.ics, isEmpty);
    });

    test('delete logs the children it re-parents', () async {
      await start();
      await call(c, 'create', {'kind': 'note', 'title': 'F', 'folder': true});
      await call(c, 'create', {'kind': 'note', 'title': 'K', 'parent': 'F'});
      final dd = await call(c, 'delete', {'id': 'F'});
      final d = lines().last;
      expect(dd.$1, isFalse, reason: '${dd.$2}');
      expect(d['tool'], 'delete');
      expect(d['children'], hasLength(1));
      expect(d['before'], hasLength(2));
      expect(d['before'][1], contains('SUMMARY:K'));
    });

    test('history tool: filters, hides bodies unless asked', () async {
      await start();
      await call(c, 'create', {'kind': 'note', 'title': 'A', 'writer': 'w'});
      await call(c, 'create', {'kind': 'note', 'title': 'B'});
      await call(c, 'update', {'id': 'A', 'body': 'q' * 500});
      var (e, r) = await call(c, 'history', {});
      expect(e, isFalse, reason: '$r');
      expect(r['count'], 3);
      expect(r['entries'].first['tool'], 'update');
      expect(r['entries'].first.containsKey('before'), isFalse);
      expect(r['entries'].first['beforeCount'], 1);
      expect(r['entries'].first['args']['body'].length, lessThan(250));
      (e, r) = await call(c, 'history', {'id': 'A', 'limit': 1});
      expect(r['count'], 1);
      (e, r) = await call(c, 'history', {'id': 'B'});
      expect(r['entries'].single['title'], 'B');
      (e, r) = await call(c, 'history',
          {'id': 'A', 'include_bodies': true, 'collection': 'Work'});
      expect(r['entries'].first['before'].single, contains('SUMMARY:A'));
      (e, r) = await call(c, 'history', {'collection': 'Nope'});
      expect(e, isTrue);
    });

    test('never logs secrets; line size is capped', () async {
      c = await connect(buildMcpServer(
          items: env.items,
          groups: {ToolGroup.read, ToolGroup.write},
          history: HistoryLog(file.path, maxLine: 20000, maxBefore: 50000)));
      await call(c, 'create', {'kind': 'note', 'title': 'A'});
      await call(c, 'update', {'id': 'A', 'body': 'b' * 90000});
      await call(c, 'update', {'id': 'A', 'body': 'c' * 90000});
      final raw = file.readAsStringSync();
      for (final l in raw.split('\n')) {
        expect(l.length, lessThanOrEqualTo(20500));
      }
      expect(raw, isNot(contains('p-secret')));
      expect(lines().last['before'].single.length, lessThan(5100));
      final log = HistoryLog(file.path);
      expect(log.cleanArgs({'token': 't', 'Password': 'p', 'title': 'x'}),
          {'title': 'x'});
    });

    test('an unwritable history refuses update and delete', () async {
      await start();
      await call(c, 'create', {'kind': 'note', 'title': 'A'});
      file.deleteSync();
      Directory(file.path).createSync(); // a directory cannot be appended to
      final (e, m) = await call(c, 'update', {'id': 'A', 'body': 'z'});
      expect(e, isTrue);
      expect(m, contains('history log failed'));
      final (e2, _) = await call(c, 'delete', {'id': 'A'});
      expect(e2, isTrue);
      expect(env.fake.ics, hasLength(1));
      expect(env.fake.ics.values.single, isNot(contains('DESCRIPTION:z')));
    });

    test('--read-only semantics: read group alone has no write tools',
        () async {
      c = await connect(buildMcpServer(
          items: env.items,
          groups: {ToolGroup.read},
          history: HistoryLog(file.path)));
      for (final t in ['create', 'update', 'move', 'delete']) {
        await expectLater(call(c, t, {'id': 'x'}), throwsA(anything));
      }
    });
  });

  group('streamable HTTP', () {
    late StreamableMcpServer http;
    late HttpClient client;
    late Uri url;

    setUp(() async {
      http = buildHttpServer(() => env.server({ToolGroup.read}),
          token: _token, port: 0);
      await http.start();
      url = Uri.parse('http://127.0.0.1:${http.boundPort}/mcp');
      client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await http.stop();
      });
    });

    Future<(int, Map<String, dynamic>?, HttpHeaders)> post(
        Map<String, Object?> body,
        {String? bearer,
        String? session}) async {
      final req = await client.postUrl(url);
      req.headers
        ..set('content-type', 'application/json')
        ..set('accept', 'application/json, text/event-stream');
      if (bearer != null) req.headers.set('authorization', 'Bearer $bearer');
      if (session != null) req.headers.set('mcp-session-id', session);
      req.write(jsonEncode(body));
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      Map<String, dynamic>? json;
      try {
        json = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {}
      return (res.statusCode, json, res.headers);
    }

    test('refuses a missing or wrong token', () async {
      const init = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-03-26',
          'capabilities': {},
          'clientInfo': {'name': 't', 'version': '1'},
        },
      };
      for (final bad in [null, 'wrong', '']) {
        final (code, _, _) = await post(init, bearer: bad);
        expect(code, anyOf(401, 403), reason: 'bearer=$bad');
      }
    });

    test('initialize, tools/list, tools/call with the token', () async {
      final (code, init, h) = await post({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-03-26',
          'capabilities': {},
          'clientInfo': {'name': 't', 'version': '1'},
        },
      }, bearer: _token);
      expect(code, 200);
      expect(init!['result']['serverInfo']['name'], 'davdart');
      final sid = h.value('mcp-session-id');
      expect(sid, isNotNull);

      await post({'jsonrpc': '2.0', 'method': 'notifications/initialized'},
          bearer: _token, session: sid);

      final (_, list, _) = await post(
          {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
          bearer: _token, session: sid);
      final names = [
        for (final t in list!['result']['tools'] as List) t['name']
      ]..sort();
      expect(names, ['collections', 'get', 'list', 'overview']);

      final (_, res, _) = await post({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {'name': 'overview', 'arguments': {}},
      }, bearer: _token, session: sid);
      final text = res!['result']['content'][0]['text'] as String;
      expect(jsonDecode(text)['total'], 0);

      final (c2, _, _) = await post(
          {'jsonrpc': '2.0', 'id': 4, 'method': 'tools/list'},
          bearer: 'wrong', session: sid);
      expect(c2, anyOf(401, 403), reason: 'token is checked on every request');
    });

    test('an empty token is refused at construction', () {
      expect(
          () => buildHttpServer(() => env.server({ToolGroup.read}), token: ''),
          throwsArgumentError);
    });
  });

  group('config', () {
    test('missing keys are named, values never printed', () {
      expect(
          () => servicesFromConfig({'url': 'https://x/dav/u/c', 'user': 'u'}),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              allOf(contains('password'), isNot(contains('https://x'))))));
    });
    test('home defaults to the parent of the collection', () {
      final s = servicesFromConfig(
          {'url': 'https://x/dav/u/c/', 'user': 'u', 'password': 'p'});
      expect(s.collections.home.path, '/dav/u/');
    });
  });
}
