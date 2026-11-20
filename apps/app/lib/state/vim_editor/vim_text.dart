import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Characters;

/// Pure text helpers of the Vim editing engine: lines, word classes and
/// text objects over a plain string. Offsets are UTF-16 code units, but
/// character steps ([snapDown], [snapUp], [nextChar], [prevChar]) move by
/// grapheme clusters, so a caret never lands inside a surrogate pair or a
/// combining sequence. A line ends at `\n` or `\r\n`.

final _wordRe = RegExp(r'[\p{L}\p{N}\p{M}_]', unicode: true);

/// The largest grapheme boundary at or before [i].
int snapDown(String t, int i) => _snap(t, i, false);

/// The smallest grapheme boundary at or after [i].
int snapUp(String t, int i) => _snap(t, i, true);

/// The boundary after the cluster that starts at [i].
int nextChar(String t, int i) => i >= t.length ? t.length : snapUp(t, i + 1);

/// The start of the cluster that ends at [i].
int prevChar(String t, int i) => i <= 0 ? 0 : snapDown(t, i - 1);

/// [i] moved [n] clusters forward, not past [limit].
int stepFwd(String t, int i, int n, int limit) {
  var p = i;
  for (var k = 0; k < n && p < limit; k++) {
    p = nextChar(t, p);
  }
  return math.min(p, limit);
}

/// [i] moved [n] clusters back, not before [limit].
int stepBack(String t, int i, int n, int limit) {
  var p = i;
  for (var k = 0; k < n && p > limit; k++) {
    p = prevChar(t, p);
  }
  return math.max(p, limit);
}

int _snap(String t, int i, bool up) {
  if (i <= 0) return 0;
  if (i >= t.length) return t.length;
  final a = t.codeUnitAt(i - 1);
  final b = t.codeUnitAt(i);
  // Below U+0300 nothing combines, except the CR LF pair.
  if (a < 0x300 && b < 0x300 && !(a == 13 && b == 10)) return i;
  final s = math.max(lineStart(t, i), i - 4096);
  final sub = t.substring(s, math.min(t.length, i + 4096));
  var pos = s;
  for (final g in Characters(sub)) {
    final end = pos + g.length;
    if (end > i) return pos == i ? i : (up ? end : pos);
    pos = end;
  }
  return i;
}

/// Length of the line terminator at [le] (a line end): 2 for CRLF, 1 for LF,
/// 0 at the text end.
int nlLen(String t, int le) {
  if (le >= t.length) return 0;
  return t.codeUnitAt(le) == 13 &&
          le + 1 < t.length &&
          t.codeUnitAt(le + 1) == 10
      ? 2
      : 1;
}

/// Whether the line starting at [j] is empty (and not the text end).
bool emptyLineAt(String t, int j) =>
    j < t.length && lineStart(t, j) == j && lineEnd(t, j) == j;

/// Start offset of the line containing offset [i].
int lineStart(String t, int i) {
  if (i <= 0) return 0;
  if (i > t.length) i = t.length;
  return t.lastIndexOf('\n', i - 1) + 1;
}

/// Offset of the newline ending the line containing [i] (or the text end).
int lineEnd(String t, int i) {
  if (i < 0) i = 0;
  if (i >= t.length) return t.length;
  final k = t.indexOf('\n', i);
  if (k < 0) return t.length;
  return k > i && t.codeUnitAt(k - 1) == 13 ? k - 1 : k;
}

/// Start offsets of every line (always at least one).
List<int> lineStarts(String t) {
  final r = <int>[0];
  for (var i = 0; i < t.length; i++) {
    if (t.codeUnitAt(i) == 10) r.add(i + 1);
  }
  return r;
}

/// Index of the line holding offset [i] among [starts].
int lineNoOf(List<int> starts, int i) {
  var n = 0;
  for (var k = 0; k < starts.length; k++) {
    if (starts[k] <= i) n = k;
  }
  return n;
}

/// First non-blank offset of the line starting at [ls] (the line end when
/// the line is blank).
int firstNonBlank(String t, int ls) {
  final le = lineEnd(t, ls);
  var j = ls;
  while (j < le && (t[j] == ' ' || t[j] == '\t')) {
    j++;
  }
  return j;
}

/// 0 blank, 1 punctuation, 2 word character. With [big] (W B E) every
/// non-blank is one class.
int charClass(String ch, bool big) {
  if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') return 0;
  if (big) return 1;
  return _wordRe.hasMatch(ch) ? 2 : 1;
}

/// `w` / `W`: start of the next word (an empty line counts as a word).
int nextWordStart(String t, int i, bool big) {
  final len = t.length;
  var j = i;
  if (j >= len) return len;
  final c0 = charClass(t[j], big);
  if (c0 != 0) {
    while (j < len && charClass(t[j], big) == c0) {
      j++;
    }
  }
  while (j < len && charClass(t[j], big) == 0) {
    if (j > i && emptyLineAt(t, j)) break;
    j++;
  }
  return j;
}

/// `b` / `B`: start of the previous word.
int prevWordStart(String t, int i, bool big) {
  if (i <= 0) return 0;
  var j = math.min(i, t.length) - 1;
  while (j > 0 && charClass(t[j], big) == 0) {
    if (emptyLineAt(t, j)) return j;
    j--;
  }
  if (charClass(t[j], big) == 0) return 0;
  final c = charClass(t[j], big);
  while (j > 0 && charClass(t[j - 1], big) == c) {
    j--;
  }
  return j;
}

/// `e` / `E`: last character of the next word end (at least one step on).
int wordEnd(String t, int i, bool big) {
  final len = t.length;
  var j = i + 1;
  while (j < len && charClass(t[j], big) == 0) {
    j++;
  }
  if (j >= len) return math.max(0, len - 1);
  final c = charClass(t[j], big);
  while (j + 1 < len && charClass(t[j + 1], big) == c) {
    j++;
  }
  return j;
}

/// Last character of the word run under [i] (stays when already there).
int runEnd(String t, int i, bool big) {
  final c = charClass(t[i], big);
  var j = i;
  while (j + 1 < t.length && charClass(t[j + 1], big) == c) {
    j++;
  }
  return j;
}

/// A text object range. Characterwise: offsets [s, e) ; linewise: line
/// numbers s..e inclusive.
class VimRange {
  const VimRange(this.s, this.e, {this.linewise = false});
  final int s;
  final int e;
  final bool linewise;
}

const _pairs = {'(': ')', '[': ']', '{': '}', '<': '>'};
const _closers = {')': '(', ']': '[', '}': '{', '>': '<'};
const _aliases = {'b': '(', 'B': '{'};

/// The text object `i<obj>` or `a<obj>` ([inner] true for i) around offset
/// [c], or null when there is none. Objects: `w W p " ' ` ( ) b [ ] { } B < >`.
VimRange? textObject(String t, int c, bool inner, String obj) {
  switch (obj) {
    case 'w':
    case 'W':
      return _wordObject(t, c, inner, obj == 'W');
    case 'p':
      return _paragraphObject(t, c, inner);
    case '"':
    case "'":
    case '`':
      return _quoteObject(t, c, inner, obj);
  }
  final o = _aliases[obj] ?? (_pairs.containsKey(obj) ? obj : _closers[obj]);
  if (o == null) return null;
  return _bracketObject(t, c, inner, o, _pairs[o]!);
}

VimRange? _wordObject(String t, int c, bool inner, bool big) {
  if (t.isEmpty || c >= lineEnd(t, c)) return null;
  final ls = lineStart(t, c);
  final le = lineEnd(t, c);
  final cl = charClass(t[c], big);
  var s = c;
  var e = c;
  while (s > ls && charClass(t[s - 1], big) == cl) {
    s--;
  }
  while (e + 1 < le && charClass(t[e + 1], big) == cl) {
    e++;
  }
  e++;
  if (inner) return VimRange(s, e);
  bool blank(int i) => t[i] == ' ' || t[i] == '\t';
  if (cl == 0) {
    // On blanks: the blanks and the word after them.
    if (e < le) {
      final wc = charClass(t[e], big);
      while (e < le && charClass(t[e], big) == wc) {
        e++;
      }
    }
    return VimRange(s, e);
  }
  var trail = e;
  while (trail < le && blank(trail)) {
    trail++;
  }
  if (trail > e) return VimRange(s, trail);
  while (s > ls && blank(s - 1)) {
    s--;
  }
  return VimRange(s, e);
}

VimRange? _paragraphObject(String t, int c, bool inner) {
  final starts = lineStarts(t);
  final last = starts.length - 1;
  bool blankLine(int n) {
    final s = starts[n];
    return t.substring(s, lineEnd(t, s)).trim().isEmpty;
  }

  final n = lineNoOf(starts, c);
  final b = blankLine(n);
  var s = n;
  var e = n;
  while (s > 0 && blankLine(s - 1) == b) {
    s--;
  }
  while (e < last && blankLine(e + 1) == b) {
    e++;
  }
  if (inner) return VimRange(s, e, linewise: true);
  if (e < last) {
    // The following block of the other kind.
    final nb = blankLine(e + 1);
    e++;
    while (e < last && blankLine(e + 1) == nb) {
      e++;
    }
  } else if (!b && s > 0) {
    // No blank lines after: take the ones before.
    s--;
    while (s > 0 && blankLine(s - 1)) {
      s--;
    }
  }
  return VimRange(s, e, linewise: true);
}

VimRange? _quoteObject(String t, int c, bool inner, String q) {
  if (c >= t.length) return null;
  final ls = lineStart(t, c);
  final le = lineEnd(t, c);
  final pos = <int>[];
  for (var i = ls; i < le; i++) {
    if (t[i] == q && (i == ls || t[i - 1] != '\\')) pos.add(i);
  }
  (int, int)? pair;
  for (var k = 0; k + 1 < pos.length; k += 2) {
    if (pos[k] <= c && c <= pos[k + 1]) {
      pair = (pos[k], pos[k + 1]);
      break;
    }
  }
  if (pair == null) {
    for (var k = 0; k + 1 < pos.length; k += 2) {
      if (pos[k] > c) {
        pair = (pos[k], pos[k + 1]);
        break;
      }
    }
  }
  if (pair == null) return null;
  final (a, b) = pair;
  if (inner) return VimRange(a + 1, b);
  var e = b + 1;
  var s = a;
  final hasTrail = e < le && (t[e] == ' ' || t[e] == '\t');
  if (hasTrail) {
    while (e < le && (t[e] == ' ' || t[e] == '\t')) {
      e++;
    }
  } else {
    while (s > ls && (t[s - 1] == ' ' || t[s - 1] == '\t')) {
      s--;
    }
  }
  return VimRange(s, e);
}

VimRange? _bracketObject(
  String t,
  int c,
  bool inner,
  String open,
  String close,
) {
  if (c >= t.length) return null;
  int? o;
  if (t[c] == open) {
    o = c;
  } else {
    var depth = 0;
    for (var i = t[c] == close ? c - 1 : c; i >= 0; i--) {
      if (t[i] == close) {
        depth++;
      } else if (t[i] == open) {
        if (depth == 0) {
          o = i;
          break;
        }
        depth--;
      }
    }
  }
  if (o == null) return null;
  var depth = 0;
  int? cl;
  for (var i = o + 1; i < t.length; i++) {
    if (t[i] == open) {
      depth++;
    } else if (t[i] == close) {
      if (depth == 0) {
        cl = i;
        break;
      }
      depth--;
    }
  }
  if (cl == null) return null;
  if (!inner) return VimRange(o, cl + 1);
  var s = o + 1;
  var e = cl;
  // `{` newline ... newline `}`: the inner part is the lines between.
  final nl = s < e ? nlLen(t, s) : 0;
  if (nl > 0 && s == lineEnd(t, s)) {
    final cs = lineStart(t, cl);
    if (t.substring(cs, cl).trim().isEmpty && cs > s) {
      s += nl;
      e = cs;
    }
  }
  return VimRange(s, e);
}

/// The bracket matching the one at or after [c] on its line (`%`), or -1.
int matchBracket(String t, int c) {
  const open = '([{';
  const close = ')]}';
  final le = lineEnd(t, c);
  var i = c;
  while (i < le && !open.contains(t[i]) && !close.contains(t[i])) {
    i++;
  }
  if (i >= le) return -1;
  final ch = t[i];
  if (open.contains(ch)) {
    final cl = close[open.indexOf(ch)];
    var d = 0;
    for (var j = i + 1; j < t.length; j++) {
      if (t[j] == ch) d++;
      if (t[j] == cl) {
        if (d == 0) return j;
        d--;
      }
    }
  } else {
    final op = open[close.indexOf(ch)];
    var d = 0;
    for (var j = i - 1; j >= 0; j--) {
      if (t[j] == ch) d++;
      if (t[j] == op) {
        if (d == 0) return j;
        d--;
      }
    }
  }
  return -1;
}

/// [ch] with its case swapped.
String swapCase(String ch) {
  final u = ch.toUpperCase();
  return u == ch ? ch.toLowerCase() : u;
}
