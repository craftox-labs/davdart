import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the core never imports Flutter', () {
    final offenders = <String>[];
    for (final dir in ['lib', 'bin']) {
      for (final f in Directory(dir)
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
