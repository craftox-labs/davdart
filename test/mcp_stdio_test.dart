import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'support/fake_caldav.dart';
import 'support/fake_dav_server.dart';

/// Spawns bin/davdart_mcp.dart as a subprocess talking stdio, with its CalDAV
/// pointed at an in-process fake on an ephemeral localhost port.
void main() {
  late FakeCalDav fake;
  late FakeDavServer dav;
  late Directory tmp;

  setUp(() async {
    fake = FakeCalDav();
    dav = await FakeDavServer.start(withHome(fake));
    tmp = Directory.systemTemp.createTempSync('davdart-stdio-');
    addTearDown(() async {
      await dav.close();
      tmp.deleteSync(recursive: true);
    });
  });

  Future<McpClient> spawn(List<String> flags) async {
    // `dart run` can take longer than the default 5s discovery probe to start
    // the server under load; a timeout makes the client fall back to
    // `initialize`, which the already-stateless server rejects.
    final client = McpClient(const Implementation(name: 't', version: '1'),
        options: const McpClientOptions(
            legacyDiscoveryTimeout: Duration(seconds: 60)));
    await client.connect(StdioClientTransport(StdioServerParameters(
      command: Platform.resolvedExecutable,
      args: ['run', 'bin/davdart_mcp.dart', '--stdio', ...flags],
      environment: {
        'DAVDART_CONFIG': '${tmp.path}/none',
        'DAVDART_URL': dav.collectionUrl,
        'DAVDART_USER': 'u',
        'DAVDART_PASSWORD': 'p',
      },
      stderrMode: ProcessStartMode.normal,
    )));
    addTearDown(client.close);
    return client;
  }

  Future<dynamic> call(McpClient c, String n, Map<String, dynamic> a) async {
    final r = await c.callTool(CallToolRequest(name: n, arguments: a));
    final text = (r.content.single as TextContent).text;
    if (r.isError) throw StateError(text);
    return jsonDecode(text);
  }

  test('default is read only; read tools work over stdio', () async {
    final c = await spawn([]);
    final names = (await c.listTools()).tools.map((t) => t.name).toSet();
    expect(names, {'overview', 'list', 'get', 'collections'});
    expect((await call(c, 'overview', {}))['total'], 0);
    final cols = await call(c, 'collections', {'action': 'list'});
    expect(cols['collections'].single['name'], 'Work');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('write group creates an item the fake server stores', () async {
    final c = await spawn(['--tools', 'read,write']);
    final made = await call(c, 'create', {
      'kind': 'task',
      'title': 'From stdio',
      'tags': ['x']
    });
    expect(made['item']['title'], 'From stdio');
    expect(fake.ics, hasLength(1));
    final page = await call(c, 'list', {'tag': 'x'});
    expect(page['total'], 1);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('read,write does not serve delete; delete group does', () async {
    var c = await spawn(['--tools', 'read,write']);
    final names = (await c.listTools()).tools.map((t) => t.name).toSet();
    expect(names, containsAll(['create', 'update', 'move']));
    expect(names, isNot(contains('delete')));
    c = await spawn(['--tools', 'read,write,delete']);
    expect((await c.listTools()).tools.map((t) => t.name), contains('delete'));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('admin without --backup-dir refuses to start', () async {
    final r = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/davdart_mcp.dart',
      '--tools',
      'admin'
    ], environment: {
      'DAVDART_CONFIG': '${tmp.path}/none',
      'DAVDART_URL': dav.collectionUrl,
      'DAVDART_USER': 'u',
      'DAVDART_PASSWORD': 'p',
    });
    expect(r.exitCode, 2);
    expect(r.stderr, contains('--backup-dir'));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('HTTP without a token refuses to start and never echoes secrets',
      () async {
    final env = {
      'DAVDART_CONFIG': '${tmp.path}/none',
      'DAVDART_URL': dav.collectionUrl,
      'DAVDART_USER': 'u',
      'DAVDART_PASSWORD': 'p-secret',
    };
    for (final args in [
      ['--http', '0'],
      ['--http', '0', '--token-env', 'NOPE_UNSET'],
    ]) {
      final r = await Process.run(
          Platform.resolvedExecutable, ['run', 'bin/davdart_mcp.dart', ...args],
          environment: env);
      expect(r.exitCode, 2);
      expect(r.stderr, contains('token'));
      expect('${r.stderr}${r.stdout}', isNot(contains('p-secret')));
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
