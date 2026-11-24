import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

const nextcloud = '''BEGIN:VCALENDAR\r
VERSION:2.0\r
PRODID:-//Nextcloud Tasks//EN\r
BEGIN:VTODO\r
UID:t-1\r
CREATED:20261101T080000Z\r
LAST-MODIFIED:20261105T101500Z\r
DTSTAMP:20261105T101500Z\r
SUMMARY:Pay rent\\, flat 4\r
DESCRIPTION:Line one\\nLine two\r
STATUS:NEEDS-ACTION\r
PERCENT-COMPLETE:40\r
PRIORITY:1\r
DUE;VALUE=DATE:20261125\r
CATEGORIES:home,status-doing\r
RELATED-TO:parent-9\r
X-APPLE-SORT-ORDER:12\r
BEGIN:VALARM\r
ACTION:DISPLAY\r
TRIGGER:-PT1H\r
DESCRIPTION:Reminder\r
END:VALARM\r
END:VTODO\r
END:VCALENDAR\r
''';

const thunderbird = '''BEGIN:VCALENDAR
PRODID:-//Mozilla.org/NONSGML Mozilla Calendar V1.1//EN
VERSION:2.0
BEGIN:VTIMEZONE
TZID:Europe/Berlin
BEGIN:STANDARD
DTSTART:19701025T030000
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10
END:STANDARD
END:VTIMEZONE
BEGIN:VTODO
CREATED:20261101T080000Z
LAST-MODIFIED:20261101T080000Z
DTSTAMP:20261101T080000Z
UID:t-2
SUMMARY:Weekly report
DTSTART;TZID=Europe/Berlin:20261123T090000
DUE;TZID=Europe/Berlin:20261123T170000
RRULE:FREQ=WEEKLY;BYDAY=MO
EXDATE;TZID=Europe/Berlin:20261130T090000
COMPLETED:20261116T150000Z
STATUS:COMPLETED
END:VTODO
BEGIN:VTODO
UID:t-2
RECURRENCE-ID;TZID=Europe/Berlin:20261207T090000
SUMMARY:Weekly report (moved)
DTSTAMP:20261101T080000Z
END:VTODO
END:VCALENDAR
''';

void main() {
  test('parses the modelled fields of a VTODO', () {
    final t = parseTask(nextcloud);
    expect(t.uid, 't-1');
    expect(t.summary, 'Pay rent, flat 4');
    expect(t.description, 'Line one\nLine two');
    expect(t.status, 'NEEDS-ACTION');
    expect(t.percentComplete, 40);
    expect(t.priority, 1);
    expect(t.due!.allDay, isTrue);
    expect(t.due!.wall, DateTime.utc(2026, 11, 25));
    expect(t.categories, ['home', 'status-doing']);
    expect(t.parentUid, 'parent-9');
    expect(t.created, DateTime.utc(2026, 11, 1, 8));
    expect(t.boardStatus, 'doing');
    expect(t.isRecurring, isFalse);
  });

  test('unknown properties and VALARM survive a round trip', () {
    final t = parseTask(nextcloud);
    expect(t.extraLines, contains('X-APPLE-SORT-ORDER:12'));
    expect(t.extraLines, contains('BEGIN:VALARM'));
    final again = parseTask(serializeTask(t));
    expect(again.extraLines, t.extraLines);
    final out = serializeTask(t);
    expect(out, contains('BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT1H'));
    expect(out, contains('DUE;VALUE=DATE:20261125\r\n'));
    expect(out, contains('RELATED-TO;RELTYPE=PARENT:parent-9'));
    expect(out, contains('PERCENT-COMPLETE:40'));
  });

  test('TZID dates, RRULE, overrides and VTIMEZONE are kept', () {
    final t = parseTask(thunderbird);
    expect(t.uid, 't-2');
    expect(t.summary, 'Weekly report');
    expect(t.rrule, 'FREQ=WEEKLY;BYDAY=MO');
    expect(t.isRecurring, isTrue);
    expect(t.dtstart!.tzid, 'Europe/Berlin');
    expect(t.dtstart!.allDay, isFalse);
    expect(t.due!.value, '20261123T170000');
    expect(t.completed, DateTime.utc(2026, 11, 16, 15));
    expect(t.extraLines, ['EXDATE;TZID=Europe/Berlin:20261130T090000']);
    expect(t.calendarLines, contains('BEGIN:VTIMEZONE'));
    expect(t.siblingLines.first, 'BEGIN:VTODO');
    final out = serializeTask(t);
    expect(out, contains('DTSTART;TZID=Europe/Berlin:20261123T090000\r\n'));
    expect(out, contains('DUE;TZID=Europe/Berlin:20261123T170000\r\n'));
    expect(out, contains('RECURRENCE-ID;TZID=Europe/Berlin:20261207T090000'));
    expect(out, contains('TZOFFSETTO:+0100'));
    // Second pass is stable.
    expect(serializeTask(parseTask(out)), out);
  });

  test('DATE-TIME UTC due and an unparsable DUE stays verbatim', () {
    final t = parseTask('BEGIN:VCALENDAR\nBEGIN:VTODO\nUID:x\n'
        'DUE:20261125T090000Z\nEND:VTODO\nEND:VCALENDAR\n');
    expect(t.due!.isUtc, isTrue);
    final bad = parseTask('BEGIN:VCALENDAR\nBEGIN:VTODO\nUID:x\n'
        'DUE:garbage\nDURATION:PT1H\nEND:VTODO\nEND:VCALENDAR\n');
    expect(bad.due, isNull);
    expect(serializeTask(bad), contains('DUE:garbage'));
    expect(serializeTask(bad), contains('DURATION:PT1H'));
  });

  test('parseTask needs a VTODO and a UID; notes and tasks do not mix', () {
    final note = serializeNote(Note(uid: 'n', summary: 'N'));
    expect(() => parseTask(note), throwsA(isA<ICalException>()));
    expect(() => parseNote(nextcloud), throwsA(isA<ICalException>()));
    expect(parseNotes(nextcloud), isEmpty);
    expect(parseTasks(note), isEmpty);
    expect(
        () =>
            parseTask('BEGIN:VCALENDAR\nBEGIN:VTODO\nEND:VTODO\nEND:VCALENDAR'),
        throwsA(isA<ICalException>()));
  });

  test('complete, reopen and board status', () {
    final now = DateTime.utc(2026, 11, 26, 8);
    final t = parseTask(nextcloud);
    t.complete(now);
    expect(t.status, 'COMPLETED');
    expect(t.percentComplete, 100);
    expect(t.completed, now);
    expect(t.boardStatus, 'done');
    t.reopen();
    expect(t.status, 'NEEDS-ACTION');
    expect(t.completed, isNull);
    expect(t.percentComplete, isNull);
    t.setBoardStatus('blocked', now);
    expect(t.status, 'NEEDS-ACTION');
    expect(t.boardStatus, 'blocked');
    expect(t.categories, contains('status-blocked'));
    t.setBoardStatus('review', now);
    expect(t.status, 'NEEDS-ACTION');
    expect(t.boardStatus, 'review');
    expect(t.categories, contains('status-review'));
    t.setBoardStatus('doing', now);
    expect(t.status, 'IN-PROCESS');
    final plain = Task(uid: 'p');
    expect(plain.boardStatus, 'todo');
    plain.setBoardStatus('done', now);
    expect(plain.categories, isEmpty);
    expect(plain.boardStatus, 'done');
  });

  test('a task can be a child of a note', () {
    final t = Task(uid: 'c', summary: 'Child', parentUid: 'note-1');
    expect(parseTask(serializeTask(t)).parentUid, 'note-1');
  });
}
