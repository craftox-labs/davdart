import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _f(String uid, String name, {String? parent, bool container = false}) =>
    Note(
      uid: uid,
      summary: name,
      parentUid: parent,
      categories: [folderTag, if (container) projectsTag],
    );

Note _n(String uid, String parent, String status) => Note(
  uid: uid,
  summary: uid,
  parentUid: parent,
  description: 'status: $status\n\nx',
);

final _notes = [
  _f('c', 'Projects', container: true),
  _f('a', 'Alpha', parent: 'c'),
  _f('b', 'Beta', parent: 'c'),
  _f('sub', 'Sub', parent: 'a'),
  _n('n1', 'sub', 'done'),
  _n('n2', 'a', 'review'),
  _n('out', 'zz', 'todo'),
];

Future<AppState> _app(
  WidgetTester t, {
  Size size = const Size(1280, 900),
  List<Note>? notes,
}) async {
  AppState.debugDefaultFocus = HomeFocus.board;
  final s = await pumpTasksApp(
    t,
    size: size,
    notes: notes ?? _notes,
    tasks: [
      mkTask('t1', parent: 'a'),
      mkTask('t2', parent: 'sub'),
    ],
  );
  await s.activateTab(null);
  await t.pumpAndSettle();
  return s;
}

Future<void> _end(WidgetTester t) => t.pump(const Duration(seconds: 1));

void main() {
  group('rail and panel', () {
    testWidgets('rail item opens the Projects panel with counts', (t) async {
      final s = await _app(t);
      await t.tap(_k('rail-projects'));
      await t.pumpAndSettle();
      expect(s.section, Section.projects);
      expect(_k('projects-view'), findsOneWidget);
      expect(_k('projects-all'), findsOneWidget);
      expect(_k('project-a'), findsOneWidget);
      expect(_k('project-b'), findsOneWidget);
      expect(_k('project-sub'), findsNothing); // not a project
      // Alpha: tasks t1, t2 open, n2 review, n1 done.
      final counts = t.widget<Text>(_k('project-counts-a')).data;
      expect(counts, '2 open · 1 review · 1 done');
      expect(t.widget<Text>(_k('project-counts-b')).data, 'Nothing to count');
      expect(_k('project-progress-a'), findsOneWidget);
      expect(t.widget<Text>(_k('projects-else-counts')).data, '1 open');
      await _end(t);
    });

    testWidgets('tap sets the folder scope, All clears it', (t) async {
      final s = await _app(t);
      await t.tap(_k('rail-projects'));
      await t.pumpAndSettle();
      await t.tap(_k('project-b'));
      await t.pumpAndSettle();
      expect(s.scopeUid, 'b');
      await t.tap(_k('projects-all'));
      await t.pumpAndSettle();
      expect(s.scopeUid, isNull);
      // A folder inside a project keeps that project selected.
      s.openFolder('sub');
      await t.pumpAndSettle();
      expect(s.projectIndex.projectOf(s.scopeUid!)!.uid, 'a');
      await _end(t);
    });

    testWidgets('Everything else is a non-interactive count row', (t) async {
      final s = await _app(t);
      await t.tap(_k('rail-projects'));
      await t.pumpAndSettle();
      s.openFolder('a');
      await t.pumpAndSettle();
      expect(
        find.ancestor(
          of: _k('projects-else'),
          matching: find.byType(FTappable),
        ),
        findsNothing,
      );
      expect(s.scopeUid, 'a');
      await _end(t);
    });

    testWidgets('New project creates the container once', (t) async {
      final s = await _app(t, notes: const []);
      // No project yet, so the rail leaves the item out: the panel is
      // reachable from the palette (and the phone's scope pill).
      expect(_k('rail-projects'), findsNothing);
      s.setSection(Section.projects);
      await t.pumpAndSettle();
      expect(_k('projects-empty'), findsOneWidget);
      await t.tap(_k('new-project'));
      await t.pumpAndSettle();
      await t.enterText(_k('new-project-title'), 'First');
      await t.tap(_k('new-project-add'));
      await t.pumpAndSettle();
      expect(s.projectIndex.containers(), hasLength(1));
      expect(s.projectIndex.containers().single.summary, 'Projects');
      expect(s.projectIndex.containers().single.categories, [
        folderTag,
        projectsTag,
      ]);
      expect(s.projectIndex.projects().single.summary, 'First');
      expect(s.scopeUid, s.projectIndex.projects().single.uid);
      await t.tap(_k('new-project'));
      await t.pumpAndSettle();
      await t.enterText(_k('new-project-title'), 'Second');
      await t.tap(_k('new-project-add'));
      await t.pumpAndSettle();
      expect(s.projectIndex.containers(), hasLength(1));
      expect(s.projectIndex.projects(), hasLength(2));
      await _end(t);
    });

    testWidgets('a view row sets the scope and the section together', (
      t,
    ) async {
      final s = await _app(t);
      s.setSection(Section.projects);
      await t.pumpAndSettle();
      await t.tap(_k('project-toggle-a'));
      await t.pumpAndSettle();
      await t.tap(_k('project-view-a-notes'));
      await t.pumpAndSettle();
      expect(s.scopeUid, 'a');
      expect(s.section, Section.notes);
      // Board is the Tasks list scoped, until the board lands in the panel.
      s.setSection(Section.projects);
      await t.pumpAndSettle();
      await t.tap(_k('project-view-a-board'));
      await t.pumpAndSettle();
      expect(s.scopeUid, 'a');
      expect(s.section, Section.tasks);
      // Overview is the project's own page (a placeholder for now).
      s.setSection(Section.projects);
      await t.pumpAndSettle();
      await t.tap(_k('project-view-a-overview'));
      await t.pumpAndSettle();
      expect(s.scopeUid, 'a');
      expect(s.section, Section.overview);
      expect(_k('overview-panel'), findsOneWidget);
      expect(
        find.text('More coming: a summary of this project here.'),
        findsOneWidget,
      );
      // Without the project scope the page has nothing to show: Notes.
      s.openFolder(null);
      await t.pumpAndSettle();
      expect(s.section, Section.notes);
      await _end(t);
    });

    testWidgets('context menu offers rename, new folder, delete', (t) async {
      await _app(t);
      await t.tap(_k('rail-projects'));
      await t.pumpAndSettle();
      await t.tap(_k('project-a'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-project-rename-a'), findsOneWidget);
      expect(_k('menu-project-new-folder-a'), findsOneWidget);
      expect(_k('menu-project-delete-a'), findsOneWidget);
      await _end(t);
    });
  });

  group('notes tree, crumbs, tags, new items', () {
    testWidgets('project rows get the project icon', (t) async {
      final s = await _app(t);
      // The Projects panel lists the projects with the project icon (the
      // Notes panel shows one scope's notes now, not the whole tree).
      s.setSection(Section.projects);
      await t.pumpAndSettle();
      expect(find.byIcon(FLucideIcons.folderKanban), findsNWidgets(3));
      await _end(t);
    });

    testWidgets('wide crumb skips the container', (t) async {
      final s = await _app(t);
      s.openFolder('sub');
      await t.pumpAndSettle();
      final text = t.widget<Text>(_k('crumb-folder')).data;
      expect(text, 'Alpha  ›  Sub');
      await _end(t);
    });

    testWidgets('phone crumb and its sheet skip the container', (t) async {
      final s = await _app(t, size: const Size(390, 800));
      s.openFolder('a');
      await t.pumpAndSettle();
      expect(_k('crumb-more'), findsNothing); // Space > Alpha
      s.openFolder('sub');
      await t.pumpAndSettle();
      await t.tap(_k('crumb-more'));
      await t.pumpAndSettle();
      expect(_k('crumb-anc-1'), findsOneWidget);
      expect(_k('crumb-anc-2'), findsNothing);
      expect(
        find.descendant(of: _k('crumb-anc-1'), matching: find.text('Alpha')),
        findsOneWidget,
      );
      expect(find.text('Projects'), findsNothing);
      await _end(t);
    });

    testWidgets('the container itself still shows when it is the scope', (
      t,
    ) async {
      final s = await _app(t);
      s.openFolder('c');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await _end(t);
    });

    testWidgets('kind-projects is hidden from tag lists', (t) async {
      final s = await _app(t);
      expect(s.tags, isNot(contains(projectsTag)));
      expect(s.tags, isNot(contains(folderTag)));
      await _end(t);
    });

    testWidgets('new tasks and events go under the scoped project', (t) async {
      final s = await _app(t);
      s.openFolder('sub');
      final tid = await t.runAsync(() => s.addTask('Scoped'));
      final eid = await t.runAsync(
        () => s.addEvent('Meet', start: DateTime(2026, 12, 1, 9)),
      );
      await t.pumpAndSettle();
      expect(s.tasks.firstWhere((k) => k.uid == tid).parentUid, 'sub');
      expect(s.events.firstWhere((e) => e.uid == eid).parentUid, 'sub');
      expect(s.projectIndex.projectOf(tid!)!.uid, 'a');
      s.openFolder(null);
      final free = await t.runAsync(() => s.addTask('Free'));
      expect(s.tasks.firstWhere((k) => k.uid == free).parentUid, isNull);
      await _end(t);
    });

    testWidgets('container scope gives new items no container parent', (
      t,
    ) async {
      final s = await _app(t);
      s.openFolder('c');
      final tid = await t.runAsync(() => s.addTask('Loose'));
      final eid = await t.runAsync(
        () => s.addEvent('Evt', start: DateTime.utc(2026, 12, 1, 9)),
      );
      await t.runAsync(() => s.addNote('Nt', parentUid: 'c'));
      expect(s.tasks.firstWhere((k) => k.uid == tid).parentUid, isNull);
      expect(s.events.firstWhere((e) => e.uid == eid).parentUid, isNull);
      expect(s.notes.firstWhere((n) => n.summary == 'Nt').parentUid, isNull);
      await _end(t);
    });

    testWidgets('concurrent addProject creates one container', (t) async {
      final s = await _app(t, notes: [_f('x', 'Other')]);
      final r = await t.runAsync(
        () => Future.wait([s.addProject('P1'), s.addProject('P2')]),
      );
      expect(r!.every((u) => u != null), isTrue);
      expect(s.projectIndex.containers(), hasLength(1));
      expect(s.projectIndex.projects(), hasLength(2));
      await _end(t);
    });
  });

  group('phone', () {
    testWidgets('side menu has a Projects section listing projects', (t) async {
      final s = await _app(t, size: const Size(390, 800));
      await t.tap(_k('menu'));
      await t.pumpAndSettle();
      await t.tap(_k('rail-projects'));
      await t.pumpAndSettle();
      expect(s.section, Section.projects);
      expect(_k('project-a'), findsOneWidget);
      await t.tap(_k('project-a'));
      await t.pumpAndSettle();
      expect(s.scopeUid, 'a');
      await _end(t);
    });
  });
}
