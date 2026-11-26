import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/uid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('newUid never repeats, even within one clock tick', () {
    final seen = <String>{for (var i = 0; i < 20000; i++) newUid()};
    expect(seen.length, 20000);
    expect(newUid(prefix: 'davdart-view'), startsWith('davdart-view-'));
  });

  test('a personal item never shares the uid of its container', () async {
    final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
    final s = AppState(SpaceNoteSource(space));
    await s.load();
    await s.addNote('Mine', personal: true);
    final container = s.personalContainer;
    expect(container, isNotNull);
    final note = s.notes.firstWhere((n) => n.summary == 'Mine');
    expect(note.uid, isNot(container!.uid));
    expect(note.parentUid, container.uid);
  });

  test('a project and its Projects container get different uids', () async {
    final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
    final s = AppState(SpaceNoteSource(space));
    await s.load();
    final uid = await s.addProject('Alpha');
    expect(uid, isNotNull);
    final p = s.notes.firstWhere((n) => n.uid == uid);
    expect(s.notes.where((n) => n.uid == p.parentUid), hasLength(1));
    expect(p.parentUid, isNot(uid));
  });
}
