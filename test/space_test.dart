import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart/io.dart';
import 'package:test/test.dart';

import 'support/fake_caldav.dart';

CalDavClient clientFor(FakeCalDav s) => CalDavClient(
    collection: FakeCalDav.collection,
    username: 'u',
    password: 'p',
    client: s.client);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('davdart'));

  test('a local-only space works with no server and survives a restart',
      () async {
    var book = await SpaceBook.open(dir.path);
    final s = await book.createLocal('Notes');
    expect(s.isLocalOnly, isTrue);
    await s.save(Note(uid: 'a', summary: 'First'));
    expect(await s.sync(), isNull);
    book = await SpaceBook.open(dir.path);
    expect(book.configs.single.name, 'Notes');
    final again = await book.open_(book.configs.single.id);
    expect((await again.notes()).single.summary, 'First');
  });

  test('attaching a server sends local notes and merges with its own',
      () async {
    final server = FakeCalDav();
    server.external(
        'r.ics', serializeNote(Note(uid: 'r', summary: 'On server')));
    final book = await SpaceBook.open(dir.path);
    final s = await book.createLocal('Project');
    await s.save(Note(uid: 'l', summary: 'Local'));
    await s.attach(clientFor(server));
    expect(s.isLocalOnly, isFalse);
    final r = await s.sync();
    expect(r!.errors, isEmpty);
    expect((await s.notes()).map((n) => n.uid).toSet(), {'l', 'r'});
    expect(server.ics.keys.toSet(), {'l.ics', 'r.ics'});
    final reopened = await SpaceBook.open(dir.path);
    expect(reopened.configs.single.hasServer, isTrue);
    final back = await reopened.open_(reopened.configs.single.id);
    expect(back.needsPassword, isTrue);
    expect(back.sync(), throwsStateError);
  });

  test('detaching keeps every note and stops syncing', () async {
    final server = FakeCalDav();
    final book = await SpaceBook.open(dir.path);
    final s = await book.createLocal('P');
    await s.save(Note(uid: 'a', summary: 'A'));
    await s.attach(clientFor(server));
    await s.sync();
    await s.detach();
    expect((await SpaceBook.open(dir.path)).configs.single.hasServer, isFalse);
    expect(s.isLocalOnly, isTrue);
    expect(await s.sync(), isNull);
    expect((await s.notes()).single.uid, 'a');
    await s.save(Note(uid: 'b', summary: 'B'));
    expect(server.ics.keys, ['a.ics']);
  });

  test('remove deletes the local copy only', () async {
    final book = await SpaceBook.open(dir.path);
    final s = await book.createLocal('Gone');
    await s.save(Note(uid: 'a'));
    await book.remove(book.configs.single.id);
    expect(book.configs, isEmpty);
  });
}
