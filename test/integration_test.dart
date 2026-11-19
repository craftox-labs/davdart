import 'dart:io';

import 'package:davdart/davdart.dart';
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
  });
}
