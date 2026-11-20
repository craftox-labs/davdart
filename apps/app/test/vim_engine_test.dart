import 'package:davdart_app/state/vim_editor/vim_engine.dart';
import 'package:davdart_app/state/vim_editor/vim_keys.dart';
import 'package:davdart_app/state/vim_editor/vim_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tokens of a key string: `<Esc> <CR> <BS> <C-r> <Space>` are named keys,
/// everything else is one character per key.
List<String> tokens(String s) {
  final out = <String>[];
  var i = 0;
  while (i < s.length) {
    if (s[i] == '<') {
      final j = s.indexOf('>', i);
      if (j > i) {
        final name = s.substring(i + 1, j);
        const named = {
          'Esc': 'Esc',
          'CR': 'Enter',
          'BS': 'BS',
          'C-r': 'C-r',
          'Space': ' ',
          'Left': 'Left',
          'Right': 'Right',
          'Up': 'Up',
          'Down': 'Down',
          'Home': 'Home',
          'End': 'End',
        };
        if (named.containsKey(name)) {
          out.add(named[name]!);
          i = j + 1;
          continue;
        }
      }
    }
    out.add(s[i]);
    i++;
  }
  return out;
}

/// An engine over `text` where `|` marks the cursor; typed text in INSERT
/// goes through [type] like the text field would do it.
VimEngine mk(
  String marked, {
  List<VimAction>? actions,
  LeaderResolver? leader,
}) {
  final c = marked.indexOf('|');
  final text = marked.replaceFirst('|', '');
  return VimEngine(
    text: text,
    cursor: c < 0 ? 0 : c,
    onAction: actions?.add,
    leader: leader,
  );
}

/// Feeds [keys]. In INSERT mode, characters are typed into the text like the
/// field would (the engine does not take them), Enter adds a newline and BS
/// deletes.
void run(VimEngine e, String keys) {
  for (final k in tokens(keys)) {
    if (e.mode == VimMode.insert && k != 'Esc') {
      final v = e.value;
      var t = v.text;
      var at = v.selection.extentOffset;
      if (k == 'BS') {
        if (at > 0) {
          t = t.replaceRange(at - 1, at, '');
          at--;
        }
      } else {
        final ch = k == 'Enter' ? '\n' : k;
        t = t.replaceRange(at, at, ch);
        at += ch.length;
      }
      e.external(
        TextEditingValue(
          text: t,
          selection: TextSelection.collapsed(offset: at),
        ),
      );
      continue;
    }
    e.feed(k);
  }
}

String show(VimEngine e) {
  final t = e.text;
  final c = e.cursor.clamp(0, t.length);
  return '${t.substring(0, c)}|${t.substring(c)}';
}

typedef Case = (String name, String from, String keys, String to);

void table(String group, List<Case> cases) {
  group_(group, () {
    for (final (name, from, keys, to) in cases) {
      test(name, () {
        final e = mk(from);
        run(e, keys);
        expect(show(e), to, reason: '$from + $keys');
      });
    }
  });
}

void group_(String name, void Function() body) => group(name, body);

void main() {
  table('motions', [
    ('l', '|abc', 'l', 'a|bc'),
    ('l stops at the last char', 'ab|c', 'lll', 'ab|c'),
    ('3l', '|abcdef', '3l', 'abc|def'),
    ('h', 'ab|c', 'h', 'a|bc'),
    ('h stops at line start', '|abc', 'hh', '|abc'),
    ('arrow aliases', '|abc', '<Right><Right><Left>', 'a|bc'),
    ('j keeps column', 'abc|d\nab\nabcd', 'jj', 'abcd\nab\nabc|d'),
    ('j then k restores column', 'ab|cd\nx\nabcd', 'jj', 'abcd\nx\nab|cd'),
    ('j clamps short line', 'abcd|\nx\nabcd', 'j', 'abcd\n|x\nabcd'),
    ('k', 'abc\nde|f', 'k', 'ab|c\ndef'),
    ('j at last line stays', 'a\n|b', 'j', 'a\n|b'),
    ('3j', '|a\nb\nc\nd', '3j', 'a\nb\nc\n|d'),
    ('w', '|foo bar baz', 'w', 'foo |bar baz'),
    ('2w', '|foo bar baz', '2w', 'foo bar |baz'),
    ('w punctuation', '|foo.bar', 'w', 'foo|.bar'),
    ('w across lines', 'foo|\nbar', 'w', 'foo\n|bar'),
    ('w stops at empty line', '|foo\n\nbar', 'w', 'foo\n|\nbar'),
    ('W', '|foo.bar baz', 'W', 'foo.bar |baz'),
    ('b', 'foo bar|', 'b', 'foo |bar'),
    ('b over punctuation', 'foo.bar|', 'b', 'foo.|bar'),
    ('B', 'foo.bar baz|', 'B', 'foo.bar |baz'),
    ('2b', 'foo bar baz|', '2b', 'foo |bar baz'),
    ('e', '|foo bar', 'e', 'fo|o bar'),
    ('e from word end goes to next', 'fo|o bar', 'e', 'foo ba|r'),
    ('E', '|foo.bar baz', 'E', 'foo.ba|r baz'),
    ('0', 'foo |bar', '0', '|foo bar'),
    ('^', '   fo|o', '^', '   |foo'),
    ('\$', '|foo bar', r'$', 'foo ba|r'),
    ('\$ keeps end on j', '|ab\nabcdef', r'$j', 'ab\nabcde|f'),
    ('2\$', '|ab\ncd', r'2$', 'ab\nc|d'),
    ('gg', 'a\nb\n|c', 'gg', '|a\nb\nc'),
    ('G', '|a\nb\nc', 'G', 'a\nb\n|c'),
    ('5G', '|a\nb\nc\nd\ne\nf', '5G', 'a\nb\nc\nd\n|e\nf'),
    ('3gg', '|a\nb\nc\nd', '3gg', 'a\nb\n|c\nd'),
    ('G goes to first non blank', '|a\n  b', 'G', 'a\n  |b'),
    ('f', '|a,b,c', 'f,', 'a|,b,c'),
    ('2f', '|a,b,c', '2f,', 'a,b|,c'),
    ('F', 'a,b,|c', 'F,', 'a,b|,c'),
    ('t', '|a,b,c', 't,', '|a,b,c'),
    ('t further', '|abc,d', 't,', 'ab|c,d'),
    ('T', 'a,bc|d', 'T,', 'a,|bcd'),
    ('; repeats f', '|a,b,c', 'f,;', 'a,b|,c'),
    (', reverses', '|a,b,c', 'f,;,', 'a|,b,c'),
    ('; repeats t past adjacent', '|a,b,c', 't,;', 'a,|b,c'),
    ('f missing', '|abc', 'fz', '|abc'),
    ('}', '|a\nb\n\nc', '}', 'a\nb\n|\nc'),
    ('} to end', '|a\nb', '}', 'a\n|b'),
    ('{', 'a\n\nb\nc|', '{', 'a\n|\nb\nc'),
    ('{ to start', 'a\nb|', '{', '|a\nb'),
    ('%', '|(a [b] c)', '%', '(a [b] c|)'),
    ('% back', '(a [b] c|)', '%', '|(a [b] c)'),
    ('count 0 is a motion', 'abc|', '0', '|abc'),
    ('10l', '|a bcdefghijklm', '10l', 'a bcdefghi|jklm'),
  ]);

  table('operators', [
    ('x', '|abc', 'x', '|bc'),
    ('3x', '|abcde', '3x', '|de'),
    ('x at end of line moves left', 'ab|c', 'x', 'a|b'),
    ('X', 'ab|c', 'X', 'a|c'),
    ('dd', 'a\n|b\nc', 'dd', 'a\n|c'),
    ('dd last line', 'a\n|b', 'dd', '|a'),
    ('dd only line', '|abc', 'dd', '|'),
    ('2dd', '|a\nb\nc', '2dd', '|c'),
    ('dw', '|foo bar', 'dw', '|bar'),
    ('dw last word keeps the line break', 'x |foo\nbar', 'dw', 'x| \nbar'),
    ('d2w', '|a b c d', 'd2w', '|c d'),
    ('2dw', '|a b c d', '2dw', '|c d'),
    ('d3w counts multiply', '|a b c d e f g', '2d2w', '|e f g'),
    ('de', '|foo bar', 'de', '| bar'),
    ('db', 'foo |bar', 'db', '|bar'),
    ('d\$', 'ab|cd\nef', r'd$', 'a|b\nef'),
    ('D', 'ab|cd\nef', 'D', 'a|b\nef'),
    ('d0', 'abc|d', 'd0', '|d'),
    ('d^', '  ab|c', 'd^', '  |c'),
    ('dj', '|a\nb\nc', 'dj', '|c'),
    ('dk', 'a\n|b\nc', 'dk', '|c'),
    ('dG', 'a\n|b\nc', 'dG', '|a'),
    ('dgg', 'a\n|b\nc', 'dgg', '|c'),
    ('dfx', '|abxcd', 'dfx', '|cd'),
    ('dtx', '|abxcd', 'dtx', '|xcd'),
    ('dh', 'a|bc', 'dh', '|bc'),
    ('dl', '|abc', 'dl', '|bc'),
    ('d}', '|a\nb\n\nc', 'd}', '|\nc'),
    ('d%', '|(a)b', 'd%', '|b'),
    ('dd then p linewise', '|a\nb', 'ddp', 'b\n|a'),
    ('cw', '|foo bar', 'cwxy<Esc>', 'x|y bar'),
    ('cw keeps trailing space', '|foo bar', 'cwX<Esc>', '|X bar'),
    ('c2w', '|a b c', 'c2wX<Esc>', '|X c'),
    ('ce', '|foo bar', 'ceX<Esc>', '|X bar'),
    ('cc', 'a\n|bcd\ne', 'ccX<Esc>', 'a\n|X\ne'),
    ('C', 'ab|cd', 'CX<Esc>', 'ab|X'),
    ('c\$', 'ab|cd', r'c$X<Esc>', 'ab|X'),
    ('s', '|abc', 'sX<Esc>', '|Xbc'),
    ('S', 'a\n|bcd', 'SX<Esc>', 'a\n|X'),
    ('yy p', '|a\nb', 'yyp', 'a\n|a\nb'),
    ('yy P', 'a\n|b', 'yyP', 'a\n|b\nb'),
    ('2yy p', '|a\nb\nc', '2yyGp', 'a\nb\nc\n|a\nb'),
    ('Y', '|a\nb', 'Yp', 'a\n|a\nb'),
    ('yw P', '|foo bar', 'ywP', 'foo| foo bar'),
    ('yw p after', '|foo bar', 'ywp', 'ffoo| oo bar'),
    ('y\$ P', '|ab', r'y$$P', 'aa|bb'),
    ('3p', '|ab', 'yl3p', 'aaa|ab'),
    ('x then p', '|ab', 'xp', 'b|a'),
    ('r', '|abc', 'rX', '|Xbc'),
    ('3r', '|abcd', '3rX', 'XX|Xd'),
    ('r too long', '|ab', '5rX', '|ab'),
    ('J', 'a|\nb', 'J', 'a| b'),
    ('J strips indent', 'a\n   b', 'J', 'a| b'),
    ('3J', '|a\nb\nc', '3J', 'a b| c'),
    ('J with empty line', 'a|\n\nb', 'J', '|a\nb'),
    ('~', '|abC', '~~~', 'AB|c'),
    ('3~', '|abcd', '3~', 'ABC|d'),
    ('>>', '|a\nb', '>>', '  |a\nb'),
    ('2>>', '|a\nb\nc', '2>>', '  |a\n  b\nc'),
    ('<<', '    |a', '<<', '  |a'),
    ('>j', '|a\nb\nc', '>j', '  |a\n  b\nc'),
    ('p on empty buffer register', '|abc', 'p', '|abc'),
  ]);

  table('insert entries', [
    ('i', 'a|c', 'ib<Esc>', 'a|bc'),
    ('a', '|ac', 'ab<Esc>', 'a|bc'),
    ('a at end', 'ab|', 'ac<Esc>', 'ab|c'),
    ('I', '  a|b', 'IX<Esc>', '  |Xab'),
    ('A', '|ab\ncd', 'AX<Esc>', 'ab|X\ncd'),
    ('o', 'a|b\ncd', 'oX<Esc>', 'ab\n|X\ncd'),
    ('O', 'ab\nc|d', 'OX<Esc>', 'ab\n|X\ncd'),
    ('o on last line', 'a|b', 'oX<Esc>', 'ab\n|X'),
    ('3ix repeats', '|a', '3iX<Esc>', 'XX|Xa'),
    ('3ox repeats lines', '|a', '3oX<Esc>', 'a\nX\nX\n|X'),
    ('Esc moves left', 'ab|c', 'iX<Esc>', 'ab|Xc'),
    ('Esc at line start stays', '|ab', 'iX<Esc>', '|Xab'),
    ('backspace in insert', '|ab', 'ixy<BS><BS><Esc>', '|ab'),
    ('multi-line insert', '|a', 'Ax<CR>y<Esc>', 'ax\n|y'),
  ]);

  table('text objects', [
    ('diw', 'foo b|ar baz', 'diw', 'foo | baz'),
    ('diw on blanks', 'foo| bar', 'diw', 'foo|bar'),
    ('daw', 'foo b|ar baz', 'daw', 'foo |baz'),
    ('daw at end takes leading blank', 'foo ba|r', 'daw', 'fo|o'),
    ('ciw', 'foo b|ar baz', 'ciwX<Esc>', 'foo |X baz'),
    ('yiw P', 'foo b|ar', 'yiwP', 'foo ba|rbar'),
    ('diW', 'x fo|o.bar y', 'diW', 'x | y'),
    ('dip', 'a\nb|\n\nc', 'dip', '|\nc'),
    ('dap', 'a\nb|\n\nc', 'dap', '|c'),
    ('dap last paragraph takes blank before', 'a\n\nb|', 'dap', '|a'),
    ('yip p', '|a\nb\n\nc', 'yipGp', 'a\nb\n\nc\n|a\nb'),
    ('di"', 'x "a|bc" y', 'di"', 'x "|" y'),
    ('da"', 'x "a|bc" y', 'da"', 'x |y'),
    ('di" before the quotes', '|x "abc" y', 'di"', 'x "|" y'),
    ("di'", "x 'a|b' y", "di'", "x '|' y"),
    ('ci"', 'say "he|llo"', 'ci"X<Esc>', 'say "|X"'),
    ('di(', 'f(a, |b)', 'di(', 'f(|)'),
    ('da(', 'f(a, |b) x', 'da(', 'f| x'),
    ('di( nested', 'f(a, (b|), c)', 'di(', 'f(a, (|), c)'),
    ('di) alias', 'f(a|)', 'di)', 'f(|)'),
    ('dib alias', 'f(a|)', 'dib', 'f(|)'),
    ('di[', 'x[a|b]', 'di[', 'x[|]'),
    ('da[', 'x[a|b]y', 'da[', 'x|y'),
    ('di{', 'x{a|b}', 'di{', 'x{|}'),
    ('da{', 'x{a|b}y', 'da{', 'x|y'),
    ('di{ multiline', '{\n  a|\n}', 'di{', '{\n|}'),
    ('di( on the bracket', '|(abc)', 'di(', '(|)'),
    ('no object', 'a|b', 'di(', 'a|b'),
  ]);

  table('visual', [
    ('v d', '|abcd', 'vld', '|cd'),
    ('v extends with motion', '|foo bar', 'vwd', '|ar'),
    ('v e d', '|foo bar', 'ved', '| bar'),
    ('v y p', '|abc', 'vly\$p', 'abca|b'),
    ('v c', '|foo bar', 'vecX<Esc>', '|X bar'),
    ('v x', '|abc', 'vx', '|bc'),
    ('v backwards', 'ab|cd', 'vhd', 'a|d'),
    ('v o swaps ends', '|abcd', 'vllold', 'a|d'),
    ('v Esc leaves', 'a|bc', 'vl<Esc>x', 'a|b'),
    ('v v leaves', 'a|bc', 'vvx', 'a|c'),
    ('V d', 'a\n|b\nc', 'Vd', 'a\n|c'),
    ('V j d', '|a\nb\nc', 'Vjd', '|c'),
    ('V y p', '|a\nb', 'Vyp', 'a\n|a\nb'),
    ('V c', 'a\n|bcd\ne', 'VcX<Esc>', 'a\n|X\ne'),
    ('V > indents', '|a\nb', 'Vj>', '  |a\n  b'),
    ('v iw', 'foo b|ar baz', 'viwd', 'foo | baz'),
    ('v i(', 'f(a|b)', 'vi(d', 'f(|)'),
    ('v ip goes linewise', 'a\nb|\n\nc', 'vipd', '|\nc'),
    ('v J', '|a\nb', 'vjJ', 'a| b'),
    ('v ~', '|abc', 'vl~', '|ABc'),
    ('v u / U', '|ABC', 'vlu', '|abC'),
    ('v U', '|abc', 'vlU', '|ABc'),
    ('v r', '|abc', 'vlrx', '|xxc'),
    ('v p replaces', '|ab cd', 'yiwwviwp', 'ab |ab'),
    ('v D deletes the line', 'a\nb|c\nd', 'vD', 'a\n|d'),
    ('v Y yanks the line', 'a|b\nc', 'vYGp', 'ab\nc\n|ab'),
    ('v with count', '|abcdef', 'v3ld', '|ef'),
    ('v \$', '|ab cd', r'v$d', '|'),
    ('V G', '|a\nb\nc', 'VGd', '|'),
  ]);

  group('modes and selection', () {
    test('starts in NORMAL with a one char block selection', () {
      final e = mk('a|bc');
      expect(e.mode, VimMode.normal);
      expect(
        e.value.selection,
        const TextSelection(baseOffset: 1, extentOffset: 2),
      );
      expect(e.modeLabel, 'NORMAL');
    });

    test('empty line and end of text show a collapsed caret', () {
      expect(mk('|').value.selection, const TextSelection.collapsed(offset: 0));
      expect(
        mk('a\n|\nb').value.selection,
        const TextSelection.collapsed(offset: 2),
      );
    });

    test('INSERT selection is collapsed at the cursor', () {
      final e = mk('a|bc');
      e.feed('i');
      expect(e.mode, VimMode.insert);
      expect(e.modeLabel, 'INSERT');
      expect(e.value.selection, const TextSelection.collapsed(offset: 1));
    });

    test('INSERT does not take keys, Esc leaves', () {
      final e = mk('abc');
      e.feed('i');
      expect(e.feed('x'), isFalse);
      expect(e.feed('Esc'), isTrue);
      expect(e.mode, VimMode.normal);
    });

    test('Esc in NORMAL does nothing', () {
      final e = mk('a|bc');
      e.feed('Esc');
      expect(e.mode, VimMode.normal);
      expect(show(e), 'a|bc');
    });

    test('VISUAL selection covers both ends inclusive', () {
      final e = mk('|abcd');
      run(e, 'vll');
      expect(e.modeLabel, 'VISUAL');
      expect(
        e.value.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
    });

    test('backwards VISUAL selection is reversed', () {
      final e = mk('ab|cd');
      run(e, 'vh');
      expect(
        e.value.selection,
        const TextSelection(baseOffset: 3, extentOffset: 1),
      );
    });

    test('V-LINE selects whole lines', () {
      final e = mk('a\nb|c\nd');
      run(e, 'V');
      expect(e.modeLabel, 'V-LINE');
      expect(
        e.value.selection,
        const TextSelection(baseOffset: 2, extentOffset: 4),
      );
    });

    test('mode label of every mode', () {
      final e = mk('a');
      expect(e.modeLabel, 'NORMAL');
      run(e, 'v');
      expect(e.modeLabel, 'VISUAL');
      run(e, 'V');
      expect(e.modeLabel, 'V-LINE');
    });

    test('pending shows unfinished keys', () {
      final e = mk('abc');
      run(e, '2d');
      expect(e.pending, '2d');
      run(e, 'w');
      expect(e.pending, '');
      run(e, 'g');
      expect(e.pending, 'g');
      run(e, '<Esc>');
      expect(e.pending, '');
    });

    test('bad key after an operator cancels it', () {
      final e = mk('|abc');
      run(e, 'dzx');
      expect(show(e), '|bc');
    });

    test('external text change in NORMAL is adopted', () {
      final e = mk('|abc');
      e.external(const TextEditingValue(text: 'xy'));
      expect(e.text, 'xy');
      expect(e.cursor, 0);
    });

    test('enterInsertAt starts INSERT at the click', () {
      final e = mk('abc');
      e.enterInsertAt(2);
      expect(e.mode, VimMode.insert);
      expect(e.value.selection, const TextSelection.collapsed(offset: 2));
    });

    test('enterInsertAt keeps a dragged selection', () {
      final e = mk('abcd');
      e.enterInsertAt(1, 3);
      expect(
        e.value.selection,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      );
    });
  });

  group('registers', () {
    test('yank sets the unnamed register charwise', () {
      final e = mk('|foo bar');
      run(e, 'yw');
      expect(e.register!.text, 'foo ');
      expect(e.register!.linewise, isFalse);
    });

    test('yy sets it linewise', () {
      final e = mk('|foo\nbar');
      run(e, 'yy');
      expect(e.register!.text, 'foo');
      expect(e.register!.linewise, isTrue);
    });

    test('delete sets it', () {
      final e = mk('|foo bar');
      run(e, 'dw');
      expect(e.register!.text, 'foo ');
    });

    test('p with an empty register does nothing', () {
      final e = mk('|abc');
      run(e, 'p');
      expect(e.text, 'abc');
    });

    test('yank leaves the cursor at the start of the range', () {
      final e = mk('foo ba|r');
      run(e, 'yb');
      expect(show(e), 'foo |bar');
    });
  });

  group('undo and redo', () {
    test('u undoes one change', () {
      final e = mk('|abc');
      run(e, 'xx');
      run(e, 'u');
      expect(e.text, 'bc');
      run(e, 'u');
      expect(e.text, 'abc');
    });

    test('an insert session is one undo step', () {
      final e = mk('|abc');
      run(e, 'ixyz<Esc>');
      expect(e.text, 'xyzabc');
      run(e, 'u');
      expect(e.text, 'abc');
    });

    test('cw with typing is one undo step', () {
      final e = mk('|foo bar');
      run(e, 'cwxyz<Esc>');
      run(e, 'u');
      expect(e.text, 'foo bar');
    });

    test('3u undoes three', () {
      final e = mk('|abcdef');
      run(e, 'xxx3u');
      expect(e.text, 'abcdef');
    });

    test('Ctrl-r redoes', () {
      final e = mk('|abc');
      run(e, 'xxuu');
      expect(e.text, 'abc');
      run(e, '<C-r>');
      expect(e.text, 'bc');
      run(e, '<C-r>');
      expect(e.text, 'c');
      run(e, '<C-r>');
      expect(e.text, 'c');
    });

    test('a new change clears redo', () {
      final e = mk('|abc');
      run(e, 'xux');
      run(e, '<C-r>');
      expect(e.text, 'bc');
    });

    test('empty insert is not an undo step', () {
      final e = mk('|abc');
      run(e, 'x');
      run(e, 'i<Esc>');
      run(e, 'u');
      expect(e.text, 'abc');
    });

    test('u with nothing to undo is a no-op', () {
      final e = mk('|abc');
      run(e, 'u');
      expect(e.text, 'abc');
      expect(e.canUndo, isFalse);
    });

    test('undo puts the cursor at the change', () {
      final e = mk('abc def|');
      run(e, 'bdw');
      run(e, 'G0');
      run(e, 'u');
      expect(e.cursor, 4);
    });

    test('engine undo works from INSERT (Ctrl+Z)', () {
      final e = mk('|abc');
      run(e, 'ixy');
      expect(e.text, 'xyabc');
      expect(e.undo(), isTrue);
      expect(e.text, 'abc');
      expect(e.mode, VimMode.insert);
      // typing continues as a fresh session
      run(e, 'q<Esc>');
      expect(e.text, 'qabc');
      run(e, 'u');
      expect(e.text, 'abc');
    });

    test('Ctrl+Z in INSERT with an empty session undoes the previous step', () {
      final e = mk('|abc');
      run(e, 'x');
      run(e, 'i');
      expect(e.undo(), isTrue);
      expect(e.text, 'abc');
    });

    test('redo from INSERT', () {
      final e = mk('|abc');
      run(e, 'xu');
      run(e, 'i');
      expect(e.redo(), isTrue);
      expect(e.text, 'bc');
    });

    test('undo after visual delete', () {
      final e = mk('|abcd');
      run(e, 'vlldu');
      expect(e.text, 'abcd');
      expect(e.mode, VimMode.normal);
    });

    test('dot repeat replay is one undo step', () {
      final e = mk('|a b c d');
      run(e, 'dw.');
      expect(e.text, 'c d');
      run(e, 'u');
      expect(e.text, 'b c d');
    });
  });

  group('dot repeat', () {
    test('x', () {
      final e = mk('|abcd');
      run(e, 'x.');
      expect(show(e), '|cd');
    });

    test('dw', () {
      final e = mk('|a b c d');
      run(e, 'dw..');
      expect(show(e), '|d');
    });

    test('dd with count', () {
      final e = mk('|a\nb\nc\nd\ne');
      run(e, '2dd.');
      expect(show(e), '|e');
    });

    test('cw with typed text', () {
      final e = mk('|foo bar baz');
      run(e, 'cwX<Esc>w.');
      expect(e.text, 'X X baz');
    });

    test('insert session', () {
      final e = mk('|ab');
      run(e, 'Ax<Esc>');
      run(e, 'j.');
      expect(e.text, 'abxx');
    });

    test('o repeats', () {
      final e = mk('|a');
      run(e, 'oX<Esc>.');
      expect(e.text, 'a\nX\nX');
    });

    test('3ix repeats with the count', () {
      final e = mk('|a');
      run(e, '3iX<Esc>');
      run(e, '.');
      expect(e.text, 'XXXXXXa');
    });

    test('p repeats', () {
      final e = mk('|ab');
      run(e, 'ylp.');
      expect(e.text, 'aaab');
    });

    test('J repeats', () {
      final e = mk('|a\nb\nc');
      run(e, 'J.');
      expect(e.text, 'a b c');
    });

    test('text object operator repeats', () {
      final e = mk('|"a" "b"');
      run(e, 'di"');
      run(e, 'fb');
      run(e, '.');
      expect(e.text, '"" ""');
    });

    test('r repeats', () {
      final e = mk('|abc');
      run(e, 'rXl.');
      expect(e.text, 'XXc');
    });

    test('yank is not repeated', () {
      final e = mk('|ab');
      run(e, 'xyl.');
      expect(e.text, '');
    });

    test('dot with no change does nothing', () {
      final e = mk('|ab');
      run(e, '.');
      expect(e.text, 'ab');
    });

    test('>> repeats', () {
      final e = mk('|a\nb');
      run(e, '>>j.');
      expect(e.text, '  a\n  b');
    });
  });

  group('search', () {
    test('/ finds the next match', () {
      final e = mk('|foo bar foo');
      run(e, '/foo<CR>');
      expect(show(e), 'foo bar |foo');
    });

    test('wraps around', () {
      final e = mk('foo bar fo|o');
      run(e, '/bar<CR>');
      expect(show(e), 'foo |bar foo');
    });

    test('n and N', () {
      final e = mk('|a x a x a');
      run(e, '/a<CR>');
      expect(e.cursor, 4);
      run(e, 'n');
      expect(e.cursor, 8);
      run(e, 'n');
      expect(e.cursor, 0);
      run(e, 'N');
      expect(e.cursor, 8);
    });

    test('? searches backward and n continues backward', () {
      final e = mk('a x a x |a');
      run(e, '?x<CR>');
      expect(e.cursor, 6);
      run(e, 'n');
      expect(e.cursor, 2);
      run(e, 'N');
      expect(e.cursor, 6);
    });

    test('regex pattern', () {
      final e = mk('|ab 12 cd');
      run(e, r'/\d+<CR>');
      expect(show(e), 'ab |12 cd');
    });

    test('invalid regex falls back to literal', () {
      final e = mk('|a (b c');
      run(e, '/(b<CR>');
      expect(show(e), 'a |(b c');
    });

    test('not found keeps the cursor and says so', () {
      final e = mk('|abc');
      run(e, '/zzz<CR>');
      expect(show(e), '|abc');
      expect(e.message, contains('not found'));
    });

    test('empty pattern reuses the last one', () {
      final e = mk('|a x a x a');
      run(e, '/a<CR>/<CR>');
      expect(e.cursor, 8);
    });

    test('count n', () {
      final e = mk('|a a a a');
      run(e, '/a<CR>');
      run(e, '2n');
      expect(e.cursor, 6);
    });

    test('dn deletes to the next match', () {
      final e = mk('|ab cd ab');
      run(e, '/ab<CR>');
      run(e, 'G0');
      run(e, 'dn');
      expect(e.text, 'ab');
    });

    test('search line shows in lineText and Esc cancels', () {
      final e = mk('abc');
      run(e, '/ab');
      expect(e.lineText, '/ab');
      run(e, '<Esc>');
      expect(e.lineText, isNull);
    });

    test('Backspace on an empty line cancels', () {
      final e = mk('abc');
      run(e, '/<BS>');
      expect(e.lineText, isNull);
    });

    test('search extends VISUAL', () {
      final e = mk('|ab cd ab');
      run(e, 'v/cd<CR>d');
      expect(e.text, 'd ab');
    });

    test('n without a pattern does nothing', () {
      final e = mk('a|bc');
      run(e, 'n');
      expect(show(e), 'a|bc');
    });
  });

  group('ex line', () {
    test('typing shows the line, BS edits it', () {
      final e = mk('abc');
      run(e, ':wq');
      expect(e.lineText, ':wq');
      run(e, '<BS>');
      expect(e.lineText, ':w');
      run(e, '<Esc>');
      expect(e.lineText, isNull);
      expect(e.mode, VimMode.normal);
    });

    final cmds = <String, VimAction>{
      ':w<CR>': VimAction.write,
      ':write<CR>': VimAction.write,
      ':q<CR>': VimAction.quit,
      ':q!<CR>': VimAction.forceQuit,
      ':wq<CR>': VimAction.writeQuit,
      ':x<CR>': VimAction.writeQuit,
      'ZZ': VimAction.writeQuit,
      'ZQ': VimAction.quit,
    };
    cmds.forEach((keys, action) {
      test('$keys asks for $action', () {
        final log = <VimAction>[];
        final e = mk('abc', actions: log);
        run(e, keys);
        expect(log, [action]);
        expect(e.lineText, isNull);
      });
    });

    test(':3 goes to line 3', () {
      final e = mk('a\nb\n  c\nd');
      run(e, ':3<CR>');
      expect(show(e), 'a\nb\n  |c\nd');
    });

    test(':99 clamps to the last line', () {
      final e = mk('a\nb');
      run(e, ':99<CR>');
      expect(show(e), 'a\n|b');
    });

    test(r':$ goes to the last line', () {
      final e = mk('|a\nb\nc');
      run(e, r':$<CR>');
      expect(show(e), 'a\nb\n|c');
    });

    test('unknown command gives a message', () {
      final e = mk('abc');
      run(e, ':foo<CR>');
      expect(e.message, contains('foo'));
      run(e, 'l');
      expect(e.message, '');
    });

    test('ZX is not a command', () {
      final log = <VimAction>[];
      final e = mk('abc', actions: log);
      run(e, 'ZX');
      expect(log, isEmpty);
    });

    test(': from VISUAL leaves VISUAL', () {
      final log = <VimAction>[];
      final e = mk('abc', actions: log);
      run(e, 'v:w<CR>');
      expect(e.mode, VimMode.normal);
      expect(log, [VimAction.write]);
    });

    test('empty command does nothing', () {
      final log = <VimAction>[];
      final e = mk('abc', actions: log);
      run(e, ':<CR>');
      expect(log, isEmpty);
    });
  });

  group('leader', () {
    test('Space starts the leader and shows it', () {
      final e = mk('abc', leader: (k) => const LeaderStep.wait());
      run(e, '<Space>');
      expect(e.pending, '<Space>');
      run(e, 'g');
      expect(e.pending, '<Space>g');
    });

    test('resolver run', () {
      var ran = '';
      final e = mk(
        'abc',
        leader: (k) {
          if (k.join() == 'g') return const LeaderStep.wait();
          if (k.join() == 'gt') return LeaderStep.run(() => ran = 'tasks');
          return const LeaderStep.none();
        },
      );
      run(e, '<Space>gt');
      expect(ran, 'tasks');
      expect(e.pending, '');
      expect(e.text, 'abc');
    });

    test('a key that is not bound cancels', () {
      var ran = false;
      final e = mk('abc', leader: (k) => const LeaderStep.none());
      run(e, '<Space>z');
      expect(ran, isFalse);
      expect(e.pending, '');
      run(e, 'x');
      expect(e.text, 'bc');
    });

    test('Esc cancels the leader', () {
      final e = mk('abc', leader: (k) => const LeaderStep.wait());
      run(e, '<Space>g<Esc>');
      expect(e.pending, '');
    });

    test('Space Space reaches the resolver as one space key', () {
      List<String>? got;
      final e = mk(
        'abc',
        leader: (k) {
          got = k;
          return const LeaderStep.none();
        },
      );
      run(e, '<Space><Space>');
      expect(got, [' ']);
    });

    test('no leader in VISUAL mode', () {
      final e = mk('|abc', leader: (k) => const LeaderStep.wait());
      run(e, 'v');
      run(e, '<Space>');
      expect(e.pending, isNot(startsWith('<Space>g')));
    });
  });

  group('text helpers', () {
    test('lineStart / lineEnd', () {
      const t = 'ab\ncd\n\nef';
      expect(lineStart(t, 0), 0);
      expect(lineStart(t, 2), 0);
      expect(lineStart(t, 3), 3);
      expect(lineEnd(t, 3), 5);
      expect(lineStart(t, 6), 6);
      expect(lineEnd(t, 6), 6);
      expect(lineEnd(t, 9), 9);
    });

    test('lineStarts / lineNoOf', () {
      final s = lineStarts('a\nb\n');
      expect(s, [0, 2, 4]);
      expect(lineNoOf(s, 3), 1);
      expect(lineNoOf(s, 4), 2);
    });

    test('char classes', () {
      expect(charClass('a', false), 2);
      expect(charClass('_', false), 2);
      expect(charClass('.', false), 1);
      expect(charClass(' ', false), 0);
      expect(charClass('.', true), 1);
      expect(charClass('é', false), 2);
    });

    test('unicode words', () {
      final e = mk('|héllo wörld');
      run(e, 'dw');
      expect(e.text, 'wörld');
    });

    test('empty text is safe for every key', () {
      for (final k in 'hjklwbeWBE0^\$GgxXDdCcYyJ~pPuo.nN%{};,'.split('')) {
        final e = mk('');
        run(e, k);
        run(e, '<Esc>');
        expect(e.text.length < 3, isTrue, reason: k);
      }
    });

    test('operators on empty text are safe', () {
      for (final k in [
        'dd',
        'dw',
        'cc',
        'yy',
        'D',
        'dG',
        'dgg',
        'd}',
        'x',
        '>>',
      ]) {
        final e = mk('');
        run(e, k);
        run(e, '<Esc>');
        expect(e.cursor, 0, reason: k);
      }
    });
  });

  group('help table', () {
    test('lists the main bindings', () {
      final keys = vimHelpRows.map((r) => r.$1).join(' | ');
      for (final k in [':wq', 'ZZ', ':q!', 'Space', 'u Ctrl+r', 'd c y']) {
        expect(keys, contains(k));
      }
      expect(vimHelpGroup, 'Vim editing');
    });
  });
}
