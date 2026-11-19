import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

void main() {
  test('view note round trip keeps every field', () {
    final v = SavedViewSpec(
      uid: 'v1',
      name: 'Open docs',
      mode: 'list',
      search: 'release notes',
      tags: ['davdart', 'planning'],
      folderUid: 'f1',
    );
    final n = v.toNote();
    expect(n.categories, [viewTag]);
    expect(n.summary, 'Open docs');
    expect(
      n.description,
      'mode: list\nsearch: release notes\ntags: davdart, planning\nfolder: f1',
    );
    final back = SavedViewSpec.fromNote(parseNote(serializeNote(n)))!;
    expect(back.name, 'Open docs');
    expect(back.mode, 'list');
    expect(back.search, 'release notes');
    expect(back.tags, ['davdart', 'planning']);
    expect(back.folderUid, 'f1');
  });

  test('missing, unknown and odd keys are tolerated', () {
    final n = Note(
      uid: 'v',
      summary: 'Bare',
      description: 'mode: sideways\nfuture_key: x\n\nfree text',
      categories: [viewTag],
    );
    final v = SavedViewSpec.fromNote(n)!;
    expect((v.mode, v.search, v.folderUid), ('board', '', null));
    expect(v.tags, isEmpty);
    expect(
      SavedViewSpec.fromNote(
        Note(uid: 'e', summary: 'Empty', categories: [viewTag]),
      )!.mode,
      'board',
    );
    expect(SavedViewSpec.fromNote(Note(uid: 'x', summary: 'n')), isNull);
    expect(
      SavedViewSpec.fromNote(Note(uid: 'y', categories: [viewTag])),
      isNull,
    );
  });

  test('writeTo updates fields and keeps unknown keys and text', () {
    final n = Note(
      uid: 'v',
      summary: 'Old',
      description: 'mode: list\nfuture_key: x\nfolder: f\n\nnotes',
      categories: [viewTag, 'extra'],
    );
    SavedViewSpec(uid: 'v', name: 'New', search: 'a\nb').writeTo(n);
    expect(n.summary, 'New');
    expect(n.categories, [viewTag, 'extra']);
    expect(n.description, 'mode: board\nfuture_key: x\nsearch: a b\n\nnotes');
  });

  test('structural notes are folders and views', () {
    expect(isStructuralNote(Note(uid: 'a', categories: [folderTag])), isTrue);
    expect(isStructuralNote(Note(uid: 'a', categories: [viewTag])), isTrue);
    expect(isStructuralNote(Note(uid: 'a', categories: ['x'])), isFalse);
  });
}
