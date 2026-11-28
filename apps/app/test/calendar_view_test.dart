import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/calendar_view.dart';
import 'package:davdart_app/ui/chips.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Finder _k(String k) => find.byKey(Key(k));

/// The grid's weekday header, in order (Monday-first unless the locale says
/// otherwise).
List<String> _header(WidgetTester t) {
  const labels = {'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'};
  return [
    for (final w in t.widgetList<Text>(find.byType(Text)))
      if (labels.contains(w.data)) w.data!,
  ].take(7).toList();
}

/// A fixed clock: mid-November 2026 (the 1st is a Sunday, 30 days).
final _now = DateTime.utc(2026, 11, 18, 10);

const _container = 'c';
const _project = 'p';

final _tree = [
  Note(
    uid: _container,
    summary: 'Projects',
    categories: [folderTag, projectsTag],
  ),
  Note(uid: _project, summary: 'Alpha', parentUid: _container),
];

class _Seed implements NoteSource {
  _Seed(this.notes);
  final List<Note> notes;
  @override
  Future<List<Note>> load() async => notes;
}

Future<AppState> _state(
  WidgetTester t, {
  List<Note> notes = const [],
  List<Task> tasks = const [],
  List<Event> events = const [],
}) async {
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final src = SpaceNoteSource(space, seed: _Seed([..._tree, ...notes]));
  await t.runAsync(() async {
    for (final k in tasks) {
      await src.saveTask(k);
    }
    for (final e in events) {
      await src.saveEvent(e);
    }
  });
  final s = AppState(src, prefs: MemoryStorage());
  await t.runAsync(s.load);
  return s;
}

/// One all-day event on [day] of November 2026.
Event _event(String uid, String summary, int day, {String? parent}) => Event(
  uid: uid,
  parentUid: parent,
  summary: summary,
  dtstart: ICalDate.date(2026, 11, day),
  dtend: ICalDate.date(2026, 11, day + 1),
);

Task _task(String uid, String summary, int day, {String? parent}) => Task(
  uid: uid,
  parentUid: parent,
  summary: summary,
  due: ICalDate.date(2026, 11, day),
);

Future<void> _pump(
  WidgetTester t,
  AppState s, {
  Size size = const Size(1280, 900),
  bool scoped = false,
  Locale locale = const Locale('en', 'GB'),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    FTheme(
      data: buildTheme(Brightness.light, touch: false, tokens: Tokens.light),
      child: TokensScope(
        tokens: Tokens.light,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: Localizations(
            locale: locale,
            delegates: const [DefaultWidgetsLocalizations.delegate],
            child: Directionality(
              textDirection: TextDirection.ltr,
              // Rows drag, so they need an Overlay ancestor.
              child: Navigator(
                onGenerateRoute: (_) => PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) =>
                      CalendarView(state: s, scoped: scoped, now: _now),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));

  testWidgets('grid math: Monday-first weeks from the locale', (t) async {
    final s = await _state(t);
    await _pump(t, s);
    expect(t.widget<Text>(_k('calendar-month')).data, 'November 2026');
    // Nov 1 2026 is a Sunday: the grid starts on Monday 26 October and runs
    // six weeks to Sunday 6 December.
    expect(_k('calendar-day-2026-10-26'), findsOneWidget);
    expect(_k('calendar-day-2026-10-25'), findsNothing);
    expect(_k('calendar-day-2026-12-6'), findsOneWidget);
    expect(_k('calendar-day-2026-12-7'), findsNothing);
    expect(_header(t), ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']);
  });

  testWidgets('grid math: a Sunday-first region starts on 1 November', (
    t,
  ) async {
    final s = await _state(t);
    await _pump(t, s, locale: const Locale('en', 'US'));
    expect(_k('calendar-day-2026-11-1'), findsOneWidget);
    expect(_k('calendar-day-2026-10-31'), findsNothing);
    expect(_k('calendar-day-2026-12-5'), findsOneWidget);
    expect(_k('calendar-day-2026-12-6'), findsNothing);
    expect(_header(t), ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']);
  });

  testWidgets('month arrows move the month; Today comes back', (t) async {
    final s = await _state(t);
    await _pump(t, s);
    await t.tap(_k('calendar-next'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('calendar-month')).data, 'December 2026');
    expect(_k('calendar-day-2026-12-1'), findsOneWidget);
    await t.tap(_k('calendar-prev'));
    await t.pumpAndSettle();
    await t.tap(_k('calendar-prev'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('calendar-month')).data, 'October 2026');
    await t.tap(_k('calendar-today'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('calendar-month')).data, 'November 2026');
  });

  testWidgets('a month arrow moves the selection into the shown month', (
    t,
  ) async {
    final s = await _state(
      t,
      events: [
        Event(
          uid: 'ny',
          summary: 'New year',
          dtstart: ICalDate.date(2027, 1, 1),
          dtend: ICalDate.date(2027, 1, 2),
        ),
      ],
    );
    await _pump(t, s);
    expect(find.text('Wed 18 Nov'), findsOneWidget);
    // December: the selection follows to the 1st, and the grid is a year
    // rollover away from January.
    await t.tap(_k('calendar-next'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('calendar-month')).data, 'December 2026');
    expect(find.text('Tue 1 Dec'), findsOneWidget);
    expect(_k('calendar-empty'), findsOneWidget);
    // December to January rolls the year over; that day's items show.
    await t.tap(_k('calendar-next'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('calendar-month')).data, 'January 2027');
    expect(find.text('Fri 1 Jan 2027'), findsOneWidget);
    expect(
      find.descendant(
        of: _k('calendar-day-card'),
        matching: find.text('New year'),
      ),
      findsOneWidget,
    );
    // Back to the current month: the selection returns to today.
    await t.tap(_k('calendar-today'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('calendar-month')).data, 'November 2026');
    expect(find.text('Wed 18 Nov'), findsOneWidget);
  });

  testWidgets('selecting a day lists its items; an empty day says so', (
    t,
  ) async {
    final s = await _state(
      t,
      events: [_event('e20', 'Review', 20)],
      tasks: [_task('k20', 'Pay rent', 20)],
    );
    await _pump(t, s);
    // Today by default, and nothing on it.
    expect(find.text('Wed 18 Nov'), findsOneWidget);
    expect(_k('calendar-empty'), findsOneWidget);
    expect(
      find.descendant(
        of: _k('calendar-day-card'),
        matching: find.text('Review'),
      ),
      findsNothing,
    );
    await t.tap(_k('calendar-day-2026-11-20'));
    await t.pumpAndSettle();
    expect(find.text('Fri 20 Nov'), findsOneWidget);
    expect(_k('calendar-empty'), findsNothing);
    final card = find.ancestor(
      of: find.text('Review'),
      matching: _k('calendar-day-card'),
    );
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: _k('calendar-day-card'),
        matching: find.text('Pay rent'),
      ),
      findsOneWidget,
    );
    // Back to an empty day.
    await t.tap(_k('calendar-day-2026-11-21'));
    await t.pumpAndSettle();
    expect(_k('calendar-empty'), findsOneWidget);
  });

  testWidgets('wide cells show chips, three at most, then "+N more"', (
    t,
  ) async {
    final s = await _state(
      t,
      events: [
        _event('e1', 'Alpha ev', 20),
        _event('e2', 'Beta ev', 20),
        _event('e3', 'Gamma ev', 20),
      ],
      tasks: [_task('t1', 'Delta task', 20)],
    );
    await _pump(t, s);
    expect(_k('calendar-chip-2026-11-20-0'), findsOneWidget);
    expect(_k('calendar-chip-2026-11-20-1'), findsOneWidget);
    expect(_k('calendar-chip-2026-11-20-2'), findsOneWidget);
    expect(_k('calendar-chip-2026-11-20-3'), findsNothing);
    expect(t.widget<Text>(_k('calendar-more-2026-11-20')).data, '+1 more');
    // No dots on the wide grid.
    expect(_k('calendar-dot-event-2026-11-20'), findsNothing);
  });

  testWidgets('chips lead with all-day items, then times; a task dot rings', (
    t,
  ) async {
    // Bangkok is UTC+7: 02:00Z is 09:00 and 09:00Z is 16:00.
    final s = await _state(
      t,
      events: [
        _event('e1', 'All day ev', 20),
        Event(
          uid: 'e2',
          summary: 'Early ev',
          dtstart: const ICalDate('20261120T020000Z'),
          dtend: const ICalDate('20261120T030000Z'),
        ),
        Event(
          uid: 'e3',
          summary: 'Late ev',
          dtstart: const ICalDate('20261120T090000Z'),
          dtend: const ICalDate('20261120T100000Z'),
        ),
      ],
      tasks: [_task('t1', 'All day task', 20)],
    );
    await _pump(t, s);
    Finder chip(int i) => _k('calendar-chip-2026-11-20-$i');
    String first(int i) => t
        .widget<Text>(
          find.descendant(of: chip(i), matching: find.byType(Text)).first,
        )
        .data!;
    // All-day items first (the event, then the task), then by start time.
    expect(first(0), 'All day ev');
    expect(first(1), 'All day task');
    expect(first(2), '09:00');
    expect(
      find.descendant(of: chip(2), matching: find.text('Early ev')),
      findsOneWidget,
    );
    expect(t.widget<Text>(_k('calendar-more-2026-11-20')).data, '+1 more');
    // The task chip's mark is a hollow dot; the event chip carries none.
    BoxDecoration mark(int i) =>
        t
                .widget<Container>(
                  find
                      .descendant(of: chip(i), matching: find.byType(Container))
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(mark(1).color, isNull);
    expect(mark(1).border, isNotNull);
    expect(
      find.descendant(of: chip(0), matching: find.byType(StatusDot)),
      findsNothing,
    );
  });

  testWidgets('narrow cells show a dot per kind', (t) async {
    final s = await _state(
      t,
      events: [_event('e1', 'Alpha ev', 20)],
      tasks: [_task('t1', 'Delta task', 20)],
    );
    await _pump(t, s, size: const Size(400, 800));
    expect(_k('calendar-dot-event-2026-11-20'), findsOneWidget);
    expect(_k('calendar-dot-task-2026-11-20'), findsOneWidget);
    expect(_k('calendar-chip-2026-11-20-0'), findsNothing);
    // The day is still selectable and lists its items below.
    await t.tap(_k('calendar-day-2026-11-20'));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: _k('calendar-day-card'),
        matching: find.text('Alpha ev'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no overflow at 320 with items on the selected day', (t) async {
    final s = await _state(
      t,
      events: [_event('e1', 'Alpha ev', 20)],
      tasks: [_task('t1', 'Delta task', 20)],
    );
    await _pump(t, s, size: const Size(320, 800));
    await t.tap(_k('calendar-day-2026-11-20'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('the selection is a filled circle; today keeps the ring', (
    t,
  ) async {
    BoxDecoration circle(String day) =>
        t.widget<Container>(_k('calendar-number-2026-11-$day')).decoration!
            as BoxDecoration;
    final s = await _state(t);
    await _pump(t, s);
    // November 18 is today and the selection: filled, no ring.
    expect(circle('18').color, Tokens.light.accent);
    expect(circle('18').border, isNull);
    // Another day is plain.
    expect(circle('20').color, isNull);
    expect(circle('20').border, isNull);
    await t.tap(_k('calendar-day-2026-11-20'));
    await t.pumpAndSettle();
    expect(circle('20').color, Tokens.light.accent);
    // Today is now only the ring.
    expect(circle('18').color, isNull);
    expect(circle('18').border, isNotNull);
    // The cell itself never takes a fill. The first decoration under the
    // day's tap target is the cell.
    final cell =
        t
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: _k('calendar-day-2026-11-20'),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(cell.color, isNot(Tokens.light.accent));
  });

  testWidgets('the header row: title, arrows, Today', (t) async {
    final s = await _state(t);
    await _pump(t, s);
    final month = t.widget<Text>(_k('calendar-month'));
    expect(month.data, 'November 2026');
    expect(month.style?.fontSize, Tokens.light.type.title);
    expect(_k('calendar-prev'), findsOneWidget);
    expect(_k('calendar-next'), findsOneWidget);
    expect(
      t.widget<FButton>(_k('calendar-today')).variant,
      FButtonVariant.secondary,
    );
    // One row: all three share a vertical centre with the title.
    final y = t.getCenter(_k('calendar-month')).dy;
    for (final k in ['calendar-prev', 'calendar-next', 'calendar-today']) {
      expect((t.getCenter(_k(k)).dy - y).abs(), lessThan(1), reason: k);
    }
  });

  testWidgets('a multi-day event is one bar across its cells', (t) async {
    // Friday 20 to Sunday 22 November: one week row (16..22).
    final s = await _state(
      t,
      events: [
        Event(
          uid: 'visit',
          summary: 'Artist visit',
          dtstart: ICalDate.date(2026, 11, 20),
          dtend: ICalDate.date(2026, 11, 23),
        ),
      ],
    );
    await _pump(t, s);
    final bar = _k('calendar-bar-visit@2026-11-20-2026-11-16');
    expect(bar, findsOneWidget);
    // One bar three cells wide, inset at both real ends.
    final cell = t.getSize(_k('calendar-day-2026-11-20')).width;
    expect(t.getSize(bar).width, closeTo(3 * cell - 4, 1));
    expect(
      t.getTopLeft(bar).dx,
      closeTo(t.getTopLeft(_k('calendar-day-2026-11-20')).dx + 2, 1),
    );
    // Its days carry no chip for it; the bar's title is the only one.
    expect(_k('calendar-chip-2026-11-20-0'), findsNothing);
    expect(_k('calendar-chip-2026-11-21-0'), findsNothing);
    expect(find.text('Artist visit'), findsOneWidget);
  });

  testWidgets('overlapping visits stack on separate lanes', (t) async {
    Event visit(String uid, String title, int from, int to) => Event(
      uid: uid,
      summary: title,
      dtstart: ICalDate.date(2026, 11, from),
      dtend: ICalDate.date(2026, 11, to),
    );
    final s = await _state(
      t,
      events: [
        visit('a', 'Alpha visit', 18, 21),
        visit('b', 'Beta visit', 19, 22),
      ],
    );
    await _pump(t, s);
    final a = _k('calendar-bar-a@2026-11-18-2026-11-16');
    final b = _k('calendar-bar-b@2026-11-19-2026-11-16');
    expect(a, findsOneWidget);
    expect(b, findsOneWidget);
    // The earlier visit keeps the top lane; the one it overlaps drops below.
    expect(
      t.getTopLeft(b).dy - t.getTopLeft(a).dy,
      closeTo(Tokens.light.sizes.calendarLanePitch, 1),
    );
    expect(
      find.descendant(of: a, matching: find.text('Alpha visit')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: b, matching: find.text('Beta visit')),
      findsOneWidget,
    );
    // Nothing was pushed out of the lane layer.
    expect(_k('calendar-lanes-more-2026-11-16'), findsNothing);
  });

  testWidgets('lanes cap at three; the rest and a full cell never overflow', (
    t,
  ) async {
    Event visit(String uid, int from, int to) => Event(
      uid: uid,
      summary: 'Visit $uid',
      dtstart: ICalDate.date(2026, 11, from),
      dtend: ICalDate.date(2026, 11, to),
    );
    final s = await _state(
      t,
      events: [
        visit('va', 16, 23),
        visit('vb', 16, 23),
        visit('vc', 16, 23),
        visit('vd', 16, 23),
        _event('e1', 'One', 20),
        _event('e2', 'Two', 20),
        _event('e3', 'Three', 20),
      ],
    );
    await _pump(t, s);
    expect(_k('calendar-bar-va@2026-11-16-2026-11-16'), findsOneWidget);
    expect(_k('calendar-bar-vd@2026-11-16-2026-11-16'), findsNothing);
    expect(
      t.widget<Text>(_k('calendar-lanes-more-2026-11-16')).data,
      '+1 more',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('a Space without events hides them and the event add', (t) async {
    final s = await _noEventsState(
      t,
      events: [_event('e1', 'Alpha ev', 20)],
      tasks: [_task('t1', 'Delta task', 20)],
    );
    await _pump(t, s);
    // Only the task has a chip (the Space has no event component at all).
    expect(_k('calendar-chip-2026-11-20-0'), findsOneWidget);
    expect(_k('calendar-chip-2026-11-20-1'), findsNothing);
    await t.tap(_k('calendar-day-2026-11-20'));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: _k('calendar-day-card'),
        matching: find.text('Delta task'),
      ),
      findsOneWidget,
    );
    expect(_k('calendar-add-event'), findsNothing);
  });
}

/// A state whose Space has no event component.
class _NoEventsState extends AppState {
  _NoEventsState(super.source, {super.prefs});
  @override
  bool get supportsEvents => false;
}

Future<AppState> _noEventsState(
  WidgetTester t, {
  List<Task> tasks = const [],
  List<Event> events = const [],
}) async {
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final src = SpaceNoteSource(space, seed: _Seed(_tree));
  await t.runAsync(() async {
    for (final k in tasks) {
      await src.saveTask(k);
    }
    for (final e in events) {
      await src.saveEvent(e);
    }
  });
  final s = _NoEventsState(src, prefs: MemoryStorage());
  await t.runAsync(s.load);
  return s;
}
