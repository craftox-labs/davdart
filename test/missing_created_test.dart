import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

void main() {
  test('siblings without CREATED sort the same however DTSTAMP defaults', () {
    final a = Note(uid: 'a', summary: 'Same');
    final b = Note(uid: 'b', summary: 'Same');
    final dated = Note(uid: 'c', summary: 'A', created: DateTime.utc(2026));
    for (final order in [
      [a, b, dated],
      [b, dated, a]
    ]) {
      final roots = NoteTree.build(order).roots.map((n) => n.note.uid);
      expect(roots, ['a', 'b', 'c']);
    }
  });

  test('board order breaks ties by uid when CREATED is missing', () {
    final a = BoardItem.note(Note(uid: 'a', summary: 'Same'));
    final b = BoardItem.note(Note(uid: 'b', summary: 'Same'));
    expect(compareBoardItems(a, b), lessThan(0));
    expect(compareBoardItems(b, a), greaterThan(0));
  });
}
