import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter/services.dart' show TextEditingValue, TextSelection;

import 'vim_text.dart';

/// Modal editing engine of the Vim editor: a pure state machine over text,
/// a cursor and a selection. No widgets: [VimField] feeds it key tokens and
/// mirrors [value] into the text field.
///
/// Key tokens: a printable character (`d`, `G`, `$`, ` `) or one of `Esc`,
/// `Enter`, `BS`, `C-r` and the aliases `Left Right Up Down Home End`.
///
/// In scope: modes NORMAL, INSERT, VISUAL, VISUAL LINE; counts; motions
/// h j k l w b e W B E 0 ^ $ gg G f F t T ; , { } % n N; operators d c y
/// (also > <) with motions, text objects and doubled forms; D C Y x X s S
/// r J ~; put p P from the unnamed register; undo u / redo Ctrl-r with the
/// engine's own stack; dot repeat; search / ? n N; Ex line (:w :q :wq :q!
/// :x :N :$); ZZ ZQ; the Space leader.
///
/// Out of scope (seams marked below): named registers and the system
/// clipboard ([_regSet] / [_reg]), marks, macros, `*` `#`, `gv`, visual
/// block, dot repeat of visual operators, search as an operator motion,
/// counts for text objects, visual-line (wrapped) j/k ([_motionAt] `j`/`k`
/// use logical lines).
enum VimMode { normal, insert, visual, visualLine }

/// What `:w`, `:q`, `:q!`, `:wq`, `ZZ`, `ZQ` ask the host to do.
enum VimAction { write, quit, forceQuit, writeQuit }

/// The host's answer to a leader key sequence.
class LeaderStep {
  const LeaderStep.wait() : wait = true, run = null;
  const LeaderStep.none() : wait = false, run = null;
  const LeaderStep.run(void Function() this.run) : wait = false;
  final bool wait;
  final void Function()? run;
}

/// Resolves the keys typed after `<Space>`: wait for more, run, or nothing.
typedef LeaderResolver = LeaderStep Function(List<String> keys);

/// The unnamed register.
class VimRegister {
  const VimRegister(this.text, {this.linewise = false});
  final String text;
  final bool linewise;
}

class _Snap {
  const _Snap(this.t, this.c);
  final String t;
  final int c;
}

enum _P { more, done, bad }

class _Mot {
  const _Mot(
    this.pos, {
    this.lw = false,
    this.incl = false,
    this.vert = false,
    this.wantInf = false,
  });
  final int pos;
  final bool lw;
  final bool incl;
  final bool vert;
  final bool wantInf;
}

class VimEngine extends ChangeNotifier {
  VimEngine({String text = '', int cursor = 0, this.leader, this.onAction}) {
    _t = text;
    _c = cursor.clamp(0, text.length);
    _clamp();
    _want = _col();
  }

  static const _inf = 1 << 30;

  /// Largest count taken from typed digits, and the limits of repeated
  /// text (insert or put with a count).
  static const maxCount = 9999999;
  static const maxRepeat = 10000;
  static const maxText = 1000000;

  /// Search limits: text scanned, matches kept, a line run through a regex.
  static const maxSearchText = 1000000;
  static const maxMatches = 10000;
  static const maxRegexLine = 10000;
  static const _alias = {
    'Left': 'h',
    'Right': 'l',
    'Up': 'k',
    'Down': 'j',
    'Home': '0',
    'End': r'$',
    'BS': 'h',
  };

  final LeaderResolver? leader;
  final void Function(VimAction action)? onAction;

  String _t = '';
  int _c = 0; // cursor offset (on a character in NORMAL/VISUAL)
  int _ia = 0; // INSERT selection base
  int _anchor = 0;
  int _want = 0;
  VimMode mode = VimMode.normal;

  List<String> _keys = [];
  bool _leaderOn = false;
  final List<String> _leaderKeys = [];
  String? _lineKind; // ':' '/' '?'
  String _line = '';

  /// A one-line message for the footer (Ex errors), cleared on the next key.
  String message = '';

  // Seam: named registers would be a Map<String, VimRegister> here, plus a
  // register prefix (`"a`) in the parser.
  VimRegister? _reg;
  final List<_Snap> _undo = [];
  final List<_Snap> _redo = [];
  _Snap? _session;

  // Insert session
  String _insStartText = '';
  int _insCount = 1;
  bool _insNl = false;
  String _insNlStr = '\n';
  bool _insDot = true;

  // Dot repeat
  List<String>? _dotKeys;
  String? _dotInsert;
  bool _replaying = false;
  bool _wasChange = false;

  (String, String)? _lastFind;
  String? _lastPat;
  bool _lastFwd = true;

  // ------------------------------------------------------------ public

  String get text => _t;
  int get cursor => _c;
  VimRegister? get register => _reg;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// The text and selection the field should show.
  TextEditingValue get value =>
      TextEditingValue(text: _t, selection: _selection());

  String get modeLabel => switch (mode) {
    VimMode.normal => 'NORMAL',
    VimMode.insert => 'INSERT',
    VimMode.visual => 'VISUAL',
    VimMode.visualLine => 'V-LINE',
  };

  /// Keys typed so far of an unfinished command, for the footer.
  String get pending => _leaderOn
      ? '<Space>${_leaderKeys.join(' ')}'
      : _keys.map((k) => k == ' ' ? '<Space>' : k).join();

  /// The Ex / search line being typed (`:wq`), or null.
  String? get lineText => _lineKind == null ? null : '$_lineKind$_line';

  TextSelection _selection() {
    switch (mode) {
      case VimMode.insert:
        return TextSelection(
          baseOffset: _ia.clamp(0, _t.length),
          extentOffset: _c.clamp(0, _t.length),
        );
      case VimMode.normal:
        return _c < lineEnd(_t, _c)
            ? TextSelection(baseOffset: _c, extentOffset: nextChar(_t, _c))
            : TextSelection.collapsed(offset: _c);
      case VimMode.visual:
        final lo = math.min(_anchor, _c);
        final hi = nextChar(_t, math.max(_anchor, _c));
        return _anchor <= _c
            ? TextSelection(baseOffset: lo, extentOffset: hi)
            : TextSelection(baseOffset: hi, extentOffset: lo);
      case VimMode.visualLine:
        final lo = lineStart(_t, math.min(_anchor, _c));
        final hi = lineEnd(_t, math.max(_anchor, _c));
        return _anchor <= _c
            ? TextSelection(baseOffset: lo, extentOffset: hi)
            : TextSelection(baseOffset: hi, extentOffset: lo);
    }
  }

  /// The field's value changed by itself (typing in INSERT, programmatic
  /// edits). Does not notify: the field already shows it.
  void external(TextEditingValue v) {
    _t = v.text;
    if (mode == VimMode.insert) {
      final s = v.selection;
      if (s.isValid) {
        _c = s.extentOffset.clamp(0, _t.length);
        _ia = s.baseOffset.clamp(0, _t.length);
      }
      _c = _c.clamp(0, _t.length);
    } else {
      _anchor = snapDown(_t, _anchor.clamp(0, _t.length));
      _clamp();
    }
  }

  /// A mouse click placed the caret: enter INSERT there (and keep a dragged
  /// selection).
  void enterInsertAt(int offset, [int? extent]) {
    _keys = [];
    _leaderOn = false;
    _leaderKeys.clear();
    _lineKind = null;
    if (mode == VimMode.insert) return;
    mode = VimMode.insert;
    _c = snapDown(_t, (extent ?? offset).clamp(0, _t.length));
    _ia = snapDown(_t, offset.clamp(0, _t.length));
    _insStartText = _t;
    _insCount = 1;
    _insNl = false;
    _insDot = false;
    _session = _Snap(_t, _c);
    notifyListeners();
  }

  /// Feeds one key token. Returns false when the engine did not use it
  /// (a key in INSERT mode, which belongs to the text input).
  bool feed(String k) {
    message = '';
    if (_lineKind != null) {
      _feedLine(k);
      notifyListeners();
      return true;
    }
    if (mode == VimMode.insert) {
      if (k != 'Esc') return false;
      _exitInsert();
      notifyListeners();
      return true;
    }
    _feedNormal(k);
    notifyListeners();
    return true;
  }

  /// Shows [m] in the footer (the host reports a failed `:w`).
  void fail(String m) {
    message = m;
    notifyListeners();
  }

  /// Undo (also Ctrl+Z in any mode). False when there is nothing to undo.
  bool undo() {
    if (mode == VimMode.visual || mode == VimMode.visualLine) {
      mode = VimMode.normal;
    }
    if (mode == VimMode.insert) {
      final s = _session;
      if (s != null && s.t != _t) {
        _redo.add(_Snap(_t, _c));
        _restore(s.t, s.c);
        _resetSession();
        notifyListeners();
        return true;
      }
    }
    if (_undo.isEmpty) return false;
    final s = _undo.removeLast();
    _redo.add(_Snap(_t, _c));
    final at = _firstDiff(_t, s.t);
    _restore(s.t, mode == VimMode.insert ? s.c : at);
    if (mode == VimMode.insert) _resetSession();
    notifyListeners();
    return true;
  }

  /// Redo (Ctrl-r, Ctrl+Shift+Z). False when there is nothing to redo.
  bool redo() {
    if (mode == VimMode.insert) _flushSession();
    if (_redo.isEmpty) return false;
    final s = _redo.removeLast();
    _undo.add(_Snap(_t, _c));
    final at = _firstDiff(_t, s.t);
    _restore(s.t, mode == VimMode.insert ? s.c : at);
    if (mode == VimMode.insert) _resetSession();
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------ helpers

  int _col() => _c - lineStart(_t, _c);

  void _clamp() {
    _c = snapDown(_t, _c.clamp(0, _t.length));
    if (mode == VimMode.insert) return;
    final ls = lineStart(_t, _c);
    final le = lineEnd(_t, _c);
    if (le > ls && _c >= le) _c = prevChar(_t, le);
  }

  /// Whether the text's line break is CRLF.
  bool get crlf => _nl == '\r\n';

  /// The line break of the text: CRLF when it has any, else LF.
  String get _nl => _t.contains('\r\n') ? '\r\n' : '\n';

  /// [unit] repeated [n] times, capped (count and total size).
  String _rep(String unit, int n, [String sep = '']) {
    if (unit.isEmpty && sep.isEmpty) return '';
    final per = unit.length + sep.length;
    final times = math.min(n, math.min(maxRepeat, math.max(1, maxText ~/ per)));
    return List.filled(times, unit).join(sep);
  }

  void _goto(int p, {bool keepWant = false}) {
    _c = p;
    _clamp();
    if (!keepWant) _want = _col();
  }

  void _restore(String t, int c) {
    _t = t;
    _c = c;
    _clamp();
    _want = _col();
  }

  static int _firstDiff(String a, String b) {
    final m = math.min(a.length, b.length);
    var i = 0;
    while (i < m && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  void _regSet(String text, bool lw) {
    if (text.isEmpty && !lw) return;
    _reg = VimRegister(text, linewise: lw);
  }

  void _pushUndo(_Snap s) {
    _undo.add(s);
    _redo.clear();
    if (_undo.length > 500) _undo.removeAt(0);
  }

  /// Runs a change as one undo step. A body that ends in INSERT keeps the
  /// step open until the session ends.
  void _change(void Function() body, {bool dot = true}) {
    final before = _Snap(_t, _c);
    body();
    if (!_replaying && dot) _wasChange = true;
    if (mode == VimMode.insert) {
      _session = before;
    } else if (_t != before.t) {
      _pushUndo(before);
    }
  }

  void _resetSession() {
    _session = _Snap(_t, _c);
    _insStartText = _t;
    _ia = _c;
  }

  void _flushSession() {
    final s = _session;
    if (s != null && s.t != _t) {
      _pushUndo(s);
      _session = _Snap(_t, _c);
    }
  }

  void _beginInsert(int pos) {
    mode = VimMode.insert;
    _c = snapDown(_t, pos.clamp(0, _t.length));
    _ia = _c;
    _insStartText = _t;
    _insCount = 1;
    _insNl = false;
    _insDot = true;
  }

  String _insertedText() {
    final a = _insStartText;
    final b = _t;
    if (b.length < a.length) return '';
    final m = a.length;
    var p = 0;
    while (p < m && a.codeUnitAt(p) == b.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < m - p &&
        a.codeUnitAt(a.length - 1 - s) == b.codeUnitAt(b.length - 1 - s)) {
      s++;
    }
    if (p + s < a.length) return '';
    return b.substring(p, b.length - s);
  }

  void _exitInsert() {
    final inserted = _insertedText();
    if (_insCount > 1 && inserted.isNotEmpty) {
      final extra = _insNl
          ? _rep('$_insNlStr$inserted', _insCount - 1)
          : _rep(inserted, _insCount - 1);
      final at = _c.clamp(0, _t.length);
      _t = _t.replaceRange(at, at, extra);
      _c = at + extra.length;
    }
    if (!_replaying && _insDot) _dotInsert = inserted;
    mode = VimMode.normal;
    _insCount = 1;
    _insNl = false;
    final ls = lineStart(_t, _c);
    if (_c > ls) _c = prevChar(_t, _c);
    _clamp();
    _want = _col();
    final s = _session;
    _session = null;
    if (s != null && s.t != _t) _pushUndo(s);
  }

  // ------------------------------------------------------------ parsing

  void _feedNormal(String k) {
    if (k == 'Esc') {
      _keys = [];
      _leaderOn = false;
      _leaderKeys.clear();
      if (mode == VimMode.visual || mode == VimMode.visualLine) {
        mode = VimMode.normal;
        _clamp();
      }
      return;
    }
    if (_leaderOn || (k == ' ' && _keys.isEmpty && mode == VimMode.normal)) {
      _leaderKey(k);
      return;
    }
    if (_alias.containsKey(k) &&
        (_keys.isEmpty || RegExp(r'^[0-9dcy<>]$').hasMatch(_keys.last))) {
      k = _alias[k]!;
    }
    _keys.add(k);
    final r = mode == VimMode.normal ? _parseNormal() : _parseVisual();
    if (r != _P.more) {
      if (_wasChange && !_replaying) {
        _dotKeys = List.of(_keys);
        _dotInsert = null;
      }
      _wasChange = false;
      _keys = [];
    }
  }

  void _leaderKey(String k) {
    if (!_leaderOn) {
      _leaderOn = true;
      _leaderKeys.clear();
      return;
    }
    _leaderKeys.add(k);
    final step = leader?.call(List.of(_leaderKeys)) ?? const LeaderStep.none();
    if (step.wait) return;
    _leaderOn = false;
    _leaderKeys.clear();
    step.run?.call();
  }

  (int?, int) _count(int i) {
    if (i < _keys.length && RegExp(r'^[1-9]$').hasMatch(_keys[i])) {
      var n = 0;
      while (i < _keys.length && RegExp(r'^[0-9]$').hasMatch(_keys[i])) {
        n = math.min(n * 10 + int.parse(_keys[i]), maxCount);
        i++;
      }
      return (n, i);
    }
    return (null, i);
  }

  _P _parseNormal() {
    final (n1, i) = _count(0);
    if (i >= _keys.length) return _P.more;
    final k = _keys[i];
    final n = n1 ?? 1;
    switch (k) {
      case 'd' || 'c' || 'y' || '>' || '<':
        return _parseOp(k, n1, i + 1);
      case 'u':
        for (var s = 0; s < n; s++) {
          if (!undo()) break;
        }
        return _P.done;
      case 'C-r':
        for (var s = 0; s < n; s++) {
          if (!redo()) break;
        }
        return _P.done;
      case '.':
        _dot();
        return _P.done;
      case 'x':
        _change(() {
          final e = stepFwd(_t, _c, n, lineEnd(_t, _c));
          if (e > _c) _delChars(_c, e);
        });
        return _P.done;
      case 'X':
        _change(() {
          final s = stepBack(_t, _c, n, lineStart(_t, _c));
          if (_c > s) _delChars(s, _c);
        });
        return _P.done;
      case 'D' || 'C':
        _change(() {
          final starts = lineStarts(_t);
          final ln = math.min(lineNoOf(starts, _c) + n - 1, starts.length - 1);
          final e = lineEnd(_t, starts[ln]);
          if (k == 'D') {
            if (e > _c) _delChars(_c, e);
          } else {
            _regSet(_t.substring(_c, e), false);
            _t = _t.replaceRange(_c, e, '');
            _beginInsert(_c);
          }
        });
        return _P.done;
      case 's':
        _change(() {
          final e = stepFwd(_t, _c, n, lineEnd(_t, _c));
          _regSet(_t.substring(_c, e), false);
          _t = _t.replaceRange(_c, e, '');
          _beginInsert(_c);
        });
        return _P.done;
      case 'S':
        _linesOp('c', n);
        return _P.done;
      case 'Y':
        _linesOp('y', n);
        return _P.done;
      case 'J':
        _change(() => _join(n));
        return _P.done;
      case '~':
        _change(() {
          final e = stepFwd(_t, _c, n, lineEnd(_t, _c));
          if (e <= _c) return;
          final s = _t.substring(_c, e).characters.map(swapCase).join();
          _t = _t.replaceRange(_c, e, s);
          _goto(e);
        });
        return _P.done;
      case 'r':
        if (i + 1 >= _keys.length) return _P.more;
        final ch = _keys[i + 1];
        if (ch.length != 1 && ch != 'Enter') return _P.bad;
        _change(() {
          final le = lineEnd(_t, _c);
          var e = _c;
          for (var k = 0; k < n; k++) {
            if (e >= le) return;
            e = nextChar(_t, e);
          }
          if (ch == 'Enter') {
            final nl = _nl;
            _t = _t.replaceRange(_c, e, nl);
            _goto(_c + nl.length);
          } else {
            final rep = ch * n;
            _t = _t.replaceRange(_c, e, rep);
            _goto(_c + rep.length - 1);
          }
        });
        return _P.done;
      case 'p' || 'P':
        _change(() => _put(k == 'p', n));
        return _P.done;
      case 'i' || 'a' || 'I' || 'A' || 'o' || 'O':
        _change(() {
          switch (k) {
            case 'i':
              _beginInsert(_c);
            case 'a':
              _beginInsert(_c < lineEnd(_t, _c) ? nextChar(_t, _c) : _c);
            case 'I':
              _beginInsert(firstNonBlank(_t, lineStart(_t, _c)));
            case 'A':
              _beginInsert(lineEnd(_t, _c));
            case 'o':
              final le = lineEnd(_t, _c);
              final nl = _nl;
              _t = _t.replaceRange(le, le, nl);
              _beginInsert(le + nl.length);
              _insNl = true;
              _insNlStr = nl;
            default:
              final ls = lineStart(_t, _c);
              final nl = _nl;
              _t = _t.replaceRange(ls, ls, nl);
              _beginInsert(ls);
              _insNl = true;
              _insNlStr = nl;
          }
          _insCount = n;
        });
        return _P.done;
      case 'v':
        mode = VimMode.visual;
        _anchor = _c;
        return _P.done;
      case 'V':
        mode = VimMode.visualLine;
        _anchor = _c;
        return _P.done;
      case ':' || '/' || '?':
        _lineKind = k;
        _line = '';
        return _P.done;
      case 'Z':
        if (i + 1 >= _keys.length) return _P.more;
        final z = _keys[i + 1];
        if (z == 'Z') onAction?.call(VimAction.writeQuit);
        if (z == 'Q') onAction?.call(VimAction.quit);
        return z == 'Z' || z == 'Q' ? _P.done : _P.bad;
    }
    final (p, m) = _motionAt(i, n, n1 != null, null);
    if (p != _P.done) return p;
    if (m != null) _move(m);
    return _P.done;
  }

  void _move(_Mot m) {
    _goto(m.pos, keepWant: m.vert);
    if (m.wantInf) _want = _inf;
  }

  _P _parseOp(String op, int? n1, int i) {
    final (n2, j) = _count(i);
    if (j >= _keys.length) return _P.more;
    final k = _keys[j];
    final total = math.min((n1 ?? 1) * (n2 ?? 1), maxCount);
    if (k == op) {
      _linesOp(op, total);
      return _P.done;
    }
    VimRange? r;
    if (k == 'i' || k == 'a') {
      if (j + 1 >= _keys.length) return _P.more;
      r = textObject(_t, _c, k == 'i', _keys[j + 1]);
    } else {
      final (p, m) = _motionAt(j, total, n1 != null || n2 != null, op);
      if (p != _P.done) return p;
      if (m != null) r = _rangeOf(m, op);
    }
    if (r == null) return _P.done;
    final range = r;
    _change(() => _apply(op, range), dot: op != 'y');
    return _P.done;
  }

  void _linesOp(String op, int total) {
    final starts = lineStarts(_t);
    final ln = lineNoOf(starts, _c);
    final el = math.min(ln + total - 1, starts.length - 1);
    _change(() => _apply(op, VimRange(ln, el, linewise: true)), dot: op != 'y');
  }

  /// The operated range of motion [m] from the cursor.
  VimRange? _rangeOf(_Mot m, String op) {
    final starts = lineStarts(_t);
    if (m.lw) {
      final a = lineNoOf(starts, _c);
      final b = lineNoOf(starts, m.pos);
      return VimRange(math.min(a, b), math.max(a, b), linewise: true);
    }
    final s = math.min(_c, m.pos);
    var e = math.max(_c, m.pos);
    if (m.incl) {
      if (e < lineEnd(_t, e)) e = nextChar(_t, e);
    } else if (e > s &&
        e == lineStart(_t, e) &&
        lineNoOf(starts, e) > lineNoOf(starts, s)) {
      // Exclusive and ending at column 0 of a later line: ends at the end of
      // the line before, and is linewise when it starts at or before the
      // first non-blank.
      e--;
      if (s <= firstNonBlank(_t, lineStart(_t, s))) {
        return VimRange(
          lineNoOf(starts, s),
          lineNoOf(starts, e),
          linewise: true,
        );
      }
    }
    if (e <= s) return op == 'c' ? VimRange(s, s) : null;
    return VimRange(s, e);
  }

  String _rangeText(VimRange r) {
    if (!r.linewise) return _t.substring(r.s, r.e);
    final starts = lineStarts(_t);
    return _t.substring(starts[r.s], lineEnd(_t, starts[r.e]));
  }

  void _apply(String op, VimRange r) {
    if (!r.linewise) {
      r = VimRange(snapDown(_t, r.s), snapUp(_t, r.e));
    }
    switch (op) {
      case 'y':
        _regSet(_rangeText(r), r.linewise);
        if (r.linewise) {
          final col = _col();
          _goto(lineStarts(_t)[r.s] + col);
        } else {
          _goto(r.s);
        }
      case 'd':
        r.linewise ? _delLines(r.s, r.e) : _delChars(r.s, r.e);
      case 'c':
        _changeRange(r);
      default:
        final starts = lineStarts(_t);
        final sl = r.linewise ? r.s : lineNoOf(starts, r.s);
        final el = r.linewise ? r.e : lineNoOf(starts, math.max(r.s, r.e - 1));
        _shift(op == '>', sl, el);
    }
  }

  void _delChars(int s, int e) {
    _regSet(_t.substring(s, e), false);
    _t = _t.replaceRange(s, e, '');
    _goto(s);
  }

  void _delLines(int sl, int el) {
    final starts = lineStarts(_t);
    final s0 = starts[sl];
    _regSet(_t.substring(s0, lineEnd(_t, starts[el])), true);
    var s = s0;
    final e = el + 1 < starts.length ? starts[el + 1] : _t.length;
    if (el + 1 >= starts.length && sl > 0) {
      s -= s >= 2 && _t.startsWith('\r\n', s - 2) ? 2 : 1;
    }
    _t = _t.replaceRange(s, e, '');
    final ns = lineStarts(_t);
    final ln = math.min(sl, ns.length - 1);
    _c = firstNonBlank(_t, ns[ln]);
    _clamp();
    _want = _col();
  }

  void _changeRange(VimRange r) {
    if (r.linewise) {
      final starts = lineStarts(_t);
      final s = starts[r.s];
      final e = lineEnd(_t, starts[r.e]);
      _regSet(_t.substring(s, e), true);
      _t = _t.replaceRange(s, e, '');
      _beginInsert(s);
    } else {
      _regSet(_t.substring(r.s, r.e), false);
      _t = _t.replaceRange(r.s, r.e, '');
      _beginInsert(r.s);
    }
  }

  /// `>` / `<`: two spaces of indent per level (a tab is removed whole).
  void _shift(bool right, int sl, int el) {
    final lines = _t.split('\n');
    for (var i = sl; i <= el && i < lines.length; i++) {
      final l = lines[i];
      if (right) {
        if (l.isNotEmpty && l != '\r') lines[i] = '  $l';
      } else if (l.startsWith('\t')) {
        lines[i] = l.substring(1);
      } else if (l.startsWith('  ')) {
        lines[i] = l.substring(2);
      } else if (l.startsWith(' ')) {
        lines[i] = l.substring(1);
      }
    }
    _t = lines.join('\n');
    _c = firstNonBlank(_t, lineStarts(_t)[sl]);
    _clamp();
    _want = _col();
  }

  void _put(bool after, int n) {
    final r = _reg;
    if (r == null) return;
    if (r.linewise) {
      final nl = _nl;
      final txt = _rep(r.text, n, nl);
      if (after) {
        final le = lineEnd(_t, _c);
        _t = _t.replaceRange(le, le, '$nl$txt');
        _c = firstNonBlank(_t, le + nl.length);
      } else {
        final ls = lineStart(_t, _c);
        _t = _t.replaceRange(ls, ls, '$txt$nl');
        _c = firstNonBlank(_t, ls);
      }
    } else {
      final txt = _rep(r.text, n);
      if (txt.isEmpty) return;
      var at = _c;
      if (after && _c < lineEnd(_t, _c)) at = nextChar(_t, _c);
      _t = _t.replaceRange(at, at, txt);
      _c = txt.contains('\n') ? at : at + txt.length - 1;
    }
    _clamp();
    _want = _col();
  }

  void _join(int n) {
    final count = math.max(2, n);
    var pos = _c;
    for (var k = 1; k < count; k++) {
      final le = lineEnd(_t, pos);
      if (le >= _t.length) break;
      final ns = le + nlLen(_t, le);
      final ne = lineEnd(_t, ns);
      var ws = ns;
      while (ws < ne && (_t[ws] == ' ' || _t[ws] == '\t')) {
        ws++;
      }
      final cs = lineStart(_t, pos);
      final trail = le > cs && (_t[le - 1] == ' ' || _t[le - 1] == '\t');
      final nextEmpty = ws >= ne;
      final sep = (le == cs || trail || nextEmpty || _t[ws] == ')') ? '' : ' ';
      _t = _t.replaceRange(le, ws, sep);
      pos = le;
    }
    _goto(pos);
  }

  // ------------------------------------------------------------ motions

  /// Parses and evaluates the motion at `_keys[i]`. The motion is null when
  /// it fails (nothing to do).
  (_P, _Mot?) _motionAt(int i, int n, bool has, String? op) {
    final k = _keys[i];
    final c = _c;
    final t = _t;
    final ls = lineStart(t, c);
    final le = lineEnd(t, c);
    switch (k) {
      case 'h':
        return (_P.done, _Mot(stepBack(t, c, n, ls)));
      case 'l':
        final lim = op != null ? le : (le > ls ? prevChar(t, le) : ls);
        return (_P.done, _Mot(math.min(stepFwd(t, c, n, le), lim)));
      case 'j' || 'k':
        final starts = lineStarts(t);
        final ln = lineNoOf(starts, c);
        final target = k == 'j'
            ? math.min(ln + n, starts.length - 1)
            : math.max(ln - n, 0);
        if (target == ln && op != null) return (_P.done, null);
        final ts = starts[target];
        final len = lineEnd(t, ts) - ts;
        final end = ts + len;
        final int pos = ts + math.min<int>(_want, len);
        final int at = len == 0
            ? ts
            : pos >= end
            ? prevChar(t, end)
            : snapDown(t, pos);
        return (_P.done, _Mot(at, lw: true, vert: true));
      case 'w' || 'W':
        final big = k == 'W';
        if (op == 'c' && c < t.length && charClass(t[c], big) != 0) {
          var j = runEnd(t, c, big);
          for (var s = 1; s < n; s++) {
            j = wordEnd(t, j, big);
          }
          return (_P.done, _Mot(j, incl: true));
        }
        var pos = c;
        var stepStart = c;
        for (var s = 0; s < n; s++) {
          stepStart = pos;
          final nx = nextWordStart(t, pos, big);
          if (nx == pos) break;
          pos = nx;
        }
        if (op != null && pos > lineEnd(t, stepStart)) {
          pos = lineEnd(t, stepStart);
        }
        return (_P.done, _Mot(pos));
      case 'b' || 'B':
        var pos = c;
        for (var s = 0; s < n; s++) {
          pos = prevWordStart(t, pos, k == 'B');
        }
        return (_P.done, _Mot(pos));
      case 'e' || 'E':
        var pos = c;
        for (var s = 0; s < n; s++) {
          pos = wordEnd(t, pos, k == 'E');
        }
        return (_P.done, _Mot(pos, incl: true));
      case '0':
        return (_P.done, _Mot(ls));
      case '^':
        return (_P.done, _Mot(firstNonBlank(t, ls)));
      case r'$':
        final starts = lineStarts(t);
        final ln = math.min(lineNoOf(starts, c) + n - 1, starts.length - 1);
        final ts = starts[ln];
        return (
          _P.done,
          _Mot(
            math.max(ts, prevChar(t, lineEnd(t, ts))),
            incl: true,
            wantInf: true,
          ),
        );
      case 'G':
        final starts = lineStarts(t);
        final ln = has
            ? (n - 1).clamp(0, starts.length - 1)
            : starts.length - 1;
        return (_P.done, _Mot(firstNonBlank(t, starts[ln]), lw: true));
      case 'g':
        if (i + 1 >= _keys.length) return (_P.more, null);
        if (_keys[i + 1] != 'g') return (_P.bad, null);
        final starts = lineStarts(t);
        final ln = has ? (n - 1).clamp(0, starts.length - 1) : 0;
        return (_P.done, _Mot(firstNonBlank(t, starts[ln]), lw: true));
      case '{' || '}':
        final starts = lineStarts(t);
        final last = starts.length - 1;
        bool blank(int l) => lineEnd(t, starts[l]) == starts[l];
        var ln = lineNoOf(starts, c);
        for (var s = 0; s < n; s++) {
          if (k == '{') {
            while (ln > 0 && blank(ln)) {
              ln--;
            }
            while (ln > 0 && !blank(ln)) {
              ln--;
            }
          } else {
            while (ln < last && blank(ln)) {
              ln++;
            }
            while (ln < last && !blank(ln)) {
              ln++;
            }
          }
        }
        final atEnd = k == '}' && ln == last && !blank(ln);
        return (_P.done, _Mot(atEnd ? t.length : starts[ln]));
      case '%':
        final m = matchBracket(t, c);
        return (_P.done, m < 0 ? null : _Mot(m, incl: true));
      case 'f' || 'F' || 't' || 'T':
        if (i + 1 >= _keys.length) return (_P.more, null);
        final ch = _keys[i + 1];
        if (ch.length != 1) return (_P.bad, null);
        _lastFind = (k, ch);
        return (_P.done, _findMot(k, ch, n, false));
      case ';' || ',':
        final lf = _lastFind;
        if (lf == null) return (_P.done, null);
        var kind = lf.$1;
        if (k == ',') {
          kind = switch (kind) {
            'f' => 'F',
            'F' => 'f',
            't' => 'T',
            _ => 't',
          };
        }
        return (_P.done, _findMot(kind, lf.$2, n, true));
      case 'n' || 'N':
        final pat = _lastPat;
        if (pat == null) return (_P.done, null);
        final p = _searchPos(pat, k == 'n' ? _lastFwd : !_lastFwd, n);
        return (_P.done, p == null ? null : _Mot(p));
    }
    return (_P.bad, null);
  }

  _Mot? _findMot(String kind, String ch, int n, bool repeat) {
    final ls = lineStart(_t, _c);
    final le = lineEnd(_t, _c);
    var cnt = 0;
    if (kind == 'f' || kind == 't') {
      var from = _c + 1;
      if (kind == 't' && repeat && from < le && _t[from] == ch) from++;
      for (var j = from; j < le; j++) {
        if (_t[j] == ch && ++cnt == n) {
          return _Mot(kind == 't' ? prevChar(_t, j) : j, incl: true);
        }
      }
    } else {
      var from = _c - 1;
      if (kind == 'T' && repeat && from >= ls && _t[from] == ch) from--;
      for (var j = from; j >= ls; j--) {
        if (_t[j] == ch && ++cnt == n) {
          return _Mot(kind == 'T' ? nextChar(_t, j) : j);
        }
      }
    }
    return null;
  }

  // ------------------------------------------------------------ search

  /// A pattern is run as a regex only when it is simple: no groups,
  /// alternation, counted repeats or back references, at most one `*` or
  /// `+`, and short. Anything else (and a bad pattern) searches literally,
  /// so a hostile pattern cannot stall the editor.
  static bool simplePattern(String pat) =>
      pat.length <= 100 &&
      !RegExp(r'[(|{]|\\[1-9k]').hasMatch(pat) &&
      RegExp(r'[*+]').allMatches(pat).length <= 1;

  RegExp _regex(String pat) {
    if (simplePattern(pat)) {
      try {
        return RegExp(pat, multiLine: true);
      } on FormatException {
        // falls through to the literal
      }
    }
    return RegExp(RegExp.escape(pat), multiLine: true);
  }

  /// Start offsets of the matches of [pat] (at most [maxMatches], in the
  /// first [maxSearchText] characters). A regex runs per line, and lines
  /// over [maxRegexLine] characters are searched literally.
  List<int> _matchStarts(String pat) {
    final t = _t.length > maxSearchText ? _t.substring(0, maxSearchText) : _t;
    final re = _regex(pat);
    final lit = RegExp(RegExp.escape(pat));
    final out = <int>[];
    var ls = 0;
    while (ls <= t.length && out.length < maxMatches) {
      final le = lineEnd(t, ls);
      final line = t.substring(ls, le);
      final r = line.length > maxRegexLine ? lit : re;
      for (final m in r.allMatches(line)) {
        out.add(ls + m.start);
        if (out.length >= maxMatches) break;
      }
      final nl = nlLen(t, le);
      if (nl == 0) break;
      ls = le + nl;
    }
    return out;
  }

  /// The start of the [n]th match of [pat] from the cursor, wrapping.
  int? _searchPos(String pat, bool fwd, int n) {
    final starts = _matchStarts(pat);
    if (starts.isEmpty) return null;
    var pos = _c;
    final reps = math.min(n, starts.length * 2);
    for (var s = 0; s < reps; s++) {
      if (fwd) {
        pos = starts.firstWhere((x) => x > pos, orElse: () => starts.first);
      } else {
        pos = starts.lastWhere((x) => x < pos, orElse: () => starts.last);
      }
    }
    return pos;
  }

  // ------------------------------------------------------------ dot

  void _dot() {
    final keys = _dotKeys;
    if (keys == null) return;
    final ins = _dotInsert;
    final saved = _keys;
    _replaying = true;
    _keys = [];
    try {
      for (final k in keys) {
        _keys.add(k);
        if (_parseNormal() != _P.more) _keys = [];
      }
      if (mode == VimMode.insert) {
        if (ins != null && ins.isNotEmpty) {
          _t = _t.replaceRange(_c, _c, ins);
          _c += ins.length;
        }
        _exitInsert();
      }
    } finally {
      _replaying = false;
      _keys = saved;
      _wasChange = false;
    }
  }

  // ------------------------------------------------------------ visual

  VimRange _visualRange() {
    final lo = math.min(_anchor, _c);
    final hi = math.max(_anchor, _c);
    if (mode == VimMode.visualLine) {
      final starts = lineStarts(_t);
      return VimRange(
        lineNoOf(starts, lo),
        lineNoOf(starts, hi),
        linewise: true,
      );
    }
    return VimRange(lo, nextChar(_t, hi));
  }

  _P _parseVisual() {
    final (n1, i) = _count(0);
    if (i >= _keys.length) return _P.more;
    final k = _keys[i];
    final n = n1 ?? 1;
    switch (k) {
      case 'v' || 'V':
        final want = k == 'v' ? VimMode.visual : VimMode.visualLine;
        mode = mode == want ? VimMode.normal : want;
        _clamp();
        return _P.done;
      case 'o' || 'O':
        final a = _anchor;
        _anchor = _c;
        _c = a;
        return _P.done;
      case 'd' ||
          'x' ||
          'X' ||
          'D' ||
          'y' ||
          'Y' ||
          'c' ||
          's' ||
          'S' ||
          'C' ||
          'R' ||
          'J' ||
          '>' ||
          '<' ||
          '~' ||
          'u' ||
          'U':
        _visualOp(k);
        return _P.done;
      case 'p' || 'P':
        _change(_visualPut);
        return _P.done;
      case 'r':
        if (i + 1 >= _keys.length) return _P.more;
        final ch = _keys[i + 1];
        if (ch.length != 1) return _P.bad;
        _change(() {
          final r = _visualRange();
          final starts = lineStarts(_t);
          final s = r.linewise ? starts[r.s] : r.s;
          final e = r.linewise ? lineEnd(_t, starts[r.e]) : r.e;
          final body = _t
              .substring(s, e)
              .characters
              .map((g) => g == '\n' || g == '\r\n' || g == '\r' ? g : ch)
              .join();
          _t = _t.replaceRange(s, e, body);
          mode = VimMode.normal;
          _goto(s);
        });
        return _P.done;
      case 'i' || 'a':
        if (i + 1 >= _keys.length) return _P.more;
        final o = textObject(_t, _c, k == 'i', _keys[i + 1]);
        if (o == null) return _P.done;
        if (o.linewise) {
          final starts = lineStarts(_t);
          mode = VimMode.visualLine;
          _anchor = starts[o.s];
          _c = starts[o.e];
          _clamp();
        } else if (o.e > o.s) {
          _anchor = o.s;
          _c = o.e - 1;
        }
        return _P.done;
      case ':':
        mode = VimMode.normal;
        _clamp();
        _lineKind = ':';
        _line = '';
        return _P.done;
      case '/' || '?':
        _lineKind = k;
        _line = '';
        return _P.done;
    }
    final (p, m) = _motionAt(i, n, n1 != null, null);
    if (p != _P.done) return p;
    if (m != null) _move(m);
    return _P.done;
  }

  void _visualOp(String k) {
    final lw = mode == VimMode.visualLine;
    final startPos = math.min(_anchor, _c);
    final starts = lineStarts(_t);
    final lines = VimRange(
      lineNoOf(starts, math.min(_anchor, _c)),
      lineNoOf(starts, math.max(_anchor, _c)),
      linewise: true,
    );
    final sel = _visualRange();
    mode = VimMode.normal;
    _change(() {
      switch (k) {
        case 'd' || 'x':
          _apply('d', sel);
        case 'X' || 'D':
          _apply('d', lines);
        case 'y':
          _regSet(_rangeText(sel), sel.linewise);
          if (lw) {
            _goto(starts[sel.s] + (startPos - lineStart(_t, startPos)));
          } else {
            _goto(sel.s);
          }
        case 'Y':
          _regSet(_rangeText(lines), true);
          _goto(starts[lines.s] + (startPos - lineStart(_t, startPos)));
        case 'c' || 's':
          _apply('c', sel);
        case 'C' || 'S' || 'R':
          _apply('c', lines);
        case '>' || '<':
          _shift(k == '>', lines.s, lines.e);
        case 'J':
          _c = starts[lines.s];
          _join(lines.e - lines.s + 1);
        default:
          final s = lw ? starts[sel.s] : sel.s;
          final e = lw ? lineEnd(_t, starts[sel.e]) : sel.e;
          final body = _t.substring(s, e);
          final out = switch (k) {
            'u' => body.toLowerCase(),
            'U' => body.toUpperCase(),
            _ => body.characters.map(swapCase).join(),
          };
          _t = _t.replaceRange(s, e, out);
          _goto(s);
      }
    }, dot: false);
  }

  /// `p` in VISUAL: the selection is replaced by the register.
  void _visualPut() {
    final reg = _reg;
    final lw = mode == VimMode.visualLine;
    final sel = _visualRange();
    mode = VimMode.normal;
    if (reg == null) {
      _clamp();
      return;
    }
    final starts = lineStarts(_t);
    final s = lw ? starts[sel.s] : sel.s;
    final e = lw ? lineEnd(_t, starts[sel.e]) : sel.e;
    _regSet(_t.substring(s, e), lw);
    var ins = reg.text;
    if (reg.linewise && !lw) ins = '$_nl$ins$_nl';
    _t = _t.replaceRange(s, e, ins);
    _goto(reg.linewise && !lw ? s + _nl.length : s);
  }

  // ------------------------------------------------------------ line mode

  void _feedLine(String k) {
    switch (k) {
      case 'Esc':
        _lineKind = null;
        _line = '';
      case 'Enter':
        final kind = _lineKind!;
        final text = _line;
        _lineKind = null;
        _line = '';
        if (kind == ':') {
          _ex(text);
        } else {
          _doSearch(text, kind == '/');
        }
      case 'BS':
        if (_line.isEmpty) {
          _lineKind = null;
        } else {
          _line = _line.substring(0, _line.length - 1);
        }
      default:
        if (k.length == 1) _line += k;
    }
  }

  void _doSearch(String text, bool fwd) {
    final pat = text.isEmpty ? _lastPat : text;
    if (pat == null) return;
    _lastPat = pat;
    _lastFwd = fwd;
    final p = _searchPos(pat, fwd, 1);
    if (p == null) {
      message = 'Pattern not found: $pat';
      return;
    }
    _move(_Mot(p));
  }

  void _ex(String raw) {
    final c = raw.trim();
    if (c.isEmpty) return;
    final starts = lineStarts(_t);
    if (RegExp(r'^\d+$').hasMatch(c)) {
      final n = c.length > 9 ? maxCount : int.tryParse(c) ?? maxCount;
      final ln = (n - 1).clamp(0, starts.length - 1);
      _goto(firstNonBlank(_t, starts[ln]));
      return;
    }
    switch (c) {
      case r'$':
        _goto(firstNonBlank(_t, starts.last));
      case 'w' || 'w!' || 'write':
        onAction?.call(VimAction.write);
      case 'q' || 'quit':
        onAction?.call(VimAction.quit);
      case 'q!' || 'quit!':
        onAction?.call(VimAction.forceQuit);
      case 'wq' || 'wq!' || 'x' || 'x!' || 'xit' || 'exit':
        onAction?.call(VimAction.writeQuit);
      default:
        message = 'Not an editor command: $c';
    }
  }
}
