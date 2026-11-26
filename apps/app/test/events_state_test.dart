import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/event_rules.dart';
import 'package:davdart_app/state/note_draft.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:davdart_app/ui/events_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../test/support/fake_caldav.dart';
import 'catalog_helper.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha', description: 'Alpha body'),
  ];
}

class _ReadOnly implements NoteSource {
  @override
  Future<List<Note>> load() async => [Note(uid: 'a', summary: 'Alpha')];
}

Future<AppState> _open(
  MemoryStorage m, {
  NoteSource? seed,
  http.Client? client,
}) async {
  final c = catalogWithPlanning(
    m,
    planningSeed: seed,
    davBase: Uri.parse('https://fake.test/dav/'),
    httpClient: client,
  );
  final s = AppState(c.sourceFor(c.current!), prefs: m, catalog: c);
  await s.load();
  return s;
}

// 2026-11-20 is a Friday.
final _noon = DateTime(2026, 11, 20, 12);
final _day = DateTime.utc(2026, 11, 20);

Event _e(
  String uid, {
  required String start,
  String? end,
  String? rrule,
  String? status,
  String params = '',
  String summary = '',
}) => Event(
  uid: uid,
  summary: summary.isEmpty ? uid : summary,
  dtstart: ICalDate(start, params),
  dtend: end == null ? null : ICalDate(end, params),
  rrule: rrule,
  status: status,
);

const _recurringWithOverride =
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\n'
    'BEGIN:VEVENT\r\nUID:r1\r\nDTSTAMP:20261119T000000Z\r\n'
    'DTSTART:20261120T090000\r\nDTEND:20261120T100000\r\n'
    'RRULE:FREQ=DAILY;COUNT=3\r\nEXDATE:20261121T090000\r\n'
    'SUMMARY:Standup\r\nEND:VEVENT\r\n'
    'BEGIN:VEVENT\r\nUID:r1\r\nRECURRENCE-ID:20261122T090000\r\n'
    'DTSTAMP:20261119T000000Z\r\nDTSTART:20261122T110000\r\n'
    'DTEND:20261122T120000\r\nSUMMARY:Standup moved\r\nEND:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));
  group('empty', () {
    test('no events: nothing changes and nothing is written', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      expect(s.events, isEmpty);
      expect(s.eventError, isNull);
      expect(s.upcomingOccurrences(_noon, 30), isEmpty);
      expect(s.pastOccurrences(_noon), isEmpty);
      expect(s.eventTags, isEmpty);
      expect(await s.searchAllSpaces('alpha'), hasLength(1));
      expect(m.keys.where((k) => k.contains('events')), isEmpty);
      expect(s.notes.map((n) => n.uid), ['a']);
    });

    test('no Space and a read-only feed reject event writes', () async {
      final s = AppState(_ReadOnly());
      await s.load();
      expect(s.eventsEditable, isFalse);
      expect(await s.addEvent('x', start: _day), isNull);
      expect(s.error, contains('read-only'));
      expect(s.events, isEmpty);
      final e = AppState(const EmptyNoteSource());
      await e.load();
      expect(await e.addEvent('x', start: _day), isNull);
    });
  });

  group('store', () {
    test('events persist under the Space key; planning keeps legacy', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      final uid = await s.addEvent(
        ' Dentist ',
        start: DateTime.utc(2026, 12, 1, 14, 30),
        end: DateTime.utc(2026, 12, 1, 15, 15),
        location: ' Main St ',
        tags: ['health', 'status-x'],
      );
      expect(uid, isNotNull);
      final e = s.events.single;
      expect(e.summary, 'Dentist');
      expect(e.location, 'Main St');
      expect(e.categories, ['health']);
      expect(e.dtstart!.value, '20261201T073000Z');
      expect(e.dtend!.value, '20261201T081500Z');
      expect(m.read('davdart.events.v1'), contains('Dentist'));
      expect(m.keys.any((k) => k.contains('tasks')), isFalse);
      await s.createSpace('Other');
      final id = s.currentSpaceId!;
      await s.addEvent('Other event', start: _day);
      expect(m.read('sp.$id.events.v1'), contains('Other event'));
      expect(m.read('sp.$id.events.v1'), isNot(contains('Dentist')));
      expect(await s.addEvent('  ', start: _day), isNull);
      await s.switchSpace(SpaceCatalog.planningId);
      expect(s.events.map((e) => e.summary), ['Dentist']);
      final again = await _open(m);
      expect(again.events.map((e) => e.summary), ['Dentist']);
      expect(again.events.single.dtstart!.value, '20261201T073000Z');
    });

    test('a damaged event store is kept aside; notes still load', () async {
      final m = MemoryStorage()
        ..write('davdart.space.v1', '{"notes":{},"revisions":[]}')
        ..write('davdart.events.v1', 'not json');
      final s = await _open(m);
      expect(s.events, isEmpty);
      expect(m.read('davdart.events.v1.unreadable'), 'not json');
      expect(s.error, isNull);
      expect(s.eventError, isNull);
    });

    test('deleting the Space removes its event keys', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      await s.addEvent('Legacy', start: _day);
      await s.createSpace('Sub');
      final sub = s.currentSpaceId!;
      await s.addEvent('Sub', start: _day);
      await s.switchSpace(SpaceCatalog.planningId);
      await s.deleteSpace();
      expect(m.read('davdart.events.v1'), isNull);
      expect(m.read('sp.$sub.events.v1'), contains('Sub'));
    });
  });

  group('operations', () {
    test('all-day end is the last day, inclusive', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      await s.addEvent(
        'Trip',
        start: DateTime.utc(2026, 12, 1, 10),
        end: DateTime.utc(2026, 12, 3),
        allDay: true,
      );
      final e = s.events.single;
      expect(e.allDay, isTrue);
      expect(e.dtstart!.value, '20261201');
      expect(e.dtend!.value, '20261204');
      expect(eventWhen(e, _noon), 'Tue 1 Dec - Thu 3 Dec, all day');
      await s.addEvent(
        'One day',
        start: DateTime.utc(2026, 12, 9),
        allDay: true,
      );
      expect(
        s.events.firstWhere((e) => e.summary == 'One day').dtend!.value,
        '20261210',
      );
    });

    test('edit: text, tags keep markers, status, when keeps zone', () async {
      LocalZone.use('Europe/Berlin'); // local wall equals the TZID wall
      final s = await _open(MemoryStorage(), seed: _Seed());
      final src = s.source as SpaceNoteSource;
      await src.saveEvent(
        Event(
          uid: 'z',
          summary: 'Zoned',
          dtstart: const ICalDate('20261201T090000', ';TZID=Europe/Berlin'),
          dtend: const ICalDate('20261201T100000', ';TZID=Europe/Berlin'),
          categories: ['kind-x', 'old'],
        ),
      );
      await s.load();
      expect(
        await s.updateEvent(
          'z',
          title: ' Zoned 2 ',
          description: 'text',
          location: 'Berlin',
          tags: ['new', 'status-no'],
          setStatus: true,
          status: 'TENTATIVE',
          setWhen: true,
          start: DateTime.utc(2026, 12, 2, 8),
          end: DateTime.utc(2026, 12, 2, 9, 30),
        ),
        isTrue,
      );
      var e = s.eventById('z')!;
      expect(e.summary, 'Zoned 2');
      expect(e.description, 'text');
      expect(e.location, 'Berlin');
      expect(e.status, 'TENTATIVE');
      expect(e.categories, ['kind-x', 'new']);
      expect(e.dtstart!.value, '20261202T080000');
      expect(e.dtstart!.params, ';TZID=Europe/Berlin');
      expect(e.dtend!.value, '20261202T093000');
      expect(await s.updateEvent('z', title: '  '), isFalse);
      await s.updateEvent('z', setStatus: true);
      e = s.eventById('z')!;
      expect(e.status, isNull);
      expect(e.summary, 'Zoned 2');
      // timed -> all day -> timed
      await s.updateEvent(
        'z',
        setWhen: true,
        allDay: true,
        start: DateTime.utc(2026, 12, 2),
        end: DateTime.utc(2026, 12, 2),
      );
      e = s.eventById('z')!;
      expect(e.dtstart!.value, '20261202');
      expect(e.dtend!.value, '20261203');
      await s.updateEvent(
        'z',
        setWhen: true,
        start: DateTime.utc(2026, 12, 2, 9),
        end: DateTime.utc(2026, 12, 2, 9),
      );
      e = s.eventById('z')!;
      expect(
        e.dtstart!.value,
        '20261202T080000Z',
      ); // timed again: written as UTC
      expect(e.dtend, isNull);
    });

    test('editing a series keeps overrides and exceptions (shifted with the start)', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final src = s.source as SpaceNoteSource;
      await src.saveEvent(parseEvent(_recurringWithOverride));
      await s.load();
      expect(s.eventById('r1')!.siblingLines, isNotEmpty);
      await s.updateEvent(
        'r1',
        title: 'Standup 2',
        setWhen: true,
        start: DateTime.utc(2026, 11, 20, 8),
        end: DateTime.utc(2026, 11, 20, 8, 30),
      );
      final e = s.eventById('r1')!;
      expect(e.rrule, 'FREQ=DAILY;COUNT=3');
      expect(e.exdates, hasLength(1));
      expect(e.siblingLines, isNotEmpty);
      final ics = serializeEvent(e);
      expect(
        ics,
        contains('RECURRENCE-ID:20261122T080000'),
      ); // shifted with the start
      expect(ics, contains('SUMMARY:Standup moved'));
    });

    test('delete removes the event; tasks under it move up', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final ev = (await s.addEvent('Party', start: _day))!;
      final t = (await s.addTask('Bring cake', parentUid: ev))!;
      expect(s.findItem(ev), isA<Event>());
      expect(s.taskById(t)!.parentUid, ev);
      expect(await s.deleteEvent(ev), isTrue);
      expect(s.eventById(ev), isNull);
      expect(s.taskById(t), isNotNull);
      expect(s.taskById(t)!.parentUid, isNull);
      expect(await s.deleteEvent(ev), isFalse);
    });

    test('findItem knows notes, tasks and events', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final ev = (await s.addEvent('E', start: _day))!;
      expect(s.findItem('a'), isA<Note>());
      expect(s.findItem(ev), isA<Event>());
      expect(s.findItem('zz'), isNull);
      expect(s.eventTags, isEmpty);
    });
  });

  group('agenda', () {
    test(
      'grouped Today, Tomorrow, This week, Later; ranges respected',
      () async {
        final s = await _open(MemoryStorage(), seed: _Seed());
        final src = s.source as SpaceNoteSource;
        for (final e in [
          _e('early', start: '20261120T080000', end: '20261120T090000'),
          _e('allday', start: '20261120', end: '20261121'),
          _e('late', start: '20261120T180000', end: '20261120T190000'),
          _e('tom', start: '20261121T100000', end: '20261121T110000'),
          _e('wk', start: '20261125T100000'),
          _e('later', start: '20261210T100000'),
          _e('far', start: '20270301T100000'),
          _e('old', start: '20261110T100000', end: '20261110T110000'),
          _e('ancient', start: '20260101T100000', end: '20260101T110000'),
        ]) {
          await src.saveEvent(e);
        }
        await s.load();
        final g = s.upcomingOccurrences(_noon, 30);
        expect(
          [for (final x in g) x.id],
          ['today', 'tomorrow', 'week', 'later'],
        );
        expect(
          [for (final o in g[0].items) o.event.uid],
          ['allday', 'early', 'late'],
        );
        expect([for (final o in g[1].items) o.event.uid], ['tom']);
        expect([for (final o in g[2].items) o.event.uid], ['wk']);
        expect([for (final o in g[3].items) o.event.uid], ['later']);
        expect(
          [for (final x in g) x.label],
          ['Today', 'Tomorrow', 'This week', 'Later'],
        );
        expect(
          [for (final o in s.pastOccurrences(_noon)) o.event.uid],
          ['old'],
        );
        expect(
          [for (final o in s.pastOccurrences(_noon, 400)) o.event.uid],
          ['old', 'ancient'],
        );
      },
    );

    test('recurring events expand; cancelled and exceptions follow', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final src = s.source as SpaceNoteSource;
      await src.saveEvent(parseEvent(_recurringWithOverride));
      await src.saveEvent(
        _e(
          'weekly',
          start: '20261120T200000',
          end: '20261120T210000',
          rrule: 'FREQ=WEEKLY',
          status: 'CANCELLED',
        ),
      );
      await s.load();
      final g = s.upcomingOccurrences(_noon, 30);
      final today = g.firstWhere((x) => x.id == 'today').items;
      expect([for (final o in today) o.event.uid], ['r1', 'weekly']);
      expect(today.last.isCancelled, isTrue);
      // EXDATE on the 21st leaves a gap; the override moves the 22nd.
      final tomorrow = [
        for (final x in g)
          if (x.id == 'tomorrow') ...x.items,
      ];
      expect(tomorrow, isEmpty);
      final week = g.firstWhere((x) => x.id == 'week').items;
      final r1 = [
        for (final o in week)
          if (o.event.uid == 'r1') o,
      ];
      expect(r1.single.summary, 'Standup moved');
      expect(r1.single.isOverride, isTrue);
      expect(r1.single.start, DateTime.utc(2026, 11, 22, 11));
      // The weekly one comes back in 7, 14, 21, 28 days: Later and Week.
      final weekly = [
        for (final x in g)
          for (final o in x.items)
            if (o.event.uid == 'weekly') o,
      ];
      expect(weekly, hasLength(5));
      expect(s.pastOccurrences(_noon, 30), isEmpty);
      // Past expansion: a daily event began 5 days ago.
      await src.saveEvent(
        _e(
          'daily',
          start: '20261115T090000',
          end: '20261115T093000',
          rrule: 'FREQ=DAILY',
        ),
      );
      await s.load();
      final past = s.pastOccurrences(_noon, 30);
      expect(past.where((o) => o.event.uid == 'daily'), hasLength(5));
      expect(past.first.start.isAfter(past.last.start), isTrue);
    });

    test('multi-day events running today count as Today', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final src = s.source as SpaceNoteSource;
      await src.saveEvent(_e('trip', start: '20261118', end: '20261123'));
      await src.saveEvent(_e('ended', start: '20261116', end: '20261120'));
      await s.load();
      expect(
        [
          for (final o in s.upcomingOccurrences(_noon, 30).single.items)
            o.event.uid,
        ],
        ['trip'],
      );
      expect(
        [for (final o in s.pastOccurrences(_noon)) o.event.uid],
        ['ended'],
      );
    });
  });

  group('drafts', () {
    test('start, edit, dirty, save, discard', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final uid = (await s.addEvent(
        'Plan',
        start: DateTime.utc(2026, 12, 1, 9),
        end: DateTime.utc(2026, 12, 1, 10),
        location: 'Room 1',
      ))!;
      s.startEventEdit(uid);
      final d = s.eventDraftFor(uid)!;
      expect(d.dirty, isFalse);
      expect(d.allDay, isFalse);
      expect(d.start, DateTime.utc(2026, 12, 1, 9));
      d.titleController.text = 'Plan B';
      expect(s.dirtyEventFor(uid), isTrue);
      d.moveStart(minutes: 11 * 60);
      expect(d.end, DateTime.utc(2026, 12, 1, 12)); // the length stays
      d.setEnd(minutes: 10 * 60);
      expect(d.endBeforeStart, isTrue);
      expect(await s.saveEventDraft(uid), isFalse);
      d.setEnd(minutes: 13 * 60);
      expect(await s.saveEventDraft(uid), isTrue);
      expect(s.eventDraftFor(uid), isNull);
      final e = s.eventById(uid)!;
      expect(e.summary, 'Plan B');
      expect(e.dtstart!.value, '20261201T040000Z');
      expect(e.dtend!.value, '20261201T060000Z');
      s.startEventEdit(uid);
      s.eventDraftFor(uid)!.setAllDay(true);
      expect(s.eventDraftFor(uid)!.dirty, isTrue);
      s.eventDraftFor(uid)!.setAllDay(false);
      expect(s.eventDraftFor(uid)!.start.hour, 9);
      s.discardEdit(uid);
      expect(s.eventDraftFor(uid), isNull);
      // an empty title cannot be saved
      s.startEventEdit(uid);
      s.eventDraftFor(uid)!.titleController.text = ' ';
      expect(await s.saveEventDraft(uid), isFalse);
    });

    test(
      'repeat rule: set, change, clear; an untouched custom rule stays',
      () async {
        final s = await _open(MemoryStorage(), seed: _Seed());
        final uid = (await s.addEvent(
          'Standup',
          start: DateTime.utc(2026, 12, 1, 9),
          end: DateTime.utc(2026, 12, 1, 10),
        ))!;
        s.startEventEdit(uid);
        var d = s.eventDraftFor(uid)!;
        expect(d.rrule, isNull);
        d.setRrule('FREQ=WEEKLY;BYDAY=TU');
        expect(d.dirty, isTrue);
        expect(await s.saveEventDraft(uid), isTrue);
        expect(s.eventById(uid)!.rrule, 'FREQ=WEEKLY;BYDAY=TU');
        s.startEventEdit(uid);
        d = s.eventDraftFor(uid)!;
        expect(d.dirty, isFalse);
        d.setRrule('FREQ=WEEKLY;BYDAY=TU,TH;COUNT=4');
        expect(await s.saveEventDraft(uid), isTrue);
        expect(s.eventById(uid)!.rrule, 'FREQ=WEEKLY;BYDAY=TU,TH;COUNT=4');
        s.startEventEdit(uid);
        s.eventDraftFor(uid)!.setRrule(null);
        expect(await s.saveEventDraft(uid), isTrue);
        expect(s.eventById(uid)!.rrule, isNull);
        expect(s.eventById(uid)!.isRecurring, isFalse);
      },
    );

    test(
      'all-day draft shows the last day, an unchanged save keeps it',
      () async {
        final s = await _open(MemoryStorage(), seed: _Seed());
        final uid = (await s.addEvent(
          'Trip',
          start: DateTime.utc(2026, 12, 1),
          end: DateTime.utc(2026, 12, 3),
          allDay: true,
        ))!;
        s.startEventEdit(uid);
        final d = s.eventDraftFor(uid)!;
        expect(d.allDay, isTrue);
        expect(d.end, DateTime.utc(2026, 12, 3));
        d.locationController.text = 'Alps';
        expect(await s.saveEventDraft(uid), isTrue);
        final e = s.eventById(uid)!;
        expect(e.location, 'Alps');
        expect(e.dtend!.value, '20261204');
      },
    );

    test('read-only: no draft; dirty guard covers the peek and tabs', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final a = (await s.addEvent('A', start: _day))!;
      final b = (await s.addEvent('B', start: _day))!;
      s.select(a);
      s.startEventEdit(a);
      s.eventDraftFor(a)!.titleController.text = 'Changed';
      s.leaveGuard = () async => DraftChoice.keep;
      await s.openNote(b);
      expect(s.peekUid, a);
      s.leaveGuard = () async => DraftChoice.discard;
      await s.openNote(b);
      expect(s.peekUid, b);
      expect(s.eventById(a)!.summary, 'A');
      s.select(a);
      s.startEventEdit(a);
      s.eventDraftFor(a)!.titleController.text = 'Saved';
      s.leaveGuard = () async => DraftChoice.save;
      await s.openNote(b);
      expect(s.eventById(a)!.summary, 'Saved');
      // peek and main tab share the draft
      s.select(a);
      s.startEventEdit(a);
      s.eventDraftFor(a)!.titleController.text = 'Typed';
      s.promote();
      expect(s.mainEventUid, a);
      expect(s.eventDraftFor(a)!.titleController.text, 'Typed');
      expect(s.tabDirty(DocTab.event(a)), isTrue);
      expect(s.tabs.single.code, 'e:$a');
      s.leaveGuard = () async => DraftChoice.keep;
      await s.closeTab(DocTab.event(a));
      expect(s.tabs, isNotEmpty);
      expect(await s.unsyncedInCurrent(), greaterThanOrEqualTo(1));
    });

    test('a dirty draft outlives its deleted event, with a notice', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final a = (await s.addEvent('A', start: _day))!;
      final b = (await s.addEvent('B', start: _day))!;
      s.startEventEdit(a);
      s.startEventEdit(b);
      s.eventDraftFor(a)!.titleController.text = 'A typed';
      final src = s.source as SpaceNoteSource;
      await src.deleteEvent(a);
      await src.deleteEvent(b);
      await s.addEvent('C', start: _day); // reloads events
      expect(s.eventDraftFor(a), isNotNull); // dirty: kept
      expect(s.eventDraftFor(b), isNull); // clean: dropped
      expect(s.orphanDraftNotice, contains('deleted elsewhere'));
      expect(await s.saveEventDraft(a), isFalse);
      s.discardOrphanDrafts();
      expect(s.eventDraftFor(a), isNull);
      expect(s.orphanDraftNotice, isNull);
    });

    test('saving the draft of a deleted event says why and keeps it', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final a = (await s.addEvent('A', start: _day))!;
      s.startEventEdit(a);
      final d = s.eventDraftFor(a)!;
      d.titleController.text = 'Typed';
      final src = s.source as SpaceNoteSource;
      await src.deleteEvent(a);
      await s.addEvent('C', start: _day); // reloads events
      expect(s.error, isNull);
      expect(await s.saveEventDraft(a), isFalse);
      expect(s.error, contains('deleted elsewhere'));
      expect(s.eventDraftFor(a), same(d), reason: 'the text is kept');
      expect(d.titleController.text, 'Typed');
      expect(d.dirty, isTrue);
    });

    test('a read-only feed gives no draft', () async {
      final s = AppState(_ReadOnly());
      await s.load();
      s.startEventEdit('x');
      expect(s.eventDraftFor('x'), isNull);
    });
  });

  group('tabs', () {
    test('an event tab persists and is pruned with its event', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      final uid = (await s.addEvent('E', start: _day))!;
      s.setOpenMode(OpenMode.main);
      await s.openEvent(uid);
      expect(s.mainEventUid, uid);
      expect(s.mainIsPage, isTrue);
      expect(s.tabTitle(DocTab.event(uid)), 'E');
      final again = await _open(m);
      expect(again.tabs.map((t) => t.code), ['e:$uid']);
      await s.deleteEvent(uid);
      expect(s.tabs, isEmpty);
      expect(s.mainEventUid, isNull);
    });
  });

  group('sync', () {
    test('events sync with notes and tasks in one pass', () async {
      final server = FakeCalDav();
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed(), client: server.client);
      await s.addEvent('Local event', start: _day);
      server.external(
        're.ics',
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\n'
            'BEGIN:VEVENT\r\nUID:re\r\nDTSTAMP:20261119T000000Z\r\n'
            'DTSTART:20261201T090000Z\r\nDTEND:20261201T100000Z\r\n'
            'SUMMARY:Remote event\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n',
      );
      await s.connect('c/', 'tm', 'pw');
      expect(s.syncMessage, startsWith('Synced'));
      expect(s.eventError, isNull);
      expect(s.events.map((e) => e.summary).toSet(), {
        'Local event',
        'Remote event',
      });
      expect(
        server.ics.values.where((v) => v.contains('BEGIN:VEVENT')),
        hasLength(2),
      );
      expect(
        server.ics.values.where((v) => v.contains('BEGIN:VJOURNAL')),
        hasLength(1),
      );
      final uid = s.events.firstWhere((e) => e.summary == 'Local event').uid;
      await s.updateEvent(uid, title: 'Renamed');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        server.ics.values.any((v) => v.contains('SUMMARY:Renamed')),
        isTrue,
      );
      await s.deleteEvent('re');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.ics.containsKey('re.ics'), isFalse);
      expect(await (s.source as SpaceNoteSource).unsyncedCount(), 0);
    });

    test('an event sync failure is non-fatal and notes are not lost', () async {
      final server = FakeCalDav();
      var failEvents = false;
      var passes = 0;
      final client = MockClient((r) async {
        if (r.method == 'REPORT' && r.body.contains('sync-collection')) {
          passes++;
          // each pass pulls notes, then tasks, then events
          if (failEvents && passes % 3 == 0) {
            throw http.ClientException('boom');
          }
        }
        return server.respond(r);
      });
      final s = await _open(MemoryStorage(), seed: _Seed(), client: client);
      await s.connect('c/', 'tm', 'pw');
      expect(s.eventError, isNull);
      failEvents = true;
      await s.addNote('Fresh note');
      await s.addTask('Kept task');
      await s.addEvent('Kept event', start: _day);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await s.sync();
      expect(s.eventError, contains('Calendar'));
      expect(s.syncMessage, contains('Calendar'));
      expect(s.syncMessage, startsWith('Synced'));
      expect(s.error, isNull);
      expect(s.taskError, isNull);
      expect(s.notes.map((n) => n.summary), contains('Fresh note'));
      expect(s.tasks.map((t) => t.summary), contains('Kept task'));
      expect(s.events.map((e) => e.summary), contains('Kept event'));
      expect(
        server.ics.values.any((v) => v.contains('SUMMARY:Fresh note')),
        isTrue,
      );
      expect(
        server.ics.values.any((v) => v.contains('SUMMARY:Kept task')),
        isTrue,
      );
      failEvents = false;
      await s.sync();
      expect(s.eventError, isNull);
      expect(
        server.ics.values.any((v) => v.contains('SUMMARY:Kept event')),
        isTrue,
      );
    });

    test(
      'an event push the server refuses is reported, the event stays',
      () async {
        final server = FakeCalDav();
        final client = MockClient((r) async {
          if (r.method == 'PUT' && r.body.contains('BEGIN:VEVENT')) {
            return http.Response('no', 403);
          }
          return server.respond(r);
        });
        final s = await _open(MemoryStorage(), seed: _Seed(), client: client);
        await s.connect('c/', 'tm', 'pw');
        await s.addEvent('Refused', start: _day);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(s.eventError, isNotNull);
        expect(s.events.map((e) => e.summary), ['Refused']);
        expect(s.error, isNull);
      },
    );

    test('disconnect keeps events locally; reconnect sends them', () async {
      final server = FakeCalDav();
      final s = await _open(
        MemoryStorage(),
        seed: _Seed(),
        client: server.client,
      );
      await s.connect('c/', 'tm', 'pw');
      await s.addEvent('E', start: _day);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await s.disconnect();
      expect(s.events.map((e) => e.summary), ['E']);
      await s.addEvent('Offline', start: _day);
      await s.connect('c/', 'tm', 'pw');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        server.ics.values.where((v) => v.contains('BEGIN:VEVENT')),
        hasLength(2),
      );
    });
  });

  group('search and moves', () {
    test('search covers every Space with allSpaces, location too', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      await s.addEvent('Lunch with Anna', start: _day, location: 'Cafe Milk');
      await s.createSpace('Other');
      await s.addEvent('Review', start: _day, description: 'about MILK');
      final hits = await s.searchAllSpaces('milk', allSpaces: true);
      expect(hits.map((h) => h.isEvent), [true, true]);
      expect(hits.map((h) => h.isTask), [false, false]);
      expect(hits.map((h) => h.event!.summary).toSet(), {
        'Lunch with Anna',
        'Review',
      });
      expect(hits.first.note.uid, hits.first.event!.uid);
      expect(
        (await s.searchAllSpaces('alpha', allSpaces: true)).single.isEvent,
        isFalse,
      );
      final far = hits.firstWhere((h) => h.space.id == SpaceCatalog.planningId);
      await s.openHit(far);
      expect(s.currentSpaceId, SpaceCatalog.planningId);
      expect(s.peekUid, far.event!.uid);
      expect(s.peekEvent!.summary, 'Lunch with Anna');
      s.setOpenMode(OpenMode.main);
      final here = (await s.searchAllSpaces('anna')).single;
      await s.openHit(here);
      expect(s.mainEventUid, far.event!.uid);
    });

    test('moveToSpace moves an event with new id and tasks under it', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      final from = s.currentSpaceId!;
      final ev = (await s.addEvent(
        'Mover',
        start: DateTime.utc(2026, 12, 1, 9),
        end: DateTime.utc(2026, 12, 1, 10),
        location: 'Here',
        tags: ['x'],
      ))!;
      final t = (await s.addTask('Child', parentUid: ev))!;
      await s.createSpace('Other');
      final other = s.currentSpaceId!;
      await s.switchSpace(from);
      expect(await s.moveToSpace(ev, other), 2);
      expect(s.events, isEmpty);
      expect(s.taskById(t), isNull);
      await s.switchSpace(other);
      final moved = s.events.single;
      expect(moved.uid, isNot(ev));
      expect(moved.summary, 'Mover');
      expect(moved.location, 'Here');
      expect(moved.categories, ['x']);
      expect(moved.dtstart!.value, '20261201T020000Z');
      expect(moved.dtend!.value, '20261201T030000Z');
      expect(s.tasks.single.parentUid, moved.uid);
      expect(await s.moveToSpace(moved.uid, other), isNull); // same Space
      expect(await s.moveToSpace('nope', from), isNull);
    });

    test('a series with changed occurrences is not moved', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final from = s.currentSpaceId!;
      final src = s.source as SpaceNoteSource;
      await src.saveEvent(parseEvent(_recurringWithOverride));
      await s.load();
      await s.createSpace('Other');
      final other = s.currentSpaceId!;
      await s.switchSpace(from);
      expect(await s.moveToSpace('r1', other), isNull);
      expect(s.error, contains('cannot be moved'));
      expect(s.eventById('r1'), isNotNull);
    });
  });

  group('UTC events and series edits', () {
    DateTime local(DateTime u) {
      final l = u.toLocal();
      return DateTime.utc(l.year, l.month, l.day, l.hour, l.minute);
    }

    test('a UTC event is grouped, shown and edited in local time', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final src = s.source as SpaceNoteSource;
      await src.saveEvent(
        _e('u', start: '20261120T090000Z', end: '20261120T100000Z'),
      );
      await s.load();
      final e = s.eventById('u')!;
      expect(e.startWall, local(DateTime.utc(2026, 11, 20, 9)));
      expect(eventWhen(e), contains(timeLabel(e.startWall!)));
      // 'now' at the event's local midnight: it is Today.
      final day = DateTime(
        e.startWall!.year,
        e.startWall!.month,
        e.startWall!.day,
      );
      final g = s.upcomingOccurrences(day, 7);
      expect(g.first.id, 'today');
      // Editing writes back UTC: the draft holds local wall time.
      s.startEventEdit('u');
      expect(s.eventDraftFor('u')!.start, e.startWall);
      final ns = e.startWall!.add(const Duration(hours: 1));
      expect(
        await s.updateEvent(
          'u',
          setWhen: true,
          start: ns,
          end: ns.add(const Duration(hours: 2)),
        ),
        isTrue,
      );
      final w = s.eventById('u')!;
      expect(w.dtstart!.isUtc, isTrue);
      expect(w.dtend!.isUtc, isTrue);
      expect(w.dtstart!.value, '20261120T100000Z');
      expect(w.dtend!.value, '20261120T120000Z');
    });

    test('changing the start shifts EXDATE, RDATE and overrides', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final src = s.source as SpaceNoteSource;
      await src.saveEvent(parseEvent(_recurringWithOverride));
      await s.load();
      expect(
        await s.updateEvent(
          'r1',
          setWhen: true,
          start: DateTime.utc(2026, 11, 20, 10),
          end: DateTime.utc(2026, 11, 20, 11),
        ),
        isTrue,
      );
      final e = s.eventById('r1')!;
      expect(e.dtstart!.value, '20261120T100000');
      expect(e.exdates.single, 'EXDATE:20261121T100000');
      expect(e.siblingLines, contains('RECURRENCE-ID:20261122T100000'));
      expect(e.siblingLines, contains('DTSTART:20261122T120000'));
      expect(e.siblingLines, contains('DTEND:20261122T130000'));
      final o = e.occurrences(
        DateTime.utc(2026, 11, 20),
        DateTime.utc(2026, 11, 24),
      );
      expect(
        [for (final x in o) '${x.start.day} ${x.start.hour} ${x.isOverride}'],
        ['20 10 false', '22 12 true'],
      );
      // The moved instance keeps its length.
      expect(o.last.end, DateTime.utc(2026, 11, 22, 13));
    });

    test('all day to timed is refused for a series with exdates', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final src = s.source as SpaceNoteSource;
      await src.saveEvent(parseEvent(_recurringWithOverride));
      await s.load();
      expect(
        await s.updateEvent(
          'r1',
          setWhen: true,
          allDay: true,
          start: DateTime.utc(2026, 11, 20),
        ),
        isFalse,
      );
      expect(s.error, contains('all day'));
      expect(s.eventById('r1')!.dtstart!.value, '20261120T090000');
    });

    test('row keys stay unique when an override lands on another day', () {
      final v = parseEvent(
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'
        'BEGIN:VEVENT\r\nUID:k\r\nDTSTAMP:20261119T000000Z\r\n'
        'DTSTART:20261120T090000\r\nRRULE:FREQ=DAILY;COUNT=3\r\nSUMMARY:K\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nUID:k\r\nRECURRENCE-ID:20261121T090000\r\n'
        'DTSTAMP:20261119T000000Z\r\nDTSTART:20261122T140000\r\nSUMMARY:K2\r\nEND:VEVENT\r\n'
        'END:VCALENDAR\r\n',
      );
      final o = v.occurrences(
        DateTime.utc(2026, 11, 20),
        DateTime.utc(2026, 11, 24),
      );
      expect(o, hasLength(3));
      final keys = {for (final x in o) eventRowKey(x)};
      expect(keys, hasLength(3));
    });
  });
}
