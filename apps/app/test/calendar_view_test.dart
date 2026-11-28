import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/calendar_view.dart';
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
