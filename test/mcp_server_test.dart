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
      expect(await toolNames(c), ['create', 'delete', 'move', 'update']);
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
      expect(() => ToolGroup.parse('root'), throwsFormatException);
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
