import 'dart:convert';
import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../bin/davdart.dart';
import 'support/fake_caldav.dart';
import 'support/fake_dav_server.dart';

void main() {
  late FakeCalDav work, other;
  late http.Client net;
  late ItemService src, dst;
  int putsToOther = 0;
  int? failPutAt;

  ItemService svcFor(String path, http.Client c) => ItemService(CalDavClient(
      collection: Uri.parse('https://fake.test$path'),
      username: 'u',
      password: 'p',
      client: c));

  setUp(() {
    work = FakeCalDav();
    other = FakeCalDav();
    putsToOther = 0;
    failPutAt = null;
    final inner = multiHome(work, other);
    net = MockClient((r) async {
      if (r.method == 'PUT' && r.url.path.startsWith('/dav/d/')) {
        putsToOther++;
        if (failPutAt == putsToOther) return http.Response('', 500);
      }
      final req = http.Request(r.method, r.url)..headers.addAll(r.headers);
      req.body = r.body;
      return http.Response.fromStream(await inner.send(req));
    });
    src = svcFor('/dav/c', net);
    dst = svcFor('/dav/d', net);
  });

  Future<String> mk(ItemKind k, String title,
          {String? parent,
          List<String> tags = const [],
          bool folder = false,
          String? status}) async =>
      (await src.create(k, title,
              parent: parent,
              tags: tags,
              folder: folder,
              status: status,
              start: k == ItemKind.event ? '2026-12-01' : null))
          .item
          .uid;

  // Project -> (Sub A -> note, task), (Sub B -> event); plus an outsider.
  Future<Map<String, String>> tree() async {
    final ids = <String, String>{};
    ids['proj'] = await mk(ItemKind.note, 'Proj', folder: true, tags: ['x']);
    ids['a'] =
        await mk(ItemKind.note, 'SubA', parent: ids['proj'], folder: true);
    ids['b'] =
        await mk(ItemKind.note, 'SubB', parent: ids['proj'], folder: true);
    ids['note'] = await mk(ItemKind.note, 'Idea',
        parent: ids['a'], tags: ['t1', 't2'], status: 'doing');
    ids['task'] = await mk(ItemKind.task, 'Do it',
        parent: ids['a'], tags: ['t1'], status: 'review');
    ids['event'] = await mk(ItemKind.event, 'Meet', parent: ids['b']);
    ids['out'] = await mk(ItemKind.note, 'Outside');
    return ids;
  }

  test('moves a nested subtree of all kinds with remapped parents', () async {
    final ids = await tree();
    final dirs = <String, Map<String, String>>{};
    final r = await src.moveToCollection(dst, 'Proj',
        backupDir: '/b', writer: 'tester', backupWriter: (d, f) {
      dirs[d] = f;
      return f.length;
    });
    expect(r.deleted, isTrue);
    expect(r.entries, hasLength(6));
    expect(dirs.values.single, hasLength(6));
    expect(
        dirs.values.single.values.every((t) => t.contains('BEGIN:V')), isTrue);
    // Source keeps only the outsider.
    expect((await src.list(includeFolders: true)).items.single.uid, ids['out']);
    final moved = (await dst.list(includeFolders: true)).items;
    expect(moved, hasLength(6));
    final byTitle = {for (final i in moved) i.title: i};
    final map = {for (final e in r.entries) e.oldUid: e.newUid};
    expect(byTitle['Proj']!.parentUid, isNull);
    expect(byTitle['SubA']!.parentUid, map[ids['proj']]);
    expect(byTitle['SubB']!.parentUid, map[ids['proj']]);
    expect(byTitle['Idea']!.parentUid, map[ids['a']]);
    expect(byTitle['Do it']!.parentUid, map[ids['a']]);
    expect(byTitle['Meet']!.parentUid, map[ids['b']]);
    expect(byTitle['Idea']!.tags, containsAll(['t1', 't2']));
    expect(byTitle['Idea']!.status, 'doing');
    expect(byTitle['Do it']!.status, 'review');
    expect(byTitle['Proj']!.tags, contains('x'));
    expect(byTitle['Proj']!.tags, contains('kind-folder'));
    expect({for (final i in moved) i.uid}.intersection(ids.values.toSet()),
        isEmpty);
    expect((await dst.get('Meet')).writer, 'tester');
    expect((await dst.get('Meet')).kind, ItemKind.event);
  });

  test('--under places the root below a folder in the target', () async {
    await tree();
    final f =
        (await dst.create(ItemKind.note, 'Container', folder: true)).item.uid;
    await src.moveToCollection(dst, 'SubA',
        under: 'Container', backupDir: '/b', backupWriter: (d, f) => f.length);
    expect((await dst.get('SubA')).parentUid, f);
    expect((await dst.get('Idea')).parentUid, (await dst.get('SubA')).uid);
  });

  test('dry run writes nothing, not even a backup', () async {
    await tree();
    var wrote = false;
    final before = Map.of(work.ics);
    final r = await src.moveToCollection(dst, 'Proj',
        dryRun: true, backupDir: '/b', backupWriter: (d, f) {
      wrote = true;
      return f.length;
    });
    expect(r.dryRun, isTrue);
    expect(r.entries, hasLength(6));
    expect(wrote, isFalse);
    expect(other.ics, isEmpty);
    expect(work.ics, before);
    expect(work.log.where((l) => l.startsWith('PUT') || l.startsWith('DELETE')),
        hasLength(7)); // only the setup creates
  });

  test('a real move needs a backup directory', () async {
    await tree();
    expect(() => src.moveToCollection(dst, 'Proj'),
        throwsA(isA<ItemServiceException>()));
    expect(other.ics, isEmpty);
  });

  test('--no-subtree moves one item and re-parents its children', () async {
    final ids = await tree();
    final r = await src.moveToCollection(dst, 'SubA',
        subtree: false, backupDir: '/b', backupWriter: (d, f) => f.length);
    expect(r.entries, hasLength(1));
    expect((await dst.list(includeFolders: true)).total, 1);
    expect((await src.get(ids['note']!)).parentUid, ids['proj']);
    expect((await src.get(ids['task']!)).parentUid, ids['proj']);
  });

  test('a failed copy leaves every original and reports the copies', () async {
    final ids = await tree();
    failPutAt = 3;
    await expectLater(
        src.moveToCollection(dst, 'Proj',
            backupDir: '/b', backupWriter: (d, f) => f.length),
        throwsA(isA<ItemServiceException>().having((e) => e.message, 'message',
            allOf(contains('originals were kept'), contains('copies')))));
    expect((await src.list(includeFolders: true)).total, ids.length);
  });

  test('a failed backup stops before any copy', () async {
    await tree();
    await expectLater(
        src.moveToCollection(dst, 'Proj',
            backupDir: '/b', backupWriter: (d, f) => f.length - 1),
        throwsA(isA<ItemServiceException>()));
    expect(other.ics, isEmpty);
    expect((await src.list(includeFolders: true)).total, 7);
  });

  test('an original edited during the copy is kept', () async {
    final ids = await tree();
    // Edit the task through another client right after the first copy lands.
    var edited = false;
    final racing = MockClient((r) async {
      final res = await net.send(http.Request(r.method, r.url)
        ..headers.addAll(r.headers)
        ..body = r.body);
      if (!edited && r.method == 'PUT' && r.url.path.startsWith('/dav/d/')) {
        edited = true;
        await src.update(ids['note']!, body: 'edited meanwhile');
      }
      return http.Response.fromStream(res);
    });
    final dst2 = svcFor('/dav/d', racing);
    await expectLater(
        src.moveToCollection(dst2, 'Proj',
            backupDir: '/b', backupWriter: (d, f) => f.length),
        throwsA(isA<ItemServiceException>()
            .having((e) => e.message, 'message', contains('changed'))));
    expect((await src.list(includeFolders: true)).total, 7);
    expect((await src.get(ids['note']!)).body, 'edited meanwhile');
  });

  test('unreadable resources refuse unless allowed', () async {
    await tree();
    work.external('junk.ics',
        'BEGIN:VCALENDAR\r\nBEGIN:VFREEBUSY\r\nEND:VFREEBUSY\r\nEND:VCALENDAR\r\n');
    await expectLater(
        src.moveToCollection(dst, 'Proj',
            backupDir: '/b', backupWriter: (d, f) => f.length),
        throwsA(isA<ItemServiceException>()
            .having((e) => e.message, 'message', contains('unreadable'))));
    expect(other.ics, isEmpty);
    final r = await src.moveToCollection(dst, 'Proj',
        allowUnreadable: true,
        backupDir: '/b',
        backupWriter: (d, f) => f.length);
    expect(r.deleted, isTrue);
    expect(work.ics.containsKey('junk.ics'), isTrue);
  });

  test('same collection is refused', () async {
    await tree();
    expect(
        () => src.moveToCollection(svcFor('/dav/c/', net), 'Proj',
            backupDir: '/b'),
        throwsA(isA<ItemServiceException>()));
  });

  group('CLI move-to', () {
    late StringBuffer out, err;
    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });
    Future<int> cli(List<String> a) => runCli(a,
        config: {
          'url': FakeCalDav.collection.toString(),
          'user': 'u',
          'password': 'p'
        },
        env: const {},
        out: out,
        err: err,
        readStdin: () async => '',
        httpClient: net);

    test('flags are enforced', () async {
      await tree();
      expect(await cli(['move-to', 'Proj', '--to-collection', 'Other']), 3);
      expect(err.toString(), contains('--allow-admin'));
      expect(
          await cli([
            'move-to',
            'Proj',
            '--to-collection',
            'Other',
            '--allow-admin',
            '--read-only'
          ]),
          3);
      expect(
          await cli(
              ['move-to', 'Proj', '--to-collection', 'Other', '--allow-admin']),
          2,
          reason: 'backup dir required');
      expect(await cli(['move-to', 'Proj', '--allow-admin', '--dry-run']), 2);
      expect(
          await cli([
            'move-to',
            'Proj',
            '--to-collection',
            'Nope',
            '--allow-admin',
            '--dry-run'
          ]),
          1);
      expect(other.ics, isEmpty);
    });

    test('dry run prints the plan and writes nothing', () async {
      await tree();
      expect(
          await cli([
            'move-to',
            'Proj',
            '--to-collection',
            'Other',
            '--allow-admin',
            '--dry-run'
          ]),
          0,
          reason: '$err');
      expect(out.toString(), contains('dry run'));
      expect(out.toString(), contains('Proj'));
      expect(other.ics, isEmpty);
      expect(work.ics, hasLength(7));
    });

    test('moves, prints the mapping and the backup', () async {
      await tree();
      final tmp = Directory.systemTemp.createTempSync('davdart-move-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final dir = tmp.path;
      expect(
          await cli([
            'move-to',
            'Proj',
            '--to-collection',
            '/dav/d/',
            '--allow-admin',
            '--backup-dir',
            dir,
            '--json'
          ]),
          0,
          reason: '$err');
      final j = jsonDecode(out.toString()) as Map<String, dynamic>;
      expect((j['items'] as List), hasLength(6));
      expect(j['deleted'], isTrue);
      expect(other.ics, hasLength(6));
      expect(work.ics, hasLength(1));
      final b = Directory(j['backup'] as String).listSync();
      expect(b, hasLength(6));
    });
  });
}
