import 'dart:async';
import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart/mcp_server.dart';
import 'package:mcp_dart/mcp_dart.dart';

const _usage = '''davdart_mcp: MCP server over davdart notes, tasks and events.

  --stdio                      serve on stdin/stdout (default)
  --http PORT                  serve Streamable HTTP at /mcp instead
  --bind ADDR                  HTTP bind address (default 127.0.0.1)
  --token-env VAR              HTTP: env var holding the bearer token (required)
  --allow-host NAME            HTTP: extra Host header to accept (repeatable)
  --tools read,write,delete,admin
                               tool groups to expose (default: read).
                               write = create, update, move (no delete);
                               delete = delete one item; admin = collection
                               create, rename, delete
  --read-only                  same as --tools read (refuses every other group)
  --history-file PATH          append every write to this JSONL file (mode 600),
                               with a BEFORE snapshot of the item; adds the
                               read tool "history". Default: no log
  --default-writer NAME        writer label for writes that pass none (stored as
                               X-WRITER; self-declared, not authentication)
  --backup-dir DIR             admin: where collection delete writes backups
  -h, --help

config: url, user, password in ~/.config/davdart/credentials or the
DAVDART_URL, DAVDART_USER, DAVDART_PASSWORD environment variables.''';

Never _die(String msg) {
  stderr.writeln('davdart_mcp: $msg');
  exit(2);
}

Future<void> main(List<String> args) async {
  var stdio = true;
  int? httpPort;
  var bind = '127.0.0.1';
  String? tokenEnv;
  String? backupDir;
  String? historyFile;
  String? defaultWriter;
  var readOnly = false;
  Set<ToolGroup>? groups;
  final hosts = <String>{};
  String val(int i) => i < args.length
      ? args[i]
      : _die('${args[i - 1]} needs a value\n\n$_usage');
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-h' || '--help':
        stdout.writeln(_usage);
        return;
      case '--stdio':
        stdio = true;
      case '--http':
        httpPort = int.tryParse(val(++i)) ?? _die('--http needs a port number');
        stdio = false;
      case '--bind':
        bind = val(++i);
      case '--token-env':
        tokenEnv = val(++i);
      case '--allow-host':
        hosts.add(val(++i));
      case '--backup-dir':
        backupDir = val(++i);
      case '--history-file':
        historyFile = val(++i);
      case '--default-writer':
        defaultWriter = val(++i);
      case '--read-only':
        readOnly = true;
      case '--tools':
        try {
          groups = ToolGroup.parse(val(++i));
        } on FormatException catch (e) {
          _die(e.message);
        }
      default:
        _die('unknown argument "${args[i]}"\n\n$_usage');
    }
  }
  if (readOnly && groups != null && groups.any((g) => g != ToolGroup.read)) {
    _die(
        '--read-only conflicts with --tools ${groups.map((g) => g.name).join(',')}');
  }
  final enabled = readOnly ? {ToolGroup.read} : (groups ?? {ToolGroup.read});
  if (enabled.contains(ToolGroup.admin) && (backupDir ?? '').isEmpty) {
    _die('the admin group needs --backup-dir');
  }

  String? token;
  if (!stdio) {
    if (tokenEnv == null) _die('--http needs --token-env VAR (no open HTTP)');
    token = Platform.environment[tokenEnv];
    if (token == null || token.isEmpty) {
      _die('environment variable $tokenEnv is empty or unset; refusing to '
          'start HTTP without a token');
    }
  }

  final ({ItemService items, CollectionService collections}) svc;
  try {
    svc = servicesFromConfig();
  } on StateError catch (e) {
    _die(e.message);
  }
  McpServer make() => buildMcpServer(
      items: svc.items,
      collections: svc.collections,
      groups: enabled,
      backupDir: backupDir,
      history: historyFile == null ? null : HistoryLog(historyFile),
      defaultWriter: defaultWriter);

  final names = (enabled.map((g) => g.name).toList()..sort()).join(',');
  if (stdio) {
    await make().connect(StdioServerTransport());
    stderr.writeln('davdart_mcp: stdio, tools: $names');
  } else {
    final http = buildHttpServer(make,
        token: token!, port: httpPort!, host: bind, allowedHosts: hosts);
    await http.start();
    stderr.writeln(
        'davdart_mcp: http://$bind:${http.boundPort}/mcp, tools: $names');
    await ProcessSignal.sigint.watch().first;
    await http.stop();
  }
}
