import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/calendar_view.dart';
import 'package:davdart_app/ui/chips.dart';
import 'package:davdart_app/ui/property/option_picker.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/gestures.dart';
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

/// The circle (or ring) around a day's date number, from its
/// `calendar-day-<y-m-d>` id.
BoxDecoration _circle(WidgetTester t, String id) =>
    t.widget<Container>(find.byKey(Key('calendar-number-$id'))).decoration!
        as BoxDecoration;

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

/// The calendar's state with only one kind of item writable (or neither).
class _EventsOnly extends AppState {
  _EventsOnly(super.source);
  @override
  bool get tasksEditable => false;
}

class _TasksOnly extends AppState {
  _TasksOnly(super.source);
  @override
  bool get eventsEditable => false;
}

class _Neither extends AppState {
  _Neither(super.source);
  @override
  bool get eventsEditable => false;
  @override
  bool get tasksEditable => false;
}

Future<AppState> _state(
  WidgetTester t, {
  List<Note> notes = const [],
  List<Task> tasks = const [],
  List<Event> events = const [],
  AppState Function(SpaceNoteSource src)? make,
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
  final s = make == null ? AppState(src, prefs: MemoryStorage()) : make(src);
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

  testWidgets('the cell plus opens the dialog on that day, event or task', (
    t,
  ) async {
    final s = await _state(t);
    await _pump(t, s);
    // Today's cell always shows the plus; nothing is picked by tapping it.
    expect(_k('calendar-add-2026-11-18'), findsOneWidget);
    final cell = t.getRect(_k('calendar-day-2026-11-18'));
    await t.tap(_k('calendar-add-2026-11-18'));
    await t.pumpAndSettle();
    // Both kinds are supported here: the plus asks which, in a popover that
    // fits the cell it came from and lines up with its edges.
    final rows = t.getRect(_k('property-option-calendar-add-event'));
    final option = find.ancestor(
      of: _k('property-option-calendar-add-event'),
      matching: find.byType(OptionPicker<String>),
    );
    final pop = t.getRect(
      find
          .ancestor(of: option.first, matching: find.byType(ConstrainedBox))
          .first,
    );
    expect(pop.width, lessThanOrEqualTo(cell.width + 1));
    expect(pop.right, closeTo(cell.right, 1.5));
    expect(rows.width, lessThanOrEqualTo(cell.width));
    await t.tap(_k('property-option-calendar-add-event'));
    await t.pumpAndSettle();
    expect(_k('new-event-title'), findsOneWidget);
    await t.enterText(_k('new-event-title'), 'From the plus');
    await t.tap(_k('new-event-add'));
    await t.pumpAndSettle();
    final made = s.events.firstWhere((e) => e.summary == 'From the plus');
    expect(made.dtstart!.localDay, DateTime.utc(2026, 11, 18));
    // The dialog was the only thing opened: the day was not picked.
    expect(s.homeDay, isNull);
    // The task side uses the same day as its due date.
    await t.tap(_k('calendar-add-2026-11-18'));
    await t.pumpAndSettle();
    await t.tap(_k('property-option-calendar-add-task'));
    await t.pumpAndSettle();
    await t.enterText(_k('new-task-title'), 'Task from the plus');
    await t.tap(_k('new-task-add'));
    await t.pumpAndSettle();
    final task = s.tasks.firstWhere((k) => k.summary == 'Task from the plus');
    expect(task.due!.localDay, DateTime.utc(2026, 11, 18));
    expect(s.homeDay, isNull);
  });

  /// Whether the day's add button is painted (it is mounted throughout, so
  /// its popover is not dropped when it hides).
  bool plusShown(WidgetTester t, String id) {
    final box = find.ancestor(
      of: _k('calendar-add-$id'),
      matching: find.byType(Opacity),
    );
    return box.evaluate().isNotEmpty &&
        t.widget<Opacity>(box.first).opacity > 0;
  }

  testWidgets('the plus shows on hover, and for today and the picked day', (
    t,
  ) async {
    final s = await _state(t);
    await _pump(t, s);
    // A plain day shows no plus until the pointer is on its cell.
    expect(plusShown(t, '2026-11-20'), isFalse);
    final cell = t.getRect(_k('calendar-day-2026-11-20'));
    final g = await t.startGesture(cell.center, kind: PointerDeviceKind.mouse);
    await t.pump();
    await g.moveBy(const Offset(4, 0));
    await t.pump();
    expect(plusShown(t, '2026-11-20'), isTrue);
    await g.up();
    await t.pumpAndSettle();
    // Today always shows one, and so does the picked day.
    expect(plusShown(t, '2026-11-18'), isTrue);
    s.setHomeDay(DateTime.utc(2026, 11, 21));
    await t.pumpAndSettle();
    expect(plusShown(t, '2026-11-21'), isTrue);
  });

  testWidgets(
    'the plus and its popover stay when the pointer leaves the cell',
    (t) async {
      final s = await _state(t);
      await _pump(t, s);
      final cell = t.getRect(_k('calendar-day-2026-11-20'));
      // Point at the cell so its plus shows, then open the popover.
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: cell.center);
      await t.pump();
      await t.tap(_k('calendar-add-2026-11-20'));
      await t.pumpAndSettle();
      expect(_k('property-option-calendar-add-event'), findsOneWidget);
      // Move the pointer off the cell towards the popover: the button stays
      // mounted and the rows stay tappable.
      await mouse.moveTo(Offset(cell.right + 40, cell.bottom + 120));
      await t.pumpAndSettle();
      expect(_k('calendar-add-2026-11-20'), findsOneWidget);
      expect(_k('property-option-calendar-add-event'), findsOneWidget);
      await t.tap(_k('property-option-calendar-add-task'));
      await t.pumpAndSettle();
      expect(_k('new-task-title'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      await mouse.removePointer();
    },
  );

  testWidgets('events only: the plus opens the event dialog directly', (
    t,
  ) async {
    await _pump(t, await _state(t, make: (src) => _EventsOnly(src)));
    await t.tap(_k('calendar-add-2026-11-18'));
    await t.pumpAndSettle();
    // No popover: the event dialog itself.
    expect(_k('property-option-calendar-add-task'), findsNothing);
    expect(_k('new-event-title'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(_k('new-event-title'), findsNothing);
  });

  testWidgets('tasks only: the plus opens the task dialog directly', (t) async {
    await _pump(t, await _state(t, make: (src) => _TasksOnly(src)));
    await t.tap(_k('calendar-add-2026-11-18'));
    await t.pumpAndSettle();
    expect(_k('property-option-calendar-add-event'), findsNothing);
    expect(_k('new-task-title'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(_k('new-task-title'), findsNothing);
  });

  testWidgets('a read-only Space has no plus', (t) async {
    await _pump(t, await _state(t, make: (src) => _Neither(src)));
    // Not built at all: nothing to hover.
    expect(_k('calendar-add-2026-11-18'), findsNothing);
    expect(_k('calendar-add-2026-11-17'), findsNothing);
  });

  testWidgets('a chip opens its event; empty cell space picks the day', (
    t,
  ) async {
    final s = await _state(
      t,
      events: [
        Event(
          uid: 'ev',
          summary: 'Standup',
          dtstart: const ICalDate('20261120T090000Z'),
          dtend: const ICalDate('20261120T100000Z'),
        ),
      ],
    );
    await _pump(t, s);
    await t.tap(_k('calendar-chip-2026-11-20-0'));
    await t.pumpAndSettle();
    // The chip opens the event itself, not just its day.
    expect(s.peekUid, 'ev');
    // A press on the cell's empty corner still picks the day.
    s.select(null);
    await t.pumpAndSettle();
    final cell = t.getRect(_k('calendar-day-2026-11-21'));
    await t.tapAt(Offset(cell.right - 4, cell.top + 4));
    await t.pumpAndSettle();
    expect(s.homeDay, isNotNull);
    expect(s.homeDay!.day, 21);
  });

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
    // Home keeps the picked day in the app state, shared with the panel.
    // Nothing is picked yet, so the grid circles today.
    expect(s.homeDay, isNull);
    expect(_circle(t, '2026-11-18').color, Tokens.light.accent);
    // December: the selection follows to the 1st, and the grid is a year
    // rollover away from January.
    await t.tap(_k('calendar-next'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('calendar-month')).data, 'December 2026');
    expect(s.homeDay, DateTime.utc(2026, 12, 1));
    expect(_circle(t, '2026-12-1').color, Tokens.light.accent);
    // December to January rolls the year over with the selection.
    await t.tap(_k('calendar-next'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('calendar-month')).data, 'January 2027');
    expect(s.homeDay, DateTime.utc(2027, 1, 1));
    expect(_circle(t, '2027-1-1').color, Tokens.light.accent);
    // Back to the current month: the selection returns to today.
    await t.tap(_k('calendar-today'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(_k('calendar-month')).data, 'November 2026');
    expect(s.homeDay, DateTime.utc(2026, 11, 18));
    expect(_circle(t, '2026-11-18').color, Tokens.light.accent);
  });

  testWidgets('selecting a day lists its items; an empty day says so', (
    t,
  ) async {
    final s = await _state(
      t,
      events: [_event('e20', 'Review', 20)],
      tasks: [_task('k20', 'Pay rent', 20)],
    );
    // Narrow: the day list stays under the grid (wide Home shows it in the
    // Calendar panel instead; see calendar_places_test).
    await _pump(t, s, size: const Size(400, 800));
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
    BoxDecoration circle(String day) => _circle(t, '2026-11-$day');
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

  testWidgets('a press on a bar opens the event and picks the day pressed', (
    t,
  ) async {
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
    // The bar spans the 20th to the 22nd: a press over the 21st picks that
    // day, not the one the bar starts on, and opens the event.
    final x = t.getCenter(_k('calendar-day-2026-11-21')).dx;
    await t.tapAt(Offset(x, t.getCenter(bar).dy));
    await t.pumpAndSettle();
    expect(s.homeDay, DateTime.utc(2026, 11, 21));
    expect(s.peekUid, 'visit');
    expect(s.section, Section.events);
  });

  testWidgets('dragging across days makes an all-day event in that range', (
    t,
  ) async {
    final s = await _state(t);
    await _pump(t, s);
    final a = t.getCenter(_k('calendar-day-2026-11-17'));
    final b = t.getCenter(_k('calendar-day-2026-11-19'));
    await t.dragFrom(a, b - a);
    await t.pumpAndSettle();
    // The range lands in the new-event dialog, all day, from the 17th to the
    // 19th (an all-day end is its last day).
    expect(_k('new-event-title'), findsOneWidget);
    expect(t.widget<FCheckbox>(_k('new-event-allday')).value, isTrue);
    await t.enterText(_k('new-event-title'), 'Sprint');
    await t.tap(_k('new-event-add'));
    await t.pumpAndSettle();
    final e = s.events.single;
    expect(e.summary, 'Sprint');
    expect(e.allDay, isTrue);
    expect(e.dtstart!.value, '20261117');
    expect(e.dtend!.value, '20261120');
  });

  testWidgets('a drag highlights the days of its range as it goes', (t) async {
    final s = await _state(t);
    await _pump(t, s);
    // The cell's own wash: the outer fill of the day's box.
    Color? fill(String id) {
      final box = t.widget<DecoratedBox>(
        find
            .descendant(
              of: _k('calendar-day-$id'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    expect(fill('2026-11-18'), isNull);
    final g = await t.startGesture(t.getCenter(_k('calendar-day-2026-11-17')));
    await g.moveTo(t.getCenter(_k('calendar-day-2026-11-19')));
    await t.pump();
    // The three days of the range carry the event tint; the day after is
    // untouched.
    for (final d in [17, 18, 19]) {
      expect(fill('2026-11-$d'), Tokens.light.eventTint, reason: 'Nov $d');
    }
    expect(fill('2026-11-20'), isNull);
    await g.up();
    await t.pumpAndSettle();
    expect(_k('new-event-title'), findsOneWidget);
  });

  testWidgets('a drag back along the row makes the same range', (t) async {
    final s = await _state(t);
    await _pump(t, s);
    final a = t.getCenter(_k('calendar-day-2026-11-19'));
    final b = t.getCenter(_k('calendar-day-2026-11-17'));
    await t.dragFrom(a, b - a);
    await t.pumpAndSettle();
    await t.enterText(_k('new-event-title'), 'Trip');
    await t.tap(_k('new-event-add'));
    await t.pumpAndSettle();
    final e = s.events.single;
    expect(e.dtstart!.value, '20261117');
    expect(e.dtend!.value, '20261120');
  });

  testWidgets('a vertical drag scrolls and makes no event', (t) async {
    final s = await _state(t);
    await _pump(t, s);
    final a = t.getCenter(_k('calendar-day-2026-11-17'));
    await t.dragFrom(a, const Offset(0, -200));
    await t.pumpAndSettle();
    expect(_k('new-event-title'), findsNothing);
    expect(s.events, isEmpty);
  });

  testWidgets('only the primary button drags a range', (t) async {
    final s = await _state(t);
    await _pump(t, s);
    final a = t.getCenter(_k('calendar-day-2026-11-17'));
    final b = t.getCenter(_k('calendar-day-2026-11-19'));
    // A right or middle press drags nothing: those scroll or open a menu.
    for (final button in [kSecondaryButton, kMiddleMouseButton]) {
      final g = await t.startGesture(
        a,
        kind: PointerDeviceKind.mouse,
        buttons: button,
      );
      await g.moveTo(b);
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(_k('new-event-title'), findsNothing);
      expect(s.events, isEmpty);
    }
    // The primary button still drags its range.
    final g = await t.startGesture(a, kind: PointerDeviceKind.mouse);
    await g.moveTo(b);
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    expect(_k('new-event-title'), findsOneWidget);
  });

  testWidgets('the phone has no range drag; a press picks the day', (t) async {
    final s = await _state(t);
    await _pump(t, s, size: const Size(400, 800));
    final a = t.getCenter(_k('calendar-day-2026-11-17'));
    final b = t.getCenter(_k('calendar-day-2026-11-19'));
    await t.dragFrom(a, b - a);
    await t.pumpAndSettle();
    expect(_k('new-event-title'), findsNothing);
    await t.tap(_k('calendar-day-2026-11-19'));
    await t.pumpAndSettle();
    expect(s.homeDay, DateTime.utc(2026, 11, 19));
  });

  testWidgets('a project Calendar drags a range too, scoped to it', (t) async {
    final s = await _state(t);
    await _pump(t, s, scoped: true);
    final a = t.getCenter(_k('calendar-day-2026-11-17'));
    final b = t.getCenter(_k('calendar-day-2026-11-19'));
    await t.dragFrom(a, b - a);
    await t.pumpAndSettle();
    await t.enterText(_k('new-event-title'), 'Scoped');
    await t.tap(_k('new-event-add'));
    await t.pumpAndSettle();
    final e = s.events.single;
    expect(e.dtstart!.value, '20261117');
    expect(e.dtend!.value, '20261120');
    // The project's Calendar keeps its own picked day; Home's stays unset.
    expect(s.homeDay, isNull);
  });

  testWidgets('a Space without events has no range drag', (t) async {
    final s = await _noEventsState(t);
    await _pump(t, s);
    final a = t.getCenter(_k('calendar-day-2026-11-17'));
    final b = t.getCenter(_k('calendar-day-2026-11-19'));
    await t.dragFrom(a, b - a);
    await t.pumpAndSettle();
    expect(_k('new-event-title'), findsNothing);
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

  testWidgets('Home wide is the grid alone; a day press picks it', (t) async {
    final s = await _state(t, events: [_event('e20', 'Review', 20)]);
    await _pump(t, s);
    // No day column, no day-card adds: the Calendar panel shows the day.
    expect(_k('calendar-day-card'), findsNothing);
    expect(_k('calendar-add-event'), findsNothing);
    expect(s.homeDay, isNull);
    await t.tap(_k('calendar-day-2026-11-20'));
    await t.pumpAndSettle();
    expect(s.homeDay, DateTime.utc(2026, 11, 20));
    // The panel opens on Calendar, unfolded, and the main area stays Home.
    expect(s.section, Section.events);
    expect(s.sidebarCollapsed, isFalse);
    expect(s.atHome, isTrue);
    // A press with the panel already there does not fold it.
    await t.tap(_k('calendar-day-2026-11-21'));
    await t.pumpAndSettle();
    expect(s.sidebarCollapsed, isFalse);
    expect(s.section, Section.events);
    // A folded panel opens again on the Calendar section.
    s.setSidebarCollapsed(true);
    await t.pumpAndSettle();
    await t.tap(_k('calendar-day-2026-11-22'));
    await t.pumpAndSettle();
    expect(s.sidebarCollapsed, isFalse);
    expect(s.homeDay, DateTime.utc(2026, 11, 22));
  });

  testWidgets('a six-week month fits 1265x800; its last bar is whole', (
    t,
  ) async {
    // November 2026 is six Monday-first weeks (26 October to 6 December) and
    // this event runs into the last one.
    final s = await _state(
      t,
      events: [
        Event(
          uid: 'offsite',
          summary: 'Offsite',
          dtstart: ICalDate.date(2026, 11, 27),
          dtend: ICalDate.date(2026, 12, 2),
        ),
      ],
    );
    await _pump(t, s, size: const Size(1265, 800));
    final last = _k('calendar-day-2026-12-6');
    expect(last, findsOneWidget);
    // The six rows share the height: the last one is on screen whole (never
    // under the least row height, never stretched past the most), so there is
    // nothing left for the view to scroll.
    final row = t.getRect(_k('calendar-day-2026-11-30'));
    final sizes = Tokens.light.sizes;
    expect(row.height, greaterThanOrEqualTo(sizes.calendarRowMin));
    expect(row.height, lessThanOrEqualTo(sizes.calendarCellChips));
    expect(t.getBottomLeft(last).dy, lessThanOrEqualTo(800));
    final scroll = t.state<ScrollableState>(
      find
          .descendant(
            of: _k('calendar-view'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scroll.position.maxScrollExtent, lessThan(1));
    // The bar on the last week's days is a whole bar inside that row, not the
    // sliver a row cut off by the window would leave.
    final bar = _k('calendar-bar-offsite@2026-11-27-2026-11-30');
    expect(bar, findsOneWidget);
    expect(t.getSize(bar).height, sizes.calendarChip);
    expect(t.getTopLeft(bar).dy, greaterThanOrEqualTo(row.top));
    expect(t.getBottomLeft(bar).dy, lessThanOrEqualTo(row.bottom));
  });

  testWidgets('a project Calendar at 1265x800 scrolls as one piece', (t) async {
    final s = await _state(t);
    await _pump(t, s, size: const Size(1265, 800), scoped: true);
    // The grid fits the height; the picked day's card sits under it and the
    // view carries both.
    final scroll = t.state<ScrollableState>(
      find
          .descendant(
            of: _k('calendar-view'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(_k('calendar-day-card'), findsOneWidget);
    await t.drag(_k('calendar-view'), const Offset(0, -400));
    await t.pumpAndSettle();
    expect(t.getBottomLeft(_k('calendar-day-card')).dy, lessThanOrEqualTo(800));
  });

  testWidgets('a project Calendar puts its day under the grid, as Home does', (
    t,
  ) async {
    final s = await _state(t, events: [_event('e20', 'Review', 20)]);
    await _pump(t, s, scoped: true);
    expect(_k('calendar-day-card'), findsOneWidget);
    // No second column: the card is under the grid and spans its width.
    final card = _k('calendar-day-card');
    final last = _k('calendar-day-2026-12-6');
    expect(t.getTopLeft(card).dy, greaterThan(t.getBottomLeft(last).dy));
    expect(
      t.getSize(card).width,
      closeTo(t.getSize(_k('calendar-month')).width, 200),
    );
    await t.tap(_k('calendar-day-2026-11-20'));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: card, matching: find.text('Review')),
      findsOneWidget,
    );
    expect(_k('calendar-add-event'), findsOneWidget);
    // The project's card keeps its own selection; Home's day is untouched.
    expect(s.homeDay, isNull);
  });

  testWidgets('a Space without events hides them and the event add', (t) async {
    final s = await _noEventsState(
      t,
      events: [_event('e1', 'Alpha ev', 20)],
      tasks: [_task('t1', 'Delta task', 20)],
    );
    // Narrow, so the day card below the grid carries the add buttons.
    await _pump(t, s, size: const Size(400, 800));
    // Only the task has a dot (the Space has no event component at all).
    expect(_k('calendar-dot-event-2026-11-20'), findsNothing);
    expect(_k('calendar-dot-task-2026-11-20'), findsOneWidget);
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
