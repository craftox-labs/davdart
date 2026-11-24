import 'package:davdart/davdart.dart';
import 'package:davdart_app/state/app_state.dart';
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
    expect(find.text('a · b · +1'), findsOneWidget);
    expect(find.text('x · y'), findsOneWidget);
    expect(_k('card-folder-n'), findsOneWidget);
    expect(_k('card-folder-t'), findsOneWidget);
    expect(_k('card-snippet-n'), findsOneWidget);
    expect(_k('card-snippet-t'), findsNothing);
    expect(find.text('Sam'), findsOneWidget);
    expect(_k('card-due-t'), findsOneWidget);
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

  testWidgets('phone: no snippet, tags or folder; title, glyph, due stay', (
    t,
  ) async {
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
  });

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
}
