import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

class _Source implements NoteSource {
  @override
  Future<List<Note>> load() async => [Note(uid: 'a', summary: 'One')];
}

/// Design rules for lib/ui: look values live only in lib/theme/tokens.dart,
/// and anything that repeats is a shared component (CardBox, Surface,
/// CountBadge, EmptyState, SectionLabel, ...), never hand-built inline.
///
/// Each rule is a regex over the comment-stripped source, with allowlists for
/// the files where the literal is geometry the design does not own. A rule
/// that goes red means a call site should use a token or a shared component;
/// do not weaken the rule.

/// Every lib/ui source file, recursively.
Iterable<File> _uiFiles() sync* {
  for (final e in Directory('lib/ui').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}

/// Source with comments (`//`, `/* */`) blanked to spaces, so a doc comment
/// never trips a rule, while string contents (`'http://x'`) stay intact.
/// Newlines are kept, so line numbers still match the file.
String _strip(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    final two = i + 1 < s.length ? s.substring(i, i + 2) : '';
    if (two == '//') {
      while (i < s.length && s[i] != '\n') {
        out.write(' ');
        i++;
      }
    } else if (two == '/*') {
      var depth = 0;
      while (i < s.length) {
        final pair = i + 1 < s.length ? s.substring(i, i + 2) : '';
        if (pair == '/*') {
          depth++;
          out.write('  ');
          i += 2;
        } else if (pair == '*/') {
          depth--;
          out.write('  ');
          i += 2;
          if (depth == 0) break;
        } else {
          out.write(s[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
    } else if (c == "'" || c == '"') {
      final raw = i > 0 && s[i - 1] == 'r';
      final triple = s.startsWith(c * 3, i);
      final close = triple ? c * 3 : c;
      out.write(close);
      i += close.length;
      while (i < s.length && !s.startsWith(close, i)) {
        if (!raw && s[i] == r'\' && i + 1 < s.length) {
          out.write(s.substring(i, i + 2));
          i += 2;
        } else {
          if (!triple && s[i] == '\n') break;
          out.write(s[i]);
          i++;
        }
      }
      if (i < s.length && s.startsWith(close, i)) {
        out.write(close);
        i += close.length;
      }
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

String _literal(File f) => _strip(f.readAsStringSync());

int _line(String src, int at) =>
    '\n'.allMatches(src.substring(0, at)).length + 1;

/// One design rule: [pattern] must not match in any scanned file outside
/// [exempt] and [allow].
///
/// [allow] is a ratchet: each file maps to the exact number of matches it may
/// still have. Fewer or more fails, so a fixed site forces the entry to
/// shrink or go, and a new breach in an allowed file is caught.
class _Rule {
  const _Rule(
    this.name,
    this.pattern, {
    this.exempt = const {},
    this.allow = const {},
    this.only,
    required this.bad,
  });

  /// When set, only files whose path matches are scanned.
  final RegExp? only;

  final String name;
  final RegExp pattern;

  /// Files exempt for this rule (they own the literal by design).
  final Set<String> exempt;

  /// Files allowed a fixed number of matches although they are not shared
  /// components.
  final Map<String, int> allow;

  /// A snippet the rule must catch: the self-test proves it fires.
  final String bad;
}

const _tokens = 'lib/theme/tokens.dart';
const _theme = 'lib/ui/theme.dart';

/// A non-zero number literal (`8`, `0.5`, `.5`; not `0`).
const _num = r'(?:[1-9]|0*\.0*[1-9])';

/// The menu, dialog and property files the picker-words rule scans.
final _pickerFiles = RegExp(r'menu|dialog|property/');

final _rules = <_Rule>[
  _Rule(
    'radius from spacing',
    RegExp(
      r'BorderRadius\.circular\(\s*t\.space\.|'
      r'Radius\.circular\(\s*\w+\.space\.',
    ),
    bad: 'borderRadius: BorderRadius.circular(t.space.md),',
  ),
  _Rule(
    'radius argument from a radius token',
    RegExp(
      r'BorderRadius\.circular\((?!\s*(?:t\.radii\.|(?:widget\.)?radius\b))',
    ),
    bad: 'final r = 8; borderRadius: BorderRadius.circular(r),',
  ),
  _Rule(
    'radius from a local number',
    RegExp(r'\b(?:final|var|double)\s+\w*[rR]adius\w*\s*=\s*\d'),
    bad: 'final radius = 8.0;',
  ),
  _Rule(
    'alpha is a token',
    RegExp(
      r'withValues\(\s*alpha:\s*[0-9.]|withOpacity\(|withAlpha\(|'
      r'Opacity\([^)]*opacity:\s*[0-9.]',
    ),
    exempt: {_tokens, _theme},
    bad: 'color: t.accent.withValues(alpha: 0.1),',
  ),
  _Rule(
    'font weight is a token',
    RegExp(r'FontWeight\.w\d'),
    exempt: {_tokens},
    bad: 'fontWeight: on ? FontWeight.w600 : FontWeight.w400,',
  ),
  _Rule(
    'text style is a token style',
    RegExp(r'\bTextStyle\(\s*color:|fontSize:\s*t\.type\.'),
    bad: "Text('x', style: TextStyle(color: t.muted)),",
  ),
  _Rule(
    'text style is a token style (weight)',
    RegExp(r'\bTextStyle\(\s*(?:color|fontWeight):'),
    bad: 'style: TextStyle(fontWeight: t.type.bold),',
  ),
  _Rule(
    'no arithmetic on tokens',
    RegExp(
      r't\.(space|sizes|radii)\.\w+\s*[-+*/]\s*(t\.|\d)|'
      r'[\d)]\s*\*\s*t\.space',
    ),
    allow: {
      'lib/ui/shell_frame.dart': 4, // panel corner geometry
      'lib/ui/app.dart': 1, // strip edge inset from the panel corner
      'lib/ui/panel_tags_drawer.dart': 2, // chip width from the drawer width
      'lib/ui/tab_strip.dart': 2, // tab widths from their parts
    },
    bad: 'padding: EdgeInsets.only(top: t.space.lg - t.space.xxs),',
  ),
  _Rule(
    'no raw sizes',
    RegExp(
      r'\b(?:width|height|size|spacing|runSpacing|dimension):\s*'
      '$_num|'
      r'(?:minWidth|minHeight|maxWidth|maxHeight|thickness|blur|'
      r'strokeWidth):\s*'
      '$_num|'
      r'Offset\(\s*'
      '$_num|'
      r'\bSize\(\s*'
      '$_num|'
      r'\bSize\.square\(\s*'
      '$_num',
    ),
    exempt: {_tokens, _theme},
    bad: 'SizedBox(width: 24), Size(0.5, 4), Offset(.5, 1),',
  ),
  _Rule(
    'no colour literals or other colour APIs',
    RegExp(
      r'\bColor\(\s*0x|\bColor\(\s*\d|\bColors\.|Color\.from|'
      r'CupertinoColors\.|FColors\.',
    ),
    exempt: {_tokens, _theme},
    bad: 'color: const Color(0xFF000000),',
  ),
  _Rule(
    'no bare font-size, tracking or radius literals',
    RegExp(r'fontSize:\s*\d|letterSpacing:\s*-?\.?\d|Radius\.circular\(\s*\d'),
    exempt: {_tokens},
    bad: 'fontSize: 13,',
  ),
  _Rule(
    'card, selected and hover fills stay in shared surfaces',
    // Any read of the fill tokens, so `final c = t.card;` is caught too.
    RegExp(r'\b(?:t|tokens|tk|tokensOf\(context\))\.(?:card|selected|hover)\b'),
    exempt: {
      'lib/ui/card_box.dart', // the card surface
      'lib/ui/surface.dart', // the row surface
      _theme, // forui colour scheme from the tokens
    },
    allow: {
      'lib/ui/key_nav_ui.dart': 1, // the pending-key chip
      'lib/ui/shell_frame.dart': 1, // the tab hover over the panel join
      'lib/ui/app_actions.dart': 1, // the help dialog's key badge
    },
    bad: 'final c = t.card;',
  ),
  _Rule(
    'empty and error text uses EmptyState',
    RegExp(r"Text\(\s*'(?:No |Nothing)"),
    bad: "Text('No notes'),",
  ),
  _Rule(
    'taps go through FTappable',
    RegExp(r'GestureDetector\(|InkWell\('),
    allow: {
      'lib/ui/app.dart': 1, // the edge-swipe drag zone
      'lib/ui/command_palette.dart': 1, // hover tracking around Surface
      'lib/ui/mobile_nav.dart': 1, // long-press timing on the phone bar
      'lib/ui/note_menu.dart': 1, // long press opens the sheet
      'lib/ui/resize_handle.dart': 1, // drag handle
      'lib/ui/task_parts.dart': 1, // the card touch box
    },
    bad: 'GestureDetector(onTap: () {}),',
  ),
  _Rule(
    'status, priority and due pickers are built once',
    RegExp(
      r"'Set (?:status|priority|due)'|'No priority'|'needs-action'|"
      r"'in-process'|PickerOption\(\s*'(?:high|medium|low|backlog|todo|doing)'|"
      r'\bFCalendar\b',
    ),
    only: _pickerFiles,
    exempt: {
      'lib/ui/property/property_defs.dart',
      'lib/ui/property/date_property_picker.dart',
    },
    bad: "NoteMenuItem('Set status', FLucideIcons.circleDot, () {}),",
  ),
  _Rule(
    'menus take property strings only from the shared menu helpers',
    RegExp(r'''\.setLabel\b|'Set \$|"Set \$'''),
    exempt: {
      'lib/ui/property/property_defs.dart',
      'lib/ui/property/property_menu.dart',
      'lib/ui/property/property_dialog.dart',
    },
    bad: 'NoteMenuItem(Props.due.setLabel, Props.due.icon, () {}),',
  ),
];

/// Private widgets that repeat a shared piece were removed; these are the
/// last ones left. Each must still exist (a removed copy must leave the list)
/// and the list may only shrink.
const _privateWidgets = {
  'lib/ui/home_board.dart:_Card',
  'lib/ui/project_overview.dart:_Tile',
  'lib/ui/project_overview.dart:_Row',
  'lib/ui/command_palette.dart:_Row',
  'lib/ui/board_view.dart:_Card',
  'lib/ui/sections.dart:_Section',
  'lib/ui/tab_strip.dart:_TabDropTarget',
  'lib/ui/tab_strip.dart:_TabDropTargetState',
};

/// A private class named like a shared piece: Card, Row, Pill, Tile or Badge
/// (with any prefix), or the bare Empty, Chip, Tab*, Section* names.
final _privatePattern = RegExp(
  r'class _(?:\w*(?:Card|Row|Pill|Tile|Badge)|Empty|Chip|Tab\w*|Section\w*)\b',
);

/// Private widgets found in [src] of [path], as `path:_Name`.
Set<String> _privateIn(String path, String src) => {
  for (final m in _privatePattern.allMatches(src))
    '$path:${m.group(0)!.substring('class '.length)}',
};

/// Arguments of every `name(...)` call in [src] (balanced parentheses).
Iterable<String> _args(String src, RegExp opener) sync* {
  for (final m in opener.allMatches(src)) {
    var depth = 1;
    var i = m.end;
    while (i < src.length && depth > 0) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') depth--;
      i++;
    }
    yield src.substring(m.end, i - 1);
  }
}

/// Padding, margin and box-size literals: numbers other than 0 inside
/// EdgeInsets(Directional) and SizedBox calls.
final _insetOpener = RegExp(r'EdgeInsets(?:Directional)?\.\w+\(');
final _boxOpener = RegExp(r'\bSizedBox(?:\.\w+)?\(');
final _number = RegExp(r'(?<![\w.])(?:[1-9]\d*(?:\.\d+)?|0?\.0*[1-9]\d*)');
final _boxSize = RegExp(r'(?:width|height|dimension):\s*' + _num);

List<String> _insetBreaches(String path, String src) => [
  for (final a in _args(src, _insetOpener))
    if (_number.hasMatch(a)) '$path: EdgeInsets($a)',
  for (final a in _args(src, _boxOpener))
    if (_boxSize.hasMatch(a)) '$path: SizedBox($a)',
];

/// Matches of [rule] per file in the whole tree (exempt files included).
Map<String, List<int>> _breaches(_Rule rule) {
  final found = <String, List<int>>{};
  for (final f in _uiFiles()) {
    if (rule.only != null && !rule.only!.hasMatch(f.path)) continue;
    final src = _literal(f);
    for (final m in rule.pattern.allMatches(src)) {
      (found[f.path] ??= []).add(_line(src, m.start));
    }
  }
  return found;
}

void main() {
  group('design rules', () {
    for (final rule in _rules) {
      test(rule.name, () {
        final found = _breaches(rule);
        final bad = <String>[];
        found.forEach((path, lines) {
          if (rule.exempt.contains(path)) return;
          final cap = rule.allow[path] ?? 0;
          if (lines.length > cap) {
            bad.add('$path:$lines (allowed $cap)');
          }
        });
        expect(bad, isEmpty, reason: '${rule.name}: $bad');
      });

      test('${rule.name}: allowlist entries are real and still needed', () {
        final found = _breaches(rule);
        final stale = <String>[];
        for (final path in [...rule.exempt, ...rule.allow.keys]) {
          if (!File(path).existsSync()) stale.add('$path: no such file');
        }
        rule.allow.forEach((path, cap) {
          final n = found[path]?.length ?? 0;
          if (n != cap) stale.add('$path: allows $cap, has $n: shrink it');
        });
        for (final path in rule.exempt) {
          if ({_tokens, _theme}.contains(path)) continue;
          if (!found.containsKey(path)) stale.add('$path: exempt, not needed');
        }
        expect(stale, isEmpty, reason: '${rule.name}: $stale');
      });

      test('${rule.name}: the rule catches a bad snippet', () {
        expect(rule.pattern.hasMatch(rule.bad), isTrue, reason: rule.bad);
      });
    }

    test('the token file is where the rules say it is', () {
      expect(File(_tokens).existsSync(), isTrue);
      expect(File(_theme).existsSync(), isTrue);
    });

    test('no new private copy of a shared piece', () {
      final found = <String>{};
      for (final f in _uiFiles()) {
        found.addAll(_privateIn(f.path, _literal(f)));
      }
      expect(found.difference(_privateWidgets), isEmpty);
      // Ratchet: an entry whose widget is gone must leave the list.
      expect(
        _privateWidgets.difference(found),
        isEmpty,
        reason: 'stale _privateWidgets entries: remove them',
      );
    });

    test('the private-widget rule catches each shared-piece name', () {
      for (final n in ['_TaskCard', '_NoteRow', '_Pill', '_XTile', '_YBadge']) {
        expect(_privateIn('x', 'class $n extends StatelessWidget {}'), {
          'x:$n',
        }, reason: n);
      }
      expect(_privateIn('x', 'class _NavRowState extends State {}'), isEmpty);
    });

    test('the stripper blanks comments but keeps strings', () {
      const src =
          "var u = 'http://x'; // c\nvar a = 1; /* w: 9\n w: 8 */ var b = 2;"
          ' var s = "//keep";';
      final out = _strip(src);
      expect(out, contains("'http://x'"));
      expect(out, contains('"//keep"'));
      expect(out, isNot(contains('// c')));
      expect(out, isNot(contains('w: 9')));
      expect(out, contains('var b = 2;'));
      expect('\n'.allMatches(out).length, '\n'.allMatches(src).length);
    });

    test('no numeric padding or margin literals (0 is allowed)', () {
      final found = <String>[];
      for (final f in _uiFiles()) {
        if (f.path == _theme) continue;
        found.addAll(_insetBreaches(f.path, _literal(f)));
      }
      expect(found, isEmpty, reason: 'use tokensOf(context).space: $found');
    });

    test('the padding rule catches each bad form', () {
      for (final bad in [
        'EdgeInsets.all(8)',
        'EdgeInsets.all(0.5)',
        'EdgeInsets.only(left: .5)',
        'EdgeInsetsDirectional.only(start: 4)',
        'EdgeInsetsDirectional.fromSTEB(0, 4, 0, 0)',
        'SizedBox(width: 8)',
        'SizedBox(height: 0.5)',
        'SizedBox.square(dimension: 8)',
      ]) {
        expect(_insetBreaches('x', bad), isNotEmpty, reason: bad);
      }
      expect(
        _insetBreaches('x', 'EdgeInsets.all(0) SizedBox(width: t.space.md)'),
        isEmpty,
      );
    });
  });

  group('tokens drive the UI', () {
    testWidgets('changing tokens changes the themed widgets', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      const red = Color(0xFFAA0000);
      const green = Color(0xFF00AA00);
      final custom = Tokens.light.copyWith(
        frame: red,
        accent: green,
        sizes: const SizeTokens(rail: 90, railItem: 50),
        type: const TypeTokens(title: 31),
        radii: const RadiusTokens(panel: 30),
      );
      await t.pumpWidget(DavdartApp(source: _Source(), tokens: custom));
      await t.pumpAndSettle();

      // Colour: the frame, and forui's primary fed from the accent token.
      expect(
        t
            .widgetList<ColoredBox>(
              find.ancestor(
                of: find.byKey(const Key('icon-rail')),
                matching: find.byType(ColoredBox),
              ),
            )
            .any((b) => b.color == red),
        isTrue,
      );
      expect(
        FTheme.of(t.element(find.byKey(const Key('icon-rail')))).colors.primary,
        green,
      );
      // Size, type and radius.
      expect(t.getSize(find.byKey(const Key('icon-rail'))).width, 90);
      expect(t.getSize(find.byKey(const Key('logo-slot'))).width, 50);
      final panel = t.widget<Container>(find.byKey(const Key('shell-panel')));
      expect(
        (panel.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(30),
      );
    });
  });
}
