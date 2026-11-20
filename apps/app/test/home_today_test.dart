import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/home_today.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.now().toUtc();

class _Seed implements NoteSource {
  _Seed(this.notes);
  final List<Note> notes;
  @override
  Future<List<Note>> load() async => notes;
}

List<Note> _notes() => [
  Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
  Note(
    uid: 'a',
    summary: 'Alpha',
    parentUid: 'f',
    description: 'status: doing\nbody',
    categories: ['status-doing'],
    lastModified: _now.subtract(const Duration(hours: 2)),
  ),
  Note(
    uid: 'b',
    summary: 'Beta',
    description: 'status: backlog\nbody',
    categories: ['status-backlog'],
    lastModified: _now.subtract(const Duration(days: 1, hours: 1)),
  ),
];

Future<AppState> _pump(
  WidgetTester t,
  List<Note> notes, {
  Size size = const Size(1280, 900),
  MemoryStorage? prefs,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s = AppState(
    SpaceNoteSource(space, seed: _Seed(notes)),
    prefs: prefs ?? MemoryStorage(),
  );
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

Finder _k(String k) => find.byKey(Key(k));

void main() {
  test('shortAge', () {
    final n = DateTime.utc(2026, 1, 10, 12);
    expect(shortAge(n.subtract(const Duration(hours: 2)), n), '2h');
    expect(shortAge(n.subtract(const Duration(hours: 30)), n), 'yesterday');
    expect(shortAge(n.subtract(const Duration(minutes: 5)), n), '5m');
  });

  testWidgets('shows Doing and Recently changed rows', (t) async {
    await _pump(t, _notes());
    expect(_k('home-today'), findsOneWidget);
    expect(_k('home-today-doing-a'), findsOneWidget);
    expect(_k('home-today-doing-b'), findsNothing);
    expect(_k('home-today-recently-changed-a'), findsOneWidget);
    expect(_k('home-today-recently-changed-b'), findsOneWidget);
    expect(_k('home-today-recently-changed-f'), findsNothing);
    // The store stamps notes on seeding, so only the fresh age shows here.
    expect(find.text('now'), findsWidgets);
  });

  testWidgets('hidden when there is nothing', (t) async {
    await _pump(t, [
      Note(uid: 'f', summary: 'Plans', categories: ['kind-folder']),
    ]);
    expect(_k('home-today'), findsNothing);
  });

  testWidgets('Doing panel hidden when nothing is doing', (t) async {
    await _pump(t, [_notes()[2]]);
    expect(_k('home-today-doing'), findsNothing);
    expect(_k('home-today-recently-changed'), findsOneWidget);
  });

  testWidgets('collapse persists', (t) async {
    final prefs = MemoryStorage();
    await _pump(t, _notes(), prefs: prefs);
    await t.tap(_k('home-today-toggle'));
    await t.pumpAndSettle();
    expect(_k('home-today-doing'), findsNothing);
    expect(_k('home-today'), findsOneWidget);
    expect(prefs.read('davdart.home.today.collapsed.v1'), 'true');
    await _pump(t, _notes(), prefs: prefs);
    expect(_k('home-today-doing'), findsNothing);
    expect(_k('home-today-toggle'), findsOneWidget);
  });

  testWidgets('respects folder scope', (t) async {
    final s = await _pump(t, _notes());
    s.openFolder('f');
    await t.pumpAndSettle();
    expect(_k('home-today-recently-changed-a'), findsOneWidget);
    expect(_k('home-today-recently-changed-b'), findsNothing);
  });

  testWidgets('click opens the note', (t) async {
    final s = await _pump(t, _notes());
    await t.tap(_k('home-today-doing-a'));
    await t.pumpAndSettle();
    expect(s.peekUid ?? s.mainNoteUid, 'a');
  });

  testWidgets('not shown on a saved-view tab', (t) async {
    final s = await _pump(t, _notes());
    await t.runAsync(() => s.saveView('V'));
    s.applyView(s.savedViews.single);
    await t.pumpAndSettle();
    expect(s.activeTab, isNotNull);
    expect(_k('home-today'), findsNothing);
  });

  for (final w in [320.0, 880.0, 1280.0]) {
    testWidgets('no overflow at $w', (t) async {
      await _pump(t, _notes(), size: Size(w, 900));
      expect(_k('home-today'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
