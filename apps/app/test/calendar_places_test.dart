import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/event_rules.dart';
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
}
