import 'package:davdart_web/host_guard.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final h = const Pipeline()
      .addMiddleware(hostGuard(parseAllowedHosts(null)))
      .addHandler((_) => Response.ok('ok'));
  Future<int> code(Map<String, String> headers) async =>
      (await h(Request('GET', Uri.parse('http://x/api/notes'),
              headers: headers)))
          .statusCode;

  test('loopback and tailnet hosts pass, with or without port', () async {
    expect(await code({'host': '127.0.0.1:8800'}), 200);
    expect(await code({'host': 'localhost'}), 200);
    expect(await code({'host': '[::1]:8800'}), 200);
    expect(await code({'host': 'tm-serve.tailf6fba0.ts.net:10002'}), 200);
  });

  test('rebinding host and missing host are refused', () async {
    expect(await code({'host': 'evil.example:8800'}), 421);
    expect(await code({}), 421);
  });

  test('foreign Origin is refused, same-host Origin passes', () async {
    expect(
        await code({'host': 'localhost:1', 'origin': 'https://evil.example'}),
        403);
    expect(await code({'host': 'localhost:1', 'origin': 'http://localhost:1'}),
        200);
  });

  test('env list replaces defaults', () async {
    final g = const Pipeline()
        .addMiddleware(hostGuard(parseAllowedHosts('Box.lan:80, localhost')))
        .addHandler((_) => Response.ok('ok'));
    expect(
        (await g(Request('GET', Uri.parse('http://x/'),
                headers: {'host': 'box.lan:99'})))
            .statusCode,
        200);
    expect(
        (await g(Request('GET', Uri.parse('http://x/'),
                headers: {'host': '127.0.0.1'})))
            .statusCode,
        421);
  });
}
