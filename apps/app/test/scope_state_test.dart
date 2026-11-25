import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_helper.dart';

/// The app's state over [prefs]: one catalog Space (Planning) open.
Future<AppState> _open(KeyValueStorage prefs) async {
  final c = catalogWithPlanning(prefs);
  final s = AppState(c.sourceFor(c.current!), prefs: prefs, catalog: c);
  await s.load();
  return s;
}

/// A second state over the same prefs, as a fresh app start would build.
Future<AppState> _restart(KeyValueStorage prefs) async {
  final s = await _open(prefs);
  return s;
}

String _folderUid(AppState s, String name) =>
    s.notes.firstWhere((n) => n.summary == name).uid;

void main() {
  test('the folder scope comes back after a Space switch', () async {
    final prefs = MemoryStorage();
    final s = await _open(prefs);
    await s.addFolder('Work');
    final work = _folderUid(s, 'Work');
    expect(s.scopeUid, work);

    await s.createSpace('Inbox');
    final inbox = s.currentSpaceId!;
    expect(s.scopeUid, isNull, reason: 'a new Space starts on Everything');
    await s.addFolder('Home');
    final home = _folderUid(s, 'Home');

    await s.switchSpace(SpaceCatalog.planningId);
    expect(s.scopeUid, work);
    await s.switchSpace(inbox);
    expect(s.scopeUid, home);
    // Leaving a folder is remembered too.
    s.openFolder(null);
    await s.switchSpace(SpaceCatalog.planningId);
    await s.switchSpace(inbox);
    expect(s.scopeUid, isNull);
  });

  test('a fresh start restores the Space its saved scope', () async {
    final prefs = MemoryStorage();
    final s = await _open(prefs);
    await s.addFolder('Work');
    final work = _folderUid(s, 'Work');

    final again = await _restart(prefs);
    expect(again.currentSpaceId, SpaceCatalog.planningId);
    expect(again.scopeUid, work);
  });

  test('a saved folder that is gone falls back to Everything', () async {
    final prefs = MemoryStorage();
    final s = await _open(prefs);
    await s.addFolder('Work');
    final work = _folderUid(s, 'Work');
    await s.createSpace('Inbox');
    final inbox = s.currentSpaceId!;
    await s.switchSpace(SpaceCatalog.planningId);
    expect(s.scopeUid, work);

    await s.deleteNote(work);
    await s.switchSpace(inbox);
    await s.switchSpace(SpaceCatalog.planningId);
    expect(s.scopeUid, isNull);
    expect(prefs.read('davdart.scope.v1'), isNot(contains(work)));
  });

  test(
    'recents: the last five projects, newest first, no duplicates',
    () async {
      final prefs = MemoryStorage();
      final s = await _open(prefs);
      for (var i = 0; i < 6; i++) {
        await s.addProject('P$i');
      }
      final ids = [for (final p in s.projectIndex.projects()) p.uid];
      expect(ids, hasLength(6));
      for (final uid in ids) {
        s.openFolder(uid);
      }
      // Six opened, five kept: the oldest fell off, newest first.
      expect(s.recentProjects, ids.reversed.take(5).toList());
      expect(s.recentProjects, hasLength(5));
      // Re-opening an older one moves it to the front, still five, no repeat.
      s.openFolder(ids[1]);
      expect(s.recentProjects.first, ids[1]);
      expect(s.recentProjects, hasLength(5));
      expect(s.recentProjects.toSet(), hasLength(5));
      // Kept across a restart, and per Space.
      final again = await _restart(prefs);
      expect(again.recentProjects, s.recentProjects);
      await again.createSpace('Other');
      expect(again.recentProjects, isEmpty);
      // Sub-folders and loose folders are not recents, only projects are.
      await again.addFolder('Loose');
      expect(again.recentProjects, isEmpty);
    },
  );
}
