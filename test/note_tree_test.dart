import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

Note n(String uid, [String? parent, int day = 1]) => Note(
    uid: uid,
    summary: uid,
    parentUid: parent,
    created: DateTime.utc(2026, 11, day));

void main() {
  test('parent link round-trips and other relations are kept', () {
    final src = 'BEGIN:VCALENDAR\r\nBEGIN:VJOURNAL\r\nUID:c\r\n'
        'RELATED-TO;RELTYPE=PARENT:p\r\nRELATED-TO;RELTYPE=SIBLING:s\r\n'
        'END:VJOURNAL\r\nEND:VCALENDAR\r\n';
    final note = parseNote(src);
    expect(note.parentUid, 'p');
    final out = serializeNote(note);
    expect(out, contains('RELATED-TO;RELTYPE=PARENT:p'));
    expect(out, contains('RELATED-TO;RELTYPE=SIBLING:s'));
    expect(parseNote(out).parentUid, 'p');
  });

  test('builds a tree ordered by creation date', () {
    final t = NoteTree.build([n('b', 'a', 3), n('c', 'a', 2), n('a'), n('d')]);
    expect(t.roots.map((r) => r.note.uid), ['a', 'd']);
    expect(t.find('a')!.children.map((c) => c.note.uid), ['c', 'b']);
  });

  test('a missing parent puts the note at the top level', () {
    final t = NoteTree.build([n('x', 'gone')]);
    expect(t.roots.single.note.uid, 'x');
  });

  test('a loop is broken deterministically, nothing is lost', () {
    final t = NoteTree.build([n('a', 'b'), n('b', 'a')]);
    expect(t.roots, hasLength(1));
    expect(t.find('a'), isNotNull);
    expect(t.find('b'), isNotNull);
    final t2 = NoteTree.build([n('b', 'a'), n('a', 'b')]);
    expect(t2.roots.single.note.uid, t.roots.single.note.uid);
  });

  test('canMove refuses itself and descendants, descendants lists a subtree',
      () {
    final t = NoteTree.build([n('a'), n('b', 'a'), n('c', 'b')]);
    expect(t.canMove('a', 'c'), isFalse);
    expect(t.canMove('a', 'a'), isFalse);
    expect(t.canMove('c', 'a'), isTrue);
    expect(t.canMove('c', null), isTrue);
    expect(t.descendants('a').map((x) => x.uid), ['b', 'c']);
    expect(t.adoptiveParent('b'), 'a');
  });

  test('moving a note merges as a scalar (parent change wins over none)', () {
    final base = n('x');
    final local = n('x', 'p');
    final remote = n('x')..summary = 'renamed';
    final m = mergeNotes(base, local, remote);
    expect(m.note.parentUid, 'p');
    expect(m.note.summary, 'renamed');
    expect(m.hadConflict, isFalse);
  });
}
