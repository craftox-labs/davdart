import 'package:davdart_app/state/vim_editor/vim_engine.dart';
import 'package:davdart_app/state/vim_editor/vim_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vim_engine_test.dart' hide main;

const thumb = '\u{1F44D}\u{1F3FD}'; // thumbs up, skin tone (2 pairs)
const family = '\u{1F468}‍\u{1F469}‍\u{1F467}'; // ZWJ sequence

/// No lone surrogate anywhere in [s].
bool wellFormed(String s) {
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 >= s.length) return false;
      final n = s.codeUnitAt(i + 1);
      if (n < 0xDC00 || n > 0xDFFF) return false;
      i++;
    } else if (u >= 0xDC00 && u <= 0xDFFF) {
      return false;
    }
  }
  return true;
}

void main() {
  group('graphemes', () {
    for (final (name, glyph) in [
      ('emoji with skin tone', thumb),
      ('ZWJ family', family),
      ('single pair', '\u{1F600}'),
      ('combining accent', 'é'),
      ('CJK', '中'),
    ]) {
      test('x deletes a whole $name', () {
        final e = mk('|${glyph}b');
        run(e, 'x');
        expect(e.text, 'b');
      });
      test('l then h walk $name as one step', () {
        final e = mk('|${glyph}b');
        run(e, 'l');
        expect(e.cursor, glyph.length);
        run(e, 'h');
        expect(e.cursor, 0);
      });
      test('X deletes the $name before the cursor', () {
        final e = mk('a$glyph|b');
        run(e, 'X');
        expect(e.text, 'ab');
      });
      test('dl, s, r, ~ keep $name whole', () {
        var e = mk('|${glyph}b');
        run(e, 'dl');
        expect(e.text, 'b');
        e = mk('|${glyph}b');
        run(e, 'sZ<Esc>');
        expect(e.text, 'Zb');
        e = mk('|${glyph}b');
        run(e, 'rZ');
        expect(e.text, 'Zb');
        e = mk('|${glyph}b');
        run(e, '~');
        expect(wellFormed(e.text), isTrue);
      });
      test('selection of $name covers it whole, also in visual', () {
        final e = mk('|${glyph}b');
        expect(e.value.selection.end, glyph.length);
        run(e, 'vd');
        expect(e.text, 'b');
      });
      test('\$ and a land on the last $name', () {
        final e = mk('|b$glyph');
        run(e, r'$');
        expect(e.cursor, 1);
        run(e, 'x');
        expect(e.text, 'b');
      });
      test('p after $name puts after it', () {
        final e = mk('|${glyph}b');
        run(e, 'ylp');
        expect(e.text, '$glyph${glyph}b');
        expect(wellFormed(e.text), isTrue);
      });
    }

    test('undo and j keep the caret on a boundary', () {
      final e = mk('ab\n${thumb}cd');
      run(e, 'lj');
      expect(snapDown(e.text, e.cursor), e.cursor);
      run(e, 'x');
      expect(wellFormed(e.text), isTrue);
    });

    test('a word of emoji and e motion keeps text well formed', () {
      final e = mk('|$thumb$thumb x');
      run(e, 'de');
      expect(wellFormed(e.text), isTrue);
      expect(e.text, ' x');
    });

    test('3x counts clusters', () {
      final e = mk('|a${thumb}éz');
      run(e, '3x');
      expect(e.text, 'z');
    });
  });

  group('CRLF', () {
    test(r'$ stops before the CR', () {
      final e = mk('|ab\r\ncd');
      run(e, r'$');
      expect(e.cursor, 1);
    });
    test('A appends before the CR', () {
      final e = mk('|ab\r\ncd');
      run(e, 'AX<Esc>');
      expect(e.text, 'abX\r\ncd');
    });
    test('o opens a CRLF line', () {
      final e = mk('|ab\r\ncd');
      run(e, 'oX<Esc>');
      expect(e.text, 'ab\r\nX\r\ncd');
    });
    test('O opens a CRLF line above', () {
      final e = mk('ab\r\n|cd');
      run(e, 'OX<Esc>');
      expect(e.text, 'ab\r\nX\r\ncd');
    });
    test('3ox repeats with CRLF', () {
      final e = mk('|ab\r\ncd');
      run(e, '2oX<Esc>');
      expect(e.text, 'ab\r\nX\r\nX\r\ncd');
    });
    test('dd removes the whole line with its CRLF', () {
      var e = mk('|ab\r\ncd\r\nef');
      run(e, 'dd');
      expect(e.text, 'cd\r\nef');
      e = mk('ab\r\ncd\r\n|ef');
      run(e, 'dd');
      expect(e.text, 'ab\r\ncd');
      expect(e.text.contains('\n\r'), isFalse);
    });
    test('J joins CRLF lines', () {
      final e = mk('|ab\r\ncd\r\nef');
      run(e, 'J');
      expect(e.text, 'ab cd\r\nef');
    });
    test('p linewise puts a CRLF line', () {
      var e = mk('|ab\r\ncd');
      run(e, 'yyp');
      expect(e.text, 'ab\r\nab\r\ncd');
      e = mk('|ab\r\ncd');
      run(e, 'yyP');
      expect(e.text, 'ab\r\nab\r\ncd');
    });
    test('x on an empty CRLF line does nothing; l stays on the line', () {
      final e = mk('ab\r\n|\r\ncd');
      run(e, 'x');
      expect(e.text, 'ab\r\n\r\ncd');
      run(e, 'jl');
      expect(e.cursor, 7);
    });
    test('LF text keeps LF', () {
      final e = mk('|ab\ncd');
      run(e, 'oX<Esc>');
      expect(e.text, 'ab\nX\ncd');
    });
    test('yy then dw on CRLF and w across an empty CRLF line', () {
      final e = mk('|ab\r\n\r\ncd');
      run(e, 'w');
      expect(e.cursor, 4);
    });
    test('> indents a CRLF blank line not at all', () {
      final e = mk('|ab\r\n\r\ncd');
      run(e, '>G');
      expect(e.text, '  ab\r\n\r\n  cd');
    });
    test('cc keeps the CRLF', () {
      final e = mk('|ab\r\ncd');
      run(e, 'ccX<Esc>');
      expect(e.text, 'X\r\ncd');
    });
  });

  group('counts', () {
    test('99999999ix<Esc> is capped', () {
      final e = mk('|a');
      run(e, '99999999ix<Esc>');
      expect(e.text.length, lessThanOrEqualTo(VimEngine.maxRepeat + 2));
      expect(e.text.length, greaterThan(100));
    });
    test('99999999p is capped', () {
      final e = mk('|abc');
      run(e, 'ylp');
      run(e, '99999999p');
      expect(e.text.length, lessThanOrEqualTo(VimEngine.maxText + 10));
      expect(e.text.length, greaterThan(1000));
    });
    test('99999999yyp-like linewise put is capped', () {
      final e = mk('|${'x' * 1000}');
      run(e, 'yy');
      run(e, '99999999p');
      expect(e.text.length, lessThanOrEqualTo(VimEngine.maxText + 2000));
    });
    test(':huge number does not throw and goes to the last line', () {
      final e = mk('|a\nb\nc');
      run(e, ':99999999999999999999<CR>');
      expect(e.cursor, 4);
      run(e, ':0<CR>');
      expect(e.cursor, 0);
      run(e, ':2<CR>');
      expect(e.cursor, 2);
    });
    test('an overflowing count never goes negative', () {
      final e = mk('|abc\ndef');
      run(e, '99999999999999999999rx');
      expect(e.text, 'abc\ndef');
      run(e, 'x');
      expect(e.text, 'bc\ndef');
      run(e, '99999999999999999999l');
      expect(e.cursor, 1);
      run(e, '99999999999999999999j');
      expect(e.text, 'bc\ndef');
    });
    test('huge counts for operators and join', () {
      final e = mk('|a\nb\nc');
      run(e, '99999999999999999999J');
      expect(e.text, 'a b c');
      run(e, '99999999999999999999dd');
      expect(e.text, '');
    });
    test('d with a product of counts is clamped', () {
      final e = mk('|a b c');
      run(e, '99999d99999w');
      expect(e.text, '');
    });
  });

  group('search', () {
    test('a catastrophic regex returns quickly (literal)', () {
      final e = mk('|${'a' * 5000}!');
      final sw = Stopwatch()..start();
      run(e, '/(a+)+\$<CR>');
      expect(sw.elapsedMilliseconds, lessThan(1500));
      expect(e.message, startsWith('Pattern not found'));
    });
    test('a simple regex still works', () {
      final e = mk('|foo bar b2z');
      run(e, '/b.z<CR>');
      expect(e.cursor, 8);
      run(e, '/b\\d<CR>');
      expect(e.cursor, 8);
    });
    test('simplePattern', () {
      expect(VimEngine.simplePattern('foo.*bar'), isTrue);
      expect(VimEngine.simplePattern('(a+)+'), isFalse);
      expect(VimEngine.simplePattern('a|b'), isFalse);
      expect(VimEngine.simplePattern('a*b*'), isFalse);
      expect(VimEngine.simplePattern('a{2,}'), isFalse);
    });
    test('matches are capped and n still moves', () {
      final e = mk('|${'x ' * 30000}');
      run(e, '/x<CR>');
      expect(e.cursor, 2);
      run(e, '5n');
      expect(e.cursor, 12);
    });
    test('search works across CRLF lines', () {
      final e = mk('|ab\r\ncd\r\nef');
      run(e, '/ef<CR>');
      expect(e.cursor, 8);
    });
  });

  group('engine reset', () {
    test('fail sets the footer message', () {
      final e = mk('|a');
      e.fail('E: save failed');
      expect(e.message, 'E: save failed');
    });
  });
}
