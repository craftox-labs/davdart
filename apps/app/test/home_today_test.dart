import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/event_rules.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/home_today.dart';
import 'package:davdart_app/ui/task_parts.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));
  test('dueLabel', () {
    final now = DateTime(2026, 11, 20, 10);
    String l(int d) {
      final x = DateTime(2026, 11, 20).add(Duration(days: d));
      return dueLabel(
        Task(uid: 'x', due: ICalDate.date(x.year, x.month, x.day)),
        now,
      );
    }

    expect(l(0), 'Today');
    expect(l(1), 'Tomorrow');
    expect(l(-1), 'Yesterday');
    expect(l(4), 'Tue 24');
    expect(l(-3), 'Tue 17');
    expect(l(20), 'Thu 10 Dec');
    expect(dueLabel(Task(uid: 'x'), now), '');
  });

  test('dueOfDay keeps time and zone, all-day stays a date', () {
    final day = DateTime.utc(2026, 12, 5);
    final tz = dueOfDay(
      day,
      const ICalDate('20261120T093000', ';TZID=Europe/Berlin'),
    );
    expect(tz.value, '20261205T093000');
    expect(tz.params, ';TZID=Europe/Berlin');
    expect(
      dueOfDay(day, const ICalDate('20261120T093000Z')).value,
      '20261205T093000Z',
    );
    expect(
      dueOfDay(day, ICalDate.date(2026, 11, 20)),
      ICalDate.date(2026, 12, 5),
    );
    expect(dueOfDay(day), ICalDate.date(2026, 12, 5));
  });

  test(
    'eventDate: new timed values are UTC, all-day a date, like keeps flavour',
    () {
      final w = DateTime.utc(2026, 12, 5, 9, 30);
      expect(eventDate(w).value, '20261205T023000Z'); // Bangkok -> UTC
      expect(eventDate(w, allDay: true), ICalDate.date(2026, 12, 5));
      final z = eventDate(w, like: const ICalDate('20261101T000000Z'));
      expect(z.value, '20261205T023000Z');
      final tz = eventDate(
        w,
        like: const ICalDate('20261101T090000', ';TZID=Europe/Berlin'),
      );
      expect(tz.value, '20261205T033000'); // 02:30Z is 03:30 in Berlin
      expect(tz.params, ';TZID=Europe/Berlin');
      final fl = eventDate(w, like: const ICalDate('20261101T090000'));
      expect(fl.value, '20261205T093000');
      expect(fl.params, '');
      // round trip: the local wall comes back
      expect(tz.localWall, w);
      expect(z.localWall, w);
    },
  );

  test('dueOfDay near midnight keeps the local time of day', () {
    // 20:00Z is 03:00 next day in Bangkok; picking the 10th keeps 03:00 local.
    final r = dueOfDay(
      DateTime.utc(2026, 12, 10),
      const ICalDate('20261201T200000Z'),
    );
    expect(r.value, '20261209T200000Z');
    expect(r.localDay, DateTime.utc(2026, 12, 10));
  });

  testWidgets('two cards, equal width and height, empty states', (t) async {
    await pumpTasksApp(t);
    expect(_k('home-today-doing'), findsNothing);
    expect(find.text('Nothing due today'), findsOneWidget);
    expect(find.text('No events today'), findsOneWidget);
    final a = t.getRect(_k('home-today-tasks'));
    final b = t.getRect(_k('home-today-events'));
    expect(a.width, closeTo(b.width, 0.5));
    expect(a.height, closeTo(b.height, 0.5));
    expect(a.top, b.top);
    expect(b.left, greaterThan(a.right));
    expect(_k('home-today-tasks-toggle'), findsNothing);
  });

  testWidgets('Tasks card: overdue then today only, overdue marked', (t) async {
    await pumpTasksApp(
      t,
      tasks: [
        mkTask('later', days: 9),
        mkTask('nodate'),
        mkTask('tomorrow', days: 1),
        mkTask('late', days: -2),
        mkTask('today', days: 0),
        mkTask('done', days: 0, status: 'COMPLETED'),
      ],
    );
    expect(_k('home-today-tasks-late'), findsOneWidget);
    expect(_k('home-today-tasks-today'), findsOneWidget);
    for (final n in ['later', 'nodate', 'tomorrow', 'done']) {
      expect(_k('home-today-tasks-$n'), findsNothing);
    }
    expect(
      t.getTopLeft(_k('home-today-tasks-late')).dy,
      lessThan(t.getTopLeft(_k('home-today-tasks-today')).dy),
    );
    expect(t.widget<Text>(_k('home-today-tasks-count')).data, '2');
    Color chipColor(String uid) => t
        .widget<Text>(
          find.descendant(of: _k('due-$uid'), matching: find.byType(Text)),
        )
        .style!
        .color!;
    expect(chipColor('late'), Tokens.light.error);
    expect(chipColor('today'), Tokens.light.muted);
    expect(find.text('Nothing due today'), findsNothing);
  });

  testWidgets('Tasks card caps at 6 rows with "and N more"', (t) async {
    final s = await pumpTasksApp(
      t,
      tasks: [for (var i = 0; i < 8; i++) mkTask('k$i', days: 0)],
    );
    expect(_k('home-today-tasks-more'), findsOneWidget);
    expect(find.text('and 2 more'), findsOneWidget);
    await t.tap(_k('home-today-tasks-more'));
    await t.pumpAndSettle();
    expect(s.section, Section.tasks);
  });

  testWidgets('checkbox completes a task and it leaves the card', (t) async {
    final s = await pumpTasksApp(t, tasks: [mkTask('a', days: 0)]);
    await t.tap(_k('task-check-a'));
    await t.pumpAndSettle();
    expect(s.taskById('a')!.isCompleted, isTrue);
    expect(_k('home-today-tasks-a'), findsNothing);
    expect(find.text('Nothing due today'), findsOneWidget);
  });

  testWidgets('tap opens a task per the setting; All tasks switches rail', (
    t,
  ) async {
    final s = await pumpTasksApp(t, tasks: [mkTask('k', days: 0)]);
    await t.tap(find.text('k').first);
    await t.pumpAndSettle();
    expect(s.peekUid, 'k');
    expect(_k('task-detail'), findsOneWidget);
    await t.tap(_k('home-today-tasks-all'));
    await t.pumpAndSettle();
    expect(s.section, Section.tasks);
  });

  testWidgets('+ adds a task due today', (t) async {
    final s = await pumpTasksApp(t);
    await t.tap(_k('home-today-tasks-add'));
    await t.pumpAndSettle();
    await t.enterText(_k('new-task-title'), 'Buy milk');
    await t.tap(_k('new-task-add'));
    await t.pumpAndSettle();
    expect(s.tasks.single.summary, 'Buy milk');
    expect(_k('home-today-tasks-${s.tasks.single.uid}'), findsOneWidget);
  });

  testWidgets('ignores panel filters and the folder scope', (t) async {
    final s = await pumpTasksApp(
      t,
      notes: [
        Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
      ],
      tasks: [
        mkTask('in', days: 0, parent: 'f', tags: ['a']),
        mkTask('out', days: 0, tags: ['b']),
      ],
      events: [
        mkEvent('e1', summary: 'Tagged', tags: ['x']),
        mkEvent('e2', summary: 'Plain', hour: 11),
      ],
    );
    s.setTaskTagFilter('a');
    s.setTaskFolderFilter('f');
    s.setEventTagFilter('x');
    s.openFolder('f');
    await t.pumpAndSettle();
    expect(_k('home-today-tasks-in'), findsOneWidget);
    expect(_k('home-today-tasks-out'), findsOneWidget);
    expect(_k('home-today-events-count'), findsOneWidget);
    expect(t.widget<Text>(_k('home-today-events-count')).data, '2');
  });

  testWidgets('rolls over at local midnight (fake clock)', (t) async {
    final s = await pumpTasksApp(
      t,
      tasks: [
        Task(uid: 'd21', summary: 'd21', due: ICalDate.date(2026, 11, 21)),
        Task(uid: 'd22', summary: 'd22', due: ICalDate.date(2026, 11, 22)),
      ],
    );
    var clock = DateTime(2026, 11, 20, 23, 59, 30);
    final tk = Tokens.light;
    await t.pumpWidget(
      FTheme(
        data: buildTheme(Brightness.light, touch: false, tokens: tk),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TokensScope(
            tokens: tk,
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => SingleChildScrollView(
                    child: HomeToday(state: s, now: () => clock),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Nothing due today'), findsOneWidget);
    await t.pump(const Duration(seconds: 20));
    expect(find.text('Nothing due today'), findsOneWidget);
    clock = DateTime(2026, 11, 21, 0, 0, 1);
    await t.pump(const Duration(seconds: 11));
    expect(_k('home-today-tasks-d21'), findsOneWidget);
    expect(_k('home-today-tasks-d22'), findsNothing);
    // Re-armed for the next midnight.
    clock = DateTime(2026, 11, 22, 0, 0, 1);
    await t.pump(const Duration(hours: 24));
    expect(_k('home-today-tasks-d22'), findsOneWidget);
    // Disposed: no timer left pending.
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Events card: today only, all-day first, then by time', (
    t,
  ) async {
    await pumpTasksApp(
      t,
      events: [
        mkEvent('late', summary: 'Late', hour: 18),
        mkEvent('early', summary: 'Early', hour: 8, location: 'Room 4'),
        mkEvent('holiday', summary: 'Holiday', allDay: true),
        mkEvent('off', summary: 'Called off', hour: 10, status: 'CANCELLED'),
        mkEvent('daily', summary: 'Daily', hour: 12, rrule: 'FREQ=DAILY'),
        mkEvent('tmrw', summary: 'Tomorrow thing', days: 1),
      ],
    );
    expect(_k('event-row-tmrw'), findsNothing);
    double y(String k) => t.getTopLeft(find.byKey(Key(k))).dy;
    expect(y('event-row-holiday'), lessThan(y('event-row-early')));
    expect(y('event-row-early'), lessThan(y('event-row-off')));
    expect(y('event-row-off'), lessThan(y('event-row-late')));
    expect(find.text('All day'), findsOneWidget);
    expect(_k('event-location-early'), findsOneWidget);
    expect(_k('event-repeat-daily'), findsOneWidget);
    expect(t.widget<Text>(_k('home-today-events-count')).data, '5');
    expect(find.text('No events today'), findsNothing);
  });

  testWidgets('event tap opens it; All events switches rail', (t) async {
    final s = await pumpTasksApp(t, events: [mkEvent('e', summary: 'Sync')]);
    await t.tap(find.text('Sync').first);
    await t.pumpAndSettle();
    expect(s.peekUid, 'e');
    await t.tap(_k('home-today-events-all'));
    await t.pumpAndSettle();
    expect(s.section, Section.events);
  });

  testWidgets('read-only Space: no add buttons, still listed', (t) async {
    await pumpTasksApp(
      t,
      tasks: [mkTask('a', days: 0)],
      events: [mkEvent('e')],
      readOnly: true,
    );
    expect(_k('home-today-tasks-add'), findsNothing);
    expect(_k('home-today-events-add'), findsNothing);
    expect(_k('home-today-tasks-a'), findsOneWidget);
    expect(t.widget<FCheckbox>(_k('task-check-a')).enabled, isFalse);
  });

  testWidgets('not shown on a saved-view tab', (t) async {
    final s = await pumpTasksApp(t);
    await t.runAsync(() => s.saveView('V'));
    s.applyView(s.savedViews.single);
    await t.pumpAndSettle();
    expect(s.activeTab, isNotNull);
    expect(_k('home-today'), findsNothing);
  });

  testWidgets('narrow width stacks the cards, same width', (t) async {
    await pumpTasksApp(t, size: const Size(400, 900));
    final a = t.getRect(_k('home-today-tasks'));
    final b = t.getRect(_k('home-today-events'));
    expect(b.top, greaterThanOrEqualTo(a.bottom));
    expect(a.width, closeTo(b.width, 0.5));
    expect(t.takeException(), isNull);
  });

  for (final w in [320.0, 880.0, 1280.0, 1911.0]) {
    testWidgets('no overflow at $w', (t) async {
      await pumpTasksApp(
        t,
        tasks: [
          mkTask('late', summary: 'A rather long overdue task title', days: -2),
          mkTask('today', days: 0, tags: ['home']),
        ],
        events: [
          mkEvent(
            'e',
            summary: 'A rather long event title indeed',
            location: 'Somewhere far away',
            rrule: 'FREQ=DAILY',
          ),
        ],
        size: Size(w, 900),
      );
      expect(_k('home-today'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('the Today header chevron collapses and expands it (desktop)', (
    t,
  ) async {
    await pumpTasksApp(t, size: const Size(1280, 900));
    expect(_k('home-today'), findsOneWidget);
    await t.tap(_k('today-section-toggle'));
    await t.pumpAndSettle();
    expect(_k('home-today'), findsNothing);
    await t.tap(_k('today-section-toggle'));
    await t.pumpAndSettle();
    expect(_k('home-today'), findsOneWidget);
  });

  testWidgets('homeStacked is kept while Today is collapsed; one state', (
    t,
  ) async {
    final s = await pumpTasksApp(t, size: const Size(400, 800));
    await t.tap(_k('today-section-toggle'));
    await t.pumpAndSettle();
    expect(_k('home-today'), findsNothing);
    expect(s.nav.homeStacked, isTrue);
    // The pref is written once, by the owner, and read back on a rebuild.
    expect(s.prefs?.read('davdart.home.today.collapsed.v1'), 'true');
    t.view.physicalSize = const Size(1280, 900);
    await t.pumpAndSettle();
    expect(s.nav.homeStacked, isFalse);
    expect(_k('home-today'), findsNothing);
    await t.tap(_k('today-section-toggle'));
    await t.pumpAndSettle();
    expect(_k('home-today'), findsOneWidget);
    expect(s.prefs?.read('davdart.home.today.collapsed.v1'), isNull);
  });
}
