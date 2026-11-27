import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

String _ics(String uid) =>
    serializeNote(Note(uid: uid, summary: uid))
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;');

String _resp(String name, String uid) =>
    '''
<d:response><d:href>/dav/memo/$name.ics</d:href><d:propstat><d:prop>
<d:getetag>"$name"</d:getetag>
<c:calendar-data>${_ics(uid)}</c:calendar-data>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>''';

String _multi(String inner, [String token = 'tok2']) =>
    '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" '
    'xmlns:c="urn:ietf:params:xml:ns:caldav">$inner'
    '<d:sync-token>$token</d:sync-token></d:multistatus>';

void main() {
  final base = Uri.parse('https://example.test/dav/memo');
  CalDavClient make(MockClient m, [List<String?>? errors]) => CalDavClient(
    collection: base,
    username: 'u',
    password: 'p',
    client: m,
    onResourceError: (h, e) => errors?.add(h),
  );
  http.Response r207(String b) => http.Response.bytes(utf8.encode(b), 207);

  test('initial sync sends empty token and returns everything', () async {
    late http.Request seen;
    final c = make(
      MockClient((req) async {
        seen = req;
        return r207(_multi(_resp('a', 'a') + _resp('b', 'b'), 'tok1'));
      }),
    );
    final res = await c.sync();
    expect(seen.method, 'REPORT');
    expect(seen.body, contains('<d:sync-token></d:sync-token>'));
    expect(seen.body, contains('<d:sync-level>1</d:sync-level>'));
    expect(res.changed.map((n) => n.uid), ['a', 'b']);
    expect(res.changed.first.etag, '"a"');
    expect(res.deletedHrefs, isEmpty);
    expect(res.syncToken, 'tok1');
  });

  test('incremental sync reports deletions', () async {
    late http.Request seen;
    final c = make(
      MockClient((req) async {
        seen = req;
        return r207(
          _multi(
            '${_resp('a', 'a')}'
            '<d:response><d:href>/dav/memo/gone.ics</d:href>'
            '<d:status>HTTP/1.1 404 Not Found</d:status></d:response>'
            '<d:response><d:href>/dav/memo/gone2.ics</d:href><d:propstat>'
            '<d:prop><d:getetag/></d:prop>'
            '<d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>'
            '</d:response>',
          ),
        );
      }),
    );
    final res = await c.sync(syncToken: 'tok1');
    expect(seen.body, contains('<d:sync-token>tok1</d:sync-token>'));
    expect(res.changed.single.uid, 'a');
    expect(res.deletedHrefs, ['/dav/memo/gone.ics', '/dav/memo/gone2.ics']);
    expect(res.syncToken, 'tok2');
  });

  test('invalid token throws SyncTokenInvalid', () async {
    final c = make(
      MockClient(
        (req) async => http.Response(
          '<d:error xmlns:d="DAV:"><d:valid-sync-token/></d:error>',
          403,
        ),
      ),
    );
    expect(c.sync(syncToken: 'old'), throwsA(isA<SyncTokenInvalid>()));
  });

  test('other failures throw plain CalDavException', () async {
    final c = make(MockClient((req) async => http.Response('', 500)));
    expect(
      c.sync(),
      throwsA(
        isA<CalDavException>().having(
          (e) => e is SyncTokenInvalid,
          'invalid',
          isFalse,
        ),
      ),
    );
  });

  test('malformed resource is skipped and reported', () async {
    final errors = <String?>[];
    final c = make(
      MockClient((req) async {
        return r207(
          _multi(
            '<d:response><d:href>/dav/memo/bad.ics</d:href><d:propstat><d:prop>'
            '<c:calendar-data>BEGIN:VCALENDAR\nBEGIN:VJOURNAL\nEND:VCALENDAR'
            '</c:calendar-data></d:prop></d:propstat></d:response>'
            '${_resp('ok', 'ok')}',
          ),
        );
      }),
      errors,
    );
    final res = await c.sync();
    expect(res.changed.map((n) => n.uid), ['ok']);
    expect(errors, ['/dav/memo/bad.ics']);
  });

  test('missing calendar-data falls back to getNote', () async {
    final c = make(
      MockClient((req) async {
        if (req.method == 'GET') {
          expect(req.url.path, '/dav/memo/m.ics');
          return http.Response(
            _ics('m').replaceAll('&amp;', '&').replaceAll('&lt;', '<'),
            200,
            headers: {'etag': '"m1"'},
          );
        }
        return r207(
          _multi(
            '<d:response><d:href>/dav/memo/m.ics</d:href>'
            '<d:propstat><d:prop><d:getetag>"m1"</d:getetag></d:prop>'
            '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>',
          ),
        );
      }),
    );
    final res = await c.sync();
    expect(res.changed.single.uid, 'm');
    expect(res.changed.single.etag, '"m1"');
  });
}
