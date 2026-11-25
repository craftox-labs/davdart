import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

void main() {
  test('parses and writes simple rules', () {
    for (final r in [
      'FREQ=DAILY',
      'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=5',
      'FREQ=MONTHLY;UNTIL=20270131',
      'FREQ=YEARLY',
      'FREQ=DAILY;UNTIL=20270131T235959Z',
    ]) {
      expect(RepeatRule.parse(r)!.toRrule(), r);
    }
  });

  test('normalises order and WKST=MO', () {
    expect(
      RepeatRule.parse('freq=weekly;byday=WE,MO;wkst=mo')!.toRrule(),
      'FREQ=WEEKLY;BYDAY=MO,WE',
    );
  });

  test('anything else stays raw (null)', () {
    for (final r in [
      null,
      '',
      'FREQ=MONTHLY;BYDAY=-1FR',
      'FREQ=MONTHLY;BYMONTHDAY=15',
      'FREQ=DAILY;BYDAY=MO',
      'FREQ=WEEKLY;UNTIL=20270131T000000Z',
      'FREQ=DAILY;COUNT=2;UNTIL=20270131',
      'FREQ=HOURLY',
      'FREQ=DAILY;INTERVAL=0',
      'FREQ=WEEKLY;WKST=SU',
      'COUNT=3',
      'FREQ=DAILY;UNTIL=20270131T170000Z',
      'FREQ=DAILY;UNTIL=20260230',
    ]) {
      expect(RepeatRule.parse(r), isNull, reason: '$r');
    }
  });

  test('copyWith drops weekdays off weekly and clears the end', () {
    final r = RepeatRule.parse('FREQ=WEEKLY;BYDAY=MO;COUNT=3')!;
    expect(r.copyWith(freq: 'DAILY').toRrule(), 'FREQ=DAILY;COUNT=3');
    expect(r.copyWith(clearEnd: true).toRrule(), 'FREQ=WEEKLY;BYDAY=MO');
  });
}
