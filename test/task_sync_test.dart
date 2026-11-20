import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

import 'support/fake_caldav.dart';
import 'task_test.dart' show nextcloud, thunderbird;

String tics(String uid, String summary, {String extra = ''}) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VTODO\r\nUID:$uid\r\n'
    'DTSTAMP:20261101T080000Z\r\nSUMMARY:$summary\r\n$extra'
    'END:VTODO\r\nEND:VCALENDAR\r\n';

void main() {
  late FakeCalDav server;
  late DateTime clock;

  CalDavClient client() => CalDavClient(
      collection: FakeCalDav.collection,
      username: 'u',
      password: 'p',
      client: server.client);
  TaskSyncEngine tengine(TaskStore s) => TaskSyncEngine(client(), s,
      now: () => clock = clock.add(const Duration(minutes: 1)));
  SyncEngine nengine(NoteStore s) => SyncEngine(client(), s,
      now: () => clock = clock.add(const Duration(minutes: 1)));

  setUp(() {
    server = FakeCalDav();
    clock = DateTime.utc(2026, 11, 20, 12);
  });

  group('merge', () {
    final base = Task(
        uid: 'm',
        summary: 'Base',
        description: 'a\nb\nc',
        status: 'NEEDS-ACTION',
        categories: ['x'],
        lastModified: DateTime.utc(2026, 11, 1));

    test('independent field edits combine', () {
      final l = base.copyWith(
          due: ICalDate.date(2026, 12, 1),
          description: 'A\nb\nc',
          categories: ['x', 'l'],
          lastModified: DateTime.utc(2026, 11, 2));
      final r = base.copyWith(
          priority: 1,
          description: 'a\nb\nC',
          categories: ['x', 'r'],
          lastModified: DateTime.utc(2026, 11, 3));
      final m = mergeTasks(base, l, r);
      expect(m.hadConflict, isFalse);
      expect(m.task.due, ICalDate.date(2026, 12, 1));
      expect(m.task.priority, 1);
      expect(m.task.description, 'A\nb\nC');
      expect(m.task.categories.toSet(), {'x', 'l', 'r'});
    });

    test('same field changed twice: later edit wins, loser reported', () {
      final l = base.copyWith(
          summary: 'Local', lastModified: DateTime.utc(2026, 11, 5));
      final r = base.copyWith(
          summary: 'Remote', lastModified: DateTime.utc(2026, 11, 4));
      final m = mergeTasks(base, l, r);
      expect(m.task.summary, 'Local');
      expect(m.conflicts.single.what, 'title');
      expect(m.conflicts.single.remote, 'Remote');
    });

    test('completed locally, retitled remotely: both apply', () {
      final l = base.copyWith(lastModified: DateTime.utc(2026, 11, 5))
        ..complete(DateTime.utc(2026, 11, 5));
      final r = base.copyWith(
          summary: 'New', lastModified: DateTime.utc(2026, 11, 4));
      final m = mergeTasks(base, l, r);
      expect(m.hadConflict, isFalse);
      expect(m.task.summary, 'New');
      expect(m.task.status, 'COMPLETED');
      expect(m.task.completed, DateTime.utc(2026, 11, 5));
    });

    test('reopened remotely wins over stale completion time', () {
      final done = base.copyWith()..complete(DateTime.utc(2026, 11, 2));
      final l = done.copyWith(lastModified: DateTime.utc(2026, 11, 2));
      final r = done.copyWith(lastModified: DateTime.utc(2026, 11, 3))
        ..reopen();
      final m = mergeTasks(done, l, r);
      expect(m.task.status, 'NEEDS-ACTION');
      expect(m.task.completed, isNull);
    });

    test('unknown lines: the side that changed them wins', () {
      final r = base.copyWith(lastModified: DateTime.utc(2026, 11, 3));
      r.extraLines.add('X-FOO:1');
      final l =
          base.copyWith(summary: 'L', lastModified: DateTime.utc(2026, 11, 2));
      final m = mergeTasks(base, l, r);
      expect(m.task.extraLines, ['X-FOO:1']);
      expect(m.task.summary, 'L');
    });
  });

  group('client', () {
    test('listTasks asks for VTODO and returns tasks only', () async {
      server.external('n.ics', serializeNote(Note(uid: 'n', summary: 'N')));
      server.external('t.ics', tics('t', 'T'));
      final c = client();
      final tasks = await c.listTasks();
      expect(tasks.map((t) => t.uid), ['t']);
      expect(tasks.single.href, '/dav/c/t.ics');
      expect((await c.listNotes()).map((n) => n.uid), ['n']);
    });

    test('put, get, conflict, delete', () async {
      final c = client();
      final stored = await c.putTask(Task(uid: 'a', summary: 'A'));
      expect(server.ics['a.ics'], contains('BEGIN:VTODO'));
      expect(stored.etag, isNotNull);
      expect((await c.getTask('a.ics')).summary, 'A');
      server.external('a.ics', tics('a', 'Other'));
      stored.summary = 'Mine';
      expect(() => c.putTask(stored), throwsA(isA<ConflictException>()));
      final cur = await c.getTask('a.ics');
      await c.deleteTask(cur);
      expect(server.ics, isEmpty);
    });

    test('syncTasks and sync each keep their own component', () async {
      server.external('n.ics', serializeNote(Note(uid: 'n', summary: 'N')));
      server.external('t.ics', tics('t', 'T'));
      final skipped = <String?>[];
      final c = CalDavClient(
          collection: FakeCalDav.collection,
          username: 'u',
          password: 'p',
          client: server.client,
          onResourceError: (h, e) => skipped.add(h));
      expect((await c.syncTasks()).changed.map((t) => t.uid), ['t']);
      expect((await c.sync()).changed.map((n) => n.uid), ['n']);
      expect(skipped, isEmpty);
    });
  });

  group('engine', () {
    test('pulls tasks, pushes an edit, ignores notes', () async {
      server.external('n.ics', serializeNote(Note(uid: 'n', summary: 'N')));
      server.external('t.ics', nextcloud);
      final e = tengine(MemoryTaskStore());
      final r = await e.sync();
      expect(r.pulled, 1);
      final t = (await e.tasks()).single;
      t.complete(DateTime.utc(2026, 11, 20));
      await e.save(t);
      expect((await e.sync()).pushed, 1);
      final body = server.ics['t.ics']!;
      expect(body, contains('STATUS:COMPLETED'));
      expect(body, contains('BEGIN:VALARM'));
      expect(body, contains('X-APPLE-SORT-ORDER:12'));
      expect(server.ics['n.ics'], contains('BEGIN:VJOURNAL'));
      final r2 = await e.sync();
      expect(r2.pulled + r2.pushed + r2.merged, 0);
    });

    test('notes and tasks engines share a collection without interfering',
        () async {
      server.external('t.ics', tics('t', 'T'));
      server.external('rr.ics', thunderbird);
      final ns = MemoryNoteStore(), ts = MemoryTaskStore();
      final ne = nengine(ns), te = tengine(ts);
      await ne.save(Note(uid: 'n', summary: 'N'));
      await te.save(Task(uid: 'new', summary: 'New'));
      await ne.sync();
      await te.sync();
      await ne.sync();
      expect((await ne.notes()).map((n) => n.uid), ['n']);
      expect((await te.tasks()).map((t) => t.uid).toSet(), {'t', 'new', 't-2'});
      // Foreign tasks stay exactly as they were.
      expect(server.ics['rr.ics'], thunderbird);
      expect(server.ics['t.ics'], tics('t', 'T'));
      expect(server.ics.keys.where((k) => k != 't.ics' && k != 'rr.ics'),
          hasLength(2));
    });

    test('remote delete, local delete and recreate', () async {
      server.external('a.ics', tics('a', 'A'));
      server.external('b.ics', tics('b', 'B'));
      final e = tengine(MemoryTaskStore());
      await e.sync();
      server.externalDelete('a.ics');
      await e.delete('b');
      final r = await e.sync();
      expect(r.deleted, 1);
      expect(await e.tasks(), isEmpty);
      expect(server.ics, isEmpty);
    });

    test('overlapping edits merge field by field; conflict kept as revision',
        () async {
      server.external('a.ics', tics('a', 'A', extra: 'PRIORITY:5\r\n'));
      final e = tengine(MemoryTaskStore());
      await e.sync();
      final t = (await e.tasks()).single..summary = 'Local title';
      await e.save(t);
      server.external(
          'a.ics', tics('a', 'Remote title', extra: 'PRIORITY:1\r\n'));
      final r = await e.sync();
      expect(r.merged, 1);
      expect(r.conflicts.single.what, 'title');
      final got = (await e.tasks()).single;
      expect(got.priority, 1);
      expect(got.summary, 'Local title');
      expect(server.ics['a.ics'], contains('SUMMARY:Local title'));
      expect(server.ics['a.ics'], contains('PRIORITY:1'));
    });

    test('store survives toJson and loadJson', () async {
      server.external('t.ics', nextcloud);
      final s = MemoryTaskStore();
      await tengine(s).sync();
      final s2 = MemoryTaskStore()..loadJson(s.toJson());
      final t = (await s2.get('t-1'))!;
      expect(t.local.due, ICalDate.date(2026, 11, 25));
      expect(t.local.extraLines, contains('BEGIN:VALARM'));
      expect(t.local.etag, isNotNull);
    });

    test('token rejected falls back to a full sync', () async {
      server.external('a.ics', tics('a', 'A'));
      final s = MemoryTaskStore();
      final e = tengine(s);
      await e.sync();
      server.rejectTokens = true;
      server.external('b.ics', tics('b', 'B'));
      await e.sync();
      expect((await e.tasks()).length, 2);
    });
  });
}
