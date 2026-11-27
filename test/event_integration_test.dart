import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

/// Live VEVENT round trip, same gating as task_integration_test.dart. Point
/// DAVDART_TEST_URL at the scratch collection davdart-test only.
void main() {
  final env = Platform.environment;
  final url = env['DAVDART_TEST_URL'];
  final segments = url == null || url.isEmpty
      ? const <String>[]
      : Uri.parse(url).pathSegments.where((x) => x.isNotEmpty).toList();
  final skipReason = (url == null || url.isEmpty)
      ? 'DAVDART_TEST_URL not set (live CalDAV integration test)'
      : (segments.isEmpty || segments.last != 'davdart-test')
      ? 'DAVDART_TEST_URL must end with the davdart-test collection; '
            'refusing to write anywhere else'
      : null;

  test(
    'live: events next to notes and tasks in one collection',
    skip: skipReason,
    () async {
      final c = CalDavClient(
        collection: Uri.parse(url!),
        username: env['DAVDART_TEST_USER'] ?? '',
        password: env['DAVDART_TEST_PASSWORD'] ?? '',
      );
      final stamp = DateTime.now().microsecondsSinceEpoch;
      Event? event;
      Task? task;
      Note? note;
      try {
        note = await c.putNote(Note(uid: 'davdart-it-n-$stamp', summary: 'N'));
        task = await c.putTask(Task(uid: 'davdart-it-t-$stamp', summary: 'T'));
        event = await c.putEvent(
          Event(
            uid: 'davdart-it-e-$stamp',
            summary: 'Event, with; chars',
            description: 'one\ntwo',
            location: 'Room 4',
            status: 'CONFIRMED',
            dtstart: ICalDate('20261201T090000', ';TZID=Europe/Berlin'),
            dtend: ICalDate('20261201T100000', ';TZID=Europe/Berlin'),
            rrule: 'FREQ=WEEKLY;BYDAY=TU',
            exdates: ['EXDATE;TZID=Europe/Berlin:20261208T090000'],
            categories: ['a'],
            parentUid: note.uid,
            extraLines: [
              'X-DAVDART-TEST:1',
              'BEGIN:VALARM',
              'ACTION:DISPLAY',
              'TRIGGER:-PT15M',
              'DESCRIPTION:x',
              'END:VALARM',
            ],
          ),
        );
        final got = await c.getEvent(event.href!);
        expect(got.summary, 'Event, with; chars');
        expect(got.location, 'Room 4');
        expect(got.dtstart!.tzid, 'Europe/Berlin');
        expect(got.rrule, 'FREQ=WEEKLY;BYDAY=TU');
        expect(got.exdates, hasLength(1));
        expect(got.parentUid, note.uid);
        expect(got.extraLines, contains('BEGIN:VALARM'));
        expect((await c.listEvents()).map((x) => x.uid), contains(event.uid));
        expect(
          (await c.listEvents()).map((x) => x.uid),
          isNot(contains(task.uid)),
        );
        expect(
          (await c.listNotes()).map((x) => x.uid),
          isNot(contains(event.uid)),
        );
        expect(
          (await c.listTasks()).map((x) => x.uid),
          isNot(contains(event.uid)),
        );
        expect(
          (await c.syncEvents()).changed.map((x) => x.uid),
          contains(event.uid),
        );
        got.summary = 'Renamed';
        event = await c.putEvent(got);
        expect((await c.getEvent(event.href!)).summary, 'Renamed');
        expect(() => c.putEvent(got), throwsA(isA<ConflictException>()));
      } finally {
        if (event != null) await c.deleteEvent(event);
        if (task != null) await c.deleteTask(task);
        if (note != null) await c.deleteNote(note);
        c.close();
      }
    },
  );
}
