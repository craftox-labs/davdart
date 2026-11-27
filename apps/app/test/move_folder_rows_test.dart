import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/move_folder_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _folder(
  String uid,
  String name, {
  String? parent,
  bool container = false,
  bool personal = false,
}) => Note(
  uid: uid,
  summary: name,
  parentUid: parent,
  categories: [
    folderTag,
    if (container) projectsTag,
    if (personal) personalTag,
  ],
);

final _notes = [
  _folder('pc', 'Personal', personal: true),
  _folder('pf', 'Personal sub', parent: 'pc'),
  _folder('c', 'Projects', container: true),
  _folder('p', 'Alpha', parent: 'c'),
  _folder('ps', 'Alpha sub', parent: 'p'),
  _folder('q', 'Beta', parent: 'c'),
  Note(uid: 'in-p', summary: 'In Alpha', parentUid: 'p'),
  Note(uid: 'loose', summary: 'Loose note'),
];

Future<AppState> _open(
  WidgetTester t,
  String uid, {
  Size size = const Size(1280, 900),
}) async {
  final s = await pumpTasksApp(t, notes: _notes, size: size);
  showMoveFolderDialog(t.element(_k('home-page')), s, s.tree.find(uid)!.note);
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
  return s;
}

bool _enabled(WidgetTester t, String k) =>
    t.widget<FItem>(_k(k)).enabled ?? true;

void main() {
  testWidgets('rows: Personal, each project, sub-folders; no containers', (
    t,
  ) async {
    await _open(t, 'loose');
    expect(_k('move-folder-personal'), findsOneWidget);
    expect(_k('move-folder-p'), findsOneWidget);
    expect(_k('move-folder-q'), findsOneWidget);
    expect(_k('move-folder-ps'), findsOneWidget); // sub-folder of a project
    expect(_k('move-folder-pf'), findsOneWidget); // sub-folder of Personal
    expect(_k('move-folder-pc'), findsNothing);
    expect(_k('move-folder-c'), findsNothing);
    expect(_k('move-folder-top'), findsNothing);
    for (final k in ['personal', 'p', 'q', 'ps', 'pf']) {
      expect(_enabled(t, 'move-folder-$k'), isTrue, reason: k);
    }
  });

  testWidgets('a sub-folder row is indented under its project', (t) async {
    await _open(t, 'loose');
    final project = t.getTopLeft(_k('move-folder-p')).dx;
    final sub = t.getTopLeft(_k('move-folder-ps')).dx;
    expect(sub, greaterThan(project));
  });

  testWidgets('the current parent project row is disabled', (t) async {
    await _open(t, 'in-p');
    expect(_enabled(t, 'move-folder-p'), isFalse);
    expect(_enabled(t, 'move-folder-q'), isTrue);
    expect(_enabled(t, 'move-folder-personal'), isTrue);
  });

  testWidgets('a project is not offered Personal and not itself or children', (
    t,
  ) async {
    await _open(t, 'p');
    expect(_enabled(t, 'move-folder-personal'), isFalse);
    expect(_k('move-folder-p'), findsNothing);
    expect(_k('move-folder-ps'), findsNothing);
  });

  testWidgets('tapping a project row moves the note into it', (t) async {
    final s = await _open(t, 'loose');
    await t.tap(_k('move-folder-q'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(s.tree.find('loose')!.note.parentUid, 'q');
    expect(_k('move-folder-q'), findsNothing, reason: 'dialog closed');
  });

  testWidgets('tapping a project sub-folder row moves the note into it', (
    t,
  ) async {
    final s = await _open(t, 'loose');
    await t.tap(_k('move-folder-ps'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(s.tree.find('loose')!.note.parentUid, 'ps');
  });

  testWidgets('phone width: rows fit and a tap still moves', (t) async {
    final s = await _open(t, 'loose', size: const Size(390, 800));
    for (final k in ['personal', 'p', 'q', 'ps']) {
      final r = t.getRect(_k('move-folder-$k'));
      expect(r.left, greaterThanOrEqualTo(0), reason: k);
      expect(r.right, lessThanOrEqualTo(390), reason: k);
    }
    await t.tap(_k('move-folder-p'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(s.tree.find('loose')!.note.parentUid, 'p');
    expect(t.takeException(), isNull);
  });
}
