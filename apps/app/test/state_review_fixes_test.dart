import 'dart:async';

import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog_helper.dart';

class _Seed implements NoteSource {
  _Seed(this.notes);
  final List<Note> notes;
  @override
  Future<List<Note>> load() async => notes;
}

/// Reads of tasks or events fail while [fail] is set.
class _Flaky extends SpaceNoteSource {
  _Flaky(super.space, {super.taskStore, super.eventStore});
  bool fail = false;
  @override
  Future<List<Task>> loadTasks() async =>
      fail ? throw StateError('offline') : super.loadTasks();
  @override
  Future<List<Event>> loadEvents() async =>
      fail ? throw StateError('offline') : super.loadEvents();
}

/// Holds a note save until [gate] completes.
class _SlowSave extends SpaceNoteSource {
  _SlowSave(super.space);
  Completer<void>? gate;
  @override
  Future<Note> save(Note note) async {
    await gate?.future;
    return super.save(note);
  }
}

Space _space(String id) =>
    Space(SpaceConfig(id: id, name: id), MemoryNoteStore());

void main() {
  test('M1: failed task and event loads keep the saved tabs', () async {
    final prefs = MemoryStorage();
    final space = _space('s');
    final tasks = MemoryTaskStore();
    final events = MemoryEventStore();
    final a = AppState(
      SpaceNoteSource(space, taskStore: tasks, eventStore: events),
      prefs: prefs,
    );
    await a.load();
    final t = (await a.addTask('Keep me'))!;
    final e = (await a.addEvent(
      'Keep too',
      start: DateTime.utc(2026, 11, 26),
    ))!;
    a.openTaskTab(t);
    a.openEventTab(e);
    final saved = prefs.read('davdart.tabs.v1.default');
    expect(saved, contains(t));

    final flaky = _Flaky(space, taskStore: tasks, eventStore: events)
      ..fail = true;
    final b = AppState(flaky, prefs: prefs);
    await b.load();
    expect(b.taskError, isNotNull);
    expect(prefs.read('davdart.tabs.v1.default'), saved);

    flaky.fail = false;
    final c = AppState(flaky, prefs: prefs);
    await c.load();
    expect(c.taskError, isNull);
    expect(c.tabs.map((x) => x.id), containsAll([t, e]));
  });

  test('M1: a deleted task still drops its tab on a good load', () async {
    final prefs = MemoryStorage();
    final src = SpaceNoteSource(_space('s'));
    final a = AppState(src, prefs: prefs);
    await a.load();
    final keep = (await a.addTask('Keep'))!;
    final gone = (await a.addTask('Gone'))!;
    a.openTaskTab(keep);
    a.openTaskTab(gone);
    await src.deleteTask(gone);
    final b = AppState(src, prefs: prefs);
    await b.load();
    expect(b.tabs.map((x) => x.id), [keep]);
  });

  test('M2: a restored view tab applies its view', () async {
    final prefs = MemoryStorage();
    final src = SpaceNoteSource(
      _space('s'),
      seed: _Seed([Note(uid: 'a', summary: 'Alpha')]),
    );
    final a = AppState(src, prefs: prefs);
    await a.load();
    a.setView(ViewMode.list);
    a.setQuery('alp');
    expect(await a.saveView('V'), isNull);
    a.applyView(a.savedViews.single);
    expect(a.activeViewName, 'V');

    final b = AppState(src, prefs: prefs);
    await b.load();
    expect(b.activeViewName, 'V');
    expect(b.view, ViewMode.list);
    expect(b.query, 'alp');
  });

  test('M3: closing an unrelated tab keeps a loose folder scope', () async {
    final prefs = MemoryStorage();
    final folder = Note(
      uid: 'f',
      summary: 'F',
      categories: [AppState.folderTag],
    );
    final src = SpaceNoteSource(_space('s'), seed: _Seed([folder]));
    final s = AppState(src, prefs: prefs);
    await s.load();
    final t1 = (await s.addTask('One'))!;
    final t2 = (await s.addTask('Two'))!;
    s.openTaskTab(t1);
    s.openTaskTab(t2);
    s.openFolder('f');
    expect(s.scopeUid, 'f');
    await s.closeTab(DocTab.task(t1));
    expect(s.scopeUid, 'f');
  });

  test('M5: a save that outlives a Space switch yields no container', () async {
    final a = _SlowSave(_space('a'))..gate = Completer<void>();
    final s = AppState(a);
    await s.load();
    final pending = s.ensurePersonalContainer();
    await Future<void>.delayed(Duration.zero);
    final other = Note(
      uid: 'pb',
      summary: 'Personal',
      categories: [AppState.folderTag, personalTag],
    );
    s.source = SpaceNoteSource(_space('b'), seed: _Seed([other]));
    await s.load();
    expect(s.personalContainer?.uid, 'pb');
    a.gate!.complete();
    expect(await pending, isNull);
  });

  test('M5: addProject started in a Space never opens in the next', () async {
    final a = _SlowSave(_space('a'))..gate = Completer<void>();
    final s = AppState(a);
    await s.load();
    final pending = s.addProject('Alpha');
    await Future<void>.delayed(Duration.zero);
    s.source = SpaceNoteSource(_space('b'));
    await s.load();
    a.gate!.complete();
    expect(await pending, isNull);
    expect(s.scopeUid, isNull);
  });

  test('M6: deleteSpace removes every per-Space pref, only its own', () async {
    final m = MemoryStorage();
    final c = catalogWithPlanning(m);
    final s = AppState(c.sourceFor(c.current!), prefs: m, catalog: c);
    await s.load();
    await s.createSpace('Gone');
    final id = s.currentSpaceId!;
    final c2 = c.spaces.length; // planning + Gone
    expect(c2, 2);
    final mine = [
      'davdart.activetab.v1.$id',
      'davdart.tasktags.open.v1.$id',
      'davdart.eventtags.open.v1.$id',
      'davdart.home.cal.open.v1.$id',
      'davdart.home.focus.v1.$id',
      'davdart.home.card.collapsed.v1.tasks.$id',
      'davdart.home.card.collapsed.v1.events.$id',
      'davdart.proj.tab.v1.$id.p1',
    ];
    for (final k in mine) {
      m.write(k, 'x');
    }
    m.write('davdart.home.cal.open.v1.planning', 'keep');
    m.write('davdart.proj.tab.v1.planning.p1', 'keep');
    await s.deleteSpace();
    for (final k in mine) {
      expect(m.read(k), isNull, reason: k);
    }
    expect(m.read('davdart.home.cal.open.v1.planning'), 'keep');
    expect(m.read('davdart.proj.tab.v1.planning.p1'), 'keep');
  });

  test('M7: the project index follows the lists as they are set', () async {
    final proj = Note(
      uid: 'c',
      summary: 'Projects',
      categories: [AppState.folderTag, projectsTag],
    );
    final p = Note(
      uid: 'p',
      summary: 'P',
      parentUid: 'c',
      categories: [AppState.folderTag],
    );
    final s = AppState(SpaceNoteSource(_space('s'), seed: _Seed([proj, p])));
    await s.load();
    expect(s.projectIndex.isProject('p'), isTrue);
    // Same Space, projects removed: the next read must not see the old index.
    s.notes = [];
    s.source = SpaceNoteSource(_space('t'));
    await s.load();
    expect(s.projectIndex.isProject('p'), isFalse);
  });

  test('M4: parent walks use cached parents and survive cycles', () async {
    final folder = Note(
      uid: 'f',
      summary: 'F',
      categories: [AppState.folderTag],
    );
    final s = AppState(SpaceNoteSource(_space('s'), seed: _Seed([folder])));
    await s.load();
    final a = (await s.addTask('A', parentUid: 'f'))!;
    final b = (await s.addTask('B', parentUid: a))!;
    final tb = s.taskById(b)!;
    expect(s.taskIsUnder(tb, a), isTrue);
    expect(s.taskIsUnder(tb, 'f'), isTrue);
    expect(s.taskIsUnder(tb, 'nope'), isFalse);
    // A parent loop ends.
    final x = Task(uid: 'x', summary: 'x', parentUid: 'y');
    final y = Task(uid: 'y', summary: 'y', parentUid: 'x');
    s.tasks = [x, y];
    expect(s.taskIsUnder(x, 'f'), isFalse);
    expect(s.taskIsUnder(x, 'y'), isTrue);
  });
}
