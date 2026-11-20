import 'dart:async';

import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha', description: 'Alpha body'),
  ];
}

/// Saves only when [gate] completes, so a test can type while a save runs.
class _SlowSource extends SpaceNoteSource {
  _SlowSource(super.space, {super.seed});
  Completer<void>? gate;
  @override
  Future<Note> save(Note note) async {
    await gate?.future;
    return super.save(note);
  }
}

void main() {
  test('text typed while a save is in flight stays as the draft', () async {
    final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
    final src = _SlowSource(space, seed: _Seed());
    final s = AppState(src);
    await s.load();
    s.select('a');
    s.startEdit('a');
    final d = s.draftFor('a')!;
    d.bodyController.text = 'first';
    src.gate = Completer<void>();
    final saving = s.saveDraft('a');
    await Future<void>.delayed(Duration.zero);
    d.bodyController.text = 'first, then more';
    src.gate!.complete();
    expect(await saving, isTrue);
    expect(s.draftFor('a'), same(d)); // not dropped
    expect(d.bodyController.text, 'first, then more');
    expect(s.dirtyFor('a'), isTrue);
    expect(s.tree.find('a')!.note.description, contains('first'));
    // Saving again stores the newer text and ends the edit.
    src.gate = null;
    expect(await s.saveDraft('a'), isTrue);
    expect(s.draftFor('a'), isNull);
    expect(s.tree.find('a')!.note.description, contains('first, then more'));
  });

  test('an untouched draft is cleared after a save', () async {
    final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
    final s = AppState(SpaceNoteSource(space, seed: _Seed()));
    await s.load();
    s.select('a');
    s.startEdit('a');
    s.draftFor('a')!.bodyController.text = 'changed';
    expect(await s.saveDraft('a'), isTrue);
    expect(s.draftFor('a'), isNull);
  });
}
