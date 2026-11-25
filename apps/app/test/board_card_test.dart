import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/chips.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

final _folder = Note(
  uid: 'f',
  summary: 'Projx',
  categories: const ['kind-folder'],
  lastModified: DateTime.utc(2026, 1, 1),
);

Note _note({String body = 'Body text here', List<String> tags = const []}) =>
    Note(
      uid: 'n',
      summary: 'Alpha',
      parentUid: 'f',
      description: 'status: todo\nowner: Sam\n\n$body',
      categories: ['status-todo', ...tags],
      lastModified: DateTime.utc(2026, 1, 2),
    );

Task _task({List<String> tags = const []}) => Task(
  uid: 't',
  summary: 'Fix it',
  parentUid: 'f',
  categories: tags,
  description: 'task body',
  due: const ICalDate('20200101'),
  lastModified: DateTime.utc(2026, 1, 2),
);

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() {
    LocalZone.use(null);
    AppState.debugDefaultFocus = HomeFocus.day;
  });

  Future<AppState> pump(WidgetTester t, {Size? size}) async {
    AppState.debugDefaultFocus = HomeFocus.board;
    return pumpTasksApp(
      t,
      notes: [
        _folder,
        Note(uid: 'k', summary: 'Busy', description: 'status: doing\n\nx'),
        _note(tags: ['a', 'b', 'c']),
      ],
      tasks: [
        _task(tags: ['x', 'y']),
      ],
      size: size ?? const Size(1280, 900),
    );
  }

  testWidgets('wide: tag cap with +N, folder chip, snippet only on notes', (
    t,
  ) async {
    await pump(t);
    expect(find.text('#a #b +1'), findsOneWidget);
    expect(find.text('#x #y'), findsOneWidget);
    expect(_k('card-folder-n'), findsOneWidget);
    expect(_k('card-folder-t'), findsOneWidget);
    expect(_k('card-snippet-n'), findsOneWidget);
    expect(_k('card-snippet-t'), findsNothing);
    expect(_k('card-due-t'), findsOneWidget);
  });

  testWidgets('wide: footer order and shared left edge with the title', (
    t,
  ) async {
    await pump(t);
    double x(Finder f) => t.getTopLeft(f).dx;
    final kind = _k('card-kind-t');
    final due = _k('card-due-t');
    final tags = _k('card-tags-t');
    final folder = _k('card-folder-t');
    expect(x(kind), lessThan(x(due)));
    expect(x(due), lessThan(x(tags)));
    expect(x(tags), lessThan(x(folder)));
    final title = find.descendant(
      of: _k('nav-card-t'),
      matching: find.text('Fix it'),
    );
    expect(x(kind), x(title));
    // the kind glyph is no longer on the title row
    expect(t.getTopLeft(kind).dy, greaterThan(t.getBottomLeft(title).dy));
  });

  testWidgets('each priority has its own colour: red, orange, cool', (
    t,
  ) async {
    AppState.debugDefaultFocus = HomeFocus.board;
    await pumpTasksApp(
      t,
      tasks: [
        mkTask('h', priority: 1),
        mkTask('m', priority: 5),
        mkTask('l', priority: 7),
        mkTask('n'),
      ],
      size: const Size(1280, 900),
    );
    await showTasksBoard(t);
    await t.pumpAndSettle();
    Color col(String uid) => t
        .widget<Icon>(
          find.descendant(
            of: _k('card-priority-$uid'),
            matching: find.byType(Icon),
          ),
        )
        .color!;
    final tokens = Tokens.light;
    expect(col('h'), tokens.error);
    expect(col('m'), tokens.warning);
    expect(col('l'), tokens.priorityLow);
    expect({col('h'), col('m'), col('l')}, hasLength(3));
    // Low must not read as muted text, nor as the doing (green) or done (blue)
    // status colours.
    for (final c in [tokens.muted, tokens.statusDoing, tokens.statusDone]) {
      expect(col('l'), isNot(c));
    }
    expect(find.text('Low'), findsOneWidget);
    expect(_k('card-priority-n'), findsNothing);
  });

  testWidgets('phone: the flag shows for every priority, without its word', (
    t,
  ) async {
    AppState.debugDefaultFocus = HomeFocus.board;
    await pumpTasksApp(
      t,
      tasks: [
        mkTask('h', priority: 1),
        mkTask('m', priority: 5),
        mkTask('l', priority: 7),
      ],
      size: const Size(390, 844),
    );
    if (_k('card-priority-h').evaluate().isEmpty) {
      await t.tap(_k('board-acc-todo-toggle'));
      await t.pumpAndSettle();
    }
    for (final uid in ['h', 'm', 'l']) {
      expect(_k('card-priority-$uid'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('card-priority-$uid'),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    }
    final flag = t.widget<Icon>(
      find.descendant(of: _k('card-priority-h'), matching: find.byType(Icon)),
    );
    expect(flag.color, Tokens.light.error);
    expect(find.text('Medium'), findsNothing);
    expect(find.text('High'), findsNothing);
  });

  testWidgets('doing is green and done is blue on the column dots', (t) async {
    AppState.debugDefaultFocus = HomeFocus.board;
    await pumpTasksApp(
      t,
      notes: [
        Note(
          uid: 'k',
          summary: 'Busy',
          description: 'status: doing\n\nx',
          categories: const ['status-doing'],
        ),
        Note(
          uid: 'd',
          summary: 'Shipped',
          description: 'status: done\n\nx',
          categories: const ['status-done'],
        ),
      ],
      size: const Size(1280, 900),
    );
    Color dot(String label) {
      final header = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      final box = find.descendant(
        of: find.descendant(of: header, matching: find.byType(StatusDot)),
        matching: find.byType(Container),
      );
      return (t.widget<Container>(box.first).decoration! as BoxDecoration)
          .color!;
    }

    expect(dot('DOING'), Tokens.light.statusDoing);
    expect(dot('DONE'), Tokens.light.statusDone);
    expect(Tokens.light.statusDoing, isNot(Tokens.light.statusDone));
  });

  testWidgets('overdue due uses the error colour, a future one does not', (
    t,
  ) async {
    AppState.debugDefaultFocus = HomeFocus.board;
    await pumpTasksApp(
      t,
      tasks: [mkTask('late', days: -3), mkTask('soon', days: 3)],
      size: const Size(1280, 900),
    );
    await showTasksBoard(t);
    await t.pumpAndSettle();
    Color col(String uid) => t
        .widget<Text>(
          find.descendant(of: _k('card-due-$uid'), matching: find.byType(Text)),
        )
        .style!
        .color!;
    expect(col('late'), isNot(col('soon')));
  });

  testWidgets('owner and decided-by are not on cards', (t) async {
    AppState.debugDefaultFocus = HomeFocus.board;
    await pumpTasksApp(
      t,
      notes: [
        Note(
          uid: 'n',
          summary: 'Alpha',
          description: 'status: todo\nowner: Sam\ndecided_by: Kim\n\nbody',
          categories: const ['status-todo'],
          lastModified: DateTime.utc(2026, 1, 2),
        ),
      ],
      size: const Size(1280, 900),
    );
    expect(_k('nav-card-n'), findsOneWidget);
    final card = _k('nav-card-n');
    for (final w in ['Sam', 'Kim']) {
      expect(
        find.descendant(of: card, matching: find.textContaining(w)),
        findsNothing,
      );
    }
  });

  testWidgets('folder chip is gone when the board is scoped to a folder', (
    t,
  ) async {
    final s = await pump(t);
    s.openFolder('f');
    await t.pumpAndSettle();
    expect(_k('card-kind-n'), findsOneWidget);
    expect(_k('card-folder-n'), findsNothing);
    expect(_k('card-folder-t'), findsNothing);
  });

  testWidgets(
    'phone: no snippet, tag names or folder; kind, due, tag count stay',
    (t) async {
      await pump(t, size: const Size(390, 844));
      for (final c in ['todo', 'backlog']) {
        final h = _k('board-acc-$c-toggle');
        if (h.evaluate().isNotEmpty && _k('card-kind-n').evaluate().isEmpty) {
          await t.tap(h);
          await t.pumpAndSettle();
        }
      }
      expect(_k('card-kind-n'), findsOneWidget);
      expect(_k('card-snippet-n'), findsNothing);
      expect(_k('card-tags-n'), findsNothing);
      expect(_k('card-folder-n'), findsNothing);
      expect(find.text('Sam'), findsNothing);
      expect(_k('card-due-t'), findsOneWidget);
      expect(_k('card-tag-count-n'), findsOneWidget);
      expect(t.widget<Text>(_k('card-tag-count-n')).data, '3');
    },
  );

  testWidgets('phone: long-press drag onto another section changes status', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final s = await pump(t, size: const Size(390, 844));
    if (_k('card-kind-n').evaluate().isEmpty) {
      await t.tap(_k('board-acc-todo-toggle'));
      await t.pumpAndSettle();
    }
    final from = t.getCenter(_k('card-kind-n'));
    final to = t.getCenter(_k('board-acc-doing-toggle'));
    final g = await t.startGesture(from);
    await t.pump(const Duration(milliseconds: 700));
    await g.moveTo(to);
    await t.pump();
    await g.moveTo(to + const Offset(0, 1));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    expect(PlanItem.fromNote(s.findItem('n') as Note).status, 'doing');
  });

  testWidgets('phone: a held card drags, no menu sheet; drop on a card ranks', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    AppState.debugDefaultFocus = HomeFocus.board;
    final s = await pumpTasksApp(
      t,
      notes: [
        Note(
          uid: 'a',
          summary: 'Aaa',
          description: 'status: todo\n\nx',
          lastModified: DateTime.utc(2026, 1, 1),
        ),
        Note(
          uid: 'b',
          summary: 'Bbb',
          description: 'status: todo\n\nx',
          lastModified: DateTime.utc(2026, 1, 2),
        ),
      ],
      size: const Size(390, 844),
    );
    if (_k('card-kind-a').evaluate().isEmpty) {
      await t.tap(_k('board-acc-todo-toggle'));
      await t.pumpAndSettle();
    }
    final from = t.getCenter(_k('card-kind-a'));
    final bRect = t.getRect(_k('nav-card-b'));
    final g = await t.startGesture(from);
    await t.pump(const Duration(milliseconds: 700));
    expect(_k('menu-sheet'), findsNothing);
    final to = Offset(bRect.center.dx, bRect.bottom - 3);
    await g.moveTo(to);
    await t.pump();
    await g.moveTo(to + const Offset(0, 1));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    final a = s.findItem('a') as Note;
    final b = s.findItem('b') as Note;
    expect(a.rank, isNotNull);
    expect(b.rank == null || a.rank! > b.rank!, isTrue);
  });
}
