import 'package:davdart_app/state/vim_editor/vim_engine.dart';
import 'package:davdart_app/state/vim_editor/vim_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vim_engine_test.dart' hide main;

void main() {
  const limit = Duration(seconds: 1);
  final cases = <(String, String, int)>[
    ('CJK', '中' * 50000, 1),
    ('emoji', '\u{1F600}' * 25000, 2),
    ('emoji with tone', '\u{1F44D}\u{1F3FD}' * 12500, 4),
  ];
  for (final (name, line, unit) in cases) {
    final n = line.length;
    final last = n - unit;
    group('long $name line', () {
      void timed(String keys, void Function(VimEngine e) check) {
        test(keys, () {
          final e = mk('|$line');
          final sw = Stopwatch()..start();
          run(e, keys);
          expect(sw.elapsed, lessThan(limit), reason: keys);
          check(e);
        });
      }

      timed('9999999l', (e) => expect(e.cursor, last));
      timed('\$', (e) => expect(e.cursor, last));
      timed('w', (e) => expect(e.cursor, last));
      timed('x', (e) => expect(e.text.length, n - unit));
      timed('dw', (e) => expect(e.text, ''));
      timed('\$0', (e) => expect(e.cursor, 0));
      timed('\$9999999h', (e) => expect(e.cursor, 0));
    });
  }

  test('stepFwd and stepBack agree with single steps', () {
    final t = 'a${'\u{1F44D}\u{1F3FD}' * 300}é${'中' * 700}b';
    var p = 0;
    for (var k = 0; k < 1000; k++) {
      expect(stepFwd(t, 0, k, t.length), p, reason: 'fwd $k');
      p = nextChar(t, p);
    }
    p = t.length;
    for (var k = 0; k < 1000; k++) {
      expect(stepBack(t, t.length, k, 0), p, reason: 'back $k');
      p = prevChar(t, p);
    }
    expect(stepFwd(t, 0, 99999, 5), 5);
    expect(stepBack(t, t.length, 99999, t.length - 3), t.length - 3);
  });
}
