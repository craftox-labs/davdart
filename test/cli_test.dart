import 'dart:convert';

import 'package:test/test.dart';

import '../bin/davdart.dart';
import 'support/fake_caldav.dart';
import 'support/fake_dav_server.dart';

void main() {
  late FakeCalDav fake;
  late StringBuffer out, err;

  setUp(() {
    fake = FakeCalDav();
    out = StringBuffer();
    err = StringBuffer();
  });

  Future<int> cli(List<String> args,
          {String stdinText = '', Map<String, String> env = const {}}) =>
      runCli(args,
          config: {
            'url': FakeCalDav.collection.toString(),
            'user': 'u',
            'password': 'p'
          },
          env: env,
          out: out,
          err: err,
          readStdin: () async => stdinText,
          httpClient: fake.client);

  Future<Map<String, dynamic>> jcli(List<String> args) async {
    out.clear();
    expect(await cli([...args, '--json']), 0, reason: '$err');
    return jsonDecode(out.toString()) as Map<String, dynamic>;
  }

  group('argument parsing', () {
    test('flags, value options, = form and repeats', () {
      final p = Parsed.parse(
          ['list', '--json', '--tag', 'a', '--tag=b', '--limit', '5', 'x']);
      expect(p.positional, ['list', 'x']);
      expect(p.flag('json'), isTrue);
      expect(p.all('tag'), ['a', 'b']);
      expect(p.opt('limit'), '5');
    });
    test('a value option without a value is a usage error', () {
      expect(() => Parsed.parse(['list', '--tag']), throwsA(isA<UsageError>()));
    });
    test('no command and unknown command exit 2', () async {
      expect(await cli([]), 2);
      expect(await cli(['frobnicate']), 2);
      expect(await cli(['create', 'T']), 2, reason: 'kind missing');
      expect(err.toString(), contains('--kind'));
    });
  });

  group('--collection', () {
    test('default unchanged, second collection reachable, unknown refused',
        () async {
      final other = FakeCalDav();
      Future<int> run(List<String> a) => runCli(a,
          config: {
            'url': FakeCalDav.collection.toString(),
            'user': 'u',
            'password': 'p'
          },
          env: const {},
          out: out,
          err: err,
          readStdin: () async => '',
          httpClient: multiHome(fake, other));
      expect(await run(['create', 'A', '--kind', 'note']), 0, reason: '$err');
      expect(
          await run(['create', 'B', '--kind', 'note', '--collection', 'Other']),
          0,
          reason: '$err');
      expect(fake.ics, hasLength(1));
      expect(other.ics, hasLength(1));
      out.clear();
      expect(await run(['list', '--collection', '/dav/d/', '--json']), 0);
      expect(out.toString(), contains('"B"'));
      expect(out.toString(), isNot(contains('"A"')));
      for (final bad in ['Nope', '../x/', 'https://evil.test/dav/d/']) {
        err.clear();
        expect(await run(['list', '--collection', bad]), 1, reason: bad);
        expect(err.toString(), contains('no collection'));
      }
    });
  });

  group('access flags', () {
    test('--read-only refuses item writes, allows reads', () async {
      for (final c in [
        ['create', 'T', '--kind', 'note'],
        ['update', 'x', '--title', 'y'],
        ['move', 'x', 'top'],
        ['tag', 'x', '--add', 'a'],
        ['status', 'x', 'done'],
        ['delete', 'x'],
        ['add', 'T'],
        ['rm', 'x'],
        ['set-status', 'x', 'done'],
      ]) {
        expect(await cli([...c, '--read-only']), 3, reason: c.join(' '));
      }
      expect(fake.ics, isEmpty);
      expect(await cli(['list', '--read-only']), 0);
      expect(await cli(['overview', '--read-only']), 0);
    });

    test('DAVDART_READ_ONLY=1 acts as --read-only', () async {
      expect(
          await cli(['create', 'T', '--kind', 'note'],
              env: {'DAVDART_READ_ONLY': '1'}),
          3);
      expect(fake.ics, isEmpty);
    });

    test('collection create, rename and delete need --allow-admin', () async {
      for (final c in [
        ['collections', 'create', 'X'],
        ['collections', 'rename', 'a', 'b'],
        ['collections', 'delete', 'a', '--confirm', 'a'],
      ]) {
        expect(await cli(c), 3, reason: c.join(' '));
        expect(err.toString(), contains('--allow-admin'));
        err.clear();
        expect(await cli([...c, '--allow-admin', '--read-only']), 3);
      }
      expect(fake.log.where((l) => !l.startsWith('GET')), isEmpty,
          reason: 'refused before any request');
    });

    test('refusals are JSON with --json', () async {
      expect(await cli(['collections', 'create', 'X', '--json']), 3);
      expect(jsonDecode(err.toString()), containsPair('error', isNotEmpty));
    });
  });

  group('commands', () {
    test('create, list, get, status, tag, move, delete round trip', () async {
      final f = await jcli(['create', 'Folder', '--kind', 'note', '--folder']);
      final fid = (f['item'] as Map)['uid'] as String;
      final t = await jcli([
        'create',
        'Do it',
        '--kind',
        'task',
        '--under',
        fid,
        '--tags',
        'x,y',
        '--due',
        '2026-12-01',
        '--priority',
        '2'
      ]);
      final tid = (t['item'] as Map)['uid'] as String;
      expect((t['item'] as Map)['due'], '20261201');
      final l = await jcli(['list', '--kind', 'all', '--no-folders']);
      expect(l['total'], 1);
      final s = await jcli(['status', tid, 'done']);
      expect((s['item'] as Map)['status'], 'done');
      await jcli(['tag', tid, '--add', 'z', '--remove', 'x']);
      final g = await jcli(['get', tid]);
      expect(g['tags'], containsAll(['y', 'z']));
      expect(g['tags'], isNot(contains('x')));
      expect(await cli(['tag', tid, '--add', 'kind-projects']), 1);
      expect(err.toString(), contains('create --folder'));
      expect(await cli(['tag', tid, '--remove', 'kind-folder']), 1);
      await jcli(['move', tid, 'top']);
      expect((await jcli(['get', tid])).containsKey('parent'), isFalse);
      await jcli(['delete', tid]);
      expect((await jcli(['list', '--kind', 'task']))['total'], 0);
    });

    test('status aliases and unknown words', () async {
      final n = await jcli(['create', 'N', '--kind', 'note']);
      final id = (n['item'] as Map)['uid'] as String;
      final s = await jcli(['status', id, 'in_progress']);
      expect((s['item'] as Map)['status'], 'doing');
      final r = await jcli(['status', id, 'ready_for_review']);
      expect((r['item'] as Map)['status'], 'review');
      out.clear();
      err.clear();
      expect(await cli(['status', id, 'wip']), 1);
      expect(
          err.toString(),
          contains(
              'allowed: backlog, todo, doing, blocked, review, done, canceled'));
      err.clear();
      expect(await cli(['new', 'W', '--status', 'wip']), 1);
      expect(err.toString(), contains('unknown status "wip"'));
      expect(await cli(['task', 'T', '--status', 'wip'], stdinText: 'd'), 1);
    });

    test('priority on notes: words and numbers', () async {
      final n = await jcli(['create', 'N', '--kind', 'note']);
      final id = (n['item'] as Map)['uid'] as String;
      var p = await jcli(['priority', id, 'high']);
      expect((p['item'] as Map)['priority'], 1);
      p = await jcli(['priority', id, '6']);
      expect((p['item'] as Map)['priority'], 9);
      out.clear();
      expect(await cli(['get', id]), 0);
      expect(out.toString(), contains('priority: 9'));
      p = await jcli(['priority', id, 'none']);
      expect((p['item'] as Map).containsKey('priority'), isFalse);
      final c =
          await jcli(['create', 'M', '--kind', 'note', '--priority', '5']);
      expect((c['item'] as Map)['priority'], 5);
    });

    test('--dry-run changes nothing', () async {
      final c = await jcli(['create', 'T', '--kind', 'note', '--dry-run']);
      expect(c['dryRun'], isTrue);
      expect(fake.ics, isEmpty);
    });

    test('create reads the body from stdin with --stdin', () async {
      await cli(['create', 'T', '--kind', 'note', '--stdin'],
          stdinText: 'hello body');
      out.clear();
      await cli(['get', 'T']);
      expect(out.toString(), contains('hello body'));
    });

    test('collections delete of an unknown collection fails', () async {
      expect(await cli(['collections', 'delete', 'x', '--allow-admin']), 1,
          reason: 'collection lookup fails first');
    });
  });

  group('old aliases keep their output', () {
    test('add, list, show, set-status, move, rm', () async {
      expect(await cli(['add', 'Alpha', 'body a']), 0);
      final uid = RegExp(r'created (\S+)').firstMatch('$out')!.group(1)!;
      out.clear();
      await cli(['list']);
      expect(out.toString(), '$uid\t-\t\tAlpha\n');
      out.clear();
      expect(await cli(['set-status', 'alph', 'doing']), 0);
      expect(out.toString(), 'Alpha: status doing\n');
      out.clear();
      await cli(['list', '--status', 'doing', '--tag', 'status-doing']);
      expect(out.toString(), contains('\tdoing\t'));
      out.clear();
      await cli(['show', 'alpha']);
      expect(out.toString(), startsWith('# Alpha\nuid: $uid\n'));
      out.clear();
      await cli(['folder', 'F'], stdinText: '');
      expect(out.toString(), startsWith('folder '));
      out.clear();
      await cli(['move', 'Alpha', 'F']);
      expect(out.toString(), 'Alpha: now under F\n');
      out.clear();
      await cli(['rm', uid]);
      expect(out.toString(), 'deleted $uid\n');
    });

    test('new with plan header and task', () async {
      expect(
          await cli(['new', 'Plan', '--id', 'D-1', '--owner', 'tm'],
              stdinText: 'text'),
          0);
      out.clear();
      await cli(['board']);
      expect(out.toString(), contains('== backlog (1)'));
      expect(out.toString(), contains('D-1  [tm]'));
      out.clear();
      await cli(['task', 'T', '--status', 'doing'], stdinText: 'd');
      expect(out.toString(), startsWith('created task '));
    });

    test('board: Other column for unknown words, board order inside',
        () async {
      for (final n in ['a', 'b', 'c']) {
        await jcli(['create', n, '--kind', 'note', '--status', 'todo']);
      }
      await jcli(['rank', 'c', 'top']);
      expect(
          await cli(['create', 'W', '--kind', 'note', '--body',
              'status: waiting\n\nx']),
          0);
      expect(
          await cli(['create', 'V', '--kind', 'note', '--body',
              'status: someday\n\nx']),
          0);
      out.clear();
      expect(await cli(['board']), 0);
      final text = out.toString();
      expect(text, contains('== todo (3)'));
      expect(text, contains('\n== other (2)'));
      expect(text, isNot(contains('== waiting')));
      expect(text, isNot(contains('== someday')));
      expect(text.indexOf('== todo'), lessThan(text.indexOf('== other')));
      final col = text.substring(
          text.indexOf('== todo'), text.indexOf('== other'));
      expect(col.indexOf('\n  c\n'), lessThan(col.indexOf('\n  b\n')));
    });
  });

  group('rank', () {
    Future<List<String>> order(String status) async => [
          for (final i in (await jcli(
              ['list', '--kind', 'task', '--status', status]))['items'] as List)
            (i as Map)['title'] as String
        ];
    test('top, bottom, before, after, none, errors, read-only', () async {
      for (final n in ['a', 'b', 'c']) {
        await jcli(['create', n, '--kind', 'task', '--status', 'todo']);
      }
      var r = await jcli(['rank', 'c', 'top']);
      expect((r['order'] as List).first['title'], 'c');
      expect(await order('todo'), ['c', 'a', 'b']);
      await jcli(['rank', 'c', 'bottom']);
      expect(await order('todo'), ['a', 'b', 'c']);
      await jcli(['rank', 'c', 'before', 'a']);
      expect(await order('todo'), ['c', 'a', 'b']);
      await jcli(['rank', 'c', 'after', 'a']);
      expect(await order('todo'), ['a', 'c', 'b']);
      out.clear();
      expect(await cli(['get', 'c']), 0);
      expect(out.toString(), contains('rank: '));
      await jcli(['rank', 'c', 'none']);
      out.clear();
      expect(await cli(['rank', 'a', 'top']), 0);
      expect(out.toString(), contains('todo column now'));
      expect(await cli(['rank', 'a']), 2);
      expect(await cli(['rank', 'a', 'sideways']), 2);
      expect(await cli(['rank', 'a', 'before']), 2);
      expect(await cli(['rank', 'a', 'before', 'ghost']), 1);
      expect(await cli(['rank', 'a', 'top', '--read-only']), 3);
    });
  });
}
