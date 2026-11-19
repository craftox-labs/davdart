import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _body = '''<?xml version="1.0"?>
<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
 <response><href>/dav/bot/</href><propstat><prop>
   <resourcetype><collection/></resourcetype></prop></propstat></response>
 <response><href>/dav/bot/872f44ec-0001/</href><propstat><prop>
   <displayname>planning</displayname>
   <resourcetype><collection/><C:calendar/></resourcetype>
   <C:supported-calendar-component-set><C:comp name="VJOURNAL"/></C:supported-calendar-component-set>
 </prop></propstat></response>
 <response><href>/dav/bot/aaaa-events/</href><propstat><prop>
   <displayname>Events</displayname>
   <resourcetype><collection/><C:calendar/></resourcetype>
   <C:supported-calendar-component-set><C:comp name="VEVENT"/></C:supported-calendar-component-set>
 </prop></propstat></response>
 <response><href>/dav/bot/no-name/</href><propstat><prop>
   <resourcetype><collection/><C:calendar/></resourcetype>
 </prop></propstat></response>
</multistatus>''';

void main() {
  test('discover lists calendars by name and flags note support', () async {
    late http.Request seen;
    final client = MockClient((r) async {
      seen = r;
      return http.Response(_body, 207);
    });
    final found = await CalDavClient.discover(
      Uri.parse('http://h/dav/bot'),
      username: 'bot',
      password: 'pw',
      client: client,
    );
    expect(seen.method, 'PROPFIND');
    expect(seen.headers['Depth'], '1');
    expect(found.map((c) => c.name), ['planning', 'Events', 'no-name']);
    expect(found.map((c) => c.holdsNotes), [true, false, true]);
    expect(found.first.href.toString(), 'http://h/dav/bot/872f44ec-0001/');
  });

  test('discover reports a refused login', () async {
    final client = MockClient((_) async => http.Response('', 401));
    expect(
      () => CalDavClient.discover(
        Uri.parse('http://h/dav/bot/'),
        username: 'bot',
        password: 'x',
        client: client,
      ),
      throwsA(isA<CalDavException>()),
    );
  });
}
