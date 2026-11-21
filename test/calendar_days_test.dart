import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

DateTime u(int y, int m, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, m, d, h, mi);

String hm(DateTime d) =>
    '${d.month}-${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

void main() {
  tearDown(() => LocalZone.use(null));

  group('recurrence across daylight saving', () {
    // Berlin leaves DST on 2026-10-25 (02:00 CEST -> 01:00... CET).
    final berlin = Event(
      uid: 'b',
      dtstart: const ICalDate('20261023T090000', ';TZID=Europe/Berlin'),
      dtend: const ICalDate('20261023T100000', ';TZID=Europe/Berlin'),
      rrule: 'FREQ=DAILY;COUNT=5',
    );

    test('TZID series keeps its own wall time; viewer sees the shift', () {
      LocalZone.use('Europe/Berlin');
      var o = occurrencesBetween(berlin, u(2026, 10, 1), u(2026, 12, 1));
      expect([
        for (final x in o) hm(x.start)
      ], [
        '10-23 9:00',
        '10-24 9:00',
        '10-25 9:00',
        '10-26 9:00',
        '10-27 9:00'
      ]);
      // Bangkok has no DST: 07:00 local before the change, 08:00 after.
      LocalZone.use('Asia/Bangkok');
      o = occurrencesBetween(berlin, u(2026, 10, 1), u(2026, 12, 1));
      expect([
        for (final x in o) hm(x.start)
      ], [
        '10-23 14:00',
        '10-24 14:00',
        '10-25 15:00',
        '10-26 15:00',
        '10-27 15:00'
      ]);
    });

    test('Z series keeps its UTC time; a DST viewer sees the shift', () {
      final z = Event(
        uid: 'z',
        dtstart: const ICalDate('20261023T090000Z'),
        dtend: const ICalDate('20261023T100000Z'),
        rrule: 'FREQ=DAILY;COUNT=5',
      );
      LocalZone.use('Europe/Berlin');
      final o = occurrencesBetween(z, u(2026, 10, 1), u(2026, 12, 1));
      expect([
        for (final x in o) hm(x.start)
      ], [
        '10-23 11:00',
        '10-24 11:00',
        '10-25 10:00',
        '10-26 10:00',
        '10-27 10:00'
      ]);
      LocalZone.use('Asia/Bangkok');
      expect([
        for (final x in occurrencesBetween(z, u(2026, 10, 1), u(2026, 12, 1)))
          hm(x.start)
      ], [
        '10-23 16:00',
        '10-24 16:00',
        '10-25 16:00',
        '10-26 16:00',
        '10-27 16:00'
      ]);
    });

    test('window is the viewer day: late zoned instance moves a day', () {
      final late = Event(
        uid: 'l',
        dtstart: const ICalDate('20261120T230000', ';TZID=America/New_York'),
        rrule: 'FREQ=DAILY;COUNT=3',
      );
      LocalZone.use('Asia/Bangkok'); // 11:00 next day
      final o = occurrencesBetween(late, u(2026, 11, 21), u(2026, 11, 22));
      expect([for (final x in o) hm(x.start)], ['11-21 11:00']);
    });

    test('UNTIL as a UTC instant ends a TZID series by real time', () {
      final e = Event(
        uid: 'u',
        dtstart: const ICalDate('20261120T090000', ';TZID=Europe/Berlin'),
        rrule: 'FREQ=DAILY;UNTIL=20261122T080000Z', // 09:00 CET on the 22nd
      );
      LocalZone.use('Europe/Berlin');
      expect(occurrencesBetween(e, u(2026, 11, 1), u(2026, 12, 1)).length, 3);
    });
  });

  group('day buckets', () {
    test('events and tasks per viewer day, recurring tasks expanded', () {
      final events = [
        Event(
            uid: 'e1',
            summary: 'late',
            dtstart:
                const ICalDate('20261125T230000', ';TZID=America/New_York'),
            dtend: const ICalDate('20261126T000000', ';TZID=America/New_York')),
        Event(
            uid: 'e2',
            summary: 'trip',
            dtstart: ICalDate.date(2026, 11, 10),
            dtend: ICalDate.date(2026, 11, 13)),
      ];
      final tasks = [
        Task(
            uid: 't1',
            summary: 'weekly',
            due: const ICalDate('20261102T030000Z'),
            rrule: 'FREQ=WEEKLY;COUNT=3'),
        Task(uid: 't2', summary: 'once', due: ICalDate.date(2026, 11, 25)),
        Task(
            uid: 't3',
            summary: 'done',
            due: ICalDate.date(2026, 11, 25),
            status: 'COMPLETED'),
        Task(uid: 't4', summary: 'undated'),
      ];
      Map<DateTime, DayBucket> run() => bucketByDay(
          events: events,
          tasks: tasks,
          from: u(2026, 11, 1),
          to: u(2026, 12, 1));

      LocalZone.use(
          'Asia/Bangkok'); // late event: 26th 04:00Z -> 11:00 on the 26th
      var b = run();
      expect(b[u(2026, 11, 26)]!.events.single.summary, 'late');
      expect(b[u(2026, 11, 25)]!.events, isEmpty);
      expect(b[u(2026, 11, 25)]!.tasks.map((t) => t.task.uid), ['t2']);
      expect([
        for (final d in [2, 9, 16]) b[u(2026, 11, d)]!.tasks.length
      ], [
        1,
        1,
        1
      ]);
      expect(b.containsKey(u(2026, 11, 23)), isFalse);
      expect([
        for (final d in [10, 11, 12]) b[u(2026, 11, d)]!.events.length
      ], [
        1,
        1,
        1
      ]);
      expect(b.containsKey(u(2026, 11, 13)), isFalse);

      LocalZone.use('America/Los_Angeles'); // 25th 20:00
      b = run();
      expect(b[u(2026, 11, 25)]!.events.single.summary, 'late');
      expect(b[u(2026, 11, 26)], isNull);
      // 03:00Z Monday is Sunday 19:00 in Los Angeles.
      expect(b[u(2026, 11, 1)]!.tasks.single.task.uid, 't1');
    });

    test('window clips and spans', () {
      final trip = Event(
          uid: 'e2',
          dtstart: ICalDate.date(2026, 11, 28),
          dtend: ICalDate.date(2026, 12, 3));
      final b =
          bucketByDay(events: [trip], from: u(2026, 12, 1), to: u(2026, 12, 3));
      expect(b.keys.toList()..sort(), [u(2026, 12, 1), u(2026, 12, 2)]);
    });
  });
}
