import 'dart:io';

/// Reads connection settings (`url`, `user`, `password`) from a key=value file
/// (`$DAVDART_CONFIG`, default `~/.config/davdart/credentials`), then lets
/// `DAVDART_URL`, `DAVDART_USER` and `DAVDART_PASSWORD` override each key.
Map<String, String> loadConfig() {
  final env = Platform.environment;
  final cfg = <String, String>{};
  final file = File(
      env['DAVDART_CONFIG'] ?? '${env['HOME']}/.config/davdart/credentials');
  if (file.existsSync()) {
    for (final line in file.readAsLinesSync()) {
      final i = line.indexOf('=');
      if (i > 0 && !line.trimLeft().startsWith('#')) {
        cfg[line.substring(0, i).trim()] = line.substring(i + 1).trim();
      }
    }
  }
  for (final k in ['url', 'user', 'password']) {
    final v = env['DAVDART_${k.toUpperCase()}'];
    if (v != null && v.isNotEmpty) cfg[k] = v;
  }
  return cfg;
}
