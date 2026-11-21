import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

DateTime u(int y, int m, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, m, d, h, mi);

void main() {
  tearDown(() => LocalZone.use(null));

  group('ICalDate in zones', () {
    test('Z converts to the viewer zone', () {
      const d = ICalDate('20261125T090000Z');
      LocalZone.use('Asia/Bangkok');
      expect(d.localWall, u(2026, 11, 25, 16));
      LocalZone.use('America/Los_Angeles');
      expect(d.localWall, u(2026, 11, 25, 1));
      LocalZone.use('Australia/Sydney');
      expect(d.localWall, u(2026, 11, 25, 20));
      LocalZone.use('UTC');
      expect(d.localWall, u(2026, 11, 25, 9));
    });

    test('TZID resolves to an instant', () {
      const d = ICalDate('20261125T090000', ';TZID=Europe/Berlin');
      expect(d.toInstant(), u(2026, 11, 25, 8));
      const s = ICalDate('20260715T090000', ';TZID=Europe/Berlin');
      expect(s.toInstant(), u(2026, 7, 15, 7));
      LocalZone.use('Asia/Bangkok');
      expect(d.localWall, u(2026, 11, 25, 15));
    });

    test('event near midnight lands on a different day per viewer', () {
      const d = ICalDate('20261125T230000', ';TZID=America/New_York');
      // 04:00Z on the 26th.
      LocalZone.use('Asia/Bangkok');
      expect(d.localDay, u(2026, 11, 26));
      LocalZone.use('America/Los_Angeles');
      expect(d.localDay, u(2026, 11, 25));
      LocalZone.use('UTC');
      expect(d.localDay, u(2026, 11, 26));
    });

    test('floating and all-day stay put', () {
      const f = ICalDate('20261125T233000');
      const a = ICalDate('20261125', ';VALUE=DATE');
      for (final z in ['Asia/Bangkok', 'America/Los_Angeles', 'UTC']) {
        LocalZone.use(z);
        expect(f.localWall, u(2026, 11, 25, 23, 30));
        expect(a.localDay, u(2026, 11, 25));
        expect(a.toInstant(), isNull);
      }
      LocalZone.use('Asia/Bangkok');
      expect(f.toInstant(), u(2026, 11, 25, 16, 30));
    });

    test('unknown TZID falls back to floating', () {
      const d = ICalDate('20261125T090000', ';TZID=Mars/Olympus');
      LocalZone.use('Asia/Bangkok');
      expect(d.isFloating, isTrue);
      expect(d.localWall, u(2026, 11, 25, 9));
      expect(d.toInstant(), u(2026, 11, 25, 2));
    });

    test('DST boundary: Los Angeles spring forward', () {
      // 2027-03-14 02:00 PST jumps to 03:00 PDT.
      const before = ICalDate('20270314T090000Z'); // 01:00 PST
      const after = ICalDate('20270314T100000Z'); // 03:00 PDT
      LocalZone.use('America/Los_Angeles');
      expect(before.localWall, u(2027, 3, 14, 1));
      expect(after.localWall, u(2027, 3, 14, 3));
      // Sydney falls back 2027-04-04 03:00 AEDT -> 02:00 AEST.
      const syd = ICalDate('20270403T163000Z'); // 03:30 AEDT, before the change
      LocalZone.use('Australia/Sydney');
      expect(syd.localWall, u(2027, 4, 4, 2, 30));
    });

    test('fromLocalWall inverts localWall and keeps the flavour', () {
      LocalZone.use('Asia/Bangkok');
      const z = ICalDate('20261125T090000Z');
      expect(ICalDate.fromLocalWall(u(2026, 11, 25, 16), z).value,
          '20261125T090000Z');
      const t = ICalDate('20261125T090000', ';TZID=Europe/Berlin');
      final r = ICalDate.fromLocalWall(u(2026, 11, 25, 15), t);
      expect(r.value, '20261125T090000');
      expect(r.params, ';TZID=Europe/Berlin');
    });
  });

  group('Event.length', () {
    test('mixed Z start and TZID end uses instants', () {
      final e = Event(
        uid: 'a',
        dtstart: const ICalDate('20261125T090000Z'),
        dtend: const ICalDate('20261125T120000', ';TZID=Europe/Berlin'),
      ); // end is 11:00Z
      expect(e.length, const Duration(hours: 2));
    });

    test('same flavour uses the written difference', () {
      final e = Event(
        uid: 'a',
        dtstart: const ICalDate('20261125T090000', ';TZID=Europe/Berlin'),
        dtend: const ICalDate('20261125T100000', ';TZID=Europe/Berlin'),
      );
      expect(e.length, const Duration(hours: 1));
    });
  });
}
