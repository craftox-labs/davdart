import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/note_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../test/support/fake_caldav.dart';
import 'catalog_helper.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [
    Note(uid: 'a', summary: 'Alpha', description: 'Alpha body'),
  ];
}

class _ReadOnly implements NoteSource {
  @override
  Future<List<Note>> load() async => [Note(uid: 'a', summary: 'Alpha')];
}

Future<AppState> _open(
  MemoryStorage m, {
  NoteSource? seed,
  http.Client? client,
}) async {
  final c = catalogWithPlanning(
    m,
    planningSeed: seed,
    davBase: Uri.parse('https://fake.test/dav/'),
    httpClient: client,
  );
  final s = AppState(c.sourceFor(c.current!), prefs: m, catalog: c);
  await s.load();
  return s;
}

final _now = DateTime.utc(2026, 11, 20, 12);

Task _t(String uid, {String? due, String? params, String? rrule}) => Task(
  uid: uid,
  summary: uid,
  due: due == null ? null : ICalDate(due, params ?? ''),
  rrule: rrule,
);

void main() {
  group('empty', () {
    test('no tasks: nothing changes and nothing is written', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      expect(s.tasks, isEmpty);
      expect(s.taskError, isNull);
      expect(s.openTasks(), isEmpty);
      expect(s.overdueTasks(), isEmpty);
      expect(s.dueTodayTasks(), isEmpty);
      expect(s.completedTasks(), isEmpty);
      expect(s.tasksByParent(null), isEmpty);
      expect(s.taskTags, isEmpty);
      expect(await s.searchAllSpaces('alpha'), hasLength(1));
      expect(m.keys.where((k) => k.contains('tasks')), isEmpty);
      expect(s.notes.map((n) => n.uid), ['a']);
    });

    test('no Space and a read-only feed reject task writes', () async {
      final s = AppState(_ReadOnly());
      await s.load();
      expect(s.tasksEditable, isFalse);
      expect(await s.addTask('x'), isNull);
      expect(s.error, contains('read-only'));
      expect(s.tasks, isEmpty);
      final e = AppState(const EmptyNoteSource());
      await e.load();
      expect(await e.addTask('x'), isNull);
    });
  });

  group('operations', () {
    test(
      'add persists under the Space key; planning keeps legacy key',
      () async {
        final m = MemoryStorage();
        final s = await _open(m, seed: _Seed());
        final uid = await s.addTask(' Pay rent ', tags: ['home', 'status-x']);
        expect(uid, isNotNull);
        expect(s.tasks.single.summary, 'Pay rent');
        expect(s.tasks.single.categories, ['home']);
        expect(m.read('davdart.tasks.v1'), contains('Pay rent'));
        await s.createSpace('Other');
        final id = s.currentSpaceId!;
        await s.addTask('Other task');
        expect(m.read('sp.$id.tasks.v1'), contains('Other task'));
        expect(m.read('sp.$id.tasks.v1'), isNot(contains('Pay rent')));
        expect(await s.addTask('  '), isNull);
        // restart reloads them
        await s.switchSpace(SpaceCatalog.planningId);
        expect(s.tasks.map((t) => t.summary), ['Pay rent']);
        final again = await _open(m);
        expect(again.tasks.map((t) => t.summary), ['Pay rent']);
      },
    );

    test('edit: title, text, tags keep status tags, due, priority', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final uid = (await s.addTask('One'))!;
      await s.setTaskStatus(uid, 'blocked');
      expect(
        await s.updateTask(
          uid,
          title: 'Two',
          description: 'text',
          tags: ['x', 'kind-folder'],
          setDue: true,
          due: ICalDate.date(2026, 12, 1),
          setPriority: true,
          priority: 2,
        ),
        isTrue,
      );
      var t = s.taskById(uid)!;
      expect(t.summary, 'Two');
      expect(t.description, 'text');
      expect(t.categories, containsAll(['status-blocked', 'x']));
      expect(t.categories, isNot(contains('kind-folder')));
      expect(t.due!.value, '20261201');
      expect(t.priority, 2);
      expect(await s.updateTask(uid, title: '  '), isFalse);
      await s.updateTask(uid, setDue: true, setPriority: true);
      t = s.taskById(uid)!;
      expect(t.due, isNull);
      expect(t.priority, isNull);
      expect(t.summary, 'Two');
    });

    test('a cancelled task is reopened by the checkbox', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final uid = (await s.addTask('Do'))!;
      expect(await s.setTaskStatus(uid, 'cancelled'), isTrue);
      expect(s.taskById(uid)!.status, 'CANCELLED');
      expect(await s.toggleTask(uid), isTrue);
      expect(s.taskById(uid)!.status, 'NEEDS-ACTION');
      expect(s.taskById(uid)!.isClosed, isFalse);
    });

    test('complete, reopen, repeating tasks stay open with a reason', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final uid = (await s.addTask('Do'))!;
      expect(await s.toggleTask(uid), isTrue);
      expect(s.taskById(uid)!.isCompleted, isTrue);
      expect(s.completedTasks().map((t) => t.uid), [uid]);
      expect(s.openTasks(), isEmpty);
      expect(await s.toggleTask(uid), isTrue);
      expect(s.taskById(uid)!.status, 'NEEDS-ACTION');
      expect(s.taskById(uid)!.completed, isNull);
      // a repeating task (as another client made it)
      final src = s.source as SpaceNoteSource;
      await src.saveTask(_t('rep', rrule: 'FREQ=WEEKLY'));
      await s.load();
      expect(s.taskCompletionBlockerFor('rep'), contains('repeats'));
      expect(await s.setTaskDone('rep', true), isFalse);
      expect(await s.toggleTask('rep'), isFalse);
      expect(await s.setTaskStatus('rep', 'done'), isFalse);
      expect(s.taskById('rep')!.isClosed, isFalse);
      expect(s.taskCompletionBlockerFor(uid), isNull);
    });

    test('parent may be a note or a task; loops are refused', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final a = (await s.addTask('A', parentUid: 'a'))!; // under note 'a'
      final b = (await s.addTask('B', parentUid: a))!; // under task
      final c = (await s.addTask('C', parentUid: 'nope'))!; // unknown: top
      expect(s.taskById(a)!.parentUid, 'a');
      expect(s.taskById(c)!.parentUid, isNull);
      expect(s.findItem('a'), isA<Note>());
      expect(s.findItem(a), isA<Task>());
      expect(s.findItem('zz'), isNull);
      expect(s.tasksByParent('a').map((t) => t.uid), [a]);
      expect(s.tasksByParent(a).map((t) => t.uid), [b]);
      expect(s.tasksByParent(null).map((t) => t.uid), [c]);
      expect(s.canMoveTask(a, b), isFalse); // under its own child
      expect(s.canMoveTask(a, a), isFalse);
      expect(s.canMoveTask(b, 'a'), isTrue);
      expect(s.canMoveTask(b, 'missing'), isFalse);
      await s.updateTask(a, setParent: true, parentUid: b, title: 'A2');
      expect(s.taskById(a)!.parentUid, 'a'); // move dropped, rest saved
      expect(s.taskById(a)!.summary, 'A2');
      await s.updateTask(b, setParent: true, parentUid: null);
      expect(s.tasksByParent(null).map((t) => t.uid), containsAll([b, c]));
    });

    test('delete moves sub-tasks and sub-notes up', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final p = (await s.addTask('P', parentUid: 'a'))!;
      final k = (await s.addTask('K', parentUid: p))!;
      final src = s.source as SpaceNoteSource;
      await src.save(Note(uid: 'n2', summary: 'Sub note', parentUid: p));
      await s.load();
      expect(await s.deleteTask(p), isTrue);
      expect(s.taskById(p), isNull);
      expect(s.taskById(k)!.parentUid, 'a');
      expect(s.tree.find('n2')!.note.parentUid, 'a');
      expect(await s.deleteTask('nope'), isFalse);
    });

    test('tags on tasks', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      await s.addTask('x', tags: ['b', 'a']);
      await s.addTask('y', tags: ['a']);
      expect(s.taskTags, ['a', 'b']);
    });
  });

  group('selectors and overdue', () {
    late AppState s;
    setUp(() async {
      s = await _open(MemoryStorage(), seed: _Seed());
      final src = s.source as SpaceNoteSource;
      for (final t in [
        _t('past-day', due: '20261119', params: ';VALUE=DATE'),
        _t('today-allday', due: '20261120', params: ';VALUE=DATE'),
        _t('future', due: '20261201', params: ';VALUE=DATE'),
        _t('past-utc', due: '20261120T100000Z'),
        _t('later-utc', due: '20261120T230000Z'),
        _t(
          'zoned-recent',
          due: '20261120T080000',
          params: ';TZID=Europe/Berlin',
        ),
        _t('zoned-old', due: '20261119T080000', params: ';TZID=Europe/Berlin'),
        _t('none'),
      ]) {
        await src.saveTask(t);
      }
      await s.load();
    });

    test('overdue and today, by real instants', () {
      // _now is noon UTC; local day may differ in a far zone, so pin the
      // checks that cannot flip: ordering and the conservative rules.
      final o = s.overdueTasks(_now).map((t) => t.uid).toSet();
      expect(o, containsAll(['past-day', 'past-utc', 'zoned-old']));
      expect(o, isNot(contains('future')));
      expect(o, isNot(contains('later-utc')));
      expect(o, isNot(contains('none')));
      // 08:00 Berlin is 07:00Z: overdue at noon UTC, not at 06:59Z.
      expect(o, contains('zoned-recent'));
      final early = DateTime.utc(2026, 11, 20, 6, 59);
      expect(
        s.overdueTasks(early).map((t) => t.uid),
        isNot(contains('zoned-recent')),
      );
    });

    test('open list puts overdue first, undated last', () {
      final ids = s.openTasks(_now).map((t) => t.uid).toList();
      expect(ids.last, 'none');
      expect(ids.indexOf('past-day'), lessThan(ids.indexOf('future')));
      expect(ids.indexOf('zoned-old'), lessThan(ids.indexOf('past-utc')));
    });

    test('due today excludes overdue and closed', () {
      final local = DateTime(2026, 11, 20, 9);
      final today = s.dueTodayTasks(local).map((t) => t.uid);
      expect(today, contains('today-allday'));
      expect(today, isNot(contains('future')));
      expect(today, isNot(contains('past-day')));
    });

    test(
      'completed list is newest first and closed tasks are not open',
      () async {
        await s.setTaskDone('future', true);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await s.setTaskDone('none', true);
        expect(s.completedTasks().map((t) => t.uid), ['none', 'future']);
        expect(s.openTasks(_now).map((t) => t.uid), isNot(contains('none')));
        expect(s.overdueTasks(_now), isNot(contains(s.taskById('future'))));
      },
    );
  });

  group('drafts', () {
    test('edit session: dirty, save, discard, empty title', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final uid = (await s.addTask('One'))!;
      s.startTaskEdit(uid);
      final d = s.taskDraftFor(uid)!;
      expect(s.dirtyTaskFor(uid), isFalse);
      d.titleController.text = '';
      expect(await s.saveTaskDraft(uid), isFalse);
      d.titleController.text = 'Two';
      d.setPriority(3);
      d.setDue(ICalDate.date(2026, 12, 2));
      d.tagsController.text = 'a, b';
      expect(s.dirtyTaskFor(uid), isTrue);
      expect(await s.saveTaskDraft(uid), isTrue);
      expect(s.taskDraftFor(uid), isNull);
      final t = s.taskById(uid)!;
      expect((t.summary, t.priority, t.due!.value), ('Two', 3, '20261202'));
      expect(t.categories, ['a', 'b']);
      s.startTaskEdit(uid);
      s.taskDraftFor(uid)!.titleController.text = 'Nope';
      s.discardTaskDraft(uid);
      expect(s.taskById(uid)!.summary, 'Two');
    });

    test('text typed while saving stays as the draft', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final uid = (await s.addTask('One'))!;
      s.startTaskEdit(uid);
      final d = s.taskDraftFor(uid)!;
      d.bodyController.text = 'first';
      final saving = s.saveTaskDraft(uid);
      d.bodyController.text = 'first, more'; // before the save finishes
      expect(await saving, isTrue);
      expect(s.taskDraftFor(uid), same(d));
      expect(s.dirtyTaskFor(uid), isTrue);
      expect(await s.saveTaskDraft(uid), isTrue);
      expect(s.taskDraftFor(uid), isNull);
      expect(s.taskById(uid)!.description, 'first, more');
    });

    test('switching Space asks about an unsaved task edit', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      await s.createSpace('Other');
      await s.switchSpace(SpaceCatalog.planningId);
      final uid = (await s.addTask('One'))!;
      s.startTaskEdit(uid);
      s.taskDraftFor(uid)!.titleController.text = 'Edited';
      s.leaveGuard = () async => DraftChoice.keep;
      expect(await s.switchSpace(s.spaces.last.id), isFalse);
      s.leaveGuard = () async => DraftChoice.save;
      expect(await s.switchSpace(s.spaces.last.id), isTrue);
      await s.switchSpace(SpaceCatalog.planningId);
      expect(s.tasks.single.summary, 'Edited');
    });

    test('a read-only Space cannot start an edit', () async {
      final s = AppState(_ReadOnly());
      await s.load();
      s.startTaskEdit('x');
      expect(s.taskDrafts, isEmpty);
    });
  });

  group('spaces', () {
    test('moveToSpace moves a task with its sub-tasks, copy first', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      final p = (await s.addTask('P'))!;
      await s.addTask('K', parentUid: p, due: ICalDate.date(2026, 12, 3));
      await s.addTask('Stay');
      await s.createSpace('Other');
      final other = s.currentSpaceId!;
      await s.switchSpace(SpaceCatalog.planningId);
      expect(await s.moveToSpace(p, other), 2);
      expect(s.tasks.map((t) => t.summary), ['Stay']);
      await s.switchSpace(other);
      expect(s.tasks.map((t) => t.summary).toSet(), {'P', 'K'});
      final moved = s.tasks.firstWhere((t) => t.summary == 'K');
      expect(s.taskById(moved.parentUid!)!.summary, 'P');
      expect(moved.due!.value, '20261203');
      expect(s.tasks.firstWhere((t) => t.summary == 'P').parentUid, isNull);
      expect(s.tasks.any((t) => t.uid == p), isFalse); // new ids
    });

    test('moving a note takes the tasks under it', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      await s.addTask('Under a', parentUid: 'a');
      await s.createSpace('Other');
      final other = s.currentSpaceId!;
      await s.switchSpace(SpaceCatalog.planningId);
      expect(await s.moveToSpace('a', other), 2);
      expect(s.tasks, isEmpty);
      expect(s.notes, isEmpty);
      await s.switchSpace(other);
      expect(s.notes.single.summary, 'Alpha');
      expect(s.tasks.single.parentUid, s.notes.single.uid);
    });

    test('a repeating task with overrides is refused, nothing lost', () async {
      final s = await _open(MemoryStorage(), seed: _Seed());
      final src = s.source as SpaceNoteSource;
      await src.saveTask(
        _t('r', rrule: 'FREQ=DAILY')
          ..siblingLines.addAll([
            'BEGIN:VTODO',
            'UID:r',
            'RECURRENCE-ID:20261121T000000Z',
            'SUMMARY:override',
            'END:VTODO',
          ]),
      );
      await s.load();
      await s.createSpace('Other');
      final other = s.currentSpaceId!;
      await s.switchSpace(SpaceCatalog.planningId);
      expect(await s.moveToSpace('r', other), isNull);
      expect(s.error, contains('repeating'));
      expect(s.tasks.map((t) => t.uid), ['r']);
    });

    test('deleteSpace removes the task keys, only its own', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      await s.addTask('Legacy');
      await s.createSpace('Other');
      final other = s.currentSpaceId!;
      await s.addTask('Mine');
      await s.createSpace('Other.sub'); // id prefix lookalike
      await s.addTask('Sub');
      final sub = s.currentSpaceId!;
      await s.switchSpace(other);
      await s.deleteSpace();
      expect(m.keys.where((k) => k.startsWith('sp.$other.')), isEmpty);
      expect(m.read('sp.$sub.tasks.v1'), contains('Sub'));
      expect(m.read('davdart.tasks.v1'), contains('Legacy'));
      await s.switchSpace(SpaceCatalog.planningId);
      await s.deleteSpace();
      expect(m.read('davdart.tasks.v1'), isNull);
      expect(m.read('sp.$sub.tasks.v1'), contains('Sub'));
    });

    test('search covers tasks in every Space', () async {
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed());
      await s.addTask('Buy Milk', description: 'whole');
      await s.createSpace('Other');
      await s.addTask('Call dentist', description: 'about MILK teeth');
      final hits = await s.searchAllSpaces('milk');
      expect(hits.map((h) => h.isTask), [true, true]);
      expect(hits.map((h) => h.task!.summary).toSet(), {
        'Buy Milk',
        'Call dentist',
      });
      expect(hits.first.note.uid, hits.first.task!.uid);
      expect(await s.searchAllSpaces('alpha'), hasLength(1));
      expect((await s.searchAllSpaces('alpha')).single.isTask, isFalse);
      // opening a task hit switches Space and remembers the task
      final far = hits.firstWhere((h) => h.space.id == SpaceCatalog.planningId);
      await s.openHit(far);
      expect(s.currentSpaceId, SpaceCatalog.planningId);
      expect(s.selectedTaskUid, far.task!.uid);
    });

    test('a damaged task store is kept aside and notes still load', () async {
      final m = MemoryStorage()
        ..write('davdart.space.v1', '{"notes":{},"revisions":[]}')
        ..write('davdart.tasks.v1', 'not json');
      final s = await _open(m);
      expect(s.tasks, isEmpty);
      expect(m.read('davdart.tasks.v1.unreadable'), 'not json');
      expect(s.error, isNull);
    });
  });

  group('sync', () {
    test('tasks sync with notes in one pass; both directions', () async {
      final server = FakeCalDav();
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed(), client: server.client);
      await s.addTask('Local task');
      server.external(
        'rt.ics',
        'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\n'
            'BEGIN:VTODO\r\nUID:rt\r\nDTSTAMP:20261119T000000Z\r\n'
            'SUMMARY:Remote task\r\nEND:VTODO\r\nEND:VCALENDAR\r\n',
      );
      await s.connect('c/', 'tm', 'pw');
      expect(s.syncMessage, startsWith('Synced'));
      expect(s.taskError, isNull);
      expect(s.tasks.map((t) => t.summary).toSet(), {
        'Local task',
        'Remote task',
      });
      expect(
        server.ics.values.where((v) => v.contains('BEGIN:VTODO')),
        hasLength(2),
      );
      expect(
        server.ics.values.where((v) => v.contains('BEGIN:VJOURNAL')),
        hasLength(1),
      );
      // an edit syncs, a completion arrives, a delete goes
      final uid = s.tasks.firstWhere((t) => t.summary == 'Local task').uid;
      await s.toggleTask(uid);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        server.ics.values.any((v) => v.contains('STATUS:COMPLETED')),
        isTrue,
      );
      await s.deleteTask('rt');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.ics.containsKey('rt.ics'), isFalse);
      expect(await (s.source as SpaceNoteSource).unsyncedCount(), 0);
    });

    test('a task sync failure is non-fatal and notes are not lost', () async {
      final server = FakeCalDav();
      var failTasks = false;
      var passes = 0;
      final client = MockClient((r) async {
        if (r.method == 'REPORT' && r.body.contains('sync-collection')) {
          passes++;
          // each pass pulls notes, then tasks, then events
          if (failTasks && passes % 3 == 2) throw http.ClientException('boom');
        }
        return server.respond(r);
      });
      final m = MemoryStorage();
      final s = await _open(m, seed: _Seed(), client: client);
      await s.connect('c/', 'tm', 'pw');
      expect(s.taskError, isNull);
      failTasks = true;
      await s.addNote('Fresh note');
      await s.addTask('Kept task');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await s.sync();
      expect(s.taskError, contains('Tasks'));
      expect(s.syncMessage, contains('Tasks'));
      expect(s.syncMessage, startsWith('Synced'));
      expect(s.error, isNull);
      expect(s.notes.map((n) => n.summary), contains('Fresh note'));
      expect(s.tasks.map((t) => t.summary), contains('Kept task'));
      expect(
        server.ics.values.any((v) => v.contains('SUMMARY:Fresh note')),
        isTrue,
      );
      // and it recovers
      failTasks = false;
      await s.sync();
      expect(s.taskError, isNull);
      expect(
        server.ics.values.any((v) => v.contains('SUMMARY:Kept task')),
        isTrue,
      );
    });

    test(
      'a task push the server refuses is reported, the task stays',
      () async {
        final server = FakeCalDav();
        final client = MockClient((r) async {
          if (r.method == 'PUT' && r.body.contains('BEGIN:VTODO')) {
            return http.Response('no', 403);
          }
          return server.respond(r);
        });
        final s = await _open(MemoryStorage(), seed: _Seed(), client: client);
        await s.connect('c/', 'tm', 'pw');
        await s.addTask('Refused');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(s.taskError, isNotNull);
        expect(s.tasks.map((t) => t.summary), ['Refused']);
        expect(s.error, isNull);
      },
    );

    test('disconnect keeps tasks locally; reconnect sends them', () async {
      final server = FakeCalDav();
      final s = await _open(
        MemoryStorage(),
        seed: _Seed(),
        client: server.client,
      );
      await s.connect('c/', 'tm', 'pw');
      await s.addTask('T');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await s.disconnect();
      expect(s.tasks.map((t) => t.summary), ['T']);
      await s.addTask('Offline');
      await s.connect('c/', 'tm', 'pw');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        server.ics.values.where((v) => v.contains('BEGIN:VTODO')),
        hasLength(2),
      );
    });
  });
}
