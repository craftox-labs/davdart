import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/key_bindings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Future<AppState> _open(WidgetTester t) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final s = await pumpTasksApp(
    t,
    notes: [
      Note(uid: 'n1', summary: 'Note one', description: 'hello world\nsecond'),
      Note(uid: 'n2', summary: 'Note two', description: 'other text here'),
    ],
  );
  // Both are tabs in edit mode (their drafts survive switching); n1 shows.
  s.openNoteTab('n2');
  await t.pumpAndSettle();
  s.startEdit('n2');
  await t.pumpAndSettle();
  s.openNoteTab('n1');
  await t.pumpAndSettle();
  s.startEdit('n1');
  await t.pumpAndSettle();
  return s;
}

String _mode(WidgetTester t) => t.widget<Text>(_k('vim-mode')).data!;

Future<void> _esc(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.escape);
  await t.pumpAndSettle();
}

Future<void> _ch(
  WidgetTester t,
  String ch, {
  LogicalKeyboardKey key = LogicalKeyboardKey.keyA,
  List<LogicalKeyboardKey> mods = const [],
}) async {
  for (final m in mods) {
    await t.sendKeyDownEvent(m);
  }
  await t.sendKeyDownEvent(key, character: ch);
  await t.sendKeyUpEvent(key);
  for (final m in mods.reversed) {
    await t.sendKeyUpEvent(m);
  }
  await t.pump();
}

Future<void> _toNormal(WidgetTester t) async {
  await t.tap(_k('edit-body'));
  await t.pumpAndSettle();
  await _esc(t);
}

void main() {
  testWidgets('switching items in the same pane resets the editor', (t) async {
    final s = await _open(t);
    await _toNormal(t);
    await _ch(t, 'x');
    await _ch(t, 'x');
    expect(s.draftFor('n1')!.bodyController.text, isNot('hello world\nsecond'));
    s.openNoteTab('n2');
    await t.pumpAndSettle();
    expect(s.isEditing('n2'), isTrue);
    expect(_mode(t), 'NORMAL');
    await t.tap(_k('edit-body'));
    await t.pumpAndSettle();
    await _esc(t);
    await _ch(t, 'u');
    await t.pumpAndSettle();
    expect(s.draftFor('n2')!.bodyController.text, 'other text here');
    expect(_mode(t), 'NORMAL');
  });

  testWidgets('Ctrl+Z after a switch leaves the new item alone', (t) async {
    final s = await _open(t);
    await _toNormal(t);
    await _ch(t, 'x');
    s.openNoteTab('n2');
    await t.pumpAndSettle();
    expect(s.isEditing('n2'), isTrue);
    await t.tap(_k('edit-body'));
    await t.pumpAndSettle();
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(s.draftFor('n2')!.bodyController.text, 'other text here');
  });

  testWidgets('German Shift+7 is / and Shift+comma is :', (t) async {
    await _open(t);
    await _toNormal(t);
    await _ch(
      t,
      '/',
      key: LogicalKeyboardKey.digit7,
      mods: [LogicalKeyboardKey.shiftLeft],
    );
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('vim-ex')).data, '/');
    await _esc(t);
    await _ch(
      t,
      ':',
      key: LogicalKeyboardKey.comma,
      mods: [LogicalKeyboardKey.shiftLeft],
    );
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('vim-ex')).data, ':');
  });

  testWidgets('AltGr characters reach the editor ({ } as motions)', (t) async {
    final s = await _open(t);
    await _toNormal(t);
    await _ch(
      t,
      '}',
      key: LogicalKeyboardKey.digit0,
      mods: [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.altRight],
    );
    await t.pumpAndSettle();
    final c = s.draftFor('n1')!.bodyController;
    expect(c.selection.start, c.text.length - 1);
    expect(_mode(t), 'NORMAL');
  });

  test('keyToken uses the typed character and never re-shifts it', () {
    KeyEvent ev(LogicalKeyboardKey k, String? ch) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: k,
      character: ch,
      timeStamp: Duration.zero,
    );
    expect(keyToken(ev(LogicalKeyboardKey.digit7, '/'), shift: true), '/');
    expect(keyToken(ev(LogicalKeyboardKey.comma, ';'), shift: true), ';');
    expect(keyToken(ev(LogicalKeyboardKey.comma, ':'), shift: true), ':');
    expect(keyToken(ev(LogicalKeyboardKey.digit8, '['), shift: false), '[');
    expect(keyToken(ev(LogicalKeyboardKey.digit7, '{'), shift: false), '{');
    expect(keyToken(ev(LogicalKeyboardKey.keyJ, 'J'), shift: true), 'J');
    // No character: the US map still applies.
    expect(keyToken(ev(LogicalKeyboardKey.slash, null), shift: true), '?');
    expect(keyToken(ev(LogicalKeyboardKey.semicolon, null), shift: true), ':');
  });

  testWidgets(':w with an empty title shows an error; :wq stays', (t) async {
    final s = await _open(t);
    await _toNormal(t);
    s.draftFor('n1')!.titleController.text = '';
    for (final ch in ':w'.split('')) {
      await _ch(t, ch);
    }
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('vim-message')).data, 'E: title is required');
    for (final ch in ':wq'.split('')) {
      await _ch(t, ch);
    }
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(s.isEditing('n1'), isTrue);
    expect(t.widget<Text>(_k('vim-message')).data, 'E: title is required');
  });

  testWidgets('a drag or a right click does not switch to INSERT', (t) async {
    await _open(t);
    await _toNormal(t);
    final c = t.getCenter(_k('edit-body'));
    final g = await t.startGesture(c);
    await g.moveBy(const Offset(60, 0));
    await g.up();
    await t.pumpAndSettle();
    expect(_mode(t), 'NORMAL');
    await t.tap(_k('edit-body'));
    await t.pumpAndSettle();
    expect(_mode(t), 'INSERT');
    await _esc(t);
    final r = await t.startGesture(
      c,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await r.up();
    await t.pumpAndSettle();
    expect(_mode(t), 'NORMAL');
  });
}
