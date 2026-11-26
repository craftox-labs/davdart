import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/key_nav.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_helper.dart';
import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _folder(
  String uid,
  String name, {
  String? parent,
  bool container = false,
  int daysAgo = 0,
}) => Note(
  uid: uid,
  summary: name,
  parentUid: parent,
  lastModified: DateTime.now().toUtc().subtract(Duration(days: daysAgo)),
  categories: [folderTag, if (container) projectsTag],
);

Note _note(String uid, String? parent, {String? summary, int daysAgo = 0}) =>
    Note(
      uid: uid,
      summary: summary ?? uid,
      parentUid: parent,
      lastModified: DateTime.now().toUtc().subtract(Duration(days: daysAgo)),
      dtstamp: DateTime.now().toUtc().subtract(Duration(days: daysAgo)),
      description: 'body',
    );

final _notes = [
  _folder('c', 'Projects', container: true),
  _folder('a', 'Alpha', parent: 'c'),
  _folder('b', 'Beta', parent: 'c', daysAgo: 3),
  _note('pn', 'a', daysAgo: 4), // project note: not personal
  _note('n1', null, daysAgo: 0), // loose note
];

final _tasks = [
  mkTask('lt', days: 1), // loose, open
  mkTask('late', days: -2), // loose, overdue
  mkTask('pt', parent: 'a'), // project: not personal
  Task(
    uid: 'done',
    summary: 'done',
    status: 'COMPLETED',
    completed: DateTime.now(),
    lastModified: DateTime.now().toUtc(),
  ),
];

final _events = [
  mkEvent('e1', days: 0), // loose
  mkEvent('pe1', parent: 'a'), // project: not personal
];

Future<AppState> _app(
  WidgetTester t, {
  Size size = const Size(1280, 900),
  List<Note>? notes,
  List<Task>? tasks,
  List<Event>? events,
}) async {
  final s = await pumpTasksApp(
    t,
    size: size,
    notes: notes ?? _notes,
    tasks: tasks ?? _tasks,
    events: events ?? _events,
  );
  await s.activateTab(null);
  await t.pumpAndSettle();
  return s;
}

String _value(WidgetTester t, String id) =>
    t.widget<Text>(_k('home-tile-$id-value')).data!;

Set<String> _uids(AppState s, String block) => {
  for (final e in s.nav.rowsOf(KeyNav.homeList))
    if (e.block == block) e.uid ?? e.id,
};

void main() {
  testWidgets('header, tiles and the Home page itself', (t) async {
    final s = await _app(t);
    expect(_k('home-page'), findsOneWidget);
    expect(t.widget<Text>(_k('home-title')).data, 'Home');
    expect(_k('home-new-task'), findsOneWidget);
    expect(_k('home-new-note'), findsOneWidget);
    expect(_k('home-new-project'), findsOneWidget);
    expect(_k('home-tiles'), findsOneWidget);
    // The whole Space, not the open project scope.
    s.openFolder('a');
    await t.pumpAndSettle();
    expect(_k('home-page'), findsOneWidget);
    expect(_value(t, 'projects'), '2');
    expect(_value(t, 'open'), '3'); // lt, late, pt
    expect(_value(t, 'overdue'), '1');
    expect(_value(t, 'done'), '1');
    expect(s.isMine(_tasks.first), isTrue);
  });

  testWidgets('projects card: most recently changed first, progress, open', (
    t,
  ) async {
    final s = await _app(t);
    expect(_k('home-projects'), findsOneWidget);
    final order = [
      for (final e in s.nav.rowsOf(KeyNav.homeList))
        if (e.block == 'projects') e.uid,
    ];
    expect(order, ['a', 'b']); // Alpha changed more recently than Beta
    expect(_k('home-project-a'), findsOneWidget);
    expect(_k('home-project-a-progress'), findsOneWidget);
    expect(
      t.widget<Text>(_k('home-project-a-counts')).data,
      '1 open', // pn is done? no: note without status is not counted
    );
    expect(_k('placeholder-project-fields'), findsOneWidget);
  });

  testWidgets('a project row opens its Overview, scope and section together', (
    t,
  ) async {
    final s = await _app(t);
    await t.ensureVisible(_k('home-project-a'));
    await t.tap(_k('home-project-a'));
    await t.pumpAndSettle();
    expect(s.scopeUid, 'a');
    expect(s.mainProjectUid, 'a');
    expect(_k('overview-page'), findsOneWidget);
  });

  testWidgets('personal tasks: loose items only, five rows, See all', (
    t,
  ) async {
    final s = await _app(t);
    expect(_k('home-personal-tasks'), findsOneWidget);
    expect(_uids(s, 'tasks'), {'late', 'lt'}); // overdue first, no project task
    expect(_k('home-task-late'), findsOneWidget);
    expect(_k('home-task-pt'), findsNothing);
    // See all keeps the open project scope (the Tasks panel's own scope).
    s.openFolder('a');
    await t.pumpAndSettle();
    await t.ensureVisible(_k('home-tasks-all'));
    await t.tap(_k('home-tasks-all'));
    await t.pumpAndSettle();
    expect(s.section, Section.tasks);
    expect(s.scopeUid, 'a');
  });

  testWidgets('personal calendar: loose events and dated loose tasks', (
    t,
  ) async {
    final s = await _app(t);
    expect(_k('home-personal-calendar'), findsOneWidget);
    expect(_uids(s, 'calendar'), {
      'e1',
      'lt',
    }); // no project event, no past task
    await t.ensureVisible(_k('home-calendar-all'));
    await t.tap(_k('home-calendar-all'));
    await t.pumpAndSettle();
    expect(s.section, Section.events);
    expect(s.scopeUid, isNull);
  });

  testWidgets('recently modified: loose notes and tasks only', (t) async {
    final s = await _app(t);
    expect(_k('home-recent'), findsOneWidget);
    final uids = _uids(s, 'recent');
    expect(uids, containsAll(['n1', 'lt']));
    expect(uids, isNot(contains('pn'))); // project note
    expect(uids, isNot(contains('pt'))); // project task
  });

  testWidgets('items under the Projects container or a project never leak', (
    t,
  ) async {
    final s = await _app(
      t,
      notes: [
        _folder('c', 'Projects', container: true),
        _folder('a', 'Alpha', parent: 'c'),
        _note('under', 'c'), // directly under the container
        _note('deep', 'a'), // inside the project
        _folder('loose', 'Loose'),
        _note('loose-note', 'loose'), // a plain folder is personal
      ],
      tasks: [
        mkTask('under-task', parent: 'c'),
        mkTask('deep-task', parent: 'a'),
        mkTask('loose-task', days: 1, parent: 'loose'),
      ],
      events: [
        mkEvent('under-event', parent: 'c'),
        mkEvent('deep-event', parent: 'a'),
        mkEvent('loose-event', parent: 'loose'),
      ],
    );
    final tasks = _uids(s, 'tasks');
    final calendar = _uids(s, 'calendar');
    final recent = _uids(s, 'recent');
    expect(tasks, {'loose-task'});
    expect(calendar, {'loose-task', 'loose-event'});
    expect(recent, containsAll(['loose-note', 'loose-task']));
    for (final leak in [
      'under',
      'deep',
      'under-task',
      'deep-task',
      'under-event',
      'deep-event',
    ]) {
      expect(find.byKey(Key('home-recent-$leak')), findsNothing);
    }
  });

  testWidgets('switching Space on Home keeps Home', (t) async {
    final storage = MemoryStorage();
    final c = catalogWithPlanning(
      storage,
      planningSeed: SeedNotes([Note(uid: 'n1', summary: 'Planning note')]),
    );
    final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
    await t.pumpWidget(DavdartApp(state: s));
    await t.pumpAndSettle();
    expect(_k('home-page'), findsOneWidget);
    await s.createSpace('Other');
    final other = s.currentSpaceId!;
    await s.switchSpace('planning');
    // The Spaces panel keeps a list section; Home must stay Home.
    s.setSection(Section.overview); // not supported here: resolves to Notes
    s.showHome();
    await s.switchSpace(other);
    s.keepListSection();
    await t.pumpAndSettle();
    expect(_k('home-page'), findsOneWidget);
    // A panel section that cannot land in the new Space is rewritten without
    // leaving Home (the Overview case).
    s.section = Section.overview;
    s.keepListSection();
    await t.pumpAndSettle();
    expect(s.section, Section.notes);
    expect(_k('home-page'), findsOneWidget);
  });

  testWidgets('previews stop at five rows', (t) async {
    final many = [for (var i = 0; i < 8; i++) mkTask('t$i', days: i)];
    final s = await _app(t, tasks: many);
    expect(_uids(s, 'tasks').length, 5);
    expect(_uids(s, 'calendar').length, 5);
    expect(s.section, Section.notes);
  });

  testWidgets('the Inbox is a marked placeholder', (t) async {
    await _app(t);
    expect(_k('placeholder-inbox'), findsOneWidget);
    expect(_k('placeholder-inbox-label'), findsOneWidget);
    expect(
      find.textContaining('Unfiled captures you assign onwards'),
      findsOneWidget,
    );
  });

  testWidgets('an empty Space hides Projects and shows empty lists', (t) async {
    final s = await _app(t, notes: [], tasks: [], events: []);
    expect(_k('home-projects'), findsNothing);
    expect(_k('home-tasks-empty'), findsOneWidget);
    expect(_k('home-calendar-empty'), findsOneWidget);
    expect(_k('home-recent-empty'), findsOneWidget);
    expect(_value(t, 'projects'), '0');
    expect(_value(t, 'open'), '0');
    expect(s.nav.rowsOf(KeyNav.homeList), isEmpty);
  });

  testWidgets('the Home action returns to the dashboard from an Overview', (
    t,
  ) async {
    final s = await _app(t);
    await t.tap(_k('home-project-a'));
    await t.pumpAndSettle();
    expect(s.mainProjectUid, 'a');
    await t.tap(_k('rail-home'));
    await t.pumpAndSettle();
    expect(_k('home-page'), findsOneWidget);
    expect(s.activeTab, isNull);
    expect(s.scopeUid, isNull, reason: 'Home is personal');
  });

  testWidgets('Home has no Day | Board switch and no Columns toggle', (
    t,
  ) async {
    await _app(t);
    expect(_k('home-strip'), findsNothing);
    expect(_k('home-focus-day'), findsNothing);
    expect(_k('home-cols'), findsNothing);
  });

  testWidgets('phone: one column, nothing overflows', (t) async {
    await _app(t, size: const Size(360, 800));
    expect(_k('home-page'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.ensureVisible(_k('home-recent'));
    expect(t.takeException(), isNull);
  });
}
