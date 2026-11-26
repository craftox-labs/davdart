import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/persistent_event_store.dart';
import 'package:davdart_app/data/persistent_store.dart';
import 'package:davdart_app/data/persistent_task_store.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// A storage that refuses writes once [full] is set.
class _Full extends MemoryStorage {
  bool full = false;
  @override
  bool write(String key, String value) =>
      full ? false : super.write(key, value);
}

void main() {
  test('a refused write throws from the persistent stores', () async {
    final m = _Full();
    final notes = PersistentNoteStore(m);
    final tasks = PersistentTaskStore(m);
    final events = PersistentEventStore(m);
    m.full = true;
    await expectLater(
      notes.setSyncToken('x'),
      throwsA(isA<StorageWriteException>()),
    );
    await expectLater(
      tasks.setSyncToken('x'),
      throwsA(isA<StorageWriteException>()),
    );
    await expectLater(
      events.setSyncToken('x'),
      throwsA(isA<StorageWriteException>()),
    );
  });

  test('a damaged note blob is kept under .unreadable', () {
    final m = MemoryStorage()..data['davdart.space.v1'] = '{not json';
    PersistentNoteStore(m);
    expect(m.data['davdart.space.v1.unreadable'], '{not json');
  });

  test('AppState shows Not saved but keeps the edit for the session', () async {
    final m = _Full();
    final space = Space(
      SpaceConfig(id: 's', name: 'S'),
      PersistentNoteStore(m),
    );
    final s = AppState(SpaceNoteSource(space));
    await s.load();
    m.full = true;
    await s.addNote('Kept');
    expect(s.error, startsWith('Not saved'));
    expect(s.notes.map((n) => n.summary), contains('Kept'));
    m.full = false;
    await s.addNote('Second');
    expect(s.error, isNull);
  });
}
