import 'dart:io';

import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/space_catalog.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../test/support/fake_caldav.dart';
import 'catalog_helper.dart';

/// Account with one server Space "Work" holding one note; DELETE answers
/// [deleteStatus] and is logged.
Future<(AppState, List<String>, Directory)> _setup({
  int deleteStatus = 204,
}) async {
  final server = FakeCalDav();
  server.external('one.ics', serializeNote(Note(uid: 'one', summary: 'Mine')));
  final seen = <String>[];
  final client = MockClient((r) async {
    seen.add('${r.method} ${r.url.path}');
    if (r.method == 'PROPFIND' && r.url.path == '/dav/tm/') {
      return http.Response(
        '<multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">'
        '<response><href>/dav/tm/</href><propstat><prop>'
        '<resourcetype><collection/></resourcetype></prop></propstat></response>'
        '<response><href>/dav/c/</href><propstat><prop>'
        '<displayname>Work</displayname>'
        '<resourcetype><collection/><C:calendar/></resourcetype>'
        '</prop></propstat></response></multistatus>',
        207,
      );
    }
    if (r.method == 'DELETE' && r.url.path == '/dav/c/') {
      return http.Response(deleteStatus == 204 ? '' : 'no', deleteStatus);
    }
    if (r.method == 'REPORT' && r.url.path == '/dav/tm/') {
      return http.Response('', 404);
    }
    return server.respond(r);
  });
  final storage = MemoryStorage();
  catalogWithPlanning(storage); // seeds the Planning Space
  final tmp = Directory.systemTemp.createTempSync('davdart-backup-test');
  final c = SpaceCatalog(
    storage,
    davBase: Uri.parse('https://fake.test/dav/'),
    httpClient: client,
    backupDir: tmp.path,
  );
  final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
  await s.load();
  await s.signIn('tm', 'pw');
  await s.switchSpace(s.spaces.firstWhere((e) => e.name == 'Work').id);
  return (s, seen, tmp);
}

Future<void> _open(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(1400, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('rail-spaces')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('space-server-delete')));
  await t.pumpAndSettle();
}

bool _goEnabled(WidgetTester t) =>
    t.widget<FButton>(find.byKey(const Key('server-delete-go'))).onPress !=
    null;

void main() {
  testWidgets('the typed name gates the delete; success removes the Space', (
    t,
  ) async {
    final (s, seen, tmp) = await _setup();
    addTearDown(() => tmp.deleteSync(recursive: true));
    await _open(t, s);
    expect(
      find.textContaining('removes the Space from the server for everyone'),
      findsOneWidget,
    );
    expect(find.textContaining('1 item'), findsOneWidget);
    expect(_goEnabled(t), isFalse);
    await t.enterText(find.byKey(const Key('server-delete-name')), 'work');
    await t.pump();
    expect(_goEnabled(t), isFalse); // exact, case included
    await t.enterText(find.byKey(const Key('server-delete-name')), 'Work');
    await t.pump();
    expect(_goEnabled(t), isTrue);
    await t.tap(find.byKey(const Key('server-delete-go')));
    await t.pumpAndSettle();
    expect(seen.where((e) => e == 'DELETE /dav/c/'), hasLength(1));
    expect(s.spaces.map((e) => e.name), ['Planning']);
    // The backup went to disk before the delete.
    expect(
      tmp
          .listSync(recursive: true)
          .whereType<File>()
          .any((f) => f.path.endsWith('.ics')),
      isTrue,
    );
  });

  testWidgets('the narrow Spaces panel opens the dialog too', (t) async {
    final (s, seen, tmp) = await _setup();
    addTearDown(() => tmp.deleteSync(recursive: true));
    t.view.physicalSize = const Size(600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(DavdartApp(state: s));
    await t.pumpAndSettle();
    // From the drawer's Spaces panel, next to the strip.
    await t.tap(find.byKey(const Key('menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('rail-spaces')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('space-server-delete')));
    await t.pumpAndSettle();
    expect(
      find.textContaining('removes the Space from the server for everyone'),
      findsOneWidget,
    );
    expect(seen.any((e) => e.startsWith('DELETE')), isFalse);
  });

  testWidgets('cancel changes nothing', (t) async {
    final (s, seen, tmp) = await _setup();
    addTearDown(() => tmp.deleteSync(recursive: true));
    await _open(t, s);
    await t.enterText(find.byKey(const Key('server-delete-name')), 'Work');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(seen.any((e) => e.startsWith('DELETE')), isFalse);
    expect(s.spaces.map((e) => e.name), ['Planning', 'Work']);
    expect(tmp.listSync(), isEmpty);
  });

  testWidgets('a server refusal is shown and the Space stays', (t) async {
    final (s, seen, tmp) = await _setup(deleteStatus: 403);
    addTearDown(() => tmp.deleteSync(recursive: true));
    await _open(t, s);
    await t.enterText(find.byKey(const Key('server-delete-name')), 'Work');
    await t.pump();
    await t.tap(find.byKey(const Key('server-delete-go')));
    await t.pumpAndSettle();
    expect(seen.where((e) => e == 'DELETE /dav/c/'), hasLength(1));
    expect(
      find.textContaining('Could not delete on the server'),
      findsOneWidget,
    );
    expect(find.textContaining('403'), findsOneWidget);
    expect(s.spaces.map((e) => e.name), ['Planning', 'Work']);
  });

  testWidgets('skipping the backup shows a warning and writes no files', (
    t,
  ) async {
    final (s, _, tmp) = await _setup();
    addTearDown(() => tmp.deleteSync(recursive: true));
    await _open(t, s);
    await t.tap(find.byKey(const Key('server-delete-backup')));
    await t.pump();
    expect(find.byKey(const Key('server-delete-nobackup')), findsOneWidget);
    await t.enterText(find.byKey(const Key('server-delete-name')), 'Work');
    await t.pump();
    await t.tap(find.byKey(const Key('server-delete-go')));
    await t.pumpAndSettle();
    expect(s.spaces.map((e) => e.name), ['Planning']);
    expect(tmp.listSync(), isEmpty);
  });
}
