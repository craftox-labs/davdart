import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

const google = '''BEGIN:VCALENDAR\r
VERSION:2.0\r
PRODID:-//Google Inc//Google Calendar 70.9054//EN\r
BEGIN:VTIMEZONE\r
TZID:Europe/Berlin\r
BEGIN:STANDARD\r
DTSTART:19701025T030000\r
TZOFFSETFROM:+0200\r
TZOFFSETTO:+0100\r
END:STANDARD\r
END:VTIMEZONE\r
X-WR-CALNAME:Work\r
BEGIN:VEVENT\r
UID:e-1\r
DTSTAMP:20261105T101500Z\r
CREATED:20261101T080000Z\r
LAST-MODIFIED:20261105T101500Z\r
SUMMARY:Standup\\, daily\r
DESCRIPTION:Line one\\nLine two\r
LOCATION:Room 4\\; floor 2\r
STATUS:CONFIRMED\r
DTSTART;TZID=Europe/Berlin:20261123T093000\r
DTEND;TZID=Europe/Berlin:20261123T100000\r
RRULE:FREQ=WEEKLY;BYDAY=MO,WE\r
EXDATE;TZID=Europe/Berlin:20261125T093000\r
CATEGORIES:work,team\r
RELATED-TO:parent-9\r
TRANSP:OPAQUE\r
X-FOO;X-P=1:bar\r
BEGIN:VALARM\r
ACTION:DISPLAY\r
TRIGGER:-PT10M\r
DESCRIPTION:Soon\r
END:VALARM\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:e-1\r
DTSTAMP:20261105T101500Z\r
RECURRENCE-ID;TZID=Europe/Berlin:20261130T093000\r
SUMMARY:Standup (moved)\r
DTSTART;TZID=Europe/Berlin:20261130T140000\r
DTEND;TZID=Europe/Berlin:20261130T143000\r
END:VEVENT\r
END:VCALENDAR\r
''';

String ev(String body, {String uid = 'x'}) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:$uid\r\n'
    'DTSTAMP:20261101T080000Z\r\n$body'
    'END:VEVENT\r\nEND:VCALENDAR\r\n';

Event e(String start, String rule, {String extra = ''}) =>
    parseEvent(ev('DTSTART:$start\r\n${rule.isEmpty ? '' : 'RRULE:$rule\r\n'}'
        '$extra'));

List<String> days(Event ev, DateTime from, DateTime to) => [
      for (final o in occurrencesBetween(ev, from, to))
        '${o.start.month}-${o.start.day}'
    ];

void main() {
  group('model', () {
    test('parses a Google-style event', () {
      final v = parseEvent(google);
      expect(v.uid, 'e-1');
      expect(v.summary, 'Standup, daily');
      expect(v.description, 'Line one\nLine two');
      expect(v.location, 'Room 4; floor 2');
      expect(v.status, 'CONFIRMED');
      expect(v.dtstart!.tzid, 'Europe/Berlin');
      expect(v.dtend!.value, '20261123T100000');
      expect(v.length, const Duration(minutes: 30));
      expect(v.rrule, 'FREQ=WEEKLY;BYDAY=MO,WE');
      expect(v.exdates, hasLength(1));
      expect(v.categories, ['work', 'team']);
      expect(v.parentUid, 'parent-9');
      expect(v.extraLines, contains('BEGIN:VALARM'));
      expect(v.extraLines, contains('TRANSP:OPAQUE'));
      expect(v.siblingLines,
          contains('RECURRENCE-ID;TZID=Europe/Berlin:20261130T093000'));
      expect(v.calendarLines, contains('BEGIN:VTIMEZONE'));
      expect(v.calendarLines, contains('X-WR-CALNAME:Work'));
      expect(v.isRecurring, isTrue);
    });

    test('round trip keeps every line', () {
      final once = serializeEvent(parseEvent(google));
      final twice = serializeEvent(parseEvent(once));
      expect(twice, once);
      for (final l in [
        'BEGIN:VALARM',
        'X-FOO;X-P=1:bar',
        'EXDATE;TZID=Europe/Berlin:20261125T093000',
        'RECURRENCE-ID;TZID=Europe/Berlin:20261130T093000',
        'BEGIN:VTIMEZONE',
        'DTSTART;TZID=Europe/Berlin:20261123T093000',
        'DTEND;TZID=Europe/Berlin:20261123T100000',
        'LOCATION:Room 4\\; floor 2',
      ]) {
        expect(once, contains(l));
      }
    });

    test('all-day, UTC, duration and copyWith', () {
      final a = parseEvent(
          ev('DTSTART;VALUE=DATE:20261224\r\nDTEND;VALUE=DATE:20261226\r\n'));
      expect(a.allDay, isTrue);
      expect(a.length, const Duration(days: 2));
      final b =
          parseEvent(ev('DTSTART:20261224T100000Z\r\nDURATION:P1DT2H\r\n'));
      expect(b.dtstart!.isUtc, isTrue);
      final l = DateTime.utc(2026, 12, 24, 10).toLocal();
      expect(
          b.endWall,
          DateTime.utc(l.year, l.month, l.day, l.hour)
              .add(const Duration(hours: 26)));
      expect(parseEvent(ev('DTSTART;VALUE=DATE:20261224\r\n')).length,
          const Duration(days: 1));
      final c =
          b.copyWith(summary: 'S', clearDuration: true, rrule: 'FREQ=DAILY');
      expect(c.summary, 'S');
      expect(c.duration, isNull);
      expect(c.rrule, 'FREQ=DAILY');
      expect(c.extraLines, b.extraLines);
      expect(serializeEvent(c), contains('RRULE:FREQ=DAILY'));
    });

    test('parseEvent needs a VEVENT and a UID; types do not mix', () {
      expect(() => parseEvent(serializeNote(Note(uid: 'n'))),
          throwsA(isA<ICalException>()));
      expect(() => parseEvent(ev('X:1\r\n', uid: '')),
          throwsA(isA<ICalException>()));
      expect(() => parseNote(google), throwsA(isA<ICalException>()));
      expect(() => parseTask(google), throwsA(isA<ICalException>()));
      expect(parseEvents(google), hasLength(2));
    });

    test('duration parser', () {
      expect(parseIcalDuration('PT1H30M'), const Duration(minutes: 90));
      expect(parseIcalDuration('P1W'), const Duration(days: 7));
      expect(parseIcalDuration('-PT15M'), const Duration(minutes: -15));
      expect(parseIcalDuration('P'), isNull);
      expect(parseIcalDuration('nope'), isNull);
    });
  });

  group('expansion', () {
    final from = DateTime.utc(2026, 11, 1), to = DateTime.utc(2027, 1, 1);

    test('single event: in and out of the window', () {
      final v = e('20261120T090000Z', '');
      expect(days(v, from, to), ['11-20']);
      expect(days(v, DateTime.utc(2026, 11, 21), to), isEmpty);
      expect(days(v, from, DateTime.utc(2026, 11, 20, 9)), isEmpty);
    });

    test('multi-day all-day event overlaps from the middle', () {
      final v = parseEvent(
          ev('DTSTART;VALUE=DATE:20261124\r\nDTEND;VALUE=DATE:20261127\r\n'));
      expect(days(v, DateTime.utc(2026, 11, 26), DateTime.utc(2026, 11, 27)),
          ['11-24']);
      expect(days(v, DateTime.utc(2026, 11, 27), to), isEmpty);
    });

    test('daily with interval and count', () {
      final v = e('20261120T090000', 'FREQ=DAILY;INTERVAL=3;COUNT=4');
      expect(days(v, from, to), ['11-20', '11-23', '11-26', '11-29']);
    });

    test('daily until (date) is inclusive; until (UTC time) compares time', () {
      expect(days(e('20261120T090000Z', 'FREQ=DAILY;UNTIL=20261122'), from, to),
          ['11-20', '11-21', '11-22']);
      expect(
          days(e('20261120T090000Z', 'FREQ=DAILY;UNTIL=20261122T085959Z'), from,
              to),
          ['11-20', '11-21']);
    });

    test('weekly byday, interval and wkst', () {
      expect(
          days(e('20261123T090000', 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=5'), from,
              to),
          ['11-23', '11-25', '11-30', '12-2', '12-7']);
      // Every other week, starting on a Wednesday: first week has only WE.
      expect(
          days(
              e('20261125T090000',
                  'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=4'),
              from,
              to),
          ['11-25', '12-7', '12-9', '12-21']);
      // WKST=SU moves Sunday to the start of the week.
      expect(
          days(
              e('20261122T090000',
                  'FREQ=WEEKLY;INTERVAL=2;BYDAY=SU,MO;WKST=SU;COUNT=4'),
              from,
              to),
          ['11-22', '11-23', '12-6', '12-7']);
    });

    test('weekly default is the start weekday', () {
      expect(days(e('20261120T090000', 'FREQ=WEEKLY;COUNT=3'), from, to),
          ['11-20', '11-27', '12-4']);
    });

    test('monthly: day 31 skips short months; bymonthday list and negative',
        () {
      final y = DateTime.utc(2027, 6, 1);
      expect(days(e('20270131T090000', 'FREQ=MONTHLY'), DateTime.utc(2027), y),
          ['1-31', '3-31', '5-31']);
      expect(
          days(e('20261101T090000', 'FREQ=MONTHLY;BYMONTHDAY=1,15,-1;COUNT=6'),
              from, DateTime.utc(2028)),
          ['11-1', '11-15', '11-30', '12-1', '12-15', '12-31']);
    });

    test('monthly byday with ordinals (DTSTART counts as the first)', () {
      expect(
          days(e('20261101T090000', 'FREQ=MONTHLY;BYDAY=2TU;COUNT=3'), from,
              DateTime.utc(2028)),
          ['11-1', '11-10', '12-8']);
      expect(
          days(e('20261101T090000', 'FREQ=MONTHLY;BYDAY=-1FR;COUNT=3'), from,
              DateTime.utc(2028)),
          ['11-1', '11-27', '12-25']);
      expect(
          days(e('20261101T090000', 'FREQ=MONTHLY;BYDAY=SA;COUNT=3'), from,
              DateTime.utc(2028)),
          ['11-1', '11-7', '11-14']);
    });

    test('monthly interval across a year end', () {
      expect(
          days(e('20261115T090000', 'FREQ=MONTHLY;INTERVAL=2;COUNT=3'), from,
              DateTime.utc(2028)),
          ['11-15', '1-15', '3-15']);
    });

    test('yearly: leap day, bymonth and bymonthday', () {
      final r = [
        for (final o in occurrencesBetween(e('20240229T090000Z', 'FREQ=YEARLY'),
            DateTime.utc(2024), DateTime.utc(2033)))
          o.start.year
      ];
      expect(r, [2024, 2028, 2032]);
      final y = occurrencesBetween(
          e('20261105T090000Z',
              'FREQ=YEARLY;BYMONTH=3,11;BYMONTHDAY=5;COUNT=3'),
          from,
          DateTime.utc(2030));
      expect([for (final o in y) '${o.start.year}-${o.start.month}'],
          ['2026-11', '2027-3', '2027-11']);
    });

    test('all-day recurrence matches by date, keeps the length', () {
      final v = parseEvent(ev('DTSTART;VALUE=DATE:20261124\r\n'
          'DTEND;VALUE=DATE:20261126\r\nRRULE:FREQ=WEEKLY;COUNT=2\r\n'));
      final o = occurrencesBetween(v, from, to);
      expect(o.map((x) => x.start.day), [24, 1]);
      expect(o.first.end, DateTime.utc(2026, 11, 26));
      expect(o.every((x) => x.allDay), isTrue);
      expect(o.first.recurrenceId!.value, '20261124');
    });

    test('count includes excluded dates', () {
      final v = e('20261120T090000', 'FREQ=DAILY;COUNT=4',
          extra: 'EXDATE:20261121T090000\r\n');
      expect(days(v, from, to), ['11-20', '11-22', '11-23']);
    });

    test('exdate: several values, date-only for an all-day event', () {
      final v = e('20261120T090000', 'FREQ=DAILY;COUNT=5',
          extra: 'EXDATE:20261121T090000,20261122T090000\r\n'
              'EXDATE;VALUE=DATE:20261123\r\n');
      expect(days(v, from, to), ['11-20', '11-24']);
    });

    test('rdate adds instances', () {
      final v = e('20261120T090000', 'FREQ=DAILY;COUNT=2',
          extra: 'RDATE:20261201T090000\r\n');
      expect(days(v, from, to), ['11-20', '11-21', '12-1']);
      final only = e('20261120T090000', '', extra: 'RDATE:20261201T090000\r\n');
      expect(days(only, from, to), ['11-20', '12-1']);
    });

    test('window clips; far-future window needs no count', () {
      final v = e('20261120T090000Z', 'FREQ=DAILY');
      expect(days(v, DateTime.utc(2026, 12, 1), DateTime.utc(2026, 12, 4)),
          ['12-1', '12-2', '12-3']);
      expect(
          occurrencesBetween(v, DateTime.utc(2030), DateTime.utc(2030, 1, 3))
              .length,
          2);
    });

    test('overrides: edited, moved in, moved out and cancelled', () {
      final v = parseEvent(google);
      final o = occurrencesBetween(
          v, DateTime.utc(2026, 11, 23), DateTime.utc(2026, 12, 8));
      expect([
        for (final x in o) '${x.start.month}-${x.start.day} ${x.start.hour}'
      ], [
        '11-23 9',
        '11-30 14',
        '12-2 9',
        '12-7 9'
      ]);
      final moved = o.firstWhere((x) => x.isOverride);
      expect(moved.summary, 'Standup (moved)');
      expect(moved.end, DateTime.utc(2026, 11, 30, 14, 30));
      expect(moved.recurrenceId!.value, '20261130T093000');
      expect(moved.event, same(v));
      // The excluded 25 Nov does not show.
      expect(o.where((x) => x.start.day == 25), isEmpty);
      // Original slot is replaced, not duplicated.
      expect(o.where((x) => x.start.day == 30), hasLength(1));
    });

    test('override moved to a different day outside the original window', () {
      final v = e('20261120T090000', 'FREQ=DAILY;COUNT=3');
      v.siblingLines.addAll([
        'BEGIN:VEVENT',
        'UID:x',
        'RECURRENCE-ID:20261121T090000',
        'DTSTART:20261215T090000',
        'SUMMARY:Later',
        'END:VEVENT',
      ]);
      expect(days(v, from, DateTime.utc(2026, 12, 1)), ['11-20', '11-22']);
      expect(days(v, DateTime.utc(2026, 12, 1), to), ['12-15']);
    });

    test('cancelled override stays visible as cancelled', () {
      final v = e('20261120T090000', 'FREQ=DAILY;COUNT=2');
      v.siblingLines.addAll([
        'BEGIN:VEVENT',
        'UID:x',
        'RECURRENCE-ID:20261121T090000',
        'DTSTART:20261121T090000',
        'STATUS:CANCELLED',
        'END:VEVENT',
      ]);
      final o = occurrencesBetween(v, from, to);
      expect(o.map((x) => x.isCancelled), [false, true]);
    });

    test('unsupported rules return the base occurrence and flag it', () {
      for (final r in [
        'FREQ=HOURLY;COUNT=5',
        'FREQ=MONTHLY;BYDAY=MO;BYSETPOS=1',
        'FREQ=YEARLY;BYDAY=MO',
        'FREQ=WEEKLY;BYMONTH=3',
        'FREQ=DAILY;BYHOUR=9',
        'FREQ=MONTHLY;BYDAY=MO;BYMONTHDAY=1',
        'FREQ=WEEKLY;BYDAY=1MO',
        'COUNT=3',
      ]) {
        final v = e('20261120T090000', r);
        expect(v.recurrenceUnsupported, isTrue, reason: r);
        final o = occurrencesBetween(v, from, to);
        expect(o, hasLength(1), reason: r);
        expect(o.single.unsupported, isTrue);
        expect(o.single.start, DateTime.utc(2026, 11, 20, 9));
      }
      expect(e('20261120T090000', 'FREQ=DAILY').recurrenceUnsupported, isFalse);
      expect(parseEvent(google).recurrenceUnsupported, isFalse);
    });

    test('rdate periods are unsupported', () {
      final v = e('20261120T090000', 'FREQ=DAILY;COUNT=2',
          extra: 'RDATE;VALUE=PERIOD:20261201T090000Z/PT1H\r\n');
      expect(v.recurrenceUnsupported, isTrue);
    });

    test('no start: no occurrences', () {
      expect(occurrencesBetween(Event(uid: 'n'), from, to), isEmpty);
    });
  });

  group('UTC values are shown in the local zone', () {
    DateTime local(DateTime u) {
      final l = u.toLocal();
      return DateTime.utc(l.year, l.month, l.day, l.hour, l.minute);
    }

    test('start, end and expansion use local wall time', () {
      final u = DateTime.utc(2026, 11, 20, 9);
      final v = parseEvent(ev('DTSTART:20261120T090000Z\r\n'
          'DTEND:20261120T100000Z\r\nRRULE:FREQ=DAILY;COUNT=2\r\n'
          'EXDATE:20261121T090000Z\r\n'));
      expect(v.startWall, local(u));
      expect(v.endWall, local(u).add(const Duration(hours: 1)));
      final o = occurrencesBetween(
          v, DateTime.utc(2026, 11, 19), DateTime.utc(2026, 11, 23));
      expect([for (final x in o) x.start], [local(u)]);
      expect(o.single.recurrenceId!.value, '20261120T090000Z');
    });

    test('fromLocalWall inverts localWall and keeps Z, TZID and dates', () {
      const z = ICalDate('20261120T090000Z');
      expect(ICalDate.fromLocalWall(z.localWall!, z).value, z.value);
      const t = ICalDate('20261120T090000', ';TZID=Europe/Berlin');
      expect(t.localWall, t.wall);
      expect(ICalDate.fromLocalWall(t.wall!, t).value, t.value);
      const d = ICalDate('20261120', ';VALUE=DATE');
      expect(d.shifted(const Duration(days: 2)).value, '20261122');
      expect(z.shifted(const Duration(hours: 3)).localWall,
          z.localWall!.add(const Duration(hours: 3)));
    });
  });

  group('DTSTART off the rule pattern', () {
    final from = DateTime.utc(2026, 11, 1), to = DateTime.utc(2027, 1, 1);

    test('weekly: DTSTART is the first instance and counts', () {
      // 2026-11-20 is a Friday, BYDAY=MO.
      expect(
          days(e('20261120T090000', 'FREQ=WEEKLY;BYDAY=MO;COUNT=3'), from, to),
          ['11-20', '11-23', '11-30']);
      expect(
          days(e('20261120T090000', 'FREQ=WEEKLY;BYDAY=MO'), from,
              DateTime.utc(2026, 12, 1)),
          ['11-20', '11-23', '11-30']);
    });

    test('monthly: DTSTART is the first instance and counts', () {
      expect(
          days(e('20261120T090000', 'FREQ=MONTHLY;BYMONTHDAY=5;COUNT=3'), from,
              DateTime.utc(2027, 6, 1)),
          ['11-20', '12-5', '1-5']);
    });

    test('a matching DTSTART is not doubled; until still applies', () {
      expect(
          days(e('20261123T090000', 'FREQ=WEEKLY;BYDAY=MO;COUNT=2'), from, to),
          ['11-23', '11-30']);
      expect(
          days(e('20261120T090000', 'FREQ=WEEKLY;BYDAY=MO;UNTIL=20261119'),
              from, to),
          isEmpty);
    });
  });
}
