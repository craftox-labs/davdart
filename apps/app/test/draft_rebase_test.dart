import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test/support/fake_caldav.dart';
import 'catalog_helper.dart';

class _Seed implements NoteSource {
  @override
  Future<List<Note>> load() async => [Note(uid: 'a', summary: 'Alpha')];
}

String _todo({String summary = 'Task', String body = '', int? priority}) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\n'
    'BEGIN:VTODO\r\nUID:rt\r\nDTSTAMP:20261119T000000Z\r\n'
    'SUMMARY:$summary\r\n'
    '${body.isEmpty ? '' : 'DESCRIPTION:$body\r\n'}'
    '${priority == null ? '' : 'PRIORITY:$priority\r\n'}'
    'END:VTODO\r\nEND:VCALENDAR\r\n';

String _event({String summary = 'Event', String location = ''}) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\n'
    'BEGIN:VEVENT\r\nUID:re\r\nDTSTAMP:20261119T000000Z\r\n'
    'DTSTART:20261201T090000Z\r\nDTEND:20261201T100000Z\r\n'
    'SUMMARY:$summary\r\n'
    '${location.isEmpty ? '' : 'LOCATION:$location\r\n'}'
    'END:VEVENT\r\nEND:VCALENDAR\r\n';

Future<AppState> _open(FakeCalDav server) async {
  final m = MemoryStorage();
  final c = catalogWithPlanning(
    m,
    planningSeed: _Seed(),
    davBase: Uri.parse('https://fake.test/dav/'),
    httpClient: server.client,
  );
  final s = AppState(c.sourceFor(c.current!), prefs: m, catalog: c)
    ..narrow = true;
  await s.load();
  await s.connect('c/', 'tm', 'pw');
  return s;
}

void main() {
  group('a clean draft takes what a sync brings', () {
    test('task: a clean text buffer follows the synced text', () async {
      final server = FakeCalDav()
        ..external('rt.ics', _todo(summary: 'Old', body: 'old body'));
      final s = await _open(server);
      s.startTaskEdit('rt');
      final d = s.taskDraftFor('rt')!;
      expect(d.titleController.text, 'Old');
      server.external(
        'rt.ics',
        _todo(summary: 'Remote edit', body: 'new body', priority: 1),
      );
      await s.sync();
      expect(d.titleController.text, 'Remote edit');
      expect(d.bodyController.text, 'new body');
      expect(d.dirty, isFalse);
      // A pick writes straight to the task, so the buffer stays out of it.
      await s.updateTask('rt', setPriority: true, priority: 9);
      expect(s.taskById('rt')!.priority, 9);
      expect(d.dirty, isFalse);
    });

    test('task: a draft with changes is never overwritten', () async {
      final server = FakeCalDav()..external('rt.ics', _todo(summary: 'Old'));
      final s = await _open(server);
      s.autosaveDelay = const Duration(hours: 1);
      s.startTaskEdit('rt');
      final d = s.taskDraftFor('rt')!;
      d.bodyController.text = 'mine';
      server.external('rt.ics', _todo(summary: 'Remote edit', body: 'theirs'));
      await s.sync();
      expect(d.bodyController.text, 'mine');
      expect(d.titleController.text, 'Old');
      expect(d.dirty, isTrue);
    });

    test(
      'event: fields follow; a selector save keeps the remote text',
      () async {
        final server = FakeCalDav()..external('re.ics', _event(summary: 'Old'));
        final s = await _open(server);
        s.startEventEdit('re');
        final d = s.eventDraftFor('re')!;
        server.external(
          're.ics',
          _event(summary: 'Remote edit', location: 'Hall'),
        );
        await s.sync();
        expect(d.titleController.text, 'Remote edit');
        expect(d.locationController.text, 'Hall');
        expect(d.dirty, isFalse);
        d.setStatus('TENTATIVE');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final e = s.eventById('re')!;
        expect(e.summary, 'Remote edit');
        expect(e.location, 'Hall');
        expect(e.status, 'TENTATIVE');
      },
    );

    test('event: a draft with changes is never overwritten', () async {
      final server = FakeCalDav()..external('re.ics', _event(summary: 'Old'));
      final s = await _open(server);
      s.autosaveDelay = const Duration(hours: 1);
      s.startEventEdit('re');
      final d = s.eventDraftFor('re')!;
      d.locationController.text = 'Mine';
      server.external('re.ics', _event(summary: 'Remote edit', location: 'X'));
      await s.sync();
      expect(d.locationController.text, 'Mine');
      expect(d.titleController.text, 'Old');
      expect(d.dirty, isTrue);
    });
  });
}
