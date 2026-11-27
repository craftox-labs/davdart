import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _folder(
  String uid,
  String name, {
  String? parent,
  bool container = false,
}) => Note(
  uid: uid,
  summary: name,
  parentUid: parent,
  categories: [folderTag, if (container) projectsTag],
);

final _notes = [
  _folder('c', 'Projects', container: true),
  _folder('p', 'Alpha', parent: 'c'),
  _folder('q', 'Beta', parent: 'c'),
  _folder('r', 'Gamma', parent: 'c'),
  Note(uid: 'n1', summary: 'Note one'),
];

Future<void> _drag(WidgetTester t, Offset from, Offset to) async {
  final g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
  await t.pump();
  await g.moveBy(const Offset(12, 0));
  await t.pump();
  await g.moveTo(to);
  await t.pump();
  await g.moveBy(const Offset(1, 0));
  await t.pump();
  await g.up();
  await t.pump(const Duration(milliseconds: 300));
  // Let hover tooltips' timers run out.
  await t.pump(const Duration(seconds: 1));
}

Future<(AppState, MemoryStorage)> _three(WidgetTester t) async {
  final prefs = MemoryStorage();
  final s = await pumpTasksApp(t, notes: _notes, prefs: prefs);
  s.openProjectTab('p');
  s.openProjectTab('q');
  s.openProjectTab('r');
  await t.pump(const Duration(milliseconds: 300));
  expect(s.tabs.map((e) => e.code), ['p:p', 'p:q', 'p:r']);
  return (s, prefs);
}

void main() {
  testWidgets('the Home tab has no drag handle, project tabs do', (t) async {
    await _three(t);
    expect(_k('tab-home'), findsOneWidget);
    expect(_k('tab-drag-home'), findsNothing);
    expect(
      find.descendant(
        of: _k('tab-home'),
        matching: find.byWidgetPredicate((w) => w is Draggable),
      ),
      findsNothing,
    );
    for (final c in ['p:p', 'p:q', 'p:r']) {
      expect(_k('tab-drag-$c'), findsOneWidget);
    }
  });

  testWidgets('dragging a project tab to empty strip space moves it last', (
    t,
  ) async {
    final (s, prefs) = await _three(t);
    await _drag(
      t,
      t.getCenter(_k('tab-p:p')),
      t.getRect(_k('tab-end-drop')).center,
    );
    expect(s.tabs.map((e) => e.code), ['p:q', 'p:r', 'p:p']);
    // The order is saved.
    final saved = TabList()
      ..decode(prefs.read('davdart.tabs.v1.default') ?? '');
    expect(saved.tabs.map((e) => e.code), ['p:q', 'p:r', 'p:p']);
  });

  testWidgets('dragging a project tab onto the left half of another inserts '
      'before it', (t) async {
    final (s, _) = await _three(t);
    final r = t.getRect(_k('tab-p:q'));
    await _drag(t, t.getCenter(_k('tab-p:r')), Offset(r.left + 8, r.center.dy));
    expect(s.tabs.map((e) => e.code), ['p:p', 'p:r', 'p:q']);
  });

  testWidgets('dropping a tab on the Home tab is rejected, order unchanged', (
    t,
  ) async {
    final (s, prefs) = await _three(t);
    final before = prefs.read('davdart.tabs.v1.default');
    final h = t.getRect(_k('tab-home'));
    await _drag(t, t.getCenter(_k('tab-p:q')), Offset(h.left + 8, h.center.dy));
    expect(s.tabs.map((e) => e.code), ['p:p', 'p:q', 'p:r']);
    expect(prefs.read('davdart.tabs.v1.default'), before);
    expect(s.activeTab, const DocTab.project('r'));
  });

  testWidgets('a note tab cannot be dropped before Home either', (t) async {
    final s = await pumpTasksApp(t, notes: _notes);
    s.openNoteTab('n1');
    s.openProjectTab('p');
    await t.pump(const Duration(milliseconds: 300));
    final h = t.getRect(_k('tab-home'));
    await _drag(
      t,
      t.getCenter(_k('tab-n:n1')),
      Offset(h.left + 4, h.center.dy),
    );
    expect(s.tabs.map((e) => e.code), ['n:n1', 'p:p']);
    expect(_k('tab-home'), findsOneWidget);
  });
}
