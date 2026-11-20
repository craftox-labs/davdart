import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'tasks_helper.dart';

import 'package:http/testing.dart';

// A server with a notes calendar and a bot calendar that takes only VEVENT
// and VTODO (no VJOURNAL).
http.Client _server(
  List<String> seen, {
  List<String> botComps = const ['VEVENT', 'VTODO'],
}) => MockClient((r) async {
  seen.add('${r.method} ${r.url.path}');
  if (r.method == 'REPORT' && r.body.contains('name="VJOURNAL"')) {
    seen.add('VJOURNAL-QUERY ${r.url.path}');
  }
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
      '${coll('/dav/bot/', 'Bot', botComps)}'
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

  Future<(AppState, List<String>)> open(List<String> comps, String name) async {
    final seen = <String>[];
    final m = MemoryStorage();
    final c = SpaceCatalog(
      m,
      davBase: Uri.parse('https://fake.test/dav/'),
      httpClient: _server(seen, botComps: comps),
    );
    await c.signIn('tm', 'pw');
    c.current = c.spaces.firstWhere((s) => s.name == name).id;
    final s = _app(c, m);
    await s.load();
    // Let the sync that load() starts finish.
    for (var i = 0; i < 20 && s.syncing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    seen.removeWhere(
      (r) => !r.endsWith(' /dav/bot/') || r.startsWith('PROPFIND'),
    );
    return (s, seen);
  }

  test('no sync request for an unsupported component', () async {
    final (all, allSeen) = await open(['VJOURNAL', 'VTODO', 'VEVENT'], 'Bot');
    expect(all.syncMessage, isNot(contains('problem')));
    // Login check plus three syncs.
    expect(allSeen, hasLength(5), reason: '$allSeen');
    final (bot, botSeen) = await open(['VEVENT', 'VTODO'], 'Bot');
    expect(botSeen, hasLength(3), reason: '$botSeen');
    expect(botSeen.where((r) => r.startsWith('VJOURNAL')), isEmpty);
    expect(bot.syncMessage, startsWith('Synced'));
    // A VJOURNAL collection is a project Space: tasks and events too,
    // whatever it advertises (the real davdart collection holds events).
    final (davdart, s1) = await open(['VJOURNAL', 'VTODO'], 'Bot');
    expect(s1, hasLength(5), reason: '$s1');
    expect(davdart.supportsEvents && davdart.supportsTasks, isTrue);
    expect(davdart.editable && davdart.eventsEditable, isTrue);
    final (onlyNotes, s2) = await open(['VJOURNAL'], 'Bot');
    expect(onlyNotes.supportsEvents && onlyNotes.tasksEditable, isTrue);
    expect(s2, hasLength(5), reason: '$s2');
  });

  test(
    'a type the collection does not advertise stays when items exist',
    () async {
      final (tasksOnly, _) = await open(['VTODO'], 'Bot');
      expect(tasksOnly.supportsEvents, isFalse);
      await (tasksOnly.source as SpaceNoteSource).saveEvent(mkEvent('e1'));
      await tasksOnly.load();
      expect(tasksOnly.supportsEvents, isTrue);
      expect(tasksOnly.supportsNotes, isFalse);
    },
  );

  test('sections redirect to a supported one in the state itself', () async {
    final (bot, _) = await open(['VEVENT', 'VTODO'], 'Bot');
    bot.setSection(Section.notes);
    expect(bot.section, Section.tasks);
    bot.openEventsPanel();
    expect(bot.section, Section.events);
    // An org-style collection has no Notes; a project one keeps Tasks.
    final (proj, _) = await open(['VJOURNAL', 'VEVENT'], 'Bot');
    proj.openTasksPanel();
    expect(proj.section, Section.tasks);
  });

  test('persisted Space JSON without component fields supports all', () {
    final m = MemoryStorage();
    m.write(
      'davdart.spaces.v1',
      '[{"id":"a","name":"A"},{"id":"b","name":"B","collection":"x/"},'
          '{"id":"c","name":"C","notes":false}]',
    );
    final c = SpaceCatalog(m);
    final a = c.spaces[0], b = c.spaces[1], cc = c.spaces[2];
    expect((a.notes, a.tasks, a.events), (true, true, true));
    expect((b.notes, b.tasks, b.events), (true, true, true));
    expect((cc.notes, cc.tasks, cc.events), (false, true, true));
    // An old save with events off on a notes Space is migrated on.
    final m2 = MemoryStorage();
    m2.write(
      'davdart.spaces.v1',
      '[{"id":"d","name":"D","notes":true,"events":false},'
          '{"id":"e","name":"E","notes":false,"events":false}]',
    );
    final c2 = SpaceCatalog(m2);
    expect(c2.spaces[0].events, isTrue);
    expect(c2.spaces[1].events, isFalse);
  });
}
