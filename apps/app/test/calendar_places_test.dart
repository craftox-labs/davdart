import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/event_rules.dart';
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
}) => Note(
  uid: uid,
  summary: name,
  parentUid: parent,
  categories: [folderTag, if (container) projectsTag],
);

final _notes = [
  _folder('c', 'Projects', container: true),
  _folder('p', 'Alpha', parent: 'c'),
];

/// A loose event and task, and the project's own: Home must show only the
/// loose ones, the project's tab only the project's.
Future<AppState> _app(WidgetTester t) => pumpTasksApp(
  t,
  notes: _notes,
  events: [
    mkEvent('le', summary: 'Loose ev', days: 0),
    mkEvent('pe', summary: 'Project ev', days: 0, parent: 'p'),
  ],
  tasks: [
    mkTask('lt', summary: 'Loose task', days: 0),
    mkTask('pt', summary: 'Project task', days: 0, parent: 'p'),
  ],
);

/// The day one away from today, in the same month (there is one on the 1st).
DateTime _otherDay() {
  final n = DateTime.now();
  final d = n.day == 1
      ? n.add(const Duration(days: 1))
      : n.add(const Duration(days: -1));
  return DateTime.utc(d.year, d.month, d.day);
}

String _dayKey(DateTime d) => 'calendar-day-${d.year}-${d.month}-${d.day}';

/// Two Spaces: the legacy Planning one (local) and a fresh one.
Future<(AppState, String, MemoryStorage)> _spaces(WidgetTester t) async {
  t.view.physicalSize = const Size(1280, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final storage = MemoryStorage();
  final c = catalogWithPlanning(storage, planningSeed: SeedNotes([]));
  final other = c.add('Other').id;
  final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return (s, other, storage);
}

/// A state whose "is this mine" answer can hide items: the seam Home's
/// Calendar reads for its loose items.
class _MineState extends AppState {
  _MineState(super.source, {super.prefs, required this.hidden});
  final Set<String> hidden;

  @override
  bool isMine(Object item) => switch (item) {
    Event e => !hidden.contains(e.uid),
    Task k => !hidden.contains(k.uid),
    _ => true,
  };
}

Future<AppState> _mineApp(
  WidgetTester t,
  Set<String> hidden, {
  List<Event> events = const [],
  List<Task> tasks = const [],
}) async {
  t.view.physicalSize = const Size(1280, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final src = SpaceNoteSource(space, seed: SeedNotes([]));
  await t.runAsync(() async {
    for (final e in events) {
      await src.saveEvent(e);
    }
    for (final k in tasks) {
      await src.saveTask(k);
    }
  });
  final s = _MineState(src, prefs: MemoryStorage(), hidden: hidden);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));

  testWidgets('Home has the Overview | Calendar switcher, Overview first', (
    t,
  ) async {
    final s = await _app(t);
    expect(s.homeView, HomeView.overview);
    expect(_k('home-tabs'), findsOneWidget);
    expect(_k('home-page'), findsOneWidget);
    await t.tap(_k('home-tab-calendar'));
    await t.pumpAndSettle();
    expect(s.homeView, HomeView.calendar);
    expect(_k('calendar-view'), findsOneWidget);
    expect(_k('home-page'), findsNothing);
    await t.tap(_k('home-tab-overview'));
    await t.pumpAndSettle();
    expect(_k('home-page'), findsOneWidget);
    expect(_k('calendar-view'), findsNothing);
  });

  testWidgets('Home Calendar shows loose items only, never a project item', (
    t,
  ) async {
    final s = await _app(t);
    s.setHomeView(HomeView.calendar);
    await t.pumpAndSettle();
    expect(find.text('Loose ev'), findsWidgets);
    expect(find.text('Project ev'), findsNothing);
    // The loose dated task is on today; the project one is not.
    final day = wallDay(wallNow(DateTime.now()));
    await t.tap(_k(_dayKey(day)));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: _k('calendar-day-card'),
        matching: find.text('Loose task'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _k('calendar-day-card'),
        matching: find.text('Project task'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'a project item stays off Home even with the project scope open',
    (t) async {
      final s = await _app(t);
      s.openFolder('p');
      await t.pumpAndSettle();
      s.setHomeView(HomeView.calendar);
      await t.pumpAndSettle();
      expect(_k('calendar-view'), findsOneWidget);
      expect(find.text('Project ev'), findsNothing);
      expect(find.text('Loose ev'), findsWidgets);
    },
  );

  testWidgets(
    'a project Calendar shows that project items only, and adds to it',
    (t) async {
      final s = await _app(t);
      s.openProjectTab('p');
      s.setProjectTab('p', ProjectTab.calendar);
      await t.pumpAndSettle();
      expect(_k('proj-calendar-tab'), findsOneWidget);
      expect(find.text('Project ev'), findsWidgets);
      expect(find.text('Loose ev'), findsNothing);
      final day = _otherDay();
      await t.tap(_k(_dayKey(day)));
      await t.pumpAndSettle();
      await t.tap(_k('calendar-add-event'));
      await t.pumpAndSettle();
      await t.enterText(_k('new-event-title'), 'Site visit');
      await t.pump();
      await t.tap(_k('new-event-add'));
      await t.pumpAndSettle();
      final made = s.events.firstWhere((e) => e.summary == 'Site visit');
      expect(made.dtstart!.localDay, day);
      // Added in the project, not Personal.
      expect(made.parentUid, 'p');
      await t.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('the add buttons pre-fill the selected day (event and task)', (
    t,
  ) async {
    final s = await _app(t);
    s.setHomeView(HomeView.calendar);
    await t.pumpAndSettle();
    final day = _otherDay();
    await t.tap(_k(_dayKey(day)));
    await t.pumpAndSettle();
    await t.tap(_k('calendar-add-event'));
    await t.pumpAndSettle();
    await t.enterText(_k('new-event-title'), 'Coffee');
    await t.pump();
    await t.tap(_k('new-event-add'));
    await t.pumpAndSettle();
    final event = s.events.firstWhere((e) => e.summary == 'Coffee');
    expect(event.dtstart!.localDay, day);
    // A new event on Home goes to Personal, not to the open project.
    expect(event.parentUid, isNot('p'));

    await t.tap(_k('calendar-add-task'));
    await t.pumpAndSettle();
    await t.enterText(_k('new-task-title'), 'Water plants');
    await t.pump();
    await t.tap(_k('new-task-add'));
    await t.pumpAndSettle();
    final task = s.tasks.firstWhere((k) => k.summary == 'Water plants');
    expect(task.due!.localDay, day);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('Home view is remembered per Space; a switch starts on today', (
    t,
  ) async {
    final (s, other, storage) = await _spaces(t);
    final first = s.currentSpaceId!;
    expect(s.homeView, HomeView.overview);
    s.setHomeView(HomeView.calendar);
    await t.pumpAndSettle();
    final day = _otherDay();
    await t.tap(_k(_dayKey(day)));
    await t.pumpAndSettle();
    expect(storage.read('davdart.home.view.v1.$first'), 'calendar');
    // The other Space has its own pref: Overview, and none written for it.
    await t.runAsync(() => s.switchSpace(other));
    await t.pumpAndSettle();
    expect(s.homeView, HomeView.overview);
    expect(_k('home-page'), findsOneWidget);
    expect(storage.read('davdart.home.view.v1.$other'), isNull);
    // Back: Calendar again, but the view was rebuilt for the Space, so the
    // selected day is today rather than the day picked before the switch.
    await t.runAsync(() => s.switchSpace(first));
    await t.pumpAndSettle();
    expect(s.homeView, HomeView.calendar);
    expect(_k('calendar-view'), findsOneWidget);
    final today = wallDay(wallNow(DateTime.now()));
    expect(find.text(dayLabel(today)), findsOneWidget);
    expect(find.text(dayLabel(day)), findsNothing);
  });

  testWidgets('Home Calendar reads the isMine seam for its loose items', (
    t,
  ) async {
    final s = await _mineApp(
      t,
      {'hidden', 'htask'},
      events: [
        mkEvent('hidden', summary: 'Not mine', days: 0),
        mkEvent('shown', summary: 'Mine', days: 0),
      ],
      tasks: [mkTask('htask', summary: 'Not my task', days: 0)],
    );
    s.setHomeView(HomeView.calendar);
    await t.pumpAndSettle();
    expect(find.text('Mine'), findsWidgets);
    expect(find.text('Not mine'), findsNothing);
    final today = wallDay(wallNow(DateTime.now()));
    await t.tap(_k(_dayKey(today)));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: _k('calendar-day-card'), matching: find.text('Mine')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _k('calendar-day-card'),
        matching: find.text('Not my task'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'a project Calendar takes its subfolders, never another project',
    (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          _folder('c', 'Projects', container: true),
          _folder('p', 'Alpha', parent: 'c'),
          _folder('ps', 'Work', parent: 'p'),
          _folder('q', 'Beta', parent: 'c'),
        ],
        events: [
          mkEvent('p1', summary: 'Alpha ev', days: 0, parent: 'p'),
          mkEvent('p2', summary: 'Alpha sub ev', days: 0, parent: 'ps'),
          mkEvent('q1', summary: 'Beta ev', days: 0, parent: 'q'),
        ],
        tasks: [mkTask('p3', summary: 'Alpha sub task', days: 0, parent: 'ps')],
      );
      s.openProjectTab('p');
      s.setProjectTab('p', ProjectTab.calendar);
      await t.pumpAndSettle();
      expect(find.text('Alpha ev'), findsWidgets);
      expect(find.text('Alpha sub ev'), findsWidgets);
      expect(find.text('Beta ev'), findsNothing);
      final today = wallDay(wallNow(DateTime.now()));
      await t.tap(_k(_dayKey(today)));
      await t.pumpAndSettle();
      final card = _k('calendar-day-card');
      expect(
        find.descendant(of: card, matching: find.text('Alpha ev')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Alpha sub task')),
        findsOneWidget,
      );
      // The other project's Calendar is its own scope and its own state.
      s.openProjectTab('q');
      s.setProjectTab('q', ProjectTab.calendar);
      await t.pumpAndSettle();
      expect(find.text('Beta ev'), findsWidgets);
      expect(find.text('Alpha ev'), findsNothing);
      await t.pump(const Duration(seconds: 1));
    },
  );
}
