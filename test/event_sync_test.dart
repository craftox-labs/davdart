import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'event_test.dart' show google;
import 'support/fake_caldav.dart';
import 'task_sync_test.dart' show tics;
import 'task_test.dart' show nextcloud;

String eics(String uid, String summary, {String extra = ''}) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:$uid\r\n'
    'DTSTAMP:20261101T080000Z\r\nSUMMARY:$summary\r\n'
    'DTSTART:20261201T090000Z\r\n$extra'
    'END:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
  late FakeCalDav server;
  late DateTime clock;

  CalDavClient client({void Function(String?, Object)? onError}) =>
      CalDavClient(
        collection: FakeCalDav.collection,
        username: 'u',
        password: 'p',
        client: server.client,
        onResourceError: onError,
      );
  DateTime tick() => clock = clock.add(const Duration(minutes: 1));
  EventSyncEngine eengine(EventStore s) =>
      EventSyncEngine(client(), s, now: tick);
  TaskSyncEngine tengine(TaskStore s) => TaskSyncEngine(client(), s, now: tick);
  SyncEngine nengine(NoteStore s) => SyncEngine(client(), s, now: tick);

  setUp(() {
    server = FakeCalDav();
    clock = DateTime.utc(2026, 11, 20, 12);
  });

  group('merge', () {
    final base = Event(
      uid: 'm',
      summary: 'Base',
      location: 'Here',
      description: 'a\nb\nc',
      dtstart: ICalDate('20261201T090000Z'),
      categories: ['x'],
      lastModified: DateTime.utc(2026, 11, 1),
    );

    test('independent field edits combine', () {
      final l = base.copyWith(
        dtend: ICalDate('20261201T100000Z'),
        description: 'A\nb\nc',
        categories: ['x', 'l'],
        lastModified: DateTime.utc(2026, 11, 2),
      );
      final r = base.copyWith(
        location: 'There',
        description: 'a\nb\nC',
        categories: ['x', 'r'],
        lastModified: DateTime.utc(2026, 11, 3),
      );
      final m = mergeEvents(base, l, r);
      expect(m.hadConflict, isFalse);
      expect(m.event.dtend, ICalDate('20261201T100000Z'));
      expect(m.event.location, 'There');
      expect(m.event.description, 'A\nb\nC');
      expect(m.event.categories.toSet(), {'x', 'l', 'r'});
    });

    test('same field changed twice: later edit wins, loser reported', () {
      final l = base.copyWith(
        dtstart: ICalDate('20261202T090000Z'),
        lastModified: DateTime.utc(2026, 11, 5),
      );
      final r = base.copyWith(
        dtstart: ICalDate('20261203T090000Z'),
        lastModified: DateTime.utc(2026, 11, 4),
      );
      final m = mergeEvents(base, l, r);
      expect(m.event.dtstart!.value, '20261202T090000Z');
      expect(m.conflicts.single.what, 'start');
      expect(m.conflicts.single.remote, contains('20261203'));
    });

    test('exdates, overrides and unknown lines: the changing side wins', () {
      final r = base.copyWith(lastModified: DateTime.utc(2026, 11, 3));
      r.extraLines.add('X-FOO:1');
      r.siblingLines.addAll(['BEGIN:VEVENT', 'END:VEVENT']);
      final l = base.copyWith(
        summary: 'L',
        exdates: ['EXDATE:20261208T090000Z'],
        lastModified: DateTime.utc(2026, 11, 2),
      );
      final m = mergeEvents(base, l, r);
      expect(m.event.extraLines, ['X-FOO:1']);
      expect(m.event.siblingLines, hasLength(2));
      expect(m.event.exdates, ['EXDATE:20261208T090000Z']);
      expect(m.event.summary, 'L');
    });
  });

  group('client', () {
    test('listEvents asks for VEVENT and returns events only', () async {
      server.external('n.ics', serializeNote(Note(uid: 'n', summary: 'N')));
      server.external('t.ics', tics('t', 'T'));
      server.external('e.ics', eics('e', 'E'));
      final c = client();
      final events = await c.listEvents();
      expect(events.map((x) => x.uid), ['e']);
      expect(events.single.href, '/dav/c/e.ics');
      expect((await c.listNotes()).map((n) => n.uid), ['n']);
      expect((await c.listTasks()).map((t) => t.uid), ['t']);
    });

    test('put, get, conflict, delete', () async {
      final c = client();
      final stored = await c.putEvent(
        Event(uid: 'a', summary: 'A', dtstart: ICalDate('20261201T090000Z')),
      );
      expect(server.ics['a.ics'], contains('BEGIN:VEVENT'));
      expect(stored.etag, isNotNull);
      expect((await c.getEvent('a.ics')).summary, 'A');
      server.external('a.ics', eics('a', 'Other'));
      stored.summary = 'Mine';
      expect(() => c.putEvent(stored), throwsA(isA<ConflictException>()));
      await c.deleteEvent(await c.getEvent('a.ics'));
      expect(server.ics, isEmpty);
    });

    test(
      'syncEvents, syncTasks and sync each keep their own component',
      () async {
        server.external('n.ics', serializeNote(Note(uid: 'n', summary: 'N')));
        server.external('t.ics', tics('t', 'T'));
        server.external('e.ics', eics('e', 'E'));
        server.external('g.ics', google);
        final skipped = <String?>[];
        final c = client(onError: (h, e) => skipped.add(h));
        expect((await c.syncEvents()).changed.map((x) => x.uid).toSet(), {
          'e',
          'e-1',
        });
        expect((await c.syncTasks()).changed.map((x) => x.uid), ['t']);
        expect((await c.sync()).changed.map((x) => x.uid), ['n']);
        expect(skipped, isEmpty);
      },
    );

    test('a task resource without VEVENT is skipped, not an error', () async {
      server.external('t.ics', nextcloud);
      final skipped = <String?>[];
      final r = await client(onError: (h, e) => skipped.add(h)).syncEvents();
      expect(r.changed, isEmpty);
      expect(r.unparsableHrefs, isEmpty);
      expect(skipped, isEmpty);
    });

    test('discover reports holdsEvents from the component set', () async {
      String resp(String name, List<String> comps) =>
          '<d:response><d:href>/dav/u/$name/</d:href><d:propstat><d:prop>'
          '<d:displayname>$name</d:displayname><d:resourcetype><d:collection/>'
          '<c:calendar/></d:resourcetype><c:supported-calendar-component-set>'
          '${[for (final c in comps) '<c:comp name="$c"/>'].join()}'
          '</c:supported-calendar-component-set></d:prop>'
          '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';
      final mock = MockClient(
        (r) async => http.Response(
          '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
          '${resp('all', ['VJOURNAL', 'VTODO', 'VEVENT'])}'
          '${resp('notes', ['VJOURNAL'])}'
          '${resp('cal', ['VEVENT'])}</d:multistatus>',
          207,
        ),
      );
      final found = await CalDavClient.discover(
        Uri.parse('https://h/dav/u/'),
        username: 'u',
        password: 'p',
        client: mock,
      );
      expect(found.map((c) => c.holdsEvents), [true, false, true]);
      expect(found.map((c) => c.holdsNotes), [true, true, false]);
    });
  });

  group('engine', () {
    test('pulls events, pushes an edit, ignores notes and tasks', () async {
      server.external('n.ics', serializeNote(Note(uid: 'n', summary: 'N')));
      server.external('t.ics', tics('t', 'T'));
      server.external('g.ics', google);
      final e = eengine(MemoryEventStore());
      expect((await e.sync()).pulled, 1);
      final ev = (await e.events()).single;
      ev.summary = 'Renamed';
      ev.location = 'Elsewhere';
      await e.save(ev);
      expect((await e.sync()).pushed, 1);
      final body = server.ics['g.ics']!;
      expect(body, contains('SUMMARY:Renamed'));
      expect(body, contains('BEGIN:VALARM'));
      expect(body, contains('X-FOO;X-P=1:bar'));
      expect(
        body,
        contains('RECURRENCE-ID;TZID=Europe/Berlin:20261130T093000'),
      );
      expect(body, contains('BEGIN:VTIMEZONE'));
      expect(server.ics['n.ics'], contains('BEGIN:VJOURNAL'));
      expect(server.ics['t.ics'], tics('t', 'T'));
      final r2 = await e.sync();
      expect(r2.pulled + r2.pushed + r2.merged, 0);
    });

    test(
      'notes, tasks and events share a collection without interfering',
      () async {
        server.external('t.ics', tics('t', 'T'));
        server.external('e.ics', eics('e', 'E'));
        final ns = MemoryNoteStore(),
            ts = MemoryTaskStore(),
            es = MemoryEventStore();
        final ne = nengine(ns), te = tengine(ts), ee = eengine(es);
        await ne.save(Note(uid: 'n', summary: 'N'));
        await te.save(Task(uid: 'tn', summary: 'New'));
        await ee.save(
          Event(
            uid: 'en',
            summary: 'New',
            dtstart: ICalDate('20261201T090000Z'),
          ),
        );
        for (var i = 0; i < 2; i++) {
          await ne.sync();
          await te.sync();
          await ee.sync();
        }
        expect((await ne.notes()).map((n) => n.uid), ['n']);
        expect((await te.tasks()).map((n) => n.uid).toSet(), {'t', 'tn'});
        expect((await ee.events()).map((n) => n.uid).toSet(), {'e', 'en'});
        expect(server.ics['e.ics'], eics('e', 'E'));
      },
    );

    test('remote delete, local delete', () async {
      server.external('a.ics', eics('a', 'A'));
      server.external('b.ics', eics('b', 'B'));
      final e = eengine(MemoryEventStore());
      await e.sync();
      server.externalDelete('a.ics');
      await e.delete('b');
      expect((await e.sync()).deleted, 1);
      expect(await e.events(), isEmpty);
      expect(server.ics, isEmpty);
    });

    test(
      'overlapping edits merge field by field; conflict kept as revision',
      () async {
        server.external('a.ics', eics('a', 'A', extra: 'LOCATION:One\r\n'));
        final s = MemoryEventStore();
        final e = eengine(s);
        await e.sync();
        await e.save((await e.events()).single..summary = 'Local title');
        server.external(
          'a.ics',
          eics('a', 'Remote title', extra: 'LOCATION:Two\r\n'),
        );
        final r = await e.sync();
        expect(r.merged, 1);
        expect(r.conflicts.single.what, 'title');
        final got = (await e.events()).single;
        expect(got.location, 'Two');
        expect(got.summary, 'Local title');
        expect(server.ics['a.ics'], contains('SUMMARY:Local title'));
        expect((await s.revisions('a')), hasLength(1));
      },
    );

    test('store survives toJson and loadJson', () async {
      server.external('g.ics', google);
      final s = MemoryEventStore();
      await eengine(s).sync();
      final s2 = MemoryEventStore()..loadJson(s.toJson());
      final e = (await s2.get('e-1'))!;
      expect(e.local.rrule, 'FREQ=WEEKLY;BYDAY=MO,WE');
      expect(e.local.exdates, hasLength(1));
      expect(e.local.extraLines, contains('BEGIN:VALARM'));
      expect(e.local.siblingLines, isNotEmpty);
      expect(e.local.etag, isNotNull);
    });

    test('token rejected falls back to a full sync', () async {
      server.external('a.ics', eics('a', 'A'));
      final e = eengine(MemoryEventStore());
      await e.sync();
      server.rejectTokens = true;
      server.external('b.ics', eics('b', 'B'));
      await e.sync();
      expect((await e.events()).length, 2);
    });

    test(
      'unparsable server copy: clean local event survives a full sync',
      () async {
        server.external('a.ics', eics('a', 'A'));
        final e = eengine(MemoryEventStore());
        await e.sync();
        server.external(
          'a.ics',
          'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:x\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n',
        );
        server.rejectTokens = true;
        final r = await e.sync();
        expect((await e.events()).single.summary, 'A');
        expect(r.errors.single, contains('a.ics'));
      },
    );
  });
}
