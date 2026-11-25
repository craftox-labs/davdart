// Writes THIRD_PARTY_NOTICES.md at the repo root from the two lockfiles
// (the Dart core and the Flutter app), reading each hosted package's licence
// out of the pub cache:
//
//   dart run tool/notices.dart
//
// Only hosted (pub.dev) packages are listed; SDK packages (flutter,
// flutter_test, sky_engine, ...), path packages (this repo itself) and git
// packages have no pub.dev licence to copy. Packages whose licence file is
// missing from the cache are reported on stdout and in the file.
import 'dart:convert';
import 'dart:io';

/// One package pinned in a pubspec.lock.
class Locked {
  Locked(this.name,
      {required this.version,
      required this.source,
      required this.url,
      required this.kind});

  final String name;
  final String version;
  final String source;
  final String? url;

  /// main, dev or transitive, as the lockfile says.
  final String kind;

  /// direct main beats direct dev beats transitive.
  int get weight => switch (kind) {
        'main' => 0,
        'dev' => 1,
        _ => 2,
      };
}

final _pkgLine = RegExp(r'^  ([A-Za-z0-9_]+):\s*$');
final _field = RegExp(r'^    (dependency|source|version):\s*(.*)$');
final _descField = RegExp(r'^      (name|url|path|ref|resolved-ref):\s*(.*)$');

/// The packages of one lockfile, in file order.
List<Locked> readLock(String path) {
  final file = File(path);
  if (!file.existsSync()) throw StateError('no $path');
  final out = <Locked>[];
  String? name;
  var kind = 'transitive', source = '', version = '';
  String? url;
  var inPackages = false;
  void flush() {
    if (name == null) return;
    if (source == 'hosted') {
      out.add(Locked(name!,
          version: version, source: source, url: url, kind: kind));
    }
    name = null;
    url = null;
  }

  for (final line in file.readAsLinesSync()) {
    if (!inPackages) {
      if (line.startsWith('packages:')) inPackages = true;
      continue;
    }
    if (line.startsWith('sdks:')) {
      flush();
      inPackages = false;
      break;
    }
    final p = _pkgLine.firstMatch(line);
    if (p != null) {
      flush();
      name = p.group(1);
      kind = 'transitive';
      source = '';
      version = '';
      url = null;
      continue;
    }
    final f = _field.firstMatch(line);
    if (f != null) {
      switch (f.group(1)) {
        case 'dependency':
          kind = f.group(2)!.trim().replaceAll('"', '');
        case 'source':
          source = f.group(2)!.trim();
        case 'version':
          version = f.group(2)!.trim().replaceAll('"', '');
      }
      continue;
    }
    final d = _descField.firstMatch(line);
    if (d != null && d.group(1) == 'url') {
      url = d.group(2)!.trim().replaceAll('"', '').replaceAll("'", '');
    }
  }
  flush();
  return out;
}

const _licenseNames = [
  'license',
  'licence',
  'copying',
  'unlicense',
  'copyright',
];

/// The licence file of package [name] version [version] in the pub cache, or
/// null when the package directory or its licence is missing.
File? licenseFile(String cache, String name, String version) {
  final dir = Directory('$cache/hosted/pub.dev/$name-$version');
  if (!dir.existsSync()) return null;
  final hits = <String, File>{};
  for (final e in dir.listSync()) {
    if (e is! File) continue;
    final base = e.uri.pathSegments.last.toLowerCase();
    for (final n in _licenseNames) {
      if (base == n || base.startsWith('$n.') || base.startsWith('$n-')) {
        // Prefer the plain name over a variant such as LICENSE-APACHE.
        hits.putIfAbsent(n, () => e);
        break;
      }
    }
  }
  for (final n in _licenseNames) {
    final f = hits[n];
    if (f != null) return f;
  }
  return null;
}

/// A short SPDX-ish name guessed from the licence text.
String spdxGuess(String text) {
  final t = text.toLowerCase();
  if (t.contains('mozilla public license')) {
    return t.contains('2.0') ? 'MPL-2.0' : 'MPL-1.1';
  }
  if (t.contains('apache license') && t.contains('2.0')) return 'Apache-2.0';
  if (t.contains('permission is hereby granted, free of charge')) return 'MIT';
  if (t.contains('redistribution and use in source and binary forms')) {
    return t.contains('neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
  }
  if (t.contains('permission to use, copy, modify, and/or distribute') ||
      t.contains('permission to use, copy, modify, and distribute')) {
    return 'ISC';
  }
  if (t.contains('this is free and unencumbered software')) return 'Unlicense';
  if (t.contains('creative commons') && t.contains('cc0')) return 'CC0-1.0';
  if (t.contains('boost software license')) return 'BSL-1.0';
  if (t.contains('gnu lesser general public license')) return 'LGPL';
  if (t.contains('gnu general public license')) return 'GPL';
  return 'see text';
}

/// The pub.dev page of [p]: the lockfile's url is the host without a path,
/// so the package page is the useful source link.
String pageOf(Locked p) => 'https://pub.dev/packages/${p.name}';

/// The pub cache, honouring PUB_CACHE the way pub does.
String pubCache() {
  final env = Platform.environment['PUB_CACHE'];
  if (env != null && env.isNotEmpty) return env;
  final home = Platform.environment['HOME'] ?? '';
  if (Platform.isWindows) {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null) return '$local\\Pub\\Cache';
  }
  return '$home/.pub-cache';
}

void main(List<String> args) {
  final root = Directory.current;
  final cache = pubCache();
  final locks = ['pubspec.lock', 'apps/app/pubspec.lock'];
  final merged = <String, Locked>{};
  for (final l in locks) {
    for (final p in readLock('${root.path}/$l')) {
      final key = '${p.name}@${p.version}';
      final old = merged[key];
      if (old == null || p.weight < old.weight) merged[key] = p;
    }
  }
  final pkgs = merged.values.toList()
    ..sort((a, b) {
      final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return c != 0 ? c : a.version.compareTo(b.version);
    });

  final missing = <String>[];
  final entries = <(Locked, String, String, String)>[];
  for (final p in pkgs) {
    final f = licenseFile(cache, p.name, p.version);
    if (f == null) {
      missing.add('${p.name} ${p.version}');
      entries.add((p, 'not found', 'not found', ''));
      continue;
    }
    final text = f.readAsStringSync().trim();
    entries.add((p, spdxGuess(text), text, f.uri.pathSegments.last));
  }

  final b = StringBuffer()
    ..writeln('# Third-party notices')
    ..writeln()
    ..writeln('Packages published on pub.dev and pinned by `pubspec.lock` and')
    ..writeln('`apps/app/pubspec.lock`, with the licence each ships in its')
    ..writeln('package directory. Generated by `dart run tool/notices.dart`;')
    ..writeln('do not edit by hand.')
    ..writeln()
    ..writeln('Dart and Flutter SDK packages, the local `davdart` package and')
    ..writeln('anything not hosted on pub.dev are not listed here.')
    ..writeln()
    ..writeln('| package | version | licence | scope | source |')
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final (p, spdx, _, _) in entries) {
    b.writeln('| ${p.name} | ${p.version} | $spdx | ${p.kind} | '
        '${pageOf(p)} |');
  }
  if (missing.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Licence files not found')
      ..writeln()
      ..writeln('These packages are pinned but ship no licence file in the')
      ..writeln('pub cache (check them by hand before redistributing):')
      ..writeln();
    for (final m in missing) {
      b.writeln('- $m');
    }
  }
  b
    ..writeln()
    ..writeln('## Licence texts')
    ..writeln();
  for (final (p, spdx, text, file) in entries) {
    b
      ..writeln('### ${p.name} ${p.version}')
      ..writeln()
      ..writeln('$spdx, from `$file`. ${pageOf(p)}')
      ..writeln();
    if (text.isEmpty) {
      b.writeln('    (no licence file found)');
    } else {
      for (final line in const LineSplitter().convert(text)) {
        b.writeln(line.trimRight().isEmpty ? '' : '    $line');
      }
    }
    b.writeln();
  }
  final out = File('${root.path}/THIRD_PARTY_NOTICES.md');
  out.writeAsStringSync(b.toString());

  print('${entries.length} packages from ${locks.length} lockfiles '
      '(cache: $cache)');
  print('wrote ${out.path} (${(out.lengthSync() / 1024).round()} KiB)');
  print(missing.isEmpty
      ? 'every package has a licence file'
      : '${missing.length} without a licence file: ${missing.join(', ')}');
}
