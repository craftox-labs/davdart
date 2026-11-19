import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

String _ics(String uid, String summary) =>
    serializeNote(Note(uid: uid, summary: summary));

void main() {
  toleranceTests();
  final base = Uri.parse('https://example.test/dav/memo');

  CalDavClient make(MockClient m) =>
      CalDavClient(collection: base, username: 'u', password: 'p', client: m);

  test('listNotes sends a VJOURNAL REPORT and parses the multistatus',
      () async {
    late http.Request seen;
    final c = make(MockClient((req) async {
      seen = req;
      final body = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
 <d:response><d:href>/dav/memo/a.ics</d:href><d:propstat><d:prop>
  <d:getetag>"e1"</d:getetag>
  <c:calendar-data>${_ics('a', 'First').replaceAll('&', '&amp;')}</c:calendar-data>
 </d:prop></d:propstat></d:response>
 <d:response><d:href>/dav/memo/</d:href></d:response>
</d:multistatus>''';
      return http.Response.bytes(utf8.encode(body), 207);
    }));
    final notes = await c.listNotes();
    expect(seen.method, 'REPORT');
    expect(seen.url.path, '/dav/memo/');
    expect(seen.headers['Depth'], '1');
    expect(seen.headers['Authorization'],
        'Basic ${base64.encode(utf8.encode('u:p'))}');
    expect((seen as dynamic).body, contains('name="VJOURNAL"'));
    expect(notes.single.uid, 'a');
    expect(notes.single.etag, '"e1"');
    expect(notes.single.href, '/dav/memo/a.ics');
  });

  test('putNote creates with If-None-Match and updates with If-Match',
      () async {
    final seen = <http.Request>[];
    final c = make(MockClient((req) async {
      seen.add(req);
      return http.Response('', 201, headers: {'etag': '"new"'});
    }));
    final created = await c.putNote(Note(uid: 'x', summary: 'Hi'));
    expect(seen.last.method, 'PUT');
    expect(seen.last.headers['If-None-Match'], '*');
    expect(seen.last.url.path, '/dav/memo/x.ics');
    expect(created.etag, '"new"');
    await c.putNote(created.copyWith(summary: 'Hi 2'));
    expect(seen.last.headers['If-Match'], '"new"');
    expect(seen.last.headers.containsKey('If-None-Match'), isFalse);
  });

  test('412 becomes ConflictException', () async {
    final c = make(MockClient((_) async => http.Response('', 412)));
    expect(() => c.putNote(Note(uid: 'x')), throwsA(isA<ConflictException>()));
  });

  test('getNote parses body and etag; deleteNote is conditional', () async {
    final seen = <http.Request>[];
    final c = make(MockClient((req) async {
      seen.add(req);
      if (req.method == 'GET') {
        return http.Response(_ics('g', 'Got'), 200, headers: {'etag': '"g1"'});
      }
      return http.Response('', 204);
    }));
    final n = await c.getNote('g.ics');
    expect(n.summary, 'Got');
    expect(n.etag, '"g1"');
    await c.deleteNote(n);
    expect(seen.last.method, 'DELETE');
    expect(seen.last.headers['If-Match'], '"g1"');
  });

  test('non-success statuses raise CalDavException', () async {
    final c = make(MockClient((_) async => http.Response('', 401)));
    expect(c.listNotes(), throwsA(isA<CalDavException>()));
  });
}

void toleranceTests() {
  test('one malformed resource does not abort the listing', () {
    String resp(String href, String data) =>
        '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
        '<c:calendar-data>$data</c:calendar-data></d:prop></d:propstat>'
        '</d:response>';
    final body = '<d:multistatus xmlns:d="DAV:" '
        'xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '${resp('/bad.ics', 'BEGIN:VCALENDAR\nBEGIN:VJOURNAL\nSUMMARY:x\n'
            'END:VJOURNAL\nEND:VCALENDAR')}'
        '${resp('/ok.ics', _ics('ok', 'Fine'))}</d:multistatus>';
    final errors = <String?>[];
    final notes = parseMultistatus(body, onError: (h, _) => errors.add(h));
    expect(notes.map((n) => n.uid), ['ok']);
    expect(errors, ['/bad.ics']);
  });

  test('putNote refreshes DTSTAMP and LAST-MODIFIED', () async {
    late String sent;
    final c = CalDavClient(
        collection: Uri.parse('https://example.test/c'),
        username: 'u',
        password: 'p',
        client: MockClient((req) async {
          sent = req.body;
          return http.Response('', 201, headers: {'etag': '"1"'});
        }));
    final old = DateTime.utc(2020);
    await c.putNote(Note(uid: 'x', dtstamp: old, lastModified: old));
    expect(sent, isNot(contains('20200101T000000Z')));
    expect(sent, contains('LAST-MODIFIED:'));
  });
}
