import 'package:davdart_web/dav_proxy.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late http.BaseRequest seen;
  late Handler h;
  setUp(() {
    h = davProxy(
      Uri.parse('http://radicale:5232'),
      client: MockClient((r) async {
        seen = r;
        return http.Response('ok', 207, headers: {
          'etag': '"x"',
          'set-cookie': 'secret=1',
          'content-type': 'application/xml',
        });
      }),
    );
  });

  Request rq(String method, String path, {Map<String, String>? headers}) =>
      Request(method, Uri.parse('http://app/$path'),
          headers: headers, body: 'body');

  test('forwards path, auth and body; drops other headers both ways', () async {
    final r = await h(rq('PROPFIND', 'dav/u/cal/', headers: {
      'Authorization': 'Basic abc',
      'Cookie': 'x=1',
      'Depth': '1'
    }));
    expect(r.statusCode, 207);
    expect(seen.method, 'PROPFIND');
    expect(seen.url.toString(), 'http://radicale:5232/u/cal/');
    expect(seen.headers['Authorization'], 'Basic abc');
    expect(seen.headers['Depth'], '1');
    expect(seen.headers['X-Script-Name'], '/dav');
    expect(seen.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('cookie')));
    expect(r.headers['etag'], '"x"');
    expect(r.headers.containsKey('set-cookie'), isFalse);
  });

  test('refuses other methods and path tricks', () async {
    expect((await h(rq('MKCALENDAR', 'dav/u/x/'))).statusCode, 405);
    expect((await h(rq('POST', 'dav/u/'))).statusCode, 405);
    // Dart's Uri resolves dot segments (encoded too) before the proxy sees
    // them, so these cannot climb above the upstream root.
    await h(rq('GET', 'dav/u/%2e%2e/%2e%2e/admin'));
    expect(seen.url.toString(), 'http://radicale:5232/admin');
    expect((await h(rq('GET', 'dav/u%2F..%2Fadmin'))).statusCode, 400);
  });
}
