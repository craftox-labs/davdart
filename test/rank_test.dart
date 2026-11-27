import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

DateTime t(int s) => DateTime.utc(2026, 11, 24, 10, 0, s);

void main() {
  group('rank round trip', () {
    test('note keeps rank and other X- props', () {
      final n = Note(uid: 'a', summary: 'A', lastModified: t(0))
        ..extraLines.add('X-OTHER;FOO=1:keep')
        ..rank = 2.5;
      final back = parseNote(serializeNote(n));
      expect(back.rank, 2.5);
      expect(back.extraLines, contains('X-OTHER;FOO=1:keep'));
      expect(back.copyWith(summary: 'B').rank, 2.5);
    });
    test('task keeps rank and other X- props', () {
      final x = Task(uid: 'a', summary: 'A')
        ..extraLines.add('X-APPLE-SORT-ORDER:12')
        ..rank = -0.125;
      final back = parseTask(serializeTask(x));
      expect(back.rank, -0.125);
      expect(back.extraLines, contains('X-APPLE-SORT-ORDER:12'));
    });
    test('reads a foreign rank line, clears it, ignores junk', () {
      final n = parseNote(
        'BEGIN:VCALENDAR\r\nBEGIN:VJOURNAL\r\nUID:a\r\n'
        'X-DAVDART-RANK:3\r\nEND:VJOURNAL\r\nEND:VCALENDAR\r\n',
      );
      expect(n.rank, 3);
      n.rank = null;
      expect(n.extraLines, isEmpty);
      n.extraLines.add('X-DAVDART-RANK:abc');
      expect(n.rank, isNull);
    });
  });

  group('rank merge', () {
    Note note(double? r, int at, {String? extra}) =>
        Note(uid: 'u', summary: 'T', lastModified: t(at))
          ..rank = r
          ..extraLines.addAll([if (extra != null) extra]);
    test('one side reorders, other edits another X- prop', () {
      final base = note(1, 0, extra: 'X-A:1');
      final local = note(5, 1, extra: 'X-A:1');
      final remote = note(1, 2, extra: 'X-A:2');
      final m = mergeNotes(base, local, remote);
      expect(m.note.rank, 5);
      expect(m.note.extraLines, contains('X-A:2'));
      expect(m.hadConflict, isFalse);
    });
    test('both rank: later writer wins, no conflict recorded', () {
      final base = note(1, 0);
      expect(mergeNotes(base, note(5, 3), note(7, 2)).note.rank, 5);
      expect(mergeNotes(base, note(5, 2), note(7, 3)).note.rank, 7);
    });
    test('task rank merges the same way', () {
      Task task(double? r, int at) =>
          Task(uid: 'u', summary: 'T', lastModified: t(at))..rank = r;
      expect(mergeTasks(task(null, 0), task(2, 1), task(null, 2)).task.rank, 2);
      expect(mergeTasks(task(1, 0), task(1, 1), task(4, 2)).task.rank, 4);
    });
  });

  group('planRanks', () {
    List<(String, double?)> col(List<double?> r) => [
      for (var i = 0; i < r.length; i++) ('c$i', r[i]),
    ];
    test('empty column', () => expect(planRanks([], 0, 'm'), {'m': 0.0}));
    test('top', () => expect(planRanks(col([1, 2]), 0, 'm'), {'m': 0.0}));
    test('bottom', () => expect(planRanks(col([1, 2]), 2, 'm'), {'m': 3.0}));
    test('between', () => expect(planRanks(col([1, 2]), 1, 'm'), {'m': 1.5}));
    test('equal neighbours re-spread', () {
      final r = planRanks(col([2, 2, 5]), 1, 'm');
      expect(r, {'c0': 1.0, 'm': 2.0, 'c1': 3.0, 'c2': 4.0});
    });
    test('tiny gap re-spread keeps order', () {
      final r = planRanks(col([1, 1 + 1e-12]), 1, 'm');
      expect(r['m'], 2.0);
      expect(r['c1'], 3.0);
    });
    test('unranked above get ranked first', () {
      final r = planRanks(col([1, null, null]), 2, 'm');
      expect(r, {'c1': 2.0, 'm': 3.0});
    });
    test('ranked above, unranked below: one write', () {
      expect(planRanks(col([4, null]), 1, 'm'), {'m': 5.0});
    });
    test('top of an all-unranked column', () {
      expect(planRanks(col([null, null]), 0, 'm'), {'m': 0.0});
    });
  });
}
