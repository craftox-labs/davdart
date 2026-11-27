import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

/// A plan item on the board: a `todo` note whose body header carries
/// [itemId] (what the card title is checked against).
Note _plan(String uid, String summary, {String? itemId}) => Note(
  uid: uid,
  summary: summary,
  description: [
    if (itemId != null) 'item_id: $itemId',
    'status: todo',
    '',
    'body',
  ].join('\n'),
  categories: const ['status-todo'],
  lastModified: DateTime.utc(2026, 1, 1),
);

Finder _title(String uid) =>
    find.descendant(of: _k('nav-card-$uid'), matching: find.byType(Text));

List<String> _texts(WidgetTester t, String uid) => [
  for (final e in t.widgetList<Text>(_title(uid)))
    if (e.data != null) e.data!,
];

void main() {
  testWidgets('a "slug: Title" summary shows only the title', (t) async {
    await pumpHomeApp(t, notes: [_plan('slug', 'slug: Title', itemId: 'slug')]);
    expect(_k('nav-card-slug'), findsOneWidget);
    expect(_texts(t, 'slug'), contains('Title'));
    expect(_texts(t, 'slug'), isNot(contains('slug: Title')));
  });

  testWidgets('a summary without the slug prefix is shown whole', (t) async {
    await pumpHomeApp(
      t,
      notes: [_plan('plain', 'A plain title', itemId: 'plain')],
    );
    expect(_texts(t, 'plain'), contains('A plain title'));
  });

  testWidgets('a slug alone falls back to the whole summary', (t) async {
    await pumpHomeApp(t, notes: [_plan('bare', 'bare:', itemId: 'bare')]);
    expect(_texts(t, 'bare'), contains('bare:'));
  });

  testWidgets(
    'only the item id prefix is stripped, not any word before a colon',
    (t) async {
      await pumpHomeApp(
        t,
        notes: [_plan('colon', 'topic: Something', itemId: 'other')],
      );
      expect(_texts(t, 'colon'), contains('topic: Something'));
    },
  );
}
