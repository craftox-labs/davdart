import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/note_draft.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'catalog_helper.dart';
import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

/// A widget inside the Events side panel.
Finder _p(String k) => find.descendant(of: _k('events-view'), matching: _k(k));

Finder _panelText(String x) =>
    find.descendant(of: _k('events-view'), matching: find.text(x));

/// Tears the app down and lets forui's tooltip hide timers run out.
Future<void> _end(WidgetTester t) async {
  await t.pump(const Duration(seconds: 1));
}

List<Event> _events() => [
  mkEvent('standup', summary: 'Standup', days: 0, hour: 9, location: 'Room 4'),
  mkEvent('holiday', summary: 'Holiday', days: 0, allDay: true),
  mkEvent('lunch', summary: 'Lunch', days: 1, hour: 12),
  mkEvent('review', summary: 'Review', days: 4, hour: 15),
  mkEvent(
    'daily',
    summary: 'Daily',
    days: 0,
    hour: 18,
    rrule: 'FREQ=DAILY;COUNT=3',
  ),
  mkEvent('off', summary: 'Called off', days: 2, hour: 10, status: 'CANCELLED'),
  mkEvent('old', summary: 'Last week', days: -3, hour: 10),
];

Future<AppState> _panel(
  WidgetTester t, {
  Size size = const Size(1280, 900),
  List<Event>? events,
  bool readOnly = false,
  MemoryStorage? prefs,
}) async {
  final s = await pumpTasksApp(
    t,
    events: events ?? _events(),
    size: size,
    readOnly: readOnly,
    prefs: prefs,
  );
  s.setSection(Section.events);
  await t.pumpAndSettle();
  return s;
}

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));
  group('Events panel', () {
    testWidgets('the rail Events item lists the agenda', (t) async {
      final s = await pumpTasksApp(t, events: _events());
      expect(_k('events-view'), findsNothing);
      await t.tap(_k('rail-events'));
      await t.pumpAndSettle();
      expect(s.section, Section.events);
      expect(_k('events-panel'), findsOneWidget);
      expect(_k('events-view'), findsOneWidget);
      expect(
        find.descendant(of: _k('side-header'), matching: find.text('Events')),
        findsOneWidget,
      );
      expect(_k('new-event'), findsOneWidget);
      await _end(t);
    });

    testWidgets('empty state stays without events; New event is enabled', (
      t,
    ) async {
      await pumpTasksApp(t);
      await t.tap(_k('rail-events'));
      await t.pumpAndSettle();
      expect(_k('events-empty'), findsOneWidget);
      expect(find.text('No events yet'), findsOneWidget);
      expect(_k('new-event'), findsOneWidget);
      expect(
        t
            .widget<FButton>(
              find.descendant(
                of: _k('new-event'),
                matching: find.byType(FButton),
              ),
            )
            .onPress,
        isNotNull,
      );
      await _end(t);
    });

    testWidgets('groups Today, Tomorrow, Upcoming and Past', (t) async {
      await _panel(t);
      for (final g in ['today', 'tomorrow', 'upcoming', 'past']) {
        expect(_p('events-$g-toggle'), findsOneWidget, reason: g);
      }
      expect(_panelText('Today'), findsOneWidget);
      expect(_panelText('Tomorrow'), findsOneWidget);
      expect(_panelText('Upcoming'), findsOneWidget);
      expect(_panelText('Past'), findsOneWidget);
      expect(_p('event-row-standup'), findsOneWidget);
      expect(_p('event-row-lunch'), findsOneWidget);
      expect(_p('event-row-review'), findsOneWidget);
      expect(_p('event-row-old'), findsOneWidget);
      // Today comes before Tomorrow before Upcoming.
      double y(String k) => t.getTopLeft(_p(k)).dy;
      expect(y('event-row-standup'), lessThan(y('event-row-lunch')));
      expect(y('event-row-lunch'), lessThan(y('event-row-review')));
      expect(y('event-row-review'), lessThan(y('event-row-old')));
      await _end(t);
    });

    testWidgets('rows show time or All day, title, location, repeat mark', (
      t,
    ) async {
      await _panel(t);
      expect(
        find.descendant(
          of: _p('event-row-standup'),
          matching: find.text('09:00'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _p('event-row-standup'),
          matching: find.text('Room 4'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _p('event-row-holiday'),
          matching: find.text('All day'),
        ),
        findsOneWidget,
      );
      expect(_k('event-location-lunch'), findsNothing);
      // a repeating event has a row per occurrence with the marker
      final today = DateTime.now();
      String stamp(int d) {
        final n = today.add(Duration(days: d));
        return '${n.year}${n.month.toString().padLeft(2, '0')}'
            '${n.day.toString().padLeft(2, '0')}';
      }

      for (var d = 0; d < 3; d++) {
        expect(
          _p('event-row-daily@${stamp(d)}T1800'),
          findsOneWidget,
          reason: '$d',
        );
      }
      expect(_p('event-repeat-daily'), findsNWidgets(3));
      expect(_p('event-repeat-standup'), findsNothing);
      // Upcoming and Past rows carry the day
      expect(_k('event-day-review'), findsOneWidget);
      expect(_k('event-day-standup'), findsNothing);
      // a cancelled event is struck through
      final style = t
          .widget<Text>(
            find.descendant(
              of: _p('event-row-off'),
              matching: find.text('Called off'),
            ),
          )
          .style!;
      expect(style.decoration, TextDecoration.lineThrough);
      final plain = t
          .widget<Text>(
            find.descendant(
              of: _p('event-row-lunch'),
              matching: find.text('Lunch'),
            ),
          )
          .style;
      expect(plain?.decoration, isNull);
      await _end(t);
    });

    testWidgets('Past collapses and persists', (t) async {
      final prefs = MemoryStorage();
      await _panel(t, prefs: prefs);
      await t.tap(_p('events-past-toggle'));
      await t.pumpAndSettle();
      expect(_p('event-row-old'), findsNothing);
      expect(prefs.read('davdart.events.past.collapsed.v1'), 'true');
      expect(_p('event-row-standup'), findsOneWidget);
      await _end(t);
    });

    testWidgets('nothing in sight when only far events exist', (t) async {
      await _panel(t, events: [mkEvent('far', days: 90)]);
      expect(_k('events-none'), findsOneWidget);
      expect(_k('events-empty'), findsNothing);
      await _end(t);
    });

    testWidgets('a row opens per the open setting; double click promotes', (
      t,
    ) async {
      final s = await _panel(t);
      await t.tap(_panelText('Lunch'));
      await t.pumpAndSettle();
      expect(s.peekUid, 'lunch');
      expect(_k('event-detail'), findsOneWidget);
      s.setOpenMode(OpenMode.main);
      await t.tap(_panelText('Review'));
      await t.pumpAndSettle();
      expect(s.mainEventUid, 'review');
      expect(_k('tab-e:review'), findsOneWidget);
      s.setOpenMode(OpenMode.peek);
      await t.tap(_panelText('Standup'));
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(_panelText('Standup'));
      await t.pumpAndSettle();
      expect(s.mainEventUid, 'standup');
      expect(s.peekUid, isNot('standup'));
      await _end(t);
    });

    testWidgets('New event dialog adds a timed event and opens it', (t) async {
      final s = await _panel(t, events: const []);
      await t.tap(_k('new-event'));
      await t.pumpAndSettle();
      expect(_k('new-event-title'), findsOneWidget);
      expect(_k('new-event-start-time'), findsOneWidget);
      expect(_k('new-event-end-time'), findsOneWidget);
      // an empty title adds nothing
      await t.tap(_k('new-event-add'));
      await t.pumpAndSettle();
      expect(s.events, isEmpty);
      await t.enterText(_k('new-event-title'), 'Coffee');
      await t.enterText(_k('new-event-location'), 'Cafe');
      await t.pump();
      await t.tap(_k('new-event-add'));
      await t.pumpAndSettle();
      expect(s.events, hasLength(1));
      final e = s.events.single;
      expect(e.summary, 'Coffee');
      expect(e.location, 'Cafe');
      expect(e.allDay, isFalse);
      expect(e.dtstart!.value, endsWith('T020000Z'));
      expect(e.dtend!.value, endsWith('T030000Z'));
      expect(s.peekUid, e.uid);
      expect(_k('new-event-title'), findsNothing);
      expect(_p('event-row-${e.uid}'), findsOneWidget);
      await _end(t);
    });

    testWidgets('New event dialog: all day hides the times', (t) async {
      final s = await _panel(t, events: const []);
      await t.tap(_k('new-event'));
      await t.pumpAndSettle();
      await t.tap(_k('new-event-allday'));
      await t.pumpAndSettle();
      expect(_k('new-event-start-time'), findsNothing);
      expect(_k('new-event-end-time'), findsNothing);
      await t.enterText(_k('new-event-title'), 'Day off');
      await t.pump();
      await t.tap(_k('new-event-add'));
      await t.pumpAndSettle();
      final e = s.events.single;
      expect(e.allDay, isTrue);
      expect(e.dtstart!.value.length, 8);
      expect(
        find.descendant(
          of: _p('event-row-${e.uid}'),
          matching: find.text('All day'),
        ),
        findsOneWidget,
      );
      await _end(t);
    });

    testWidgets('read-only Space has no New event', (t) async {
      await _panel(t, readOnly: true);
      expect(_k('new-event'), findsNothing);
      expect(_p('event-row-standup'), findsOneWidget);
      await _end(t);
    });
  });

  group('Event menu', () {
    testWidgets('right-click: open, move, copy id, delete confirm', (t) async {
      final s = await _panel(t);
      await t.tap(_panelText('Lunch'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      for (final k in [
        'menu-open-peek',
        'menu-open-main',
        'menu-copy-id',
        'menu-delete',
      ]) {
        expect(_k(k), findsOneWidget, reason: k);
      }
      expect(_k('menu-move-space'), findsNothing); // one Space only
      await t.tap(_k('menu-open-main'));
      await t.pumpAndSettle();
      expect(s.mainEventUid, 'lunch');
      s.setSection(Section.events);
      await t.pumpAndSettle();
      await t.tap(_panelText('Review'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_k('menu-open-peek'));
      await t.pumpAndSettle();
      expect(s.peekUid, 'review');
      // Delete asks first.
      await t.tap(_panelText('Review'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_k('menu-delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete event?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(s.eventById('review'), isNotNull);
      await t.tap(_panelText('Review'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_k('menu-delete'));
      await t.pumpAndSettle();
      await t.tap(_k('delete-confirm'));
      await t.pumpAndSettle();
      expect(s.eventById('review'), isNull);
      expect(_p('event-row-review'), findsNothing);
      await _end(t);
    });

    testWidgets('deleting a repeating event says all its repeats go', (
      t,
    ) async {
      await _panel(t);
      await t.tap(
        find
            .descendant(of: _k('events-view'), matching: find.text('Daily'))
            .first,
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      await t.tap(_k('menu-delete'));
      await t.pumpAndSettle();
      expect(find.textContaining('all its repeats'), findsOneWidget);
      await _end(t);
    });

    testWidgets('read-only menu has no Delete or Move', (t) async {
      await _panel(t, readOnly: true);
      await t.tap(_panelText('Lunch'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-open-peek'), findsOneWidget);
      expect(_k('menu-delete'), findsNothing);
      expect(_k('menu-move-space'), findsNothing);
      await _end(t);
    });

    testWidgets('the tab and the peek tab carry the event menu', (t) async {
      final s = await _panel(t);
      s.openEventTab('lunch');
      await t.pumpAndSettle();
      await t.tap(_k('tab-e:lunch'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-close'), findsOneWidget);
      expect(_k('menu-delete'), findsOneWidget);
      await t.tapAt(const Offset(2, 2));
      await t.pumpAndSettle();
      s.select('review');
      await t.pumpAndSettle();
      await t.tap(_k('detail-tab'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(_k('menu-close'), findsOneWidget);
      await _end(t);
    });
  });

  group('Event detail', () {
    testWidgets(
      'read view: title, when, location, status, repeats, tags, text',
      (t) async {
        final s = await pumpTasksApp(
          t,
          events: [
            mkEvent(
              'k',
              summary: 'Detail me',
              days: 1,
              hour: 9,
              hours: 2,
              location: 'Hall',
              status: 'TENTATIVE',
              tags: ['x'],
              description: 'Some text',
              rrule: 'FREQ=WEEKLY;BYDAY=MO',
            ),
          ],
        );
        s.select('k');
        await t.pumpAndSettle();
        Finder inDetail(Finder f) =>
            find.descendant(of: _k('event-detail'), matching: f);
        expect(
          find.descendant(
            of: _k('peek-toolbar'),
            matching: find.text('Detail me'),
          ),
          findsOneWidget,
        );
        expect(inDetail(find.text('Detail me')), findsNothing);
        expect(inDetail(find.text('Some text')), findsOneWidget);
        expect(inDetail(find.text('x')), findsOneWidget);
        expect(
          t.widget<Text>(_k('event-when')).data,
          allOf(contains('09:00-11:00'), contains(', ')),
        );
        expect(t.widget<Text>(_k('event-location')).data, 'Hall');
        expect(t.widget<Text>(_k('event-status-text')).data, 'tentative');
        expect(find.textContaining('FREQ=WEEKLY;BYDAY=MO'), findsOneWidget);
        expect(find.text('Hall'), findsWidgets); // breadcrumb too
        await _end(t);
      },
    );

    testWidgets('an all-day event reads "all day"', (t) async {
      final s = await pumpTasksApp(
        t,
        events: [mkEvent('k', days: 2, allDay: true, span: 2)],
      );
      s.select('k');
      await t.pumpAndSettle();
      expect(t.widget<Text>(_k('event-when')).data, contains('all day'));
      expect(t.widget<Text>(_k('event-when')).data, contains(' - '));
      await _end(t);
    });

    testWidgets('edit, save: title, location, status and all day', (t) async {
      final s = await pumpTasksApp(
        t,
        events: [mkEvent('k', summary: 'Edit me', days: 1, hour: 9)],
      );
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      expect(s.eventDraftFor('k'), isNotNull);
      expect(t.widget<FButton>(_k('edit-save')).onPress, isNull);
      expect(_k('event-series-note'), findsNothing);
      await t.enterText(_k('edit-title'), 'Edited');
      await t.enterText(_k('edit-location'), 'Pub');
      await t.pump();
      expect(_k('dirty-indicator'), findsOneWidget);
      await t.tap(_k('edit-status'));
      await t.pumpAndSettle();
      await t.tap(find.text('confirmed').last);
      await t.pumpAndSettle();
      expect(s.eventDraftFor('k')!.status, 'CONFIRMED');
      await t.tap(_k('edit-allday'));
      await t.pumpAndSettle();
      expect(_k('edit-start-time'), findsNothing);
      expect(s.eventDraftFor('k')!.allDay, isTrue);
      await t.tap(_k('edit-save'));
      await t.pumpAndSettle();
      final e = s.eventById('k')!;
      expect(e.summary, 'Edited');
      expect(e.location, 'Pub');
      expect(e.status, 'CONFIRMED');
      expect(e.allDay, isTrue);
      expect(s.eventDraftFor('k'), isNull);
      await _end(t);
    });

    testWidgets('the time field drives the draft; end before start blocks', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        events: [mkEvent('k', days: 1, hour: 9, hours: 1)],
      );
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      expect(_k('edit-start-date'), findsOneWidget);
      expect(_k('edit-end-date'), findsOneWidget);
      expect(_k('edit-start-time'), findsOneWidget);
      expect(_k('edit-end-time'), findsOneWidget);
      final d = s.eventDraftFor('k')!;
      d.moveStart(minutes: 14 * 60);
      await t.pumpAndSettle();
      expect(d.end.hour, 15);
      d.setEnd(minutes: 13 * 60);
      await t.pumpAndSettle();
      expect(_k('edit-error'), findsOneWidget);
      expect(t.widget<FButton>(_k('edit-save')).onPress, isNull);
      d.setEnd(minutes: 16 * 60);
      await t.pumpAndSettle();
      expect(_k('edit-error'), findsNothing);
      expect(t.widget<FButton>(_k('edit-save')).onPress, isNotNull);
      await _end(t);
    });

    testWidgets('editing a repeating event says it edits the series', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        events: [mkEvent('k', days: 1, rrule: 'FREQ=DAILY')],
      );
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      expect(_k('event-series-note'), findsOneWidget);
      expect(find.textContaining('whole series'), findsOneWidget);
      await _end(t);
    });

    testWidgets('the repeat section sets weekly days and saves', (t) async {
      final s = await pumpTasksApp(t, events: [mkEvent('k', days: 1, hour: 9)]);
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      expect(_k('edit-interval'), findsNothing);
      await t.tap(_k('edit-repeat'));
      await t.pumpAndSettle();
      await t.tap(find.text('Weekly').last);
      await t.pumpAndSettle();
      expect(s.eventDraftFor('k')!.rrule, startsWith('FREQ=WEEKLY;BYDAY='));
      expect(_k('edit-interval'), findsOneWidget);
      await t.tap(_k('edit-weekday-1'));
      await t.pumpAndSettle();
      await t.tap(_k('edit-weekday-3'));
      await t.pumpAndSettle();
      final r = RepeatRule.parse(s.eventDraftFor('k')!.rrule)!;
      expect(r.weekdays, contains(1));
      await t.tap(_k('edit-save'));
      await t.pumpAndSettle();
      expect(s.eventById('k')!.rrule, startsWith('FREQ=WEEKLY'));
      await _end(t);
    });

    testWidgets('a custom repeat rule is shown and kept', (t) async {
      final s = await pumpTasksApp(
        t,
        events: [mkEvent('k', days: 1, rrule: 'FREQ=MONTHLY;BYDAY=-1FR')],
      );
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      expect(_k('edit-custom'), findsOneWidget);
      expect(_k('edit-interval'), findsNothing);
      expect(s.eventDraftFor('k')!.dirty, isFalse);
      await _end(t);
    });

    testWidgets('an unsupported repeat rule is flagged', (t) async {
      final s = await pumpTasksApp(
        t,
        events: [
          mkEvent('k', days: 1, rrule: 'FREQ=MONTHLY;BYSETPOS=1;BYDAY=MO'),
        ],
      );
      s.select('k');
      await t.pumpAndSettle();
      expect(_k('event-unsupported'), findsOneWidget);
      await _end(t);
    });

    testWidgets('empty title cannot be saved', (t) async {
      final s = await pumpTasksApp(t, events: [mkEvent('k')]);
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      await t.enterText(_k('edit-title'), '  ');
      await t.pump();
      expect(t.widget<FButton>(_k('edit-save')).onPress, isNull);
      await _end(t);
    });

    testWidgets('dirty guard: keep editing, discard, save', (t) async {
      final s = await pumpTasksApp(
        t,
        events: [
          mkEvent('k', summary: 'Guard'),
          mkEvent('m', summary: 'Other'),
        ],
      );
      s.select('k');
      await t.pumpAndSettle();
      s.startEventEdit('k');
      s.eventDraftFor('k')!.titleController.text = 'Changed';
      await t.pump();
      expect(_k('dirty-indicator'), findsWidgets);
      s.leaveGuard = () async => DraftChoice.keep;
      await s.openNote('m');
      expect(s.peekUid, 'k');
      s.leaveGuard = () async => DraftChoice.discard;
      await s.openNote('m');
      expect(s.peekUid, 'm');
      expect(s.eventById('k')!.summary, 'Guard');
      s.select('k');
      s.startEventEdit('k');
      s.eventDraftFor('k')!.titleController.text = 'Saved';
      s.leaveGuard = () async => DraftChoice.save;
      await t.runAsync(() => s.openNote('m'));
      await t.pumpAndSettle();
      expect(s.eventById('k')!.summary, 'Saved');
      await _end(t);
    });

    testWidgets('the draft survives promoting to the main area', (t) async {
      final s = await pumpTasksApp(t, events: [mkEvent('k', summary: 'Moves')]);
      s.select('k');
      await t.pumpAndSettle();
      s.startEventEdit('k');
      s.eventDraftFor('k')!.titleController.text = 'Typed';
      await t.tap(_k('peek-promote'));
      await t.pumpAndSettle();
      expect(s.mainEventUid, 'k');
      expect(s.eventDraftFor('k')!.titleController.text, 'Typed');
      expect(find.text('Typed'), findsWidgets);
      expect(_k('main-note'), findsOneWidget);
      await _end(t);
    });

    testWidgets('read-only Space shows the event non-editable', (t) async {
      final s = await pumpTasksApp(
        t,
        events: [mkEvent('k', summary: 'Look', days: 1)],
        readOnly: true,
      );
      s.select('k');
      await t.pumpAndSettle();
      expect(_k('event-detail'), findsOneWidget);
      expect(_k('edit-note'), findsNothing);
      expect(_k('delete-note'), findsNothing);
      expect(_k('move-note'), findsNothing);
      s.startEventEdit('k');
      expect(s.eventDraftFor('k'), isNull);
      await _end(t);
    });

    testWidgets('delete from the toolbar asks first', (t) async {
      final s = await pumpTasksApp(t, events: [mkEvent('k', summary: 'Bye')]);
      s.select('k');
      await t.pumpAndSettle();
      await t.tap(_k('delete-note'));
      await t.pumpAndSettle();
      expect(find.text('Delete event?'), findsOneWidget);
      await t.tap(_k('delete-confirm'));
      await t.pumpAndSettle();
      expect(s.eventById('k'), isNull);
      expect(s.peekUid, isNull);
      await _end(t);
    });

    testWidgets('as a main tab the title, header and tab show', (t) async {
      final s = await pumpTasksApp(t, events: [mkEvent('k', summary: 'Full')]);
      s.openEventTab('k');
      await t.pumpAndSettle();
      expect(_k('main-note'), findsOneWidget);
      expect(_k('event-detail'), findsOneWidget);
      expect(_k('tab-e:k'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('tab-e:k'),
          matching: find.byIcon(FLucideIcons.calendarDays),
        ),
        findsOneWidget,
      );
      await _end(t);
    });
  });

  group('search and moves', () {
    Future<AppState> catalogApp(WidgetTester t) async {
      t.view.physicalSize = const Size(1500, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: SeedNotes([]));
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      return s;
    }

    testWidgets('an event hit shows an icon and opens the event', (t) async {
      final s = await catalogApp(t);
      await t.runAsync(
        () => s.addEvent('Zebra visit', start: DateTime.utc(2026, 12, 1, 9)),
      );
      final uid = s.events.single.uid;
      await t.tap(_k('rail-search'));
      await t.pumpAndSettle();
      await t.enterText(_k('search-all-field'), 'zebra');
      await t.pumpAndSettle();
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(_k('hit-$uid'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('hit-$uid'),
          matching: find.byIcon(FLucideIcons.calendarDays),
        ),
        findsOneWidget,
      );
      await t.tap(_k('hit-$uid'));
      await t.pumpAndSettle();
      expect(s.peekUid, uid);
      expect(_k('event-detail'), findsOneWidget);
      await _end(t);
    });

    testWidgets('Move to space dialog lists the other Spaces and moves', (
      t,
    ) async {
      t.view.physicalSize = const Size(1500, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final storage = MemoryStorage();
      final c = catalogWithPlanning(storage, planningSeed: SeedNotes([]));
      final other = c.add('Other');
      final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
      await t.pumpWidget(DavdartApp(state: s));
      await t.pumpAndSettle();
      await t.runAsync(
        () => s.addEvent('Mover', start: DateTime.now().toUtc(), end: null),
      );
      s.setSection(Section.events);
      await t.pumpAndSettle();
      await t.tap(_panelText('Mover'), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(_k('menu-move-space'));
      await t.pumpAndSettle();
      expect(_k('move-to-${other.id}'), findsOneWidget);
      await t.tap(_k('move-to-${other.id}'));
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(s.events, isEmpty);
      await _end(t);
    });
  });

  group('overflow', () {
    final long =
        'An exceedingly long event title that goes on and on '
        'without any sensible place to stop at all, really';
    for (final w in [320.0, 600.0, 880.0, 1280.0, 1911.0]) {
      testWidgets('panel, menu, dialog, detail and editor at $w', (t) async {
        final s = await pumpTasksApp(
          t,
          events: [
            for (var i = 0; i < 4; i++)
              mkEvent(
                'l$i',
                summary: '$long $i',
                days: i - 1,
                location: long,
                tags: ['alpha-tag', 'beta-tag-longer', 'gamma'],
                description: long * 3,
                rrule: i.isEven ? 'FREQ=DAILY;COUNT=40' : null,
              ),
          ],
          size: Size(w, 900),
        );
        final narrow = _k('menu').evaluate().isNotEmpty;
        if (narrow) {
          await t.tap(_k('menu'));
          await t.pumpAndSettle();
          await t.tap(_k('menu-filter'));
          await t.pumpAndSettle();
          await t.tap(_k('filter-events'));
        } else {
          await t.tap(_k('rail-events'));
        }
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'panel at $w');
        await t.tap(_k('new-event'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'dialog at $w');
        await t.tap(_k('new-event-allday'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'dialog all day at $w');
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        if (narrow) {
          await t.tap(_k('menu'));
          await t.pumpAndSettle();
        }
        s.select('l1');
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'detail at $w');
        s.startEventEdit('l1');
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'editor at $w');
        s.eventDraftFor('l1')!.setAllDay(true);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'editor all day at $w');
        s.openEventTab('l2');
        await t.pumpAndSettle();
        s.startEventEdit('l2');
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'main editor at $w');
        await _end(t);
      });
    }
  });

  group('boot matrix with events', () {
    for (final size in const [
      Size(320, 700),
      Size(880, 900),
      Size(1280, 900),
      Size(1911, 1000),
    ]) {
      for (final variant in ['home', 'panel', 'event-peek', 'event-tab']) {
        testWidgets('boots: $size $variant', (t) async {
          final s = await pumpTasksApp(t, events: _events(), size: size);
          switch (variant) {
            case 'panel':
              s.setSection(Section.events);
            case 'event-peek':
              s.select('lunch');
            case 'event-tab':
              s.openEventTab('review');
          }
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await _end(t);
        });
      }
    }
  });
}
