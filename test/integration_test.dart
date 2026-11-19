import 'dart:io';

import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Live round trip. Runs only when DAVDART_TEST_URL (plus DAVDART_TEST_USER
/// and DAVDART_TEST_PASSWORD) are set; there is no default URL.
void main() {
  final env = Platform.environment;
  final url = env['DAVDART_TEST_URL'];
  final skipReason = (url == null || url.isEmpty)
      ? 'DAVDART_TEST_URL not set (live CalDAV integration test)'
      : null;

  group('live CalDAV round trip', skip: skipReason, () {
    late CalDavClient client;
    Note? current;

    setUp(() {
      client = CalDavClient(
        collection: Uri.parse(url!),
        username: env['DAVDART_TEST_USER'] ?? '',
        password: env['DAVDART_TEST_PASSWORD'] ?? '',
      );
      current = null;
    });

    tearDown(() async {
      try {
        if (current != null) await client.deleteNote(current!);
      } finally {
        client.close();
      }
    });

    test('create, get, list, update, conflict, delete', () async {
      final uid = 'davdart-it-${DateTime.now().microsecondsSinceEpoch}';
      final created = await client.putNote(Note(uid: uid, summary: 'one'));
      current = created;
      expect(created.etag, isNotNull);

      final got = await client.getNote(created.href!);
      expect(got.uid, uid);
      expect(got.summary, 'one');

      final listed = await client.listNotes();
      expect(listed.map((n) => n.uid), contains(uid));

      final updated = await client.putNote(created.copyWith(summary: 'two'));
      current = updated;
      expect((await client.getNote(updated.href!)).summary, 'two');

      // created still carries the stale etag.
      await expectLater(client.putNote(created.copyWith(summary: 'three')),
          throwsA(isA<ConflictException>()));

      await client.deleteNote(updated);
      current = null;
      final after = await client.listNotes();
      expect(after.map((n) => n.uid), isNot(contains(uid)));
    });

    test('two devices: push, pull, merge disjoint edits, delete', () async {
      final tag = DateTime.now().microsecondsSinceEpoch;
      CalDavClient mk() => CalDavClient(
            collection: Uri.parse(url!),
            username: env['DAVDART_TEST_USER'] ?? '',
            password: env['DAVDART_TEST_PASSWORD'] ?? '',
          );
      final a = SyncEngine(mk(), MemoryNoteStore());
      final b = SyncEngine(mk(), MemoryNoteStore());
      final uid = 'davdart-it-two-$tag';
      try {
        await a.save(Note(
            uid: uid,
            summary: 'live $tag',
            description: 'item_id: it\nstatus: todo\n\nline1\nline2\nline3',
            categories: ['status-todo']));
        final ra = await a.sync();
        expect(ra.errors, isEmpty);
        expect(ra.pushed, 1);

        final rb = await b.sync();
        expect(rb.errors, isEmpty);
        expect((await b.notes()).map((n) => n.uid), contains(uid));

        // A edits the top line, B the bottom line; no overlap.
        final na = (await a.notes()).firstWhere((n) => n.uid == uid);
        await a.save(na.copyWith(
            description: na.description.replaceFirst('line1', 'A1')));
        final nb = (await b.notes()).firstWhere((n) => n.uid == uid);
        await b.save(nb.copyWith(
            description: nb.description.replaceFirst('line3', 'B3')));
        expect((await a.sync()).errors, isEmpty);
        final rb2 = await b.sync();
        expect(rb2.errors, isEmpty);
        expect(rb2.conflicts, isEmpty);
        expect((await a.sync()).errors, isEmpty);
        for (final e in [a, b]) {
          final n = (await e.notes()).firstWhere((n) => n.uid == uid);
          expect(n.description, contains('A1'));
          expect(n.description, contains('B3'));
          expect(n.description, contains('line2'));
        }

        await a.delete(uid);
        expect((await a.sync()).errors, isEmpty);
        expect((await b.sync()).errors, isEmpty);
        expect((await b.notes()).map((n) => n.uid), isNot(contains(uid)));
      } finally {
        final c = mk();
        for (final n in await c.listNotes()) {
          if (n.uid == uid) await c.deleteNote(n);
        }
        c.close();
      }
    });
  });

  test('create a collection, find it by name, delete it', skip: skipReason,
      () async {
    final user = env['DAVDART_TEST_USER'] ?? '';
    final pw = env['DAVDART_TEST_PASSWORD'] ?? '';
    final home = Uri.parse(url!).resolve('../');
    final name = 'davdart-it-tmp-${DateTime.now().microsecondsSinceEpoch}';
    final made = await CalDavClient.createCollection(home, name,
        username: user, password: pw);
    try {
      final found =
          await CalDavClient.discover(home, username: user, password: pw);
      final mine = found.where((c) => c.name == name).toList();
      expect(mine, hasLength(1));
      expect(mine.single.holdsNotes, isTrue);
      // It takes notes.
      final c = CalDavClient(collection: made, username: user, password: pw);
      final n = await c.putNote(Note(uid: 'x1', summary: 'hi'));
      expect((await c.listNotes()).map((e) => e.summary), ['hi']);
      c.close();
      expect(n.etag, isNotNull);
    } finally {
      final r = http.Request('DELETE', made)
        ..headers['Authorization'] =
            'Basic ${base64.encode(utf8.encode('$user:$pw'))}';
      final resp = await http.Response.fromStream(await r.send());
      expect(resp.statusCode, anyOf(200, 204));
    }
  });
}
