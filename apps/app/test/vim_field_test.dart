import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_action.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app_actions.dart';
import 'package:davdart_app/ui/property/inline_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

/// The one editor with Vim editing: a note's body. The task and event
/// descriptions are plain multiline inline fields (see the last group, and the
/// design doc's stage list: stage 1 defers Vim in descriptions).
class _Kind {
  _Kind(this.name, this.uid, this.start, this.body);
  final String name;
  final String uid;
  final void Function(AppState s) start;
  final String Function(AppState s) body;
}

final _kinds = [
  _Kind(
    'note',
    'n1',
    (s) => s.startEdit('n1'),
    (s) => s.draftFor('n1')!.bodyController.text,
  ),
];

Future<AppState> _open(WidgetTester t, _Kind k, {MemoryStorage? prefs}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final s = await pumpTasksApp(
    t,
    prefs: prefs,
    notes: [
      Note(uid: 'n1', summary: 'Note one', description: 'hello world\nsecond'),
    ],
    tasks: [mkTask('k1', days: 0, description: 'hello world\nsecond')],
    events: [
      mkEvent('e1', days: 0, hour: 9, description: 'hello world\nsecond'),
    ],
  );
  s.select(k.uid);
  await t.pumpAndSettle();
  k.start(s);
  await t.pumpAndSettle();
  expect(s.isEditing(k.uid), isTrue);
  return s;
}

/// Click into the body (INSERT at the click), then Esc to NORMAL.
Future<void> _toNormal(WidgetTester t) async {
  await t.tap(_k('edit-body'));
  await t.pumpAndSettle();
  await _esc(t);
}

Future<void> _esc(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.escape);
  await t.pumpAndSettle();
}

/// Presses the character [ch] the way a keyboard reports it.
Future<void> _ch(WidgetTester t, String ch) async {
  final upper = ch != ch.toLowerCase();
  final key = ch == ' ' ? LogicalKeyboardKey.space : LogicalKeyboardKey.keyA;
  if (upper) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyDownEvent(key, character: ch);
  await t.sendKeyUpEvent(key);
  if (upper) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.pump();
}

Future<void> _keys(WidgetTester t, String s) async {
  for (final ch in s.split('')) {
    await _ch(t, ch);
  }
  await t.pumpAndSettle();
}

Future<void> _enter(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pumpAndSettle();
}

String _mode(WidgetTester t) => t.widget<Text>(_k('vim-mode')).data!;

Future<void> _chord(
  WidgetTester t,
  List<LogicalKeyboardKey> mods,
  LogicalKeyboardKey key,
) async {
  for (final m in mods) {
    await t.sendKeyDownEvent(m);
  }
  await t.sendKeyDownEvent(key);
  await t.sendKeyUpEvent(key);
  for (final m in mods.reversed) {
    await t.sendKeyUpEvent(m);
  }
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final k in _kinds) {
    group('vim field: ${k.name}', () {
      testWidgets('starts in NORMAL with the footer', (t) async {
        await _open(t, k);
        expect(_mode(t), 'NORMAL');
        expect(_k('edit-body'), findsOneWidget);
      });

      testWidgets('a click enters INSERT and typing inserts text', (t) async {
        final s = await _open(t, k);
        await t.tap(_k('edit-body'));
        await t.pumpAndSettle();
        expect(_mode(t), 'INSERT');
        await t.enterText(_k('edit-body'), 'typed text');
        await t.pumpAndSettle();
        expect(k.body(s), 'typed text');
      });

      testWidgets('NORMAL does not type characters', (t) async {
        final s = await _open(t, k);
        await _toNormal(t);
        expect(_mode(t), 'NORMAL');
        await _keys(t, 'zqy');
        expect(k.body(s), 'hello world\nsecond');
        expect(_mode(t), 'NORMAL');
      });

      testWidgets('NORMAL commands edit: x, dd, i then Esc', (t) async {
        final s = await _open(t, k);
        await _toNormal(t);
        await _keys(t, 'gg');
        await _keys(t, 'x');
        expect(k.body(s), 'ello world\nsecond');
        await _keys(t, 'dd');
        expect(k.body(s), 'second');
        await _keys(t, 'iX');
        expect(_mode(t), 'INSERT');
        await t.enterText(_k('edit-body'), 'Xsecond');
        await _esc(t);
        expect(_mode(t), 'NORMAL');
        expect(k.body(s), 'Xsecond');
      });

      testWidgets('Esc: INSERT to NORMAL; NORMAL does nothing and stays', (
        t,
      ) async {
        final s = await _open(t, k);
        await t.tap(_k('edit-body'));
        await t.pumpAndSettle();
        expect(_mode(t), 'INSERT');
        s.nav.markShown();
        await _esc(t);
        expect(_mode(t), 'NORMAL');
        expect(s.isEditing(k.uid), isTrue);
        for (var i = 0; i < 3; i++) {
          await _esc(t);
        }
        expect(_mode(t), 'NORMAL');
        expect(s.isEditing(k.uid), isTrue);
        expect(s.nav.shown, isTrue, reason: 'Esc in NORMAL must not hide');
      });

      testWidgets('v, V and Esc', (t) async {
        final s = await _open(t, k);
        await _toNormal(t);
        await _keys(t, 'gg');
        await _keys(t, 'v');
        expect(_mode(t), 'VISUAL');
        await _keys(t, 'e');
        await _keys(t, 'd');
        expect(k.body(s), ' world\nsecond');
        await _keys(t, 'V');
        expect(_mode(t), 'V-LINE');
        await _esc(t);
        expect(_mode(t), 'NORMAL');
      });

      testWidgets(':wq saves and leaves', (t) async {
        final s = await _open(t, k);
        await _toNormal(t);
        await _keys(t, 'ggx');
        await _keys(t, ':wq');
        expect(find.text(':wq'), findsOneWidget);
        await _enter(t);
        expect(s.isEditing(k.uid), isFalse);
        expect(s.tree.find('n1')!.note.description, contains('ello world'));
      });

      testWidgets('ZZ saves and leaves', (t) async {
        final s = await _open(t, k);
        await _toNormal(t);
        await _keys(t, 'ggxZZ');
        expect(s.isEditing(k.uid), isFalse);
      });

      testWidgets(':w saves and stays', (t) async {
        final s = await _open(t, k);
        await _toNormal(t);
        await _keys(t, 'ggx:w');
        await _enter(t);
        expect(s.isEditing(k.uid), isTrue);
        expect(s.dirtyFor(k.uid), isFalse);
        expect(_mode(t), 'NORMAL');
      });

      testWidgets(':q! discards', (t) async {
        final s = await _open(t, k);
        await _toNormal(t);
        await _keys(t, 'ggx:q!');
        await _enter(t);
        expect(s.isEditing(k.uid), isFalse);
        expect(find.text('Unsaved changes'), findsNothing);
      });

      testWidgets(':q on a clean edit leaves, on a dirty one asks', (t) async {
        final s = await _open(t, k);
        await _toNormal(t);
        await _keys(t, 'ggx:q');
        await _enter(t);
        expect(find.text('Keep editing'), findsOneWidget);
        expect(s.isEditing(k.uid), isTrue);
        await t.tap(find.text('Keep editing'));
        await t.pumpAndSettle();
        await _keys(t, 'u');
        await _keys(t, ':q');
        await _enter(t);
        expect(s.isEditing(k.uid), isFalse);
      });

      testWidgets('ZQ goes through the guard', (t) async {
        final s = await _open(t, k);
        await _toNormal(t);
        await _keys(t, 'ggxZQ');
        expect(find.text('Keep editing'), findsOneWidget);
        expect(s.isEditing(k.uid), isTrue);
      });

      testWidgets('Ctrl+Enter saves and leaves from NORMAL', (t) async {
        final s = await _open(t, k);
        await _toNormal(t);
        await _keys(t, 'ggx');
        await _chord(t, [
          LogicalKeyboardKey.controlLeft,
        ], LogicalKeyboardKey.enter);
        expect(s.isEditing(k.uid), isFalse);
      });

      testWidgets('Esc in the title field still leaves edit mode', (t) async {
        final s = await _open(t, k);
        await t.tap(_k('edit-title'));
        await t.pumpAndSettle();
        await _esc(t);
        expect(s.isEditing(k.uid), isFalse);
      });
    });
  }

  group('vim field: keys and footer', () {
    final k = _kinds.first;

    testWidgets('pending keys, count and Ex line show in the footer', (
      t,
    ) async {
      await _open(t, k);
      await _toNormal(t);
      expect(_k('vim-pending'), findsNothing);
      await _keys(t, '2d');
      expect(t.widget<Text>(_k('vim-pending')).data, '2d');
      await _esc(t);
      expect(_k('vim-pending'), findsNothing);
      await _keys(t, ':');
      expect(t.widget<Text>(_k('vim-ex')).data, ':');
      await _esc(t);
      expect(_k('vim-ex'), findsNothing);
      await _keys(t, 'gg');
      expect(_k('vim-pending'), findsNothing);
    });

    testWidgets('an unknown Ex command shows a message', (t) async {
      await _open(t, k);
      await _toNormal(t);
      await _keys(t, ':nope');
      await _enter(t);
      expect(_k('vim-message'), findsOneWidget);
    });

    testWidgets('mode indicator text for every mode', (t) async {
      await _open(t, k);
      await _toNormal(t);
      expect(_mode(t), 'NORMAL');
      await _keys(t, 'v');
      expect(_mode(t), 'VISUAL');
      await _esc(t);
      await _keys(t, 'V');
      expect(_mode(t), 'V-LINE');
      await _esc(t);
      await _keys(t, 'i');
      expect(_mode(t), 'INSERT');
    });

    testWidgets('block caret: NORMAL selects one character', (t) async {
      final s = await _open(t, k);
      await _toNormal(t);
      await _keys(t, 'gg');
      final c = s.draftFor('n1')!.bodyController;
      expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 1));
      await _keys(t, 'l');
      expect(c.selection, const TextSelection(baseOffset: 1, extentOffset: 2));
    });

    testWidgets('search and u/Ctrl-r', (t) async {
      final s = await _open(t, k);
      await _toNormal(t);
      await _keys(t, 'gg/world');
      await _enter(t);
      await _keys(t, 'x');
      expect(s.draftFor('n1')!.bodyController.text, 'hello orld\nsecond');
      await _keys(t, 'u');
      expect(s.draftFor('n1')!.bodyController.text, 'hello world\nsecond');
      await _chord(t, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyR);
      expect(s.draftFor('n1')!.bodyController.text, 'hello orld\nsecond');
    });

    testWidgets('Ctrl+Z in INSERT undoes through the engine', (t) async {
      final s = await _open(t, k);
      await t.tap(_k('edit-body'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-body'), 'changed');
      await t.pumpAndSettle();
      expect(s.draftFor('n1')!.bodyController.text, 'changed');
      await _chord(t, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.keyZ);
      expect(s.draftFor('n1')!.bodyController.text, 'hello world\nsecond');
      expect(_mode(t), 'INSERT');
    });
  });

  group('vim field: leader and chords', () {
    final k = _kinds.first;

    testWidgets('Space g t goes to Tasks', (t) async {
      final s = await _open(t, k);
      await _toNormal(t);
      await _keys(t, ' ');
      expect(t.widget<Text>(_k('vim-pending')).data, '<Space>');
      await _keys(t, 'g');
      expect(t.widget<Text>(_k('vim-pending')).data, '<Space>g');
      await _keys(t, 't');
      expect(s.section, Section.tasks);
      expect(s.draftFor('n1'), isNotNull);
    });

    testWidgets('Space Space opens the palette', (t) async {
      await _open(t, k);
      await _toNormal(t);
      await _keys(t, '  ');
      expect(_k('palette'), findsOneWidget);
    });

    testWidgets('Space : opens the palette', (t) async {
      await _open(t, k);
      await _toNormal(t);
      await _keys(t, ' :');
      expect(_k('palette'), findsOneWidget);
    });

    testWidgets('Space with an unbound key does nothing', (t) async {
      final s = await _open(t, k);
      await _toNormal(t);
      await _keys(t, ' 9');
      expect(_k('vim-pending'), findsNothing);
      expect(s.draftFor('n1')!.bodyController.text, 'hello world\nsecond');
    });

    testWidgets('in INSERT a space types a space, no leader', (t) async {
      await _open(t, k);
      await t.tap(_k('edit-body'));
      await t.pumpAndSettle();
      await _keys(t, ' ');
      expect(_k('vim-pending'), findsNothing);
      expect(_mode(t), 'INSERT');
    });

    testWidgets('chords work in INSERT', (t) async {
      final s = await _open(t, k);
      await t.tap(_k('edit-body'));
      await t.pumpAndSettle();
      expect(_mode(t), 'INSERT');
      // Native Linux: Ctrl+Shift+Q is go to Tasks.
      await _chord(t, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyQ);
      expect(s.section, Section.tasks);
    });

    testWidgets('chords work in NORMAL', (t) async {
      final s = await _open(t, k);
      await _toNormal(t);
      await _chord(t, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyQ);
      expect(s.section, Section.tasks);
    });
  });

  group('vim field: IME and setting', () {
    final k = _kinds.first;

    testWidgets('a composing IME keeps its keys (Esc does not leave INSERT)', (
      t,
    ) async {
      final s = await _open(t, k);
      await t.tap(_k('edit-body'));
      await t.pumpAndSettle();
      final c = s.draftFor('n1')!.bodyController;
      c.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await t.pump();
      await _esc(t);
      expect(_mode(t), 'INSERT');
      expect(s.isEditing('n1'), isTrue);
    });

    testWidgets('setting off: plain field, Esc leaves edit mode as before', (
      t,
    ) async {
      final prefs = MemoryStorage();
      final s = await _open(t, k, prefs: prefs);
      s.setVimEditor(false);
      await t.pumpAndSettle();
      expect(_k('vim-mode'), findsNothing);
      expect(_k('edit-body'), findsOneWidget);
      await t.tap(_k('edit-body'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-body'), 'plain');
      await t.pumpAndSettle();
      expect(s.draftFor('n1')!.bodyController.text, 'plain');
      await _esc(t);
      // Dirty: the guard asks; discard leaves.
      await t.tap(_k('leave-discard'));
      await t.pumpAndSettle();
      expect(s.isEditing('n1'), isFalse);
    });

    testWidgets('setting is off by pref, on by default, persists', (t) async {
      final prefs = MemoryStorage();
      final s = await _open(t, k, prefs: prefs);
      expect(s.vimEditor, isTrue);
      s.setVimEditor(false);
      expect(prefs.read('davdart.vim.editor.v1'), 'false');
      s.setVimEditor(true);
      expect(prefs.read('davdart.vim.editor.v1'), isNull);
    });

    testWidgets('touch layout: plain field even with the setting on', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        notes: [Note(uid: 'n1', summary: 'Note one', description: 'body')],
      );
      s.select('n1');
      await t.pumpAndSettle();
      s.startEdit('n1');
      await t.pumpAndSettle();
      expect(s.vimEditor, isTrue);
      expect(_k('edit-body'), findsOneWidget);
      expect(_k('vim-mode'), findsNothing);
    });

    testWidgets('Settings checkbox flips the setting', (t) async {
      final s = await pumpTasksApp(t);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      s.setSection(Section.settings);
      await t.pumpAndSettle();
      expect(_k('vim-editor'), findsOneWidget);
      await t.tap(_k('vim-editor'));
      await t.pumpAndSettle();
      expect(s.vimEditor, isFalse);
    });

    testWidgets('Settings checkbox is disabled on the touch layout', (t) async {
      final s = await pumpTasksApp(t);
      s.setSection(Section.settings);
      await t.pumpAndSettle();
      expect(find.textContaining('Needs a keyboard'), findsOneWidget);
      await t.tap(_k('vim-editor'));
      await t.pumpAndSettle();
      expect(s.vimEditor, isTrue);
    });
  });

  // A task's and an event's description is a plain multiline field, not a Vim
  // one: their edit modes are gone (2026-11-28-inline-edit-design.md, section
  // 6's stage list, and its open question 2 - Vim there waits until VimField no
  // longer needs a draft).
  group('vim field: task and event descriptions are plain fields', () {
    testWidgets('no Vim field, no mode footer, a multiline InlineText', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final s = await pumpTasksApp(
        t,
        notes: [
          Note(
            uid: 'n1',
            summary: 'Note one',
            description: 'hello world\nsecond',
          ),
        ],
        tasks: [mkTask('k1', days: 0, description: 'hello world\nsecond')],
        events: [
          mkEvent('e1', days: 0, hour: 9, description: 'hello world\nsecond'),
        ],
      );
      for (final (uid, start, read) in [
        ('k1', s.startTaskEdit, (AppState s) => s.taskById('k1')!.description),
        (
          'e1',
          s.startEventEdit,
          (AppState s) => s.eventById('e1')!.description,
        ),
      ]) {
        s.select(uid);
        await t.pumpAndSettle();
        start(uid);
        await t.pumpAndSettle();
        final field = _k('edit-body');
        expect(field, findsOneWidget);
        expect(t.widget<InlineText>(field).multiline, isTrue);
        expect(_k('vim-mode'), findsNothing);
        await t.tap(field);
        await t.pumpAndSettle();
        expect(_k('inline-text-editing'), findsOneWidget);
        await t.enterText(field, 'plain text');
        await t.pump(const Duration(milliseconds: 900));
        await t.pumpAndSettle();
        expect(read(s), 'plain text');
        expect(_k('vim-mode'), findsNothing);
      }
    });
  });

  group('vim field: help and palette', () {
    testWidgets('the help has a Vim editing group from the static table', (
      t,
    ) async {
      final s = await pumpTasksApp(t);
      final rows = helpRows(buildActions(s));
      final g = rows.where((r) => r.$1 == 'Vim editing').toList();
      expect(g, hasLength(1));
      expect(g.first.$2.any((r) => r.$1.contains(':wq')), isTrue);
    });

    testWidgets('a palette action toggles Vim editing', (t) async {
      final s = await pumpTasksApp(t);
      final a = buildActions(s).firstWhere((a) => a.id == 'setting.vim-editor');
      expect(a.title, 'Turn Vim editing off');
      s.setVimEditor(false);
      expect(
        buildActions(s).firstWhere((a) => a.id == 'setting.vim-editor').title,
        'Turn Vim editing on',
      );
    });
  });
}
