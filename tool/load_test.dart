// A load test for the UI-free core, run as a plain script:
//
//   dart run tool/load_test.dart
//
// It builds a synthetic Space of 2000 items in memory (notes with parent
// chains up to depth 6, tasks and events with parents, tags, statuses,
// priorities), times the core paths the app and CLI lean on, and prints a
// table. Anything over 50 ms is reported as slow. No network and no live
// collection: the CalDAV side is the in-memory FakeCalDav from test/support.
//
// Results are written up in docs/2026-11-25-load-test.md.
import 'dart:math';

import 'package:davdart/davdart.dart';

import '../test/support/fake_caldav.dart';

const nNotes = 1000;
const nTasks = 600;
const nEvents = 400;
const slowMs = 50;

final _start = DateTime.utc(2026, 11, 25, 12);
final _rnd = Random(7);

final _rows = <(String, double, String)>[];

/// Times one synchronous step and records it.
T _t<T>(String name, T Function() body, {String note = ''}) {
  final w = Stopwatch()..start();
  final r = body();
  w.stop();
  _rows.add((name, w.elapsedMicroseconds / 1000, note));
  return r;
}

/// Times one asynchronous step and records it.
Future<T> _at<T>(String name, Future<T> Function() body,
    {String note = ''}) async {
  final w = Stopwatch()..start();
  final r = await body();
  w.stop();
  _rows.add((name, w.elapsedMicroseconds / 1000, note));
  return r;
}

// ---------------------------------------------------------------- the data

const _statuses = [
  'backlog',
  'todo',
  'doing',
  'blocked',
  'review',
  'done',
  'canceled',
];
const _oddStatuses = ['waiting', 'someday', 'wip'];
const _priorities = ['high', 'medium', 'low'];

String _pick(List<String> l) => l[_rnd.nextInt(l.length)];

/// The synthetic Space: 1000 notes, 600 tasks, 400 events.
class Data {
  Data() {
    _notes();
    _tasks();
    _events();
  }

  final notes = <Note>[];
  final tasks = <Task>[];
  final events = <Event>[];
  final depth = <String, int>{};
  final kind = <String, String>{};

  /// The deepest folder of the chain f0 -> ... -> f5, used as a scope.
  String spineRoot = '';

  void _notes() {
    // A spine of six nested folders, so a depth-6 chain always exists.
    for (var i = 0; i < 6; i++) {
      final uid = 'f$i';
      if (i == 0) spineRoot = uid;
      _note(uid,
          summary: 'Folder $i',
          parent: i == 0 ? null : 'f${i - 1}',
          folder: true,
          status: _pick(['backlog', 'todo', 'doing']));
    }
    // 20 more root folders, then notes hanging off anything not too deep.
    for (var i = 0; i < 20; i++) {
      _note('r$i', summary: 'Root folder $i', folder: true);
    }
    var n = 0;
    while (notes.length < nNotes) {
      final parent = _parentOf(notes.length);
      final odd = _rnd.nextInt(10) == 0;
      _note('n${n++}',
          summary: 'Note ${notes.length} under ${parent ?? 'top'}',
          parent: parent,
          status: odd
              ? _pick(_oddStatuses)
              : _rnd.nextInt(5) == 0
                  ? null
                  : _pick(_statuses),
          priority: _rnd.nextInt(3) == 0 ? _pick(_priorities) : null,
          body: 'Body of note ${notes.length}. ' * 6,
          tags: ['t${_rnd.nextInt(8)}']);
    }
  }

  /// A parent uid at a depth that keeps chains at 6 at most; null sometimes so
  /// there are top-level notes too.
  String? _parentOf(int i) {
    if (i % 7 == 0) return null;
    final candidates = [
      for (final e in depth.entries)
        if (e.value < 5) e.key,
    ];
    if (candidates.isEmpty) return null;
    return candidates[_rnd.nextInt(candidates.length)];
  }

  void _note(String uid,
      {required String summary,
      String? parent,
      bool folder = false,
      String? status,
      String? priority,
      String body = '',
      List<String> tags = const []}) {
    final d = parent == null ? 0 : (depth[parent] ?? 0) + 1;
    depth[uid] = d;
    kind[uid] = 'note';
    final head = [
      if (priority != null) 'priority: $priority',
      if (status != null) 'status: $status',
    ];
    notes.add(Note(
      uid: uid,
      summary: summary,
      description: head.isEmpty ? body : '${head.join('\n')}\n\n$body',
      categories: [
        if (folder) 'kind-folder',
        if (status != null && _statuses.contains(status)) 'status-$status',
        ...tags,
      ],
      parentUid: parent,
      created: _start.add(Duration(minutes: notes.length)),
      lastModified: _start.add(Duration(minutes: notes.length)),
    ));
  }

  void _tasks() {
    for (var i = 0; i < nTasks; i++) {
      final uid = 'k$i';
      // A third of the tasks hang off a note or another task.
      final parents = [
        for (final e in kind.entries)
          if (e.value == 'note' ||
              (e.value == 'task' && (depth[e.key] ?? 0) < 4))
            e.key,
      ];
      final parent = i % 3 == 0 ? parents[_rnd.nextInt(parents.length)] : null;
      if (parent != null) depth[uid] = (depth[parent] ?? 0) + 1;
      kind[uid] = 'task';
      final t = Task(
        uid: uid,
        summary: 'Task $i',
        description: 'Task body $i',
        categories: ['t${_rnd.nextInt(8)}'],
        status: 'NEEDS-ACTION',
        priority: _rnd.nextInt(3) == 0 ? 1 + _rnd.nextInt(9) : null,
        due: _rnd.nextBool()
            ? ICalDate.date(2026, 12, 1 + _rnd.nextInt(20))
            : ICalDate.utc(_start.add(Duration(hours: i))),
        parentUid: parent,
        created: _start.add(Duration(minutes: i)),
        lastModified: _start.add(Duration(minutes: i)),
      );
      t.setBoardStatus(_pick(_statuses), _start);
      tasks.add(t);
    }
  }

  void _events() {
    for (var i = 0; i < nEvents; i++) {
      final uid = 'e$i';
      final notesOnly = [for (final e in kind.entries) e.key];
      final parent = i % 4 == 0 ? notesOnly[_rnd.nextInt(notesOnly.length)] : null;
      if (parent != null) depth[uid] = (depth[parent] ?? 0) + 1;
      kind[uid] = 'event';
      final day = 1 + _rnd.nextInt(28);
      final hour = _rnd.nextInt(12) + 8;
      String t(int h) => h.toString().padLeft(2, '0');
      events.add(Event(
        uid: uid,
        summary: 'Event $i',
        description: 'Event body $i',
        location: _rnd.nextBool() ? 'Room ${_rnd.nextInt(9)}' : '',
        categories: ['t${_rnd.nextInt(8)}'],
        dtstart: ICalDate('202612${t(day)}T${t(hour)}0000',
            i % 2 == 0 ? ';TZID=Europe/Berlin' : ''),
        dtend: ICalDate('202612${t(day)}T${t(hour + 1)}0000',
            i % 2 == 0 ? ';TZID=Europe/Berlin' : ''),
        parentUid: parent,
        created: _start.add(Duration(minutes: i)),
        lastModified: _start.add(Duration(minutes: i)),
      ));
    }
  }
}

// ------------------------------------------------- the mirror of the app walks

/// True when [child] sits under [uid] at any depth. A mirror of the app's
/// `AppState.taskIsUnder` / `eventIsUnder` (apps/app/lib/state/app_state.dart,
/// read only here): a bounded walk up the parent links of notes, tasks and
/// events, so a loop or an orphan ends instead of hanging.
bool isUnder(String childUid, Map<String, String?> parent, String uid) {
  var cur = parent[childUid];
  for (var i = 0; cur != null && i <= parent.length; i++) {
    if (cur == uid) return true;
    cur = parent[cur];
  }
  return false;
}

// ---------------------------------------------------------------- the steps

Future<void> main() async {
  final data = _t('build the 2000 items (setup)', () => Data(),
      note: '${nNotes + nTasks + nEvents} items');

  // 1. Core parse: one big calendar text per kind, as list() reads it.
  final noteText = serializeNotes(data.notes);
  final taskText = serializeTasks(data.tasks);
  final eventText = serializeEvents(data.events);
  _t('core parse: 1000 notes', () => parseNotes(noteText),
      note: '${(noteText.length / 1024).round()} KiB');
  _t('core parse: 600 tasks', () => parseTasks(taskText),
      note: '${(taskText.length / 1024).round()} KiB');
  _t('core parse: 400 events', () => parseEvents(eventText),
      note: '${(eventText.length / 1024).round()} KiB');
  final tree = _t('NoteTree.build: 1000 notes', () => NoteTree.build(data.notes),
      note: '${data.notes.where((n) => n.parentUid != null).length} nested');
  _t('NoteTree.descendants: one subtree',
      () => tree.descendants(data.spineRoot));

  // 2. ItemService list and board over the same set, on the fake collection.
  final fake = FakeCalDav();
  for (final n in data.notes) {
    fake.external('${n.uid}.ics', serializeNote(n));
  }
  for (final t in data.tasks) {
    fake.external('${t.uid}.ics', serializeTask(t));
  }
  for (final e in data.events) {
    fake.external('${e.uid}.ics', serializeEvent(e));
  }
  final svc = ItemService(CalDavClient(
      collection: FakeCalDav.collection,
      username: 'u',
      password: 'p',
      client: fake.client));
  await _at('ItemService.list: 500 of 2000', () => svc.list(limit: 500),
      note: 'parses all three kinds');
  await _at('ItemService.board()', () => svc.board(),
      note: 'notes only, $nNotes');
  await _at('ItemService.list(under: a folder)',
      () => svc.list(under: data.spineRoot, limit: 500),
      note: 'scope filter');

  // 3. Scope filters and parent-chain walks, as the app does them.
  final parent = <String, String?>{
    for (final n in data.notes) n.uid: n.parentUid,
    for (final t in data.tasks) t.uid: t.parentUid,
    for (final e in data.events) e.uid: e.parentUid,
  };
  _t(
      'scope walk: every task and event under one folder',
      () => [
            for (final t in data.tasks)
              if (isUnder(t.uid, parent, data.spineRoot)) t.uid,
            for (final e in data.events)
              if (isUnder(e.uid, parent, data.spineRoot)) e.uid,
          ],
      note: '${nTasks + nEvents} walks, mirror of the app');
  final project = _t(
      'ProjectIndex build (parent chains, 2000 items)',
      () => ProjectIndex(data.notes, data.tasks, data.events));
  _t('ProjectIndex.statsOf every project', () {
    var n = 0;
    for (final p in project.projects()) {
      n += project.statsOf(p.uid).total;
    }
    return n + project.everythingElse.total;
  });

  // 4. Sync: a first full pull, then a merge of the whole set against a
  // modified copy on the server and a modified local copy.
  final syncServer = FakeCalDav();
  for (final n in data.notes) {
    syncServer.external('${n.uid}.ics', serializeNote(n));
  }
  final space = Space(
      SpaceConfig(id: 's', name: 'Synthetic'),
      MemoryNoteStore(),
      client: CalDavClient(
          collection: FakeCalDav.collection,
          username: 'u',
          password: 'p',
          client: syncServer.client));
  final first = await _at('sync: first pull of 1000 notes', space.sync,
      note: 'no local copies yet');
  if (first == null || first.pulled != nNotes) {
    throw StateError('first sync pulled ${first?.pulled}, expected $nNotes');
  }
  var n = 0;
  for (final local in await space.notes()) {
    // Both sides edited: the local summary and the remote body, so the merge
    // is clean but runs the whole field-by-field path.
    local.summary = '${local.summary} (edited)';
    await space.save(local);
    final remote = parseNote(syncServer.ics['${local.uid}.ics']!);
    remote.description = 'Changed on the server.\n\n${remote.description}';
    syncServer.external('${local.uid}.ics', serializeNote(remote));
    n++;
  }
  final merge = await _at('sync: merge 1000 against a modified copy',
      space.sync,
      note: 'pulls, merges, pushes $n');
  if (merge == null || merge.merged < n || merge.errors.isNotEmpty) {
    throw StateError('merge report looks wrong: $merge');
  }

  _print();
}

void _print() {
  final w = _rows.map((r) => r.$1.length).reduce(max);
  print('\n${'step'.padRight(w)}   ms    note');
  print('${'-' * w}  -----  ${'-' * 30}');
  for (final (name, ms, note) in _rows) {
    final flag = ms > slowMs ? '  SLOW' : '';
    print('${name.padRight(w)}  ${ms.toStringAsFixed(1).padLeft(5)}  $note$flag');
  }
  final slow = [for (final r in _rows) if (r.$2 > slowMs) r.$1];
  print(slow.isEmpty
      ? '\nnothing over $slowMs ms'
      : '\nover $slowMs ms: ${slow.join(', ')}');
}
