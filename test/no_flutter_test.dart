import 'dart:io';

import 'package:test/test.dart';

void main() {
  ioGuard();
  test('the core never imports Flutter', () {
    final offenders = <String>[];
    for (final dir in ['lib', 'bin']) {
      for (final f
          in Directory(dir)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (RegExp(r'''import\s+['"]package:flutter''')
            .hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
    }
    expect(offenders, isEmpty);
    expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('flutter')));
  });
}

void ioGuard() {
  test('the web-safe library never imports dart:io', () {
    const ioFiles = {
      'config.dart',
      'collection_backup_io.dart',
      'file_store.dart',
      'space_book.dart',
      'task_file_store.dart',
      'event_file_store.dart',
    };
    final offenders = [
      for (final f in Directory(
        'lib/src',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart')))
        if (!ioFiles.contains(f.uri.pathSegments.last) &&
            f.readAsStringSync().contains("import 'dart:io'"))
          f.path,
    ];
    expect(offenders, isEmpty);
    expect(
      File('lib/davdart.dart').readAsStringSync(),
      isNot(contains('dart:io')),
    );
  });
}
