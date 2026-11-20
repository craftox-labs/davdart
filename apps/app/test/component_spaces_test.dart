import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// A server with a notes calendar and a bot calendar that takes only VEVENT
// and VTODO (no VJOURNAL).
http.Client _server(List<String> seen) => MockClient((r) async {
  seen.add('${r.method} ${r.url.path}');
  if (r.method == 'PROPFIND' && r.url.path == '/dav/tm/') {
    String coll(String path, String name, List<String> comps) =>
        '<response><href>$path</href><propstat><prop>'
        '<displayname>$name</displayname>'
        '<resourcetype><collection/><C:calendar/></resourcetype>'
        '<C:supported-calendar-component-set>'
        '${[for (final c in comps) '<C:comp name="$c"/>'].join()}'
        '</C:supported-calendar-component-set></prop></propstat></response>';
    return http.Response(
      '<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
      '<response><href>/dav/tm/</href><propstat><prop>'
      '<resourcetype><collection/></resourcetype></prop></propstat></response>'
      '${coll('/dav/notes/', 'Notes', ['VJOURNAL', 'VTODO', 'VEVENT'])}'
      '${coll('/dav/bot/', 'Bot', ['VEVENT', 'VTODO'])}'
      '</multistatus>',
      207,
    );
  }
  if (r.method == 'REPORT') {
    return http.Response(
      '<multistatus xmlns="DAV:"><sync-token>t1</sync-token></multistatus>',
      207,
    );
  }
  return http.Response('', 404);
});

AppState _app(SpaceCatalog c, MemoryStorage m) =>
    AppState(c.sourceFor(c.current!), prefs: m, catalog: c);

void main() {
  test('a VEVENT,VTODO collection is listed and supports no notes', () async {
    final seen = <String>[];
    final m = MemoryStorage();
    final c = SpaceCatalog(
      m,
      davBase: Uri.parse('https://fake.test/dav/'),
      httpClient: _server(seen),
    );
    await c.signIn('tm', 'pw');
    final bot = c.spaces.firstWhere((s) => s.name == 'Bot');
    expect((bot.notes, bot.tasks, bot.events), (false, true, true));
    final notes = c.spaces.firstWhere((s) => s.name == 'Notes');
    expect((notes.notes, notes.tasks, notes.events), (true, true, true));
    // Kept across a restart.
    final again = SpaceCatalog(m, davBase: Uri.parse('https://fake.test/dav/'));
    expect(again.spaces.firstWhere((s) => s.name == 'Bot').notes, isFalse);

    c.current = bot.id;
    final s = _app(c, m);
    await s.load();
    expect(s.editable, isFalse);
    expect(s.tasksEditable, isTrue);
    expect(s.eventsEditable, isTrue);
    expect(s.syncMessage ?? '', isNot(contains('rror')));
    expect(s.error, isNull);
  });

  testWidgets('the Bot Space shows no Notes section', (t) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final m = MemoryStorage();
    final c = SpaceCatalog(
      m,
      davBase: Uri.parse('https://fake.test/dav/'),
      httpClient: _server([]),
    );
    await t.runAsync(() => c.signIn('tm', 'pw'));
    c.current = c.spaces.firstWhere((s) => s.name == 'Bot').id;
    final s = _app(c, m);
    await t.pumpWidget(DavdartApp(state: s));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('rail-notes')), findsNothing);
    expect(find.byKey(const Key('rail-tasks')), findsOneWidget);
    expect(find.byKey(const Key('rail-events')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
