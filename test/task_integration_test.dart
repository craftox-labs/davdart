import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

/// Live VTODO round trip, same gating as integration_test.dart. Point
/// DAVDART_TEST_URL at a scratch collection only.
void main() {
  final env = Platform.environment;
  final url = env['DAVDART_TEST_URL'];
  final skipReason = (url == null || url.isEmpty)
      ? 'DAVDART_TEST_URL not set (live CalDAV integration test)'
      : null;

  test('live: tasks next to notes in one collection', skip: skipReason,
      () async {
    final c = CalDavClient(
      collection: Uri.parse(url!),
      username: env['DAVDART_TEST_USER'] ?? '',
      password: env['DAVDART_TEST_PASSWORD'] ?? '',
    );
    final stamp = DateTime.now().microsecondsSinceEpoch;
    Task? task;
    Note? note;
    try {
      note = await c.putNote(Note(uid: 'davdart-it-n-$stamp', summary: 'N'));
      task = await c.putTask(Task(
        uid: 'davdart-it-t-$stamp',
        summary: 'Task, with; chars',
        description: 'one\ntwo',
        status: 'NEEDS-ACTION',
        priority: 3,
        due: ICalDate.date(2026, 12, 24),
        dtstart: ICalDate('20261201T090000', ';TZID=Europe/Berlin'),
        rrule: 'FREQ=WEEKLY;BYDAY=MO',
        categories: ['a', 'status-doing'],
        parentUid: note.uid,
        extraLines: [
          'X-DAVDART-TEST:1',
          'BEGIN:VALARM',
          'ACTION:DISPLAY',
          'TRIGGER:-PT15M',
          'DESCRIPTION:x',
          'END:VALARM',
        ],
      ));
      final got = await c.getTask(task.href!);
      expect(got.summary, 'Task, with; chars');
      expect(got.description, 'one\ntwo');
      expect(got.priority, 3);
      expect(got.due, ICalDate.date(2026, 12, 24));
      expect(got.dtstart!.tzid, 'Europe/Berlin');
      expect(got.rrule, 'FREQ=WEEKLY;BYDAY=MO');
      expect(got.parentUid, note.uid);
      expect(got.extraLines, contains('BEGIN:VALARM'));
      expect((await c.listTasks()).map((t) => t.uid), contains(task.uid));
      expect(
          (await c.listTasks()).map((t) => t.uid), isNot(contains(note.uid)));
      expect((await c.listNotes()).map((n) => n.uid), contains(note.uid));
      expect(
          (await c.listNotes()).map((n) => n.uid), isNot(contains(task.uid)));
      final sync = await c.syncTasks();
      expect(sync.changed.map((t) => t.uid), contains(task.uid));
      got.complete(DateTime.now());
      task = await c.putTask(got);
      final done = await c.getTask(task.href!);
      expect(done.status, 'COMPLETED');
      expect(done.completed, isNotNull);
      expect(() => c.putTask(got), throwsA(isA<ConflictException>()));
    } finally {
      if (task != null) await c.deleteTask(task);
      if (note != null) await c.deleteNote(note);
      c.close();
    }
  });
}
