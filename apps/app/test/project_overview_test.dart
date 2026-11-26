import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app_actions.dart';
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

/// A project [p] in the container [c] with tasks, notes and events: some in
/// the project, some outside it.
final _seed = [
  _folder('c', 'Projects', container: true),
  _folder('p', 'Alpha', parent: 'c'),
  Note(uid: 'n1', summary: 'Alpha note', parentUid: 'p'),
  Note(uid: 'out', summary: 'Loose note'),
];

Future<AppState> _app(
  WidgetTester t, {
  Size size = const Size(1280, 900),
}) async {
  final s = await pumpTasksApp(
    t,
    notes: _seed,
    size: size,
    tasks: [
      mkTask('open-soon', summary: 'Soon', days: 1, parent: 'p'),
      mkTask('open-late', summary: 'Later', days: 30, parent: 'p'),
      mkTask('overdue', summary: 'Late', days: -3, parent: 'p'),
      mkTask('done', summary: 'Finished', parent: 'p', status: 'COMPLETED'),
      mkTask('outside', summary: 'Other project task', days: 0),
    ],
    events: [mkEvent('ev', summary: 'Kickoff', days: 1, parent: 'p')],
  );
  await s.activateTab(null);
  s.openFolder('p');
  s.setSection(Section.overview);
  await t.pumpAndSettle();
  return s;
}

String _text(WidgetTester t, String key) => t.widget<Text>(_k(key)).data!;

Future<void> _end(WidgetTester t) => t.pump(const Duration(seconds: 1));

/// A loaded state over a memory Space holding [tasks] (no widgets).
Future<AppState> _stateWith(WidgetTester t, List<Task> tasks) async {
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final src = SpaceNoteSource(space);
  await t.runAsync(() async {
    for (final k in tasks) {
      await src.saveTask(k);
    }
  });
  final s = AppState(src);
  await t.runAsync(s.load);
  return s;
}

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));

  group('project overview', () {
    testWidgets('progress counts the project tasks, not the Space', (t) async {
      await _app(t);
      expect(_k('overview-page'), findsOneWidget);
      // Four project tasks (three open, one done); the Space's own task is
      // not the project's.
      expect(_text(t, 'proj-percent'), '25%');
      expect(_text(t, 'proj-done-line'), '1 of 4 tasks done');
      expect(
        find.descendant(
          of: _k('proj-overdue-badge'),
          matching: find.text('1 overdue'),
        ),
        findsOneWidget,
      );
      expect(_text(t, 'proj-count-todo'), 'To Do 3');
      expect(_text(t, 'proj-count-done'), 'Done 1');
      expect(_k('overview-tiles'), findsNothing);
      await _end(t);
    });

    testWidgets('the project page carries the marked placeholders', (t) async {
      await _app(t);
      for (final chip in [
        'proj-chip-star',
        'proj-chip-status',
        'proj-chip-members',
        'proj-chip-share',
        'proj-chip-settings',
      ]) {
        expect(_k(chip), findsOneWidget);
      }
      expect(_k('placeholder-project-about'), findsOneWidget);
      expect(_k('placeholder-project-milestones'), findsOneWidget);
      expect(_k('proj-placeholder-due'), findsOneWidget);
      // Status is the one derived detail row; the rest say Placeholder.
      expect(_text(t, 'proj-detail-status'), 'In progress');
      expect(_text(t, 'proj-detail-lead'), 'Placeholder');
      expect(_text(t, 'proj-detail-members'), 'Placeholder');
      await _end(t);
    });

    testWidgets('a restored project scope opens its page again', (t) async {
      final prefs = MemoryStorage()
        ..write('davdart.section.v1', 'overview')
        ..write('davdart.scope.v1', '{"default":"p"}');
      final s = await pumpTasksApp(
        t,
        notes: _seed,
        prefs: prefs,
        tasks: [mkTask('open-soon', summary: 'Soon', days: 1, parent: 'p')],
      );
      await s.activateTab(null);
      await t.pumpAndSettle();
      expect(s.scopeUid, 'p');
      expect(s.section, Section.overview);
      expect(_k('overview-page'), findsOneWidget);
    });

    testWidgets('a plain folder leaves the project page for a list', (t) async {
      final prefs = MemoryStorage();
      final s = await pumpTasksApp(
        t,
        prefs: prefs,
        notes: [
          _folder('c', 'Projects', container: true),
          _folder('p', 'Alpha', parent: 'c'),
          _folder('loose', 'Loose'),
        ],
      );
      await s.activateTab(null);
      s.openFolder('p');
      s.setSection(Section.overview);
      await t.pumpAndSettle();
      expect(_k('overview-page'), findsOneWidget);
      // A plain folder is no project: the page cannot stay open.
      s.openFolder('loose');
      await t.pumpAndSettle();
      expect(s.section, Section.notes);
      expect(_k('overview-page'), findsNothing);
      expect(prefs.read('davdart.section.v1'), 'notes');
      // Back on a project, then the Projects container: same rule.
      s.openFolder('p');
      s.setSection(Section.overview);
      await t.pumpAndSettle();
      s.openFolder('c');
      await t.pumpAndSettle();
      expect(s.section, Section.notes);
      expect(_k('overview-page'), findsNothing);
    });

    testWidgets('each project remembers its own tab', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          _folder('c', 'Projects', container: true),
          _folder('p', 'Alpha', parent: 'c'),
          _folder('q', 'Beta', parent: 'c'),
        ],
        tasks: [
          mkTask('t1', summary: 'One', parent: 'p'),
          mkTask('t2', summary: 'Two', parent: 'q'),
        ],
      );
      await s.activateTab(null);
      s.openFolder('p');
      s.setSection(Section.overview);
      await t.pumpAndSettle();
      await t.tap(_k('proj-tab-events'));
      await t.pumpAndSettle();
      expect(s.projectTab('p'), ProjectTab.calendar);
      // Another project opens on its own tab (Overview), not Alpha's.
      s.openFolder('q');
      await t.pumpAndSettle();
      expect(s.section, Section.overview);
      expect(s.projectTab('q'), ProjectTab.overview);
      expect(_k('overview-page'), findsOneWidget);
      await t.tap(_k('proj-tab-notes'));
      await t.pumpAndSettle();
      expect(s.projectTab('q'), ProjectTab.notes);
      // Back to Alpha: its Calendar tab is still its own.
      s.openFolder('p');
      await t.pumpAndSettle();
      expect(s.projectTab('p'), ProjectTab.calendar);
      expect(_k('proj-calendar-tab'), findsOneWidget);
    });

    testWidgets('the Overview palette entry applies only to real projects', (
      t,
    ) async {
      final s = await _app(t);
      bool enabled() =>
          buildActions(s).firstWhere((a) => a.id == 'go.overview').enabled(s);
      expect(enabled(), isTrue);
      s.openFolder(null);
      expect(enabled(), isFalse);
      s.openFolder('c'); // the Projects container, not a project
      expect(enabled(), isFalse);
      s.openFolder('p');
      expect(enabled(), isTrue);
    });

    testWidgets(
      'the switcher moves between Overview, Board, Notes and Calendar',
      (t) async {
        final s = await _app(t);
        expect(_k('overview-page'), findsOneWidget);
        await t.tap(_k('proj-tab-board'));
        await t.pumpAndSettle();
        expect(s.section, Section.overview);
        expect(_k('proj-board-tab'), findsOneWidget);
        expect(_k('overview-page'), findsNothing);
        expect(_k('board-drop-todo'), findsOneWidget);
        await t.tap(_k('proj-tab-notes'));
        await t.pumpAndSettle();
        expect(_k('proj-notes-tab'), findsOneWidget);
        expect(find.text('Alpha note'), findsWidgets);
        await t.tap(_k('proj-tab-events'));
        await t.pumpAndSettle();
        expect(_k('proj-calendar-tab'), findsOneWidget);
        expect(find.text('Kickoff'), findsWidgets);
        expect(s.projectTab('p'), ProjectTab.calendar);
        await t.tap(_k('proj-tab-overview'));
        await t.pumpAndSettle();
        expect(_k('overview-page'), findsOneWidget);
        expect(s.projectTab('p'), ProjectTab.overview);
        await _end(t);
      },
    );

    testWidgets('the Tasks and Recent blocks list the project items', (
      t,
    ) async {
      await _app(t);
      // Open tasks, soonest first: the overdue one leads.
      expect(_k('overview-task-overdue'), findsOneWidget);
      expect(
        t.getTopLeft(_k('overview-task-overdue')).dy,
        lessThan(t.getTopLeft(_k('overview-task-open-late')).dy),
      );
      expect(_k('overview-task-outside'), findsNothing);
      // Recent holds the project's note, tasks and event.
      expect(_k('overview-recent-n1'), findsOneWidget);
      expect(_k('overview-recent-out'), findsNothing);
      // Upcoming shows the dated tasks and the event.
      expect(
        find.descendant(
          of: _k('overview-upcoming'),
          matching: find.text('Kickoff'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _k('overview-upcoming'),
          matching: find.text('Soon'),
        ),
        findsOneWidget,
      );
      await _end(t);
    });

    testWidgets('tapping a task opens it', (t) async {
      final s = await _app(t);
      await t.tap(_k('overview-task-open-soon'));
      await t.pumpAndSettle();
      expect(s.peekUid, 'open-soon');
      await _end(t);
    });

    testWidgets('an empty project says so in every block', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          _folder('c', 'Projects', container: true),
          _folder('p', 'Alpha', parent: 'c'),
        ],
      );
      await s.activateTab(null);
      s.openFolder('p');
      s.setSection(Section.overview);
      await t.pumpAndSettle();
      expect(_text(t, 'proj-percent'), '0%');
      expect(_text(t, 'proj-done-line'), '0 of 0 tasks done');
      expect(_k('proj-overdue-badge'), findsNothing);
      expect(_text(t, 'proj-detail-status'), 'No tasks yet');
      expect(_k('overview-tasks-empty'), findsOneWidget);
      expect(_k('overview-upcoming-empty'), findsOneWidget);
      expect(_k('overview-recent-empty'), findsOneWidget);
      await _end(t);
    });

    testWidgets('a sub-folder of the project is part of it', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          _folder('c', 'Projects', container: true),
          _folder('p', 'Alpha', parent: 'c'),
          _folder('sub', 'Design', parent: 'p'),
          Note(uid: 'deep', summary: 'Deep note', parentUid: 'sub'),
        ],
        tasks: [
          mkTask('deep-task', summary: 'Deep task', days: 1, parent: 'sub'),
        ],
        events: [
          mkEvent('deep-event', summary: 'Deep event', days: 2, parent: 'sub'),
        ],
      );
      await s.activateTab(null);
      s.openFolder('p');
      s.setSection(Section.overview);
      await t.pumpAndSettle();
      expect(_text(t, 'proj-done-line'), '0 of 1 tasks done');
      expect(_k('overview-task-deep-task'), findsOneWidget);
      expect(_k('overview-recent-deep'), findsOneWidget);
      await _end(t);
    });

    testWidgets('the Calendar tag filter does not empty Upcoming', (t) async {
      final s = await _app(t);
      s.setEventTagFilter('not-this-one');
      await t.pumpAndSettle();
      // The Calendar panel filters its events; the Overview's own list does
      // not (its events are the project's, whatever the tag).
      expect(s.filteredEvents, isEmpty);
      expect(
        find.descendant(
          of: _k('overview-upcoming'),
          matching: find.text('Kickoff'),
        ),
        findsOneWidget,
      );
      await _end(t);
    });

    testWidgets('done this week starts on Monday and leaves cancelled out', (
      t,
    ) async {
      final now = DateTime(2026, 11, 26, 12); // a Thursday
      Task completed(String uid, DateTime at, {String status = 'COMPLETED'}) =>
          Task(uid: uid, summary: uid, status: status, completed: at);
      final s = await _stateWith(t, [
        completed('monday', DateTime(2026, 11, 23, 0, 30)),
        completed('sunday', DateTime(2026, 11, 22, 23, 30)),
        completed('cancelled', DateTime(2026, 11, 25, 9), status: 'CANCELLED'),
        completed('today', DateTime(2026, 11, 26, 10)),
      ]);
      final uids = s.doneThisWeek(now).map((k) => k.uid).toList()..sort();
      expect(uids, ['monday', 'today']);
      await _end(t);
    });

    testWidgets('320dp wide: no overflow', (t) async {
      await _app(t, size: const Size(320, 568));
      expect(_k('overview-page'), findsOneWidget);
      expect(_k('proj-progress'), findsOneWidget);
      // The switcher's four icon segments fit the phone with no overflow.
      for (final tab in ['board', 'notes', 'events', 'overview']) {
        await t.tap(_k('proj-tab-$tab'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: tab);
      }
      // Scroll the page to its end: every block lays out at that width.
      await t.drag(_k('overview-page'), const Offset(0, -600));
      await t.pumpAndSettle();
      final ex = t.takeException();
      expect(
        ex,
        isNull,
        reason: ex is FlutterError ? ex.toStringDeep() : '$ex',
      );
      await _end(t);
    });

    testWidgets('wide sets the blocks in two columns, a phone stacks them', (
      t,
    ) async {
      await _app(t, size: const Size(1280, 900));
      // Wide: Recent sits beside Tasks, not under it.
      expect(
        t.getTopLeft(_k('overview-recent')).dx,
        greaterThan(t.getTopLeft(_k('overview-tasks')).dx),
      );
      expect(
        t.getTopLeft(_k('overview-upcoming')).dy,
        greaterThan(t.getTopLeft(_k('overview-tasks')).dy),
      );
      await _end(t);
      await _app(t, size: const Size(390, 800));
      // Narrow: one column, in order.
      expect(
        t.getTopLeft(_k('overview-upcoming')).dy,
        greaterThan(t.getTopLeft(_k('overview-tasks')).dy),
      );
      expect(
        t.getTopLeft(_k('overview-recent')).dy,
        greaterThan(t.getTopLeft(_k('overview-upcoming')).dy),
      );
      await _end(t);
    });
  });
}
