import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

Note n(String body, {String title = 'T', List<String>? tags, DateTime? at}) =>
    Note(
      uid: 'u',
      summary: title,
      description: body,
      categories: tags ?? ['a'],
      lastModified: at,
    );

void main() {
  group('mergeText', () {
    const base = 'one\ntwo\nthree\nfour\nfive';
    test('edits in different places combine', () {
      final r = mergeText(
        base,
        'ONE\ntwo\nthree\nfour\nfive',
        'one\ntwo\nthree\nfour\nFIVE',
        preferLocal: true,
      );
      expect(r.text, 'ONE\ntwo\nthree\nfour\nFIVE');
      expect(r.conflicts, isEmpty);
    });
    test('the same edit on both sides is not a conflict', () {
      final r = mergeText(
        base,
        base.replaceAll('two', 'TWO'),
        base.replaceAll('two', 'TWO'),
        preferLocal: false,
      );
      expect(r.conflicts, isEmpty);
      expect(r.text, contains('TWO'));
    });
    test('inserts at different points and a deletion combine', () {
      final r = mergeText(
        base,
        'zero\none\ntwo\nthree\nfour\nfive',
        'one\ntwo\nfour\nfive',
        preferLocal: true,
      );
      expect(r.text, 'zero\none\ntwo\nfour\nfive');
      expect(r.conflicts, isEmpty);
    });
    test('overlapping edits: winner takes that stretch only', () {
      final r = mergeText(
        base,
        'one\nLOCAL\nthree\nfour\nFIVE-L',
        'one\nREMOTE\nthree\nfour\nfive',
        preferLocal: false,
      );
      expect(r.text, 'one\nREMOTE\nthree\nfour\nFIVE-L');
      expect(r.conflicts.single.local, 'LOCAL');
      expect(r.conflicts.single.remote, 'REMOTE');
      final l = mergeText(
        base,
        'one\nLOCAL\nthree\nfour\nfive',
        'one\nREMOTE\nthree\nfour\nfive',
        preferLocal: true,
      );
      expect(l.text, contains('LOCAL'));
    });
    test('one side unchanged takes the other', () {
      expect(mergeText(base, base, 'x', preferLocal: true).text, 'x');
      expect(mergeText(base, 'y', base, preferLocal: false).text, 'y');
    });
  });

  group('mergeNotes', () {
    const head = 'item_id: x\nstatus: backlog\nowner: tm\n\n';
    final t0 = DateTime.utc(2026, 11, 19, 1);
    final t1 = DateTime.utc(2026, 11, 19, 2);
    final t2 = DateTime.utc(2026, 11, 19, 3);

    test('two different status tags collapse to the later writer\'s', () {
      final base = n('x', tags: ['d', 'status-backlog'], at: t0);
      final local = n('x', tags: ['d', 'status-doing'], at: t2);
      final remote = n('x', tags: ['d', 'status-done'], at: t1);
      var m = mergeNotes(base, local, remote);
      expect(m.note.categories.where((c) => c.startsWith('status-')), [
        'status-doing',
      ]);
      m = mergeNotes(base, remote, local);
      expect(m.note.categories.where((c) => c.startsWith('status-')), [
        'status-doing',
      ]);
      expect(m.note.categories, contains('d'));
    });

    test('status change locally and text edit remotely both land', () {
      final base = n('${head}a\nb\nc', tags: ['d', 'status-backlog'], at: t0);
      final local = n(
        '${head.replaceFirst('backlog', 'todo')}a\nb\nc',
        tags: ['d', 'status-todo'],
        at: t1,
      );
      final remote = n('${head}a\nB\nc', tags: ['d', 'status-backlog'], at: t2);
      final m = mergeNotes(base, local, remote);
      expect(m.hadConflict, isFalse);
      final p = PlanItem.fromNote(m.note);
      expect(p.status, 'todo');
      expect(p.text, 'a\nB\nc');
      expect(m.note.categories.toSet(), {'d', 'status-todo'});
    });

    test(
      'conflicting status: later edit wins, loser reported, no duplicate',
      () {
        final base = n('${head}x', at: t0);
        final local = n('${head.replaceFirst('backlog', 'doing')}x', at: t2);
        final remote = n('${head.replaceFirst('backlog', 'done')}x', at: t1);
        final m = mergeNotes(base, local, remote);
        expect(PlanItem.fromNote(m.note).status, 'doing');
        expect(m.conflicts.single.what, 'field:status');
        expect(m.conflicts.single.remote, 'done');
      },
    );

    test('title and tags merge; remote href and etag are kept', () {
      final base = n('t', tags: ['a', 'b'], at: t0);
      final local = n('t', title: 'New', tags: ['a', 'c'], at: t1);
      final remote = n('t', tags: ['a', 'b', 'd'], at: t0)
        ..href = '/r.ics'
        ..etag = '"e"';
      final m = mergeNotes(base, local, remote);
      expect(m.note.summary, 'New');
      expect(m.note.categories.toSet(), {'a', 'c', 'd'});
      expect(m.note.href, '/r.ics');
      expect(m.note.etag, '"e"');
      expect(m.hadConflict, isFalse);
    });

    test('notes without a header merge as plain text', () {
      final base = n('l1\nl2\nl3');
      final m = mergeNotes(base, n('L1\nl2\nl3'), n('l1\nl2\nL3'));
      expect(m.note.description, 'L1\nl2\nL3');
    });
  });
}
