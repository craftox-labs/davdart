import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

const sample =
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\n'
    'BEGIN:VJOURNAL\r\nUID:abc-1\r\nDTSTAMP:20261119T010203Z\r\n'
    'CREATED:20261118T000000Z\r\nSUMMARY:Shopping\\, errands\r\n'
    'DESCRIPTION:line one\\nline two\\; end\r\n'
    'CATEGORIES:inbox,to\\,do\r\nSTATUS:FINAL\r\n'
    'X-CUSTOM;FOO=bar:keep me\r\n'
    'END:VJOURNAL\r\nEND:VCALENDAR\r\n';

void main() {
  roundTripTests();
  test('parses a VJOURNAL', () {
    final n = parseNote(sample);
    expect(n.uid, 'abc-1');
    expect(n.summary, 'Shopping, errands');
    expect(n.description, 'line one\nline two; end');
    expect(n.categories, ['inbox', 'to,do']);
    expect(n.status, 'FINAL');
    expect(n.created, DateTime.utc(2026, 11, 18));
    expect(n.dtstamp, DateTime.utc(2026, 11, 19, 1, 2, 3));
    expect(n.extraLines, ['X-CUSTOM;FOO=bar:keep me']);
  });

  test('round trip keeps every modelled and unknown field', () {
    final a = parseNote(sample);
    final b = parseNote(serializeNote(a));
    expect(b.uid, a.uid);
    expect(b.summary, a.summary);
    expect(b.description, a.description);
    expect(b.categories, a.categories);
    expect(b.status, a.status);
    expect(b.created, a.created);
    expect(b.extraLines, a.extraLines);
  });

  test('unfolds folded lines and folds long ones at 75 octets', () {
    final folded = sample.replaceFirst(
      'SUMMARY:Shopping',
      'SUMMARY:Shop\r\n ping',
    );
    expect(parseNote(folded).summary, 'Shopping, errands');
    final long = Note(uid: 'u', summary: 'é' * 100);
    final text = serializeNote(long);
    for (final l in text.split('\r\n')) {
      expect(
        l.codeUnits.fold<int>(0, (s, c) => s + (c < 0x80 ? 1 : 2)),
        lessThanOrEqualTo(75),
      );
    }
    expect(parseNote(text).summary, 'é' * 100);
  });

  test('ignores VEVENT/VTODO and keeps nested components', () {
    const mixed =
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:e\r\nEND:VEVENT\r\n'
        'BEGIN:VJOURNAL\r\nUID:j\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\n'
        'END:VALARM\r\nEND:VJOURNAL\r\nEND:VCALENDAR\r\n';
    final notes = parseNotes(mixed);
    expect(notes.map((n) => n.uid), ['j']);
    expect(notes.first.extraLines.length, 3);
    expect(serializeNote(notes.first), contains('BEGIN:VALARM'));
  });

  test('rejects a VJOURNAL without UID', () {
    expect(
      () => parseNotes(
        'BEGIN:VCALENDAR\r\nBEGIN:VJOURNAL\r\n'
        'SUMMARY:x\r\nEND:VJOURNAL\r\nEND:VCALENDAR\r\n',
      ),
      throwsA(isA<ICalException>()),
    );
  });

  test('accepts LF-only input', () {
    expect(parseNote(sample.replaceAll('\r\n', '\n')).uid, 'abc-1');
  });
}

void roundTripTests() {
  group('lossless round trip', () {
    test('recurrence overrides and calendar-level lines survive', () {
      const src =
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:Memo\r\n'
          'BEGIN:VJOURNAL\r\nUID:m\r\nSUMMARY:master\r\nEND:VJOURNAL\r\n'
          'BEGIN:VJOURNAL\r\nUID:m\r\nRECURRENCE-ID:20261120T000000Z\r\n'
          'SUMMARY:override\r\nEND:VJOURNAL\r\nEND:VCALENDAR\r\n';
      final n = parseNote(src);
      expect(n.summary, 'master');
      final out = serializeNote(n);
      expect(out, contains('X-WR-CALNAME:Memo'));
      expect(out, contains('RECURRENCE-ID:20261120T000000Z'));
      expect(out, contains('SUMMARY:override'));
    });

    test('TZID, floating and date-only values are not shifted', () {
      const src =
          'BEGIN:VCALENDAR\r\nBEGIN:VJOURNAL\r\nUID:t\r\n'
          'CREATED;TZID=Asia/Bangkok:20261119T100000\r\n'
          'LAST-MODIFIED:20261119T100000\r\nEND:VJOURNAL\r\nEND:VCALENDAR\r\n';
      final n = parseNote(src);
      expect(n.created, isNull);
      final out = serializeNote(n);
      expect(out, contains('CREATED;TZID=Asia/Bangkok:20261119T100000\r\n'));
      expect(out, contains('LAST-MODIFIED:20261119T100000\r\n'));
    });

    test('parameters and repeated DESCRIPTIONs are kept', () {
      const src =
          'BEGIN:VCALENDAR\r\nBEGIN:VJOURNAL\r\nUID:p\r\n'
          'SUMMARY;LANGUAGE=de:Hallo\r\nDESCRIPTION:one\r\n'
          'DESCRIPTION:two\r\nCATEGORIES;X-FOO=1:a\r\n'
          'END:VJOURNAL\r\nEND:VCALENDAR\r\n';
      final out = serializeNote(parseNote(src));
      expect(out, contains('SUMMARY;LANGUAGE=de:Hallo'));
      expect(out, contains('DESCRIPTION:one'));
      expect(out, contains('DESCRIPTION:two'));
      expect(out, contains('CATEGORIES;X-FOO=1:a'));
    });

    test('copyWith can clear status', () {
      final n = Note(uid: 'u', status: 'FINAL');
      expect(n.copyWith(clearStatus: true).status, isNull);
    });
  });
}
