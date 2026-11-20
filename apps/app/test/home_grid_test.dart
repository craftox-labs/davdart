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
}) async {
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

  testWidgets('Today panels line up with two columns each', (t) async {
    await _pump(t, _four, w: 1700);
    final cols = _cols(t);
    final doing = _r(t, 'home-today-doing');
    final recent = _r(t, 'home-today-tasks');
    expect(doing.left, closeTo(cols[0].left, 0.5));
    expect(doing.right, closeTo(cols[1].right, 0.5));
    expect(recent.left, closeTo(cols[2].left, 0.5));
    expect(recent.right, closeTo(cols[3].right, 0.5));
    expect(recent.left - doing.right, closeTo(_t.space.lg, 0.5));
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

  testWidgets('Board collapses, keeps heading, persists', (t) async {
    final prefs = MemoryStorage();
    await _pump(t, _four, prefs: prefs);
    expect(_k('board-drop-todo'), findsOneWidget);
    await t.tap(_k('home-board-toggle'));
    await t.pumpAndSettle();
    expect(_k('board-drop-todo'), findsNothing);
    expect(_k('home-board-toggle'), findsOneWidget);
    expect(prefs.read('davdart.home.board.collapsed.v1'), 'true');
    await _pump(t, _four, prefs: prefs);
    expect(_k('board-drop-todo'), findsNothing);
    await t.tap(_k('home-board-toggle'));
    await t.pumpAndSettle();
    expect(_k('board-drop-todo'), findsOneWidget);
    expect(prefs.read('davdart.home.board.collapsed.v1'), isNull);
  });

  testWidgets('each Today panel collapses on its own and persists', (t) async {
    final prefs = MemoryStorage();
    await _pump(t, _four, prefs: prefs);
    await t.tap(_k('home-today-doing-toggle'));
    await t.pumpAndSettle();
    expect(_k('home-today-doing-n2'), findsNothing);
    expect(_k('home-today-tasks'), findsOneWidget);
    expect(prefs.read('davdart.home.today.doing.collapsed.v1'), 'true');
    await _pump(t, _four, prefs: prefs);
    expect(_k('home-today-doing-n2'), findsNothing);
    expect(_k('home-today-doing-toggle'), findsOneWidget);
  });

  testWidgets('Home with no Today rows still has the board', (t) async {
    await _pump(t, []);
    // No notes in progress: only the Tasks panel (quick add) is left.
    expect(_k('home-today-doing'), findsNothing);
    expect(_k('home-today-tasks'), findsOneWidget);
    expect(_k('home-board-toggle'), findsOneWidget);
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
