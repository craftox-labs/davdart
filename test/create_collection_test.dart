import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('createCollection sends MKCALENDAR with the name and VJOURNAL',
      () async {
    late http.Request seen;
    final client = MockClient((r) async {
      seen = r;
      return http.Response('', 201);
    });
    final url = await CalDavClient.createCollection(
      Uri.parse('http://h/dav/bot'),
      'Work & <play>',
      username: 'bot',
      password: 'pw',
      client: client,
      id: 'abc',
    );
    expect(url.toString(), 'http://h/dav/bot/abc/');
    expect(seen.method, 'MKCALENDAR');
    expect(seen.url, url);
    expect(seen.body, contains('Work &amp; &lt;play>'));
    expect(seen.body, contains('VJOURNAL'));
    expect(seen.body, contains('VTODO'));
  });

  test('createCollection reports a refusal', () async {
    final client = MockClient((_) async => http.Response('', 403));
    expect(
      () => CalDavClient.createCollection(Uri.parse('http://h/dav/bot/'), 'x',
          username: 'bot', password: 'pw', client: client),
      throwsA(isA<CalDavException>()),
    );
  });

  test('random ids differ', () async {
    final urls = <String>{};
    final client = MockClient((r) async {
      urls.add(r.url.path);
      return http.Response('', 201);
    });
    for (var i = 0; i < 3; i++) {
      await CalDavClient.createCollection(Uri.parse('http://h/dav/bot/'), 'x',
          username: 'bot', password: 'pw', client: client);
    }
    expect(urls, hasLength(3));
  });

  test('renameCollection sends PROPPATCH with the new name', () async {
    late http.Request seen;
    final client = MockClient((r) async {
      seen = r;
      return http.Response(
          '<multistatus xmlns="DAV:"><response><propstat><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>',
          207);
    });
    await CalDavClient.renameCollection(
        Uri.parse('http://h/dav/bot/abc'), 'New <n>',
        username: 'bot', password: 'pw', client: client);
    expect(seen.method, 'PROPPATCH');
    expect(seen.url.path, '/dav/bot/abc/');
    expect(seen.body, contains('New &lt;n>'));
  });

  test('renameCollection reports a refused property', () async {
    final client = MockClient((_) async => http.Response(
        '<multistatus xmlns="DAV:"><response><propstat><status>HTTP/1.1 403 Forbidden</status></propstat></response></multistatus>',
        207));
    expect(
      () => CalDavClient.renameCollection(
          Uri.parse('http://h/dav/bot/abc/'), 'x',
          username: 'bot', password: 'pw', client: client),
      throwsA(isA<CalDavException>()),
    );
  });
}
