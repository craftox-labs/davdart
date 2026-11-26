import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
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

String _tile(WidgetTester t, String id) =>
    t.widget<Text>(_k('overview-tile-$id-value')).data!;

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
    testWidgets('the tiles count the project, not the Space', (t) async {
      await _app(t);
      expect(_k('overview-page'), findsOneWidget);
      // Soon, Later and the overdue one are all open; the Space's own task
      // is not the project's.
      expect(_tile(t, 'open'), '3');
      expect(_tile(t, 'overdue'), '1');
      expect(_tile(t, 'notes'), '1');
      expect(_tile(t, 'events'), '1');
      await _end(t);
    });

    testWidgets('a task overdue is counted, a done one this week too', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        notes: _seed,
        tasks: [
          mkTask('overdue', summary: 'Late', days: -3, parent: 'p'),
          mkTask('done', summary: 'Finished', parent: 'p', status: 'COMPLETED'),
        ],
      );
      // A completion stamped today counts as done this week.
      s.tasks.firstWhere((k) => k.uid == 'done').completed = DateTime.now();
      await s.activateTab(null);
      s.openFolder('p');
      s.setSection(Section.overview);
      await t.pumpAndSettle();
      expect(_tile(t, 'overdue'), '1');
      expect(_tile(t, 'done'), '1');
      await _end(t);
    });

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
      expect(_tile(t, 'open'), '0');
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
      expect(_tile(t, 'open'), '1');
      expect(_tile(t, 'notes'), '1');
      expect(_tile(t, 'events'), '1');
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
      expect(_k('overview-tiles'), findsOneWidget);
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
