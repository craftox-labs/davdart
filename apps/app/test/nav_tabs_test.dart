import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/tab_state.dart';
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
  Note(uid: 'pn', summary: 'Project note', parentUid: 'p'),
  Note(uid: 'loose', summary: 'Loose note'),
];

Future<AppState> _app(
  WidgetTester t, {
  MemoryStorage? prefs,
  Size size = const Size(1400, 900),
}) => pumpTasksApp(t, notes: _notes, prefs: prefs, size: size);

void main() {
  testWidgets('Home is the first tab, active at startup, not closable', (
    t,
  ) async {
    final s = await _app(t);
    expect(_k('tab-home'), findsOneWidget);
    expect(s.activeTab, isNull);
    expect(_k('home-page'), findsOneWidget);
    expect(s.tabs, isEmpty); // Home is not a document tab
    await s.closeActiveTab();
    await t.pumpAndSettle();
    expect(s.activeTab, isNull);
    expect(_k('home-page'), findsOneWidget);
  });

  testWidgets('a project opens in its own tab; picking it again focuses it', (
    t,
  ) async {
    final s = await _app(t);
    s.openProjectTab('p');
    await t.pumpAndSettle();
    expect(s.activeTab, const DocTab.project('p'));
    expect(s.mainProjectUid, 'p');
    expect(s.scopeUid, 'p');
    expect(_k('tab-p:p'), findsOneWidget);
    expect(find.text('Alpha'), findsWidgets); // the tab title and the page
    s.openProjectTab('q');
    await t.pumpAndSettle();
    expect(s.tabs, [const DocTab.project('p'), const DocTab.project('q')]);
    expect(s.mainProjectUid, 'q');
    s.openProjectTab('p');
    await t.pumpAndSettle();
    expect(s.tabs.length, 2, reason: 'already open: focused, not duplicated');
    expect(s.mainProjectUid, 'p');
  });

  testWidgets('closing a project tab returns to Home and clears the scope', (
    t,
  ) async {
    final s = await _app(t);
    s.openProjectTab('p');
    await t.pumpAndSettle();
    await s.closeTab(const DocTab.project('p'));
    await t.pumpAndSettle();
    expect(s.activeTab, isNull);
    expect(s.scopeUid, isNull);
    expect(_k('home-page'), findsOneWidget);
    expect(_k('tab-p:p'), findsNothing);
  });

  testWidgets('the Projects rail only changes the panel on Home', (t) async {
    final s = await _app(t);
    await t.tap(_k('rail-projects'));
    await t.pumpAndSettle();
    expect(s.section, Section.projects);
    expect(s.activeTab, isNull);
    expect(_k('home-page'), findsOneWidget);
    // Picking a card opens the project but keeps the panel list.
    await t.tap(_k('project-p'));
    await t.pumpAndSettle();
    expect(s.section, Section.projects);
    expect(s.mainProjectUid, 'p');
    expect(_k('projects-view'), findsOneWidget);
  });

  testWidgets('a restored active project tab comes back and owns the scope', (
    t,
  ) async {
    final prefs = MemoryStorage()
      ..write('davdart.tabs.v1.default', '["p:p"]')
      ..write('davdart.activetab.v1.default', 'p:p');
    final s = await _app(t, prefs: prefs);
    expect(s.activeTab, const DocTab.project('p'));
    expect(s.scopeUid, 'p');
    expect(_k('overview-page'), findsOneWidget);
  });

  testWidgets('a restored tab of a deleted project is dropped', (t) async {
    final prefs = MemoryStorage()
      ..write('davdart.tabs.v1.default', '["p:gone"]')
      ..write('davdart.activetab.v1.default', 'p:gone');
    final s = await _app(t, prefs: prefs);
    expect(s.tabs, isEmpty);
    expect(s.activeTab, isNull);
    expect(_k('home-page'), findsOneWidget);
  });

  testWidgets('the phone grid lists Home first, then project tabs', (t) async {
    final s = await _app(t, size: const Size(390, 800));
    s.openProjectTab('p');
    await t.pumpAndSettle();
    await t.tap(_k('bar-count'));
    await t.pumpAndSettle();
    expect(_k('open-grid'), findsOneWidget);
    expect(_k('grid-card-home'), findsOneWidget);
    expect(_k('grid-card-p:p'), findsOneWidget);
    expect(find.text('Open items (2)'), findsOneWidget);
    expect(_k('grid-close-p:p'), findsOneWidget);
    // Home is not closable.
    expect(_k('grid-close-home'), findsNothing);
    await t.tap(_k('grid-card-home'));
    await t.pumpAndSettle();
    expect(s.activeTab, isNull);
    expect(_k('home-page'), findsOneWidget);
  });

  testWidgets('Home at startup drops a stale saved folder scope', (t) async {
    final prefs = MemoryStorage()..write('davdart.scope.v1', '{"default":"p"}');
    final s = await _app(t, prefs: prefs);
    expect(s.activeTab, isNull);
    expect(s.scopeUid, isNull);
    expect(_k('home-page'), findsOneWidget);
  });

  testWidgets('closing a project tab moves the scope to the next tab', (
    t,
  ) async {
    final s = await _app(t);
    s.openProjectTab('p');
    s.openProjectTab('q');
    await t.pumpAndSettle();
    expect(s.scopeUid, 'q');
    await s.closeTab(const DocTab.project('q'));
    await t.pumpAndSettle();
    expect(s.activeTab, const DocTab.project('p'));
    expect(s.scopeUid, 'p');
  });
}
