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

/// Source with `//` comments removed, so a doc comment never trips a rule.
String _literal(File f) =>
    f.readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');

int _line(String src, int at) =>
    '\n'.allMatches(src.substring(0, at)).length + 1;

/// One design rule: [pattern] must not match in any scanned file outside
/// [exempt] and [allow].
class _Rule {
  const _Rule(
    this.name,
    this.pattern, {
    this.exempt = const {},
    this.allow = const {},
    required this.bad,
  });

  final String name;
  final RegExp pattern;

  /// Files exempt for this rule (they own the literal by design).
  final Set<String> exempt;

  /// Files allowed for this rule although they are not shared components.
  final Set<String> allow;

  /// A snippet the rule must catch: the self-test proves it fires.
  final String bad;

  Set<String> get _skip => {...exempt, ...allow};
}

const _tokens = 'lib/ui/theme/tokens.dart';
const _theme = 'lib/ui/theme.dart';

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
      r'BorderRadius\.circular\(\s*(?!t\.radii\.|[a-z_]+\s*[,)]|widget\.)',
    ),
    allow: {
      'lib/ui/key_nav_ui.dart', // widget.radius ?? t.radii.small
      'lib/ui/surface.dart', // radius ?? t.radii.small
    },
    bad: 'borderRadius: BorderRadius.circular(8),',
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
    'no arithmetic on tokens',
    RegExp(
      r't\.(space|sizes|radii)\.\w+\s*[-+*/]\s*(t\.|\d)|'
      r'[\d)]\s*\*\s*t\.space',
    ),
    exempt: {
      'lib/ui/shell_frame.dart', // panel corner geometry
      'lib/ui/app.dart', // strip edge inset from the panel corner
      'lib/ui/panel_tags_drawer.dart', // chip width from the drawer width
      'lib/ui/tab_strip.dart', // tab widths from their parts
    },
    bad: 'padding: EdgeInsets.only(top: t.space.lg - t.space.xxs),',
  ),
  _Rule(
    'no raw sizes',
    RegExp(
      r'\b(?:width|height|size|spacing|runSpacing):\s*[1-9]|'
      r'(?:minWidth|minHeight|maxWidth|maxHeight|thickness|blur|'
      r'strokeWidth):\s*[1-9]|Offset\(\s*[1-9]',
    ),
    exempt: {_tokens, _theme},
    bad: 'SizedBox(width: 24),',
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
    'no card, selected or hover fill outside a shared surface',
    RegExp(
      r'BoxDecoration\((?=[^;]*?t\.(?:card|selected|hover)\b)',
      dotAll: true,
    ),
    allow: {
      'lib/ui/card_box.dart', // the card surface
      'lib/ui/surface.dart', // the row surface
      'lib/ui/key_nav_ui.dart', // the pending-key chip
      'lib/ui/shell_frame.dart', // the tab-to-panel join
      'lib/ui/app_actions.dart', // the help dialog's key badge
    },
    bad: 'decoration: BoxDecoration(color: t.card),',
  ),
  _Rule(
    'empty and error text uses EmptyState',
    RegExp(r"Text\(\s*'(?:No |Nothing)"),
    allow: {'lib/ui/empty_state.dart'},
    bad: "Text('No notes'),",
  ),
  _Rule(
    'taps go through FTappable',
    RegExp(r'GestureDetector\(|InkWell\('),
    allow: {
      'lib/ui/app.dart', // the edge-swipe drag zone
      'lib/ui/command_palette.dart', // hover tracking around FTappable
      'lib/ui/mobile_nav.dart', // long-press timing on the phone bar
      'lib/ui/note_menu.dart', // long press opens the sheet
      'lib/ui/resize_handle.dart', // drag handle
      'lib/ui/task_parts.dart', // the card touch box
      'lib/ui/drag_drop.dart',
    },
    bad: 'GestureDetector(onTap: () {}),',
  ),
];

/// Private widgets that repeat a shared piece were removed; these names are
/// the last ones left and the list may only shrink.
const _privateWidgets = {
  'lib/ui/home_board.dart:_Card',
  'lib/ui/project_overview.dart:_Card',
  'lib/ui/project_overview.dart:_Tile',
  'lib/ui/project_overview.dart:_Row',
  'lib/ui/command_palette.dart:_Row',
  'lib/ui/home_page.dart:_Card',
  'lib/ui/board_view.dart:_Card',
  'lib/ui/sections.dart:_Section',
  'lib/ui/tab_strip.dart:_TabDropTarget',
  'lib/ui/tab_strip.dart:_TabDropTargetState',
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

void main() {
  group('design rules', () {
    for (final rule in _rules) {
      test(rule.name, () {
        final found = <String>[];
        for (final f in _uiFiles()) {
          if (rule._skip.contains(f.path)) continue;
          final src = _literal(f);
          for (final m in rule.pattern.allMatches(src)) {
            found.add('${f.path}:${_line(src, m.start)}');
          }
        }
        expect(found, isEmpty, reason: '${rule.name}: $found');
      });

      test('${rule.name}: the rule catches a bad snippet', () {
        expect(rule.pattern.hasMatch(rule.bad), isTrue, reason: rule.bad);
      });
    }

    test('no new private copy of a shared piece', () {
      final pattern = RegExp(
        r'class _(Card|Row|Empty|Tile|Chip|Badge|Tab\w*|Section\w*)\b',
      );
      final found = <String>[];
      for (final f in _uiFiles()) {
        final src = _literal(f);
        for (final m in pattern.allMatches(src)) {
          final name = m.group(0)!.substring('class '.length);
          found.add('${f.path}:$name');
        }
      }
      expect(found.toSet().difference(_privateWidgets), isEmpty);
    });

    test('no numeric padding or margin literals (0 is allowed)', () {
      final found = <String>[];
      final number = RegExp(r'(?<![\w.])[1-9]\d*(?:\.\d+)?');
      for (final f in _uiFiles()) {
        if (f.path == _theme) continue;
        final src = _literal(f);
        for (final a in _args(src, RegExp(r'EdgeInsets\.\w+\('))) {
          if (number.hasMatch(a)) found.add('${f.path}: EdgeInsets($a)');
        }
        for (final a in _args(src, RegExp(r'\bSizedBox\('))) {
          if (RegExp(r'(width|height):\s*[1-9]').hasMatch(a)) {
            found.add('${f.path}: SizedBox($a)');
          }
        }
      }
      expect(found, isEmpty, reason: 'use tokensOf(context).space: $found');
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
