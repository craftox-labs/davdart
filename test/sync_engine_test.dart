import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart/io.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/fake_caldav.dart';

String ics(String uid, String summary, [String body = '']) =>
    serializeNote(Note(uid: uid, summary: summary, description: body));

const head = 'item_id: x\nstatus: backlog\nowner: tm\n\n';

void main() {
  regressionTests();
  late FakeCalDav server;
  late DateTime clock;

  SyncEngine engine(NoteStore store) => SyncEngine(
        CalDavClient(
            collection: FakeCalDav.collection,
            username: 'u',
            password: 'p',
            client: server.client),
        store,
        now: () => clock = clock.add(const Duration(minutes: 1)),
      );

  setUp(() {
    server = FakeCalDav();
    clock = DateTime.utc(2026, 11, 19, 12);
  });

  test('initial sync pulls everything; second sync is a no-op', () async {
    server.external('a.ics', ics('a', 'A'));
    server.external('b.ics', ics('b', 'B'));
    final e = engine(MemoryNoteStore());
    final r = await e.sync();
    expect(r.pulled, 2);
    expect((await e.notes()).map((n) => n.uid).toSet(), {'a', 'b'});
    server.log.clear();
    final r2 = await e.sync();
    expect(r2.pulled + r2.pushed + r2.merged, 0);
    expect(server.log.where((l) => l.startsWith('PUT')), isEmpty);
  });

  test('a local edit is pushed with If-Match and is not re-pulled', () async {
    server.external('a.ics', ics('a', 'A', 'one'));
    final e = engine(MemoryNoteStore());
    await e.sync();
    final n = (await e.notes()).single;
    n.description = 'two';
    await e.save(n);
    final r = await e.sync();
    expect(r.pushed, 1);
    expect(server.ics['a.ics'], contains('two'));
    final r2 = await e.sync();
    expect(r2.pulled + r2.pushed, 0);
  });

  test('a new local note is created on the server', () async {
    final e = engine(MemoryNoteStore());
    await e.save(Note(uid: 'n1', summary: 'New'));
    final r = await e.sync();
    expect(r.pushed, 1);
    expect(server.ics.keys, ['n1.ics']);
    expect(r.errors, isEmpty);
  });

  test('edits to different parts merge with no conflict', () async {
    server.external('a.ics', ics('a', 'A', '${head}l1\nl2\nl3'));
    final e = engine(MemoryNoteStore());
    await e.sync();
    final n = (await e.notes()).single;
    n.description = n.description.replaceFirst('backlog', 'todo');
    await e.save(n);
    server.external('a.ics', ics('a', 'A', '${head}l1\nl2\nL3'));
    final r = await e.sync();
    expect(r.merged, 1);
    expect(r.conflicts, isEmpty);
    final body = server.ics['a.ics']!;
    expect(body, contains('status: todo'));
    expect(body, contains('L3'));
  });

  test('a true conflict picks one side, keeps a revision, no duplicate',
      () async {
    server.external('a.ics', ics('a', 'A', '${head}shared'));
    final e = engine(MemoryNoteStore());
    await e.sync();
    final n = (await e.notes()).single;
    n.description = '${head}local text';
    await e.save(n); // saved after the server edit below? no: before
    server.external('a.ics', ics('a', 'A', '${head}remote text'));
    final r = await e.sync();
    expect(r.conflicts, hasLength(1));
    expect(server.ics.length, 1);
    expect((await e.notes()).length, 1);
    final revs = await e.store.revisions('a');
    expect(revs.single.body, contains('local text'));
  });

  test('remote deletion removes an unedited local copy', () async {
    server.external('a.ics', ics('a', 'A'));
    final e = engine(MemoryNoteStore());
    await e.sync();
    server.externalDelete('a.ics');
    await e.sync();
    expect(await e.notes(), isEmpty);
  });

  test('remote deletion of an edited note recreates the edit', () async {
    server.external('a.ics', ics('a', 'A', 'x'));
    final e = engine(MemoryNoteStore());
    await e.sync();
    final n = (await e.notes()).single;
    n.description = 'edited';
    await e.save(n);
    server.externalDelete('a.ics');
    final r = await e.sync();
    expect(r.pushed, 1);
    expect(server.ics['a.ics'], contains('edited'));
  });

  test('local delete is pushed', () async {
    server.external('a.ics', ics('a', 'A'));
    final e = engine(MemoryNoteStore());
    await e.sync();
    await e.delete('a');
    expect(await e.notes(), isEmpty);
    final r = await e.sync();
    expect(r.deleted, 1);
    expect(server.ics, isEmpty);
  });

  test('an invalid sync token falls back to a full sync', () async {
    server.external('a.ics', ics('a', 'A'));
    final e = engine(MemoryNoteStore());
    await e.sync();
    server.rejectTokens = true;
    server.external('b.ics', ics('b', 'B'));
    final r = await e.sync();
    expect(r.pulled, greaterThanOrEqualTo(1));
    expect((await e.notes()).map((n) => n.uid).toSet(), {'a', 'b'});
  });

  test('two devices converge', () async {
    final a = engine(MemoryNoteStore()), b = engine(MemoryNoteStore());
    await a
        .save(Note(uid: 'n', summary: 'T', description: '${head}p1\np2\np3'));
    await a.sync();
    await b.sync();
    final na = (await a.notes()).single..description = '${head}P1\np2\np3';
    final nb = (await b.notes()).single..description = '${head}p1\np2\nP3';
    await a.save(na);
    await b.save(nb);
    await a.sync();
    await b.sync();
    await a.sync();
    final want = '${head}P1\np2\nP3';
    expect((await a.notes()).single.description, want);
    expect((await b.notes()).single.description, want);
    expect(server.ics['n.ics'], contains('P3'));
  });

  test('file store survives a restart', () async {
    final path =
        '${(await Directory.systemTemp.createTemp('davdart')).path}/s.json';
    server.external('a.ics', ics('a', 'A', 'body'));
    var e = engine(await FileNoteStore.open(path));
    await e.sync();
    final n = (await e.notes()).single..description = 'offline edit';
    await e.save(n);
    e = engine(await FileNoteStore.open(path));
    expect((await e.notes()).single.description, 'offline edit');
    final r = await e.sync();
    expect(r.pushed, 1);
    expect(server.ics['a.ics'], contains('offline edit'));
  });
}

void regressionTests() {
  late FakeCalDav server;
  late DateTime clock;
  SyncEngine engine(NoteStore store) => SyncEngine(
        CalDavClient(
            collection: FakeCalDav.collection,
            username: 'u',
            password: 'p',
            client: server.client),
        store,
        now: () => clock = clock.add(const Duration(minutes: 1)),
      );
  setUp(() {
    server = FakeCalDav();
    clock = DateTime.utc(2026, 11, 19, 12);
  });

  test('status edited locally survives a remote title edit', () async {
    server.external('a.ics', ics('a', 'A'));
    final e = engine(MemoryNoteStore());
    await e.sync();
    final n = (await e.notes()).single..status = 'FINAL';
    await e.save(n);
    server.external('a.ics', ics('a', 'New title'));
    await e.sync();
    expect(server.ics['a.ics'], contains('STATUS:FINAL'));
    expect(server.ics['a.ics'], contains('New title'));
  });

  test('delete locally then remote edit restores the note and records it',
      () async {
    server.external('a.ics', ics('a', 'A', 'x'));
    final e = engine(MemoryNoteStore());
    await e.sync();
    await e.delete('a');
    server.external('a.ics', ics('a', 'A', 'edited elsewhere'));
    final r = await e.sync();
    expect(r.restored, 1);
    expect((await e.notes()).single.description, 'edited elsewhere');
    expect(await e.store.revisions('a'), hasLength(1));
  });

  test('an edit made while the PUT is in flight is not lost', () async {
    server.external('a.ics', ics('a', 'A', 'v0'));
    final store = MemoryNoteStore();
    final e = engine(store);
    await e.sync();
    var n = (await e.notes()).single..description = 'v1';
    await e.save(n);
    // Edit again as soon as the PUT reaches the server.
    var injected = false;
    final racing = SyncEngine(
        CalDavClient(
            collection: FakeCalDav.collection,
            username: 'u',
            password: 'p',
            client: MockClient((req) async {
              final res = await server.respond(req);
              if (req.method == 'PUT' && !injected) {
                injected = true;
                n = (await store.get('a'))!.local..description = 'v2';
                await e.save(n);
              }
              return res;
            })),
        store,
        now: () => clock = clock.add(const Duration(minutes: 1)));
    await racing.sync();
    expect((await e.notes()).single.description, 'v2');
    await e.sync();
    expect(server.ics['a.ics'], contains('v2'));
  });

  test('a failed fetch aborts the sync without advancing the token', () async {
    server.external('a.ics', ics('a', 'A'));
    final store = MemoryNoteStore();
    final c = CalDavClient(
        collection: FakeCalDav.collection,
        username: 'u',
        password: 'p',
        client: MockClient((req) async {
          if (req.method == 'GET') return http.Response('', 503);
          final res = await server.respond(req);
          // Hide calendar-data so the client has to fetch each note.
          return http.Response(
              res.body.replaceAll(
                  RegExp(r'<c:calendar-data>.*?</c:calendar-data>',
                      dotAll: true),
                  ''),
              res.statusCode);
        }));
    final e = SyncEngine(c, store);
    await expectLater(e.sync(), throwsA(isA<CalDavException>()));
    expect(await store.getSyncToken(), isNull);
    expect(await store.all(), isEmpty);
  });

  test('a damaged store file is set aside, not fatal', () async {
    final dir = await Directory.systemTemp.createTemp('davdart');
    final path = '${dir.path}/s.json';
    File(path).writeAsStringSync('{"notes": {');
    final s = await FileNoteStore.open(path);
    expect(await s.all(), isEmpty);
    expect(dir.listSync().any((f) => f.path.contains('corrupt')), isTrue);
  });
}
