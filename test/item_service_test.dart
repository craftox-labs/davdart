import 'package:davdart/davdart.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/fake_caldav.dart';

void main() {
  late FakeCalDav fake;
  late CalDavClient client;
  late ItemService svc;

  setUp(() {
    fake = FakeCalDav();
    client = CalDavClient(
        collection: FakeCalDav.collection,
        username: 'u',
        password: 'p',
        client: fake.client);
    svc = ItemService(client);
  });

  Future<String> mk(ItemKind k, String title,
          {String? parent,
          List<String> tags = const [],
          bool folder = false,
          String? start}) async =>
      (await svc.create(k, title,
              parent: parent,
              tags: tags,
              folder: folder,
              start: k == ItemKind.event ? (start ?? '2026-12-01') : null))
          .item
          .uid;

  test('create, get and list across kinds', () async {
    final f = await mk(ItemKind.note, 'Folder', folder: true);
    final n = await mk(ItemKind.note, 'Note', parent: f, tags: ['a']);
    final t = await mk(ItemKind.task, 'Task', parent: f, tags: ['a', 'b']);
    await mk(ItemKind.event, 'Event', parent: f);
    expect((await svc.get(t)).kind, ItemKind.task);
    expect((await svc.get('Note')).uid, n);
    final all = await svc.list();
    expect(all.total, 3, reason: 'folders excluded by default');
    expect((await svc.list(includeFolders: true)).total, 4);
    expect((await svc.list(tag: 'a')).total, 2);
    expect((await svc.list(kind: ItemKind.task)).items.single.uid, t);
    expect((await svc.list(under: 'Folder')).total, 3);
    final page = await svc.list(limit: 2, offset: 1);
    expect(page.items, hasLength(2));
    expect(page.hasMore, isFalse);
    expect(page.toJson()['items'], isA<List>());
  });

  test('overview and tag edits hide and keep the projects tag', () async {
    final c = (await svc.create(ItemKind.note, 'Projects',
            tags: [projectsTag], folder: true))
        .item
        .uid;
    await mk(ItemKind.note, 'N', parent: c, tags: ['x']);
    final o = await svc.overview(maxDepth: 2);
    expect(o.byTag, {'x': 1});
    await svc.setTags(c, set: ['y']);
    final back = (await svc.get(c)).tags;
    expect(back, containsAll([folderTag, projectsTag, 'y']));
  });

  test('tag add and remove refuse kind-projects and kind-folder', () async {
    final c = (await svc.create(ItemKind.note, 'Projects',
            tags: [projectsTag], folder: true))
        .item
        .uid;
    final n = await mk(ItemKind.note, 'N');
    for (final t in [projectsTag, folderTag]) {
      await expectLater(
          svc.setTags(c, remove: [t]), throwsA(isA<ItemServiceException>()));
      await expectLater(
          svc.setTags(n, add: [t]), throwsA(isA<ItemServiceException>()));
    }
    expect((await svc.get(c)).tags, containsAll([folderTag, projectsTag]));
    expect((await svc.get(n)).tags, isNot(contains(projectsTag)));
  });

  test('overview gives tree and counts', () async {
    final f = await mk(ItemKind.note, 'Folder', folder: true);
    final sub = await mk(ItemKind.note, 'Sub', parent: f, folder: true);
    await mk(ItemKind.task, 'Deep', parent: sub, tags: ['x']);
    final o = await svc.overview(maxDepth: 2);
    expect(o.total, 3);
    expect(o.byKind, {'note': 2, 'task': 1});
    expect(o.byTag, {'x': 1});
    expect(o.byStatus['todo'], 1);
    final j = o.toJson();
    expect(j['tree'], hasLength(1));
    final top = o.roots.single;
    expect(top.children.single.hiddenChildren, 1);
  });

  test('move checks cycles and works across kinds', () async {
    final a = await mk(ItemKind.note, 'A', folder: true);
    final b = await mk(ItemKind.note, 'B', parent: a, folder: true);
    final t = await mk(ItemKind.task, 'T');
    expect(() => svc.move(a, b), throwsA(isA<ItemServiceException>()));
    expect(() => svc.move(a, a), throwsA(isA<ItemServiceException>()));
    expect((await svc.move(t, b)).item.parentUid, b);
    expect((await svc.get(t)).parentUid, b);
    expect((await svc.move(t, null)).item.parentUid, isNull);
  });

  test('dry run writes nothing', () async {
    final t = await mk(ItemKind.task, 'T');
    fake.log.clear();
    final r = await svc.setStatus(t, 'done', dryRun: true);
    expect(r.dryRun, isTrue);
    expect(r.item.status, 'done');
    expect(fake.log.where((l) => l.startsWith('PUT') || l.startsWith('DELETE')),
        isEmpty);
    expect((await svc.get(t)).status, 'todo');
    final c = await svc.create(ItemKind.note, 'x', dryRun: true);
    expect(c.dryRun, isTrue);
    expect(fake.ics.length, 1);
    await svc.delete(t, dryRun: true);
    expect(fake.ics.length, 1);
  });

  test('task status keeps STATUS in step; due and priority', () async {
    final t = await mk(ItemKind.task, 'T');
    await svc.setStatus(t, 'done');
    var raw = await client.listTasks();
    expect(raw.single.status, 'COMPLETED');
    expect(raw.single.completed, isNotNull);
    await svc.setStatus(t, 'doing');
    raw = await client.listTasks();
    expect(raw.single.status, 'IN-PROCESS');
    await svc.setDue(t, '2026-12-24');
    await svc.setPriority(t, 2);
    final g = await svc.get(t);
    expect(g.due, '20261224');
    expect(g.priority, 2);
    expect((await svc.setDue(t, null)).item.due, isNull);
    final n = await mk(ItemKind.note, 'N');
    expect(() => svc.setDue(n, '2026-12-24'),
        throwsA(isA<ItemServiceException>()));
  });

  test('note status uses status-* tags; tags set, add, remove', () async {
    final n = await mk(ItemKind.note, 'N', tags: ['keep']);
    await svc.setStatus(n, 'Doing');
    var g = await svc.get(n);
    expect(g.status, 'doing');
    expect(g.tags, containsAll(['keep', 'status-doing']));
    await svc.setStatus(n, 'done');
    expect((await svc.get(n)).tags.where((t) => t.startsWith('status-')),
        ['status-done']);
    await svc.setTags(n, add: ['x', 'y'], remove: ['keep']);
    g = await svc.get(n);
    expect(g.tags, containsAll(['x', 'y', 'status-done']));
    expect(g.tags, isNot(contains('keep')));
    await svc.setTags(n, set: ['only']);
    g = await svc.get(n);
    expect(g.tags.toSet(), {'only', 'status-done'});
    await svc.setStatus(n, null);
    expect((await svc.get(n)).status, isNull);
  });

  test('status is a fixed set: aliases map, unknown words are refused',
      () async {
    final n = await mk(ItemKind.note, 'N');
    final t = await mk(ItemKind.task, 'T');
    for (final (word, want) in [
      ('in_progress', 'doing'),
      ('In-Progress', 'doing'),
      ('cancelled', 'canceled'),
      ('duplicate', 'canceled'),
      ('wontfix', 'canceled'),
      ('draft', 'backlog'),
      ('blocked', 'blocked'),
      ('review', 'review'),
      ('in_review', 'review'),
      ('In-Review', 'review'),
      ('ready_for_review', 'review'),
      ('to_review', 'review'),
    ]) {
      expect((await svc.setStatus(n, word)).item.status, want, reason: word);
      expect((await svc.setStatus(t, word)).item.status, want, reason: word);
    }
    await svc.setStatus(t, 'cancelled');
    expect((await client.listTasks()).single.status, 'CANCELLED');
    await svc.setStatus(t, 'done');
    await svc.setStatus(n, 'doing');
    await expectLater(
        svc.setStatus(n, 'wip'),
        throwsA(isA<ItemServiceException>().having(
            (e) => e.message,
            'message',
            contains(
                'allowed: backlog, todo, doing, blocked, review, done, canceled'))));
    expect((await svc.get(n)).status, 'doing', reason: 'unchanged');
    expect(() => svc.create(ItemKind.note, 'X', status: 'wip'),
        throwsA(isA<ItemServiceException>()));
    expect(
        (await svc.create(ItemKind.note, 'Y', status: 'in_progress'))
            .item
            .status,
        'doing');
    expect((await svc.list(status: 'in_progress')).items.map((i) => i.uid),
        containsAll([n]));
  });

  test('note priority is a body line; sets, reads, clears', () async {
    final n = await mk(ItemKind.note, 'N');
    final c = await svc.setPriority(n, 1);
    expect(c.changes, ['priority: - -> 1']);
    var g = await svc.get(n);
    expect(g.priority, 1);
    expect(g.body, startsWith('priority: high'));
    expect((await svc.setPriority(n, 4)).changes, isEmpty,
        reason: '4 is also high');
    await svc.setPriority(n, 5);
    expect((await svc.get(n)).body, startsWith('priority: medium'));
    await svc.setPriority(n, 9);
    expect((await svc.get(n)).priority, 9);
    await svc.setStatus(n, 'doing');
    expect((await svc.get(n)).priority, 9, reason: 'status keeps the header');
    await svc.setPriority(n, null);
    g = await svc.get(n);
    expect(g.priority, isNull);
    expect(g.body, isNot(contains('priority')));
    final e = await mk(ItemKind.event, 'E');
    expect(() => svc.setPriority(e, 1), throwsA(isA<ItemServiceException>()));
    final made =
        await svc.create(ItemKind.note, 'P', body: 'text', priority: 5);
    expect(made.item.priority, 5);
    expect(made.item.body, 'priority: medium\n\ntext');
  });

  test('update and delete adopt children', () async {
    final f = await mk(ItemKind.note, 'F', folder: true);
    final c = await mk(ItemKind.note, 'C', parent: f);
    final e = await mk(ItemKind.event, 'E');
    final u =
        await svc.update(e, title: 'E2', location: 'Here', end: '2026-12-02');
    expect(u.item.title, 'E2');
    expect(u.item.location, 'Here');
    expect(u.item.end, '20261202');
    expect(() => svc.update(c, location: 'x'),
        throwsA(isA<ItemServiceException>()));
    final d = await svc.delete(f);
    expect(d.changes, hasLength(2));
    expect((await svc.get(c)).parentUid, isNull);
    expect(() => svc.get(f), throwsA(isA<ItemServiceException>()));
  });

  test('a write that loses a race is merged and retried', () async {
    final n = await mk(ItemKind.note, 'N', tags: ['a']);
    final stale = await svc.get(n);
    // Another client changes the body behind our back.
    final name = Uri.parse(stale.href!).pathSegments.last;
    fake.external(
        name,
        fake.ics[name]!
            .replaceFirst('SUMMARY:N', 'SUMMARY:N\r\nDESCRIPTION:theirs'));
    // The service loads fresh, so force staleness by wrapping the first PUT.
    var first = true;
    final racing = CalDavClient(
        collection: FakeCalDav.collection,
        username: 'u',
        password: 'p',
        client: mockClientProxy(fake, () {
          if (first) {
            first = false;
            fake.external(
                name,
                fake.ics[name]!
                    .replaceFirst('SUMMARY:N', 'SUMMARY:N\r\nX-TOUCH:1'));
          }
        }));
    final r = await ItemService(racing).setTags(n, add: ['b']);
    expect(r.item.tags, containsAll(['a', 'b']));
  });

  test('href returned by a write is absolute-path, as list returns it',
      () async {
    final r = await svc.create(ItemKind.note, 'H');
    final listed = (await svc.list()).items.single;
    expect(Uri.decodeFull(r.item.href!), Uri.decodeFull(listed.href!));
    final moved = await svc.move('H', null);
    expect(moved.item.href, startsWith('/'));
    final t = await svc.setTags('H', add: ['x']);
    expect(Uri.decodeFull(t.item.href!), Uri.decodeFull(listed.href!));
  });

  test('parseWhen', () {
    expect(parseWhen('2026-12-24').allDay, isTrue);
    expect(parseWhen('2026-12-24T09:30Z').value, '20261224T093000Z');
    expect(parseWhen('2026-12-24T09:30').isFloating, isTrue);
    expect(() => parseWhen('tomorrow'), throwsA(isA<ItemServiceException>()));
  });

  group('rankItem', () {
    Future<String> st(ItemKind k, String title, String status,
            {int? priority}) async =>
        (await svc.create(k, title, status: status, priority: priority))
            .item
            .uid;
    Future<List<String>> col(String status) async =>
        [for (final i in (await svc.list(status: status)).items) i.title];

    test('top, bottom, before, after, none', () async {
      for (final n in ['a', 'b', 'c', 'd']) {
        await st(ItemKind.task, n, 'todo');
      }
      await st(ItemKind.note, 'n', 'doing');
      var r = await svc.rankItem('c', top: true);
      expect([for (final x in r.order) x.title].first, 'c');
      expect(await col('todo'), ['c', 'a', 'b', 'd']);
      r = await svc.rankItem('a', bottom: true);
      expect(await col('todo'), ['c', 'b', 'd', 'a']);
      r = await svc.rankItem('a', before: 'b');
      expect(await col('todo'), ['c', 'a', 'b', 'd']);
      r = await svc.rankItem('c', after: 'b');
      expect(await col('todo'), ['a', 'b', 'c', 'd']);
      expect([for (final x in r.order) x.title], ['a', 'b', 'c', 'd']);
      expect((await svc.get('c')).rank, isNotNull);
      r = await svc.rankItem('c', clear: true);
      expect((await svc.get('c')).rank, isNull);
      expect(await col('todo'), ['a', 'b', 'd', 'c']);
    });

    test('ranks neighbours, outranks priority, clear falls back', () async {
      await st(ItemKind.task, 'low', 'todo', priority: 9);
      await st(ItemKind.task, 'high', 'todo', priority: 1);
      await st(ItemKind.note, 'plain', 'todo');
      expect(await col('todo'), ['high', 'low', 'plain']);
      await svc.rankItem('plain', top: true);
      expect(await col('todo'), ['plain', 'high', 'low']);
      // Dropping after the unranked 'high' ranks the unranked cards above.
      await svc.rankItem('low', after: 'high');
      expect(await col('todo'), ['plain', 'high', 'low']);
      expect((await svc.get('high')).rank, isNotNull);
      await svc.rankItem('plain', clear: true);
      expect(await col('todo'), ['high', 'low', 'plain']);
    });

    test('a tiny gap re-spreads the column', () async {
      for (final n in ['a', 'b', 'c']) {
        await st(ItemKind.task, n, 'todo');
      }
      await svc.rankItem('a', top: true);
      await svc.rankItem('b', after: 'a');
      for (var i = 0; i < 60; i++) {
        await svc.rankItem('c', after: 'a');
        await svc.rankItem('b', after: 'a');
      }
      expect(await col('todo'), ['a', 'b', 'c']);
      final ranks = [
        for (final t in ['a', 'b', 'c']) (await svc.get(t)).rank!
      ];
      expect(ranks[0] < ranks[1] && ranks[1] < ranks[2], isTrue);
    });

    test('dry run writes nothing; errors are clear', () async {
      await st(ItemKind.task, 'a', 'todo');
      await st(ItemKind.task, 'b', 'todo');
      await st(ItemKind.task, 'z', 'doing');
      final plain = (await svc.create(ItemKind.note, 'nostatus')).item.uid;
      final ev = await mk(ItemKind.event, 'Ev');
      final r = await svc.rankItem('b', top: true, dryRun: true);
      expect(r.changes, isNotEmpty);
      expect((await svc.get('b')).rank, isNull);
      Future<void> bad(Future<Object?> f, String m) => expectLater(
          f,
          throwsA(isA<ItemServiceException>()
              .having((e) => e.message, 'message', contains(m))));
      await bad(svc.rankItem(plain, top: true), 'no status');
      await bad(svc.rankItem(ev, top: true), 'event');
      final fo =
          (await svc.create(ItemKind.note, 'Fold', folder: true)).item.uid;
      await bad(svc.rankItem(fo, top: true), 'folder');
      await bad(svc.rankItem('a', before: 'z'), 'not in the todo column');
      await bad(svc.rankItem('a', before: 'a'), 'itself');
      await bad(svc.rankItem('a'), 'exactly one');
      await bad(svc.rankItem('a', top: true, bottom: true), 'exactly one');
      await bad(svc.rankItem('a', before: 'nope'), 'no item matches');
    });
  });
}

/// Runs [before] ahead of each PUT, then lets the fake server answer.
MockClient mockClientProxy(FakeCalDav fake, void Function() before) =>
    MockClient((r) async {
      if (r.method == 'PUT') before();
      return fake.respond(r);
    });
