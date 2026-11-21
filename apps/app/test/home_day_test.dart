import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/board_view.dart';
import 'package:davdart_app/ui/home_day.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

String _dayKey(DateTime d) => 'cal-day-${d.year}-${d.month}-${d.day}';

DateTime _tomorrow() {
  final n = DateTime.now().add(const Duration(days: 1));
  return DateTime.utc(n.year, n.month, n.day);
}

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));

  testWidgets('Day | Board switch; Day is the default', (t) async {
    await pumpTasksApp(
      t,
      tasks: [mkTask('a', days: 0, status: 'NEEDS-ACTION')],
    );
    expect(_k('home-focus'), findsOneWidget);
    expect(_k('home-calendar'), findsOneWidget);
    expect(find.byType(BoardView), findsNothing);
    await t.tap(_k('home-focus-board'));
    await t.pumpAndSettle();
    expect(find.byType(BoardView), findsOneWidget);
    expect(_k('home-calendar'), findsNothing);
    expect(_k('home-today'), findsNothing);
    await t.tap(_k('home-focus-day'));
    await t.pumpAndSettle();
    expect(_k('home-calendar'), findsOneWidget);
  });

  testWidgets('focus is remembered per Space', (t) async {
    final prefs = MemoryStorage();
    final s = await pumpTasksApp(t, prefs: prefs);
    await t.tap(_k('home-focus-board'));
    await t.pumpAndSettle();
    expect(s.homeFocus, HomeFocus.board);
    expect(
      prefs.read('davdart.home.focus.v1.default') ??
          prefs.read('davdart.home.focus.v1.s'),
      'board',
    );
    // A fresh app on the same prefs and Space comes back on the board.
    await t.pumpWidget(const SizedBox());
    final again = await pumpTasksApp(t, prefs: prefs);
    expect(again.homeFocus, HomeFocus.board);
    expect(find.byType(BoardView), findsOneWidget);
    // Back to Day clears it.
    await t.tap(_k('home-focus-day'));
    await t.pumpAndSettle();
    expect(again.homeFocus, HomeFocus.day);
    expect(prefs.read('davdart.home.focus.v1.default'), isNull);
  });

  testWidgets('picking a day updates the list; overdue only on today', (
    t,
  ) async {
    final tom = _tomorrow();
    final s = await pumpTasksApp(
      t,
      tasks: [
        mkTask('over', days: -3),
        mkTask('now', days: 0),
        mkTask('next', days: 1),
      ],
      events: [mkEvent('ev', summary: 'Tomorrow talk', days: 1)],
    );
    expect(_k('home-today-tasks-over'), findsOneWidget);
    expect(_k('home-today-tasks-now'), findsOneWidget);
    expect(_k('home-today-tasks-next'), findsNothing);
    expect(_k('home-day-reset'), findsNothing);
    await t.tap(_k(_dayKey(tom)));
    await t.pumpAndSettle();
    expect(s.homeDay, tom);
    expect(_k('home-today-tasks-next'), findsOneWidget);
    expect(_k('home-today-tasks-over'), findsNothing);
    expect(_k('home-today-tasks-now'), findsNothing);
    expect(find.text('Tomorrow talk'), findsOneWidget);
    expect(_k('home-day-reset'), findsOneWidget);
    await t.tap(_k('home-day-reset'));
    await t.pumpAndSettle();
    expect(s.homeDay, isNull);
    expect(_k('home-today-tasks-over'), findsOneWidget);
    expect(_k('home-day-reset'), findsNothing);
  });

  testWidgets('dots: events and tasks have their own tone', (t) async {
    await pumpTasksApp(
      t,
      tasks: [mkTask('a', days: 0)],
      events: [mkEvent('e', days: 0)],
    );
    final d = DateTime.now().day;
    expect(_k('cal-dot-event-$d'), findsOneWidget);
    expect(_k('cal-dot-task-$d'), findsOneWidget);
  });

  testWidgets('phone: calendar collapsed to one line, state persisted', (
    t,
  ) async {
    final prefs = MemoryStorage();
    final s = await pumpTasksApp(
      t,
      size: const Size(400, 800),
      prefs: prefs,
      tasks: [mkTask('a', days: 0), mkTask('b', days: 1)],
    );
    expect(_k('home-cal-label'), findsOneWidget);
    expect(_k('home-calendar'), findsNothing);
    expect(
      t.widget<Text>(_k('home-cal-label')).data,
      matches(RegExp(r'^[A-Z][a-z]{2} \d')),
    );
    // day-step arrows move the selection
    await t.tap(_k('home-cal-next-day'));
    await t.pumpAndSettle();
    expect(s.homeDay, _tomorrow());
    expect(_k('home-today-tasks-b'), findsOneWidget);
    await t.tap(_k('home-cal-prev-day'));
    await t.pumpAndSettle();
    // expand
    await t.tap(_k('home-cal-toggle'));
    await t.pumpAndSettle();
    expect(_k('home-calendar'), findsOneWidget);
    expect(s.homeCalOpen, isTrue);
    expect(
      prefs.read('davdart.home.cal.open.v1.default') ??
          prefs.read('davdart.home.cal.open.v1.s'),
      'true',
    );
    // tap target sizes
    expect(
      t.getSize(_k(_dayKey(_tomorrow()))).height,
      greaterThanOrEqualTo(44),
    );
    await t.tap(_k('home-cal-toggle'));
    await t.pumpAndSettle();
    expect(_k('home-calendar'), findsNothing);
    expect(s.homeCalOpen, isFalse);
  });

  testWidgets('wide: calendar left of the list', (t) async {
    await pumpTasksApp(t, size: const Size(1280, 900));
    final cal = t.getTopLeft(_k('home-calendar'));
    final list = t.getTopLeft(_k('home-today'));
    expect(cal.dx, lessThan(list.dx));
  });

  testWidgets('far zone: an evening UTC event lands on the viewer day', (
    t,
  ) async {
    LocalZone.use('Pacific/Auckland'); // UTC+13 in November
    final s = await pumpTasksApp(
      t,
      events: [
        Event(
          uid: 'z',
          summary: 'Late UTC',
          dtstart: const ICalDate('20261120T200000Z'), // 21 Nov 09:00 Auckland
          dtend: const ICalDate('20261120T210000Z'),
        ),
      ],
    );
    final clock = DateTime.utc(2026, 11, 20, 20, 30); // 21 Nov 09:30 there
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
                  builder: (_) => SizedBox(
                    width: 900,
                    height: 800,
                    child: HomeDayFocus(state: s, now: () => clock),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Late UTC'), findsOneWidget); // today in Auckland
    s.selectHomeDay(DateTime.utc(2026, 11, 20));
    await t.pumpAndSettle();
    expect(find.text('Late UTC'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('resume resets only a stale selection, quietly otherwise', (
    t,
  ) async {
    final s = await pumpTasksApp(t);
    var n = 0;
    s.addListener(() => n++);
    s.resetHomeDayIfStale(); // nothing selected
    expect(n, 0);
    s.selectHomeDay(_tomorrow());
    expect(n, 1);
    s.resetHomeDayIfStale(); // chosen today: kept
    expect(s.homeDay, _tomorrow());
    expect(n, 1);
    s.resetHomeDayIfStale(DateTime.now().add(const Duration(days: 1)));
    expect(s.homeDay, isNull);
    expect(n, 2);
    s.resetHomeDay(); // already null: no notification
    expect(n, 2);
  });

  testWidgets('phone: day cells are 44dp wide at 320', (t) async {
    await pumpTasksApp(t, size: const Size(320, 568));
    await t.tap(_k('home-cal-toggle'));
    await t.pumpAndSettle();
    final r = t.getRect(_k(_dayKey(_tomorrow())));
    expect(r.width, greaterThanOrEqualTo(44));
    expect(r.height, greaterThanOrEqualTo(44));
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'wide and short: the calendar sits in a scroll view, no overflow',
    (t) async {
      await pumpTasksApp(t, size: const Size(1280, 350));
      expect(_k('home-calendar-scroll'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('a repeating overdue task also shows its occurrence today', (
    t,
  ) async {
    await pumpTasksApp(
      t,
      tasks: [
        mkTask('rep', days: -3, rrule: 'FREQ=DAILY'),
        mkTask('once', days: -3),
      ],
    );
    expect(_k('home-today-tasks-rep'), findsOneWidget); // overdue row
    expect(_k('home-today-tasks-rep-occ'), findsOneWidget); // today's one
    expect(_k('home-today-tasks-once'), findsOneWidget);
    expect(_k('home-today-tasks-once-occ'), findsNothing);
  });
}
