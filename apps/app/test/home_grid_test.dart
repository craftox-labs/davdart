import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/collapsible_section.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

class _Seed implements NoteSource {
  _Seed(this.notes);
  final List<Note> notes;
  @override
  Future<List<Note>> load() async => notes;
}

List<Note> _notes(List<String> statuses) => [
  for (var i = 0; i < statuses.length; i++)
    Note(
      uid: 'n$i',
      summary: 'Note $i',
      description: 'status: ${statuses[i]}\nbody',
      categories: ['status-${statuses[i]}'],
      lastModified: DateTime.now().toUtc().subtract(Duration(hours: i + 1)),
    ),
];

const _four = ['backlog', 'todo', 'doing', 'done'];
final _t = Tokens.light;

Future<AppState> _pump(
  WidgetTester t,
  List<String> statuses, {
  double w = 1280,
  MemoryStorage? prefs,
  bool board = true,
}) async {
  AppState.debugDefaultFocus = board ? HomeFocus.board : HomeFocus.day;
  t.view.physicalSize = Size(w, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s = AppState(
    SpaceNoteSource(space, seed: _Seed(_notes(statuses))),
    prefs: prefs ?? MemoryStorage(),
  );
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

Finder _k(String k) => find.byKey(Key(k));
Rect _r(WidgetTester t, String k) => t.getRect(_k(k));

List<Rect> _cols(WidgetTester t, [List<String> names = _four]) => [
  for (final n in names) _r(t, 'board-drop-$n'),
];

void main() {
  tearDown(() => AppState.debugDefaultFocus = HomeFocus.day);
  testWidgets('board columns fill the content width at 1280', (t) async {
    const three = ['backlog', 'todo', 'doing'];
    await _pump(t, three);
    final cols = _cols(t, three);
    final gap = _t.space.lg;
    final cap = t.getRect(find.byKey(const Key('content-cap')).first);
    expect(cols.first.left, cap.left + gap);
    final sum = cols.fold<double>(0, (a, r) => a + r.width) + 2 * gap;
    expect(sum, closeTo(cap.width - 2 * gap, 1));
    expect(cols.last.right, closeTo(cap.right - gap, 1));
    expect(cols[0].width, greaterThan(_t.sizes.boardColumn));
    for (var i = 1; i < 3; i++) {
      expect(cols[i].left - cols[i - 1].right, closeTo(gap, 0.5));
      expect(cols[i].width, closeTo(cols[0].width, 0.5));
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('Events above Tasks, same width, beside the calendar', (t) async {
    await _pump(t, _four, w: 1700, board: false);
    final cal = _r(t, 'home-calendar');
    final tasks = _r(t, 'home-today-tasks');
    final events = _r(t, 'home-today-events');
    expect(tasks.left, greaterThan(cal.right));
    expect(tasks.left, closeTo(events.left, 0.5));
    expect(tasks.width, closeTo(events.width, 0.5));
    // Events above Tasks, a space.lg gap between the sections' blocks.
    expect(tasks.top, greaterThan(events.bottom));
  });

  testWidgets('falls back to scrolling below the minimum width', (t) async {
    await _pump(t, _four);
    expect(_r(t, 'board-drop-backlog').width, _t.sizes.boardColumn);
    expect(
      _r(t, 'board-drop-done').right,
      greaterThan(t.getSize(find.byType(FScaffold)).width),
    );
    expect(find.byType(ListView), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('grid stops growing at the max width, left-aligned', (t) async {
    await _pump(t, _four, w: 4000);
    final cap = t.getRect(find.byKey(const Key('content-cap')).first);
    expect(cap.width, _t.sizes.contentMax);
    final cols = _cols(t);
    expect(cols.last.right, closeTo(cap.right - _t.space.lg, 1));
    expect(cols.first.left, cap.left + _t.space.lg);
    final main = t.getSize(find.byType(FScaffold)).width;
    expect(cap.right < main, isTrue);
  });

  testWidgets('Board has no overall header; a stale collapse pref is cleared', (
    t,
  ) async {
    final prefs = MemoryStorage()
      ..write('davdart.home.board.collapsed.v1', 'true')
      ..write('davdart.home.today.collapsed.v1', 'true');
    await _pump(t, _four, prefs: prefs);
    expect(_k('home-board-toggle'), findsNothing);
    expect(_k('board-drop-todo'), findsOneWidget);
    expect(prefs.read('davdart.home.board.collapsed.v1'), isNull);
    expect(prefs.read('davdart.home.today.collapsed.v1'), isNull);
  });

  for (final w in [320.0, 480.0, 880.0, 1280.0, 1911.0]) {
    testWidgets('no overflow at $w', (t) async {
      await _pump(t, _four, w: w);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('CollapsibleSection toggles, counts, persists', (t) async {
    final prefs = MemoryStorage();
    Widget build() => FTheme(
      data: buildTheme(Brightness.light, touch: false, tokens: _t),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: TokensScope(
          tokens: _t,
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                Flexible(
                  child: CollapsibleSection(
                    id: 'x',
                    title: 'Things',
                    count: 3,
                    prefs: prefs,
                    prefKey: 'k',
                    fill: true,
                    child: const Text('body', key: Key('body')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpWidget(build());
    expect(find.text('THINGS'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(_k('body'), findsOneWidget);
    await t.tap(_k('x-toggle'));
    await t.pump();
    expect(_k('body'), findsNothing);
    expect(prefs.read('k'), 'true');
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(build());
    expect(_k('body'), findsNothing);
    await t.tap(_k('x-toggle'));
    await t.pump();
    expect(_k('body'), findsOneWidget);
    expect(prefs.read('k'), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
}
