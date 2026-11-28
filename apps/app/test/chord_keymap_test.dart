import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_action.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/chord_keymap.dart';
import 'package:davdart_app/ui/app_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

const _letterKeys = {
  'j': LogicalKeyboardKey.keyJ,
  'l': LogicalKeyboardKey.keyL,
  'q': LogicalKeyboardKey.keyQ,
  'n': LogicalKeyboardKey.keyN,
  'w': LogicalKeyboardKey.keyW,
  'p': LogicalKeyboardKey.keyP,
  'k': LogicalKeyboardKey.keyK,
  'g': LogicalKeyboardKey.keyG,
  'm': LogicalKeyboardKey.keyM,
  't': LogicalKeyboardKey.keyT,
};

/// Presses [c] and returns whether the key event was handled.
Future<bool> _chord(WidgetTester t, Chord c) async {
  final mods = [
    if (c.ctrl) LogicalKeyboardKey.controlLeft,
    if (c.alt) LogicalKeyboardKey.altLeft,
    if (c.meta) LogicalKeyboardKey.metaLeft,
    if (c.shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final m in mods) {
    await t.sendKeyDownEvent(m);
  }
  final key = _letterKeys[c.letter]!;
  final handled = await t.sendKeyDownEvent(key);
  await t.sendKeyUpEvent(key);
  for (final m in mods.reversed) {
    await t.sendKeyUpEvent(m);
  }
  await t.pumpAndSettle();
  return handled;
}

Chord _c(String s) => Chord.parse(s)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    ChordKeymap.debugIsWeb = null;
  });

  group('platform defaults', () {
    String label(TargetPlatform p, bool web, String id) =>
        ChordKeymap(platform: p, isWeb: web).labelFor(id)!;

    test('native Linux and Windows: Ctrl+Shift+letter', () {
      expect(label(TargetPlatform.linux, false, 'go.tasks'), 'Ctrl+Shift+Q');
      expect(
        label(TargetPlatform.windows, false, 'focus.left'),
        'Ctrl+Shift+J',
      );
    });
    test('native macOS: Cmd+Shift+letter', () {
      expect(label(TargetPlatform.macOS, false, 'go.tasks'), 'Cmd+Shift+T');
    });
    test('web on Linux and Windows: Alt+letter', () {
      expect(label(TargetPlatform.linux, true, 'go.tasks'), 'Alt+Q');
      expect(label(TargetPlatform.windows, true, 'peek.toggle'), 'Alt+P');
    });
    test('web on macOS: Ctrl+Alt+letter', () {
      expect(label(TargetPlatform.macOS, true, 'go.tasks'), 'Ctrl+Alt+Q');
    });
    test('the letters avoid browser mnemonics and are unique', () {
      for (final l in ChordKeymap.letters.values) {
        expect('fevsbthduz'.contains(l), isFalse, reason: l);
      }
      expect(
        ChordKeymap.letters.values.toSet().length,
        ChordKeymap.letters.length,
      );
    });
  });

  group('parse and format', () {
    test('round trip and aliases', () {
      expect(_c('ctrl+shift+j').id, 'ctrl+shift+j');
      expect(_c('Shift+Cmd+J').id, 'meta+shift+j');
      expect(_c('Option+Control+x').id, 'ctrl+alt+x');
      expect(_c('ctrl+alt+j').label, 'Ctrl+Alt+J');
    });
    test('rejects bare, shift-only, no letter, two letters, junk', () {
      for (final s in [
        'j',
        'shift+j',
        'ctrl',
        'ctrl+j+k',
        'ctrl+1',
        '',
        'a b',
      ]) {
        expect(Chord.parse(s), isNull, reason: s);
      }
    });
    test('override JSON parses leniently', () {
      expect(ChordKeymap.parseOverrides(null), isEmpty);
      expect(ChordKeymap.parseOverrides('nope'), isEmpty);
      expect(ChordKeymap.parseOverrides('[1]'), isEmpty);
      expect(ChordKeymap.parseOverrides('{"a":"ctrl+j","b":3}'), {
        'a': 'ctrl+j',
      });
      expect(
        ChordKeymap.formatOverrides({'go.tasks': 'alt+t'}),
        '{"go.tasks":"alt+t"}',
      );
    });
  });

  group('overrides', () {
    ChordKeymap km(Map<String, String> o) =>
        ChordKeymap(platform: TargetPlatform.linux, isWeb: false, overrides: o);

    test('a valid override replaces the default', () {
      final k = km({'go.tasks': 'ctrl+alt+t'});
      expect(k.labelFor('go.tasks'), 'Ctrl+Alt+T');
      expect(k.labelFor('go.notes'), 'Ctrl+Shift+N');
    });
    test('unknown ids and bad chords are ignored', () {
      final k = km({'nope': 'ctrl+alt+t', 'go.tasks': 'banana'});
      expect(k.chordFor('nope'), isNull);
      expect(k.labelFor('go.tasks'), 'Ctrl+Shift+Q');
    });
    test('palette and save chords cannot be taken', () {
      for (final c in ['ctrl+k', 'meta+k', 'ctrl+w', 'ctrl+s']) {
        expect(km({'go.tasks': c}).labelFor('go.tasks'), 'Ctrl+Shift+Q');
      }
    });
    test('a chord already used by a default is rejected', () {
      final k = km({'go.tasks': 'ctrl+shift+n'});
      expect(k.labelFor('go.tasks'), 'Ctrl+Shift+Q');
      expect(k.labelFor('go.notes'), 'Ctrl+Shift+N');
    });
    test('two overrides on one chord are both rejected', () {
      final k = km({'go.tasks': 'ctrl+alt+t', 'go.events': 'ctrl+alt+t'});
      expect(k.labelFor('go.tasks'), 'Ctrl+Shift+Q');
      expect(k.labelFor('go.events'), 'Ctrl+Shift+R');
    });
    test('swapping two defaults is allowed', () {
      final k = km({'go.tasks': 'ctrl+shift+n', 'go.notes': 'ctrl+shift+q'});
      expect(k.labelFor('go.tasks'), 'Ctrl+Shift+N');
      expect(k.labelFor('go.notes'), 'Ctrl+Shift+Q');
    });
    test('AppState reads the pref', () {
      final p = MemoryStorage()
        ..write(ChordKeymap.prefKey, '{"go.tasks":"ctrl+alt+t"}');
      final s = AppState(SeedNotes(const []), prefs: p);
      expect(s.chords.labelFor('go.tasks'), 'Ctrl+Alt+T');
      final a = buildActions(s).firstWhere((a) => a.id == 'go.tasks');
      expect(a.chords, ['Ctrl+Alt+T']);
    });
  });

  group('registry', () {
    test('every chord id is an action with its label in the help group', () {
      final s = AppState(SeedNotes(const []), prefs: MemoryStorage());
      final by = {for (final a in buildActions(s)) a.id: a};
      for (final id in s.chords.ids) {
        expect(by[id], isNotNull, reason: id);
        expect(by[id]!.chords, isNotEmpty, reason: id);
      }
      // There is no chord section: each chord is an extra key on the row of
      // the command it duplicates.
      final rows = helpRows(buildActions(s));
      expect(rows.map((r) => r.$1), isNot(contains(startsWith('Chords'))));
      final keys = [
        for (final g in rows)
          for (final r in g.$2) ...r.$1.split(' / '),
      ];
      for (final id in s.chords.ids) {
        expect(keys, contains(s.chords.labelFor(id)), reason: id);
      }
      String rowOf(String what, String group) => rows
          .firstWhere((r) => r.$1 == group)
          .$2
          .firstWhere((r) => r.$2 == what)
          .$1;
      expect(rowOf('Go to Home', 'Go to'), 'g h / Ctrl+Shift+G');
      expect(
        rowOf('Command palette', 'App'),
        'Ctrl+K / Cmd+K / : / Ctrl+Shift+K',
      );
      expect(
        rowOf('Focus the area on the left', 'Navigation'),
        'H / Ctrl+Shift+J',
      );
      expect(
        rowOf('Save and leave edit mode', 'Edit'),
        'Ctrl+Enter / Cmd+Enter',
      );
      expect(
        rows
            .firstWhere((r) => r.$1 == 'Edit')
            .$2
            .any((r) => r.$1 == 'Esc / Ctrl+Shift+W'),
        isTrue,
      );
    });
  });

  group('chords in the app', () {
    testWidgets('desktop Ctrl+Shift chords work and are handled', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n1', summary: 'N')],
      );
      expect(await _chord(t, _c('ctrl+shift+q')), isTrue);
      expect(s.section, Section.tasks);
      expect(await _chord(t, _c('ctrl+shift+n')), isTrue);
      expect(s.section, Section.notes);
    });

    testWidgets('web Alt chords work; the desktop ones do not', (t) async {
      ChordKeymap.debugIsWeb = true;
      final s = await pumpTasksApp(t);
      expect(await _chord(t, _c('ctrl+shift+q')), isFalse);
      expect(s.section, Section.notes);
      expect(await _chord(t, _c('alt+q')), isTrue);
      expect(s.section, Section.tasks);
    });

    testWidgets('macOS desktop uses Cmd+Shift', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final s = await pumpTasksApp(t);
      expect(await _chord(t, _c('ctrl+shift+q')), isFalse);
      // Cmd+Shift+Q is the system log-out: Tasks takes T on native macOS.
      expect(await _chord(t, _c('meta+shift+q')), isFalse);
      expect(s.section, Section.notes);
      expect(await _chord(t, _c('meta+shift+t')), isTrue);
      expect(s.section, Section.tasks);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('macOS web uses Ctrl+Alt on the physical key', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      ChordKeymap.debugIsWeb = true;
      final s = await pumpTasksApp(t);
      expect(await _chord(t, _c('alt+q')), isFalse);
      expect(await _chord(t, _c('ctrl+alt+q')), isTrue);
      expect(s.section, Section.tasks);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('focus and panel chords', (t) async {
      final s = await pumpTasksApp(t);
      await _chord(t, _c('ctrl+shift+l'));
      final a = s.nav.area;
      await _chord(t, _c('ctrl+shift+j'));
      expect(s.nav.area, isNot(a));
      final c = s.sidebarCollapsed;
      await _chord(t, _c('ctrl+shift+m'));
      expect(s.sidebarCollapsed, !c);
    });

    Future<AppState> editing(WidgetTester t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n1', summary: 'Note', description: 'body')],
      );
      s.select('n1');
      await t.pumpAndSettle();
      s.startEdit('n1');
      await t.pumpAndSettle();
      await t.tap(find.byType(EditableText).first);
      await t.pumpAndSettle();
      return s;
    }

    testWidgets('inside a text field a chord is handled and inserts nothing', (
      t,
    ) async {
      final s = await editing(t);
      final ctl = s.draftFor('n1')!.titleController;
      final before = ctl.text;
      expect(await _chord(t, _c('ctrl+shift+q')), isTrue);
      expect(await _chord(t, _c('ctrl+shift+j')), isTrue);
      expect(ctl.text, before);
      expect(s.section, Section.tasks);
    });

    testWidgets('leave-edit chord goes through the guard from a field', (
      t,
    ) async {
      final s = await editing(t);
      await t.enterText(find.byType(EditableText).first, 'Changed');
      await t.pumpAndSettle();
      expect(await _chord(t, _c('ctrl+shift+w')), isTrue);
      expect(_k('leave-discard'), findsOneWidget);
      await t.tap(_k('leave-discard'));
      await t.pumpAndSettle();
      expect(s.isEditing('n1'), isFalse);
    });

    testWidgets('Ctrl+Enter still saves from the field', (t) async {
      final s = await editing(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expect(s.isEditing('n1'), isFalse);
    });

    testWidgets('no chord while an IME composes', (t) async {
      final s = await editing(t);
      s.draftFor('n1')!.titleController.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await t.pump();
      expect(await _chord(t, _c('ctrl+shift+q')), isFalse);
      expect(s.section, Section.notes);
    });

    testWidgets('bare vim keys stay off while typing', (t) async {
      final s = await editing(t);
      final area = s.nav.area;
      expect(await t.sendKeyDownEvent(LogicalKeyboardKey.keyJ), isFalse);
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
      expect(await t.sendKeyDownEvent(LogicalKeyboardKey.keyH), isFalse);
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyH);
      expect(s.nav.area, area);
    });

    testWidgets('help lists the active platform labels', (t) async {
      ChordKeymap.debugIsWeb = true;
      final s = await pumpTasksApp(t);
      showKeyboardHelp(t.element(find.byType(Navigator).first), s);
      await t.pumpAndSettle();
      expect(find.text('Alt+J'), findsOneWidget);
      expect(find.text('Alt+Q'), findsOneWidget);
      expect(find.textContaining('Ctrl+Shift+J'), findsNothing);
      expect(find.textContaining('CHORDS'), findsNothing);
      expect(find.byKey(const Key('help-typing-note')), findsOneWidget);
      expect(
        find.text('Alt+ shortcuts also work while typing.'),
        findsOneWidget,
      );
    });

    testWidgets('the palette shows chord labels', (t) async {
      await pumpTasksApp(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expect(find.text('Ctrl+Shift+Q'), findsOneWidget);
    });

    testWidgets('the palette chord opens the palette from a field', (t) async {
      await editing(t);
      expect(await _chord(t, _c('ctrl+shift+k')), isTrue);
      expect(find.text('Type a command or search'), findsWidgets);
    });
  });

  group('chords and popovers', () {
    Future<AppState> openSelect(WidgetTester t) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n1', summary: 'Note one', description: 'body')],
      );
      s.select('n1');
      await t.pumpAndSettle();
      s.startEdit('n1');
      await t.pumpAndSettle();
      await t.tap(_k('property-status'));
      await t.pumpAndSettle();
      expect(_k('property-option-status-doing'), findsOneWidget);
      return s;
    }

    testWidgets('a chord does nothing while a picker is open', (t) async {
      final s = await openSelect(t);
      expect(await _chord(t, _c('ctrl+shift+q')), isTrue);
      expect(s.section, Section.notes);
      expect(_k('property-option-status-doing'), findsOneWidget);
      expect(s.isEditing('n1'), isTrue);
    });

    testWidgets('after the popover closes the chord works again', (t) async {
      final s = await openSelect(t);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(_k('property-option-status-doing'), findsNothing);
      expect(await _chord(t, _c('ctrl+shift+q')), isTrue);
      expect(s.section, Section.tasks);
    });

    testWidgets('the palette chord closes an open palette', (t) async {
      await pumpTasksApp(t);
      expect(await _chord(t, _c('ctrl+shift+k')), isTrue);
      expect(find.text('Type a command or search'), findsWidgets);
      expect(await _chord(t, _c('ctrl+shift+k')), isTrue);
      expect(find.text('Type a command or search'), findsNothing);
    });

    test('native macOS never uses Q', () {
      final mac = ChordKeymap(platform: TargetPlatform.macOS, isWeb: false);
      for (final id in mac.ids) {
        expect(mac.chordFor(id)!.letter, isNot('q'), reason: id);
      }
      expect(mac.labelFor('go.tasks'), 'Cmd+Shift+T');
    });
  });
}
