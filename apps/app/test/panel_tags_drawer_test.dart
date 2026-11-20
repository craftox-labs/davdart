import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:davdart_app/ui/panel_tags_drawer.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'catalog_helper.dart';
import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

class _Host extends StatefulWidget {
  const _Host({required this.tags, this.initiallyOpen = false, this.log});
  final List<String> tags;
  final bool initiallyOpen;
  final List<String?>? log;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool open = widget.initiallyOpen;
  String? sel;

  @override
  Widget build(BuildContext context) => PanelTagsDrawer(
    body: ListView(
      key: const Key('body'),
      children: [
        for (var i = 0; i < 5; i++) SizedBox(height: 40, child: Text('row $i')),
      ],
    ),
    tags: widget.tags,
    selected: sel,
    onSelect: (v) {
      widget.log?.add(v);
      setState(() => sel = v);
    },
    expanded: open,
    onExpandedChange: (v) => setState(() => open = v),
  );
}

Future<void> _pump(
  WidgetTester t,
  Widget child, {
  Size size = const Size(260, 600),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    FTheme(
      data: buildTheme(Brightness.light, touch: false),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
  await t.pumpAndSettle();
}

/// An app on a catalog with the Planning Space and an empty 'Other' one.
Future<(AppState, String)> _catalogApp(WidgetTester t) async {
  t.view.physicalSize = const Size(1280, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final storage = MemoryStorage();
  final c = catalogWithPlanning(storage, planningSeed: SeedNotes([]));
  final other = c.add('Other').id;
  final s = AppState(c.sourceFor(c.current!), prefs: storage, catalog: c);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return (s, other);
}

void main() {
  group('PanelTagsDrawer', () {
    testWidgets('collapsed: one row, no chips; hidden with no tags', (t) async {
      await _pump(t, const _Host(tags: ['a', 'b']));
      expect(find.text('Tags (2)'), findsOneWidget);
      expect(_k('tag-a'), findsNothing);
      expect(_k('tags-drawer'), findsOneWidget);
      await _pump(t, const _Host(tags: []));
      expect(_k('tags-drawer'), findsNothing);
      expect(find.text('row 0'), findsOneWidget);
    });

    testWidgets('expands upward: top moves up, bottom stays', (t) async {
      await _pump(t, const _Host(tags: ['a', 'b', 'c']));
      final before = t.getRect(_k('tags-drawer'));
      final bodyBefore = t.getRect(_k('body'));
      await t.tap(find.text('Tags (3)'));
      await t.pumpAndSettle();
      final after = t.getRect(_k('tags-drawer'));
      expect(after.bottom, before.bottom);
      expect(after.top, lessThan(before.top));
      expect(t.getRect(_k('body')).height, lessThan(bodyBefore.height));
      expect(_k('tag-a'), findsOneWidget);
      // Pinned to the bottom of the host.
      expect(after.bottom, 600);
      await t.tap(find.text('Tags (3)'));
      await t.pumpAndSettle();
      expect(_k('tag-a'), findsNothing);
      expect(t.getRect(_k('tags-drawer')).top, before.top);
    });

    testWidgets('selecting taps through and a second tap clears', (t) async {
      final log = <String?>[];
      await _pump(
        t,
        _Host(tags: const ['a', 'b'], initiallyOpen: true, log: log),
      );
      await t.tap(_k('tag-b'));
      await t.pumpAndSettle();
      await t.tap(_k('tag-b'));
      await t.pumpAndSettle();
      expect(log, ['b', null]);
    });

    testWidgets('is capped at 40% of the height and scrolls', (t) async {
      final tags = [for (var i = 0; i < 80; i++) 'tag$i'];
      await _pump(t, _Host(tags: tags, initiallyOpen: true));
      final r = t.getRect(_k('tags-chips'));
      expect(r.height, lessThanOrEqualTo(600 * 0.4));
      expect(
        t.getRect(_k('tags-drawer')).height,
        lessThanOrEqualTo(600 * 0.4 + 60),
      );
      expect(_k('tag-tag79').hitTestable(), findsNothing);
      await t.scrollUntilVisible(
        _k('tag-tag79'),
        100,
        scrollable: find.descendant(
          of: _k('tags-chips'),
          matching: find.byType(Scrollable),
        ),
      );
      expect(_k('tag-tag79').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a long tag does not overflow a narrow drawer', (t) async {
      await _pump(
        t,
        _Host(tags: ['x' * 120, 'b'], initiallyOpen: true),
        size: const Size(180, 500),
      );
      expect(t.takeException(), isNull);
      expect(t.getRect(_k('tag-${'x' * 120}')).width, lessThanOrEqualTo(180));
    });
  });

  group('drawer in the panels', () {
    testWidgets('Tasks: filters, hidden without tags, reset on Space switch', (
      t,
    ) async {
      final (s, other) = await _catalogApp(t);
      await t.runAsync(() async {
        await s.addTask('Alpha', tags: ['home']);
        await s.addTask('Beta', tags: ['work']);
        await s.addTask('Gamma');
      });
      s.openTasksPanel();
      await t.pumpAndSettle();
      String uidOf(String n) => s.tasks.firstWhere((k) => k.summary == n).uid;
      expect(_k('tasks-tags-drawer'), findsOneWidget);
      expect(_k('tasks-tag-filter'), findsNothing);
      await t.tap(find.text('Tags (2)'));
      await t.pumpAndSettle();
      await t.tap(_k('tag-work'));
      await t.pumpAndSettle();
      expect(s.taskTagFilter, 'work');
      expect(_k('task-row-${uidOf('Beta')}'), findsOneWidget);
      expect(_k('task-row-${uidOf('Alpha')}'), findsNothing);
      await t.tap(_k('tag-work'));
      await t.pumpAndSettle();
      expect(s.taskTagFilter, isNull);
      expect(_k('task-row-${uidOf('Alpha')}'), findsOneWidget);
      await t.tap(_k('tag-home'));
      await t.pumpAndSettle();
      expect(s.taskTagFilter, 'home');
      await t.runAsync(() => s.switchSpace(other));
      await t.pumpAndSettle();
      expect(s.taskTagFilter, isNull);
      expect(_k('tasks-tags-drawer'), findsNothing);
    });

    testWidgets('Notes: drawer at the panel bottom, hidden without tags', (
      t,
    ) async {
      await pumpTasksApp(
        t,
        notes: [Note(uid: 'n', summary: 'Plain')],
      );
      expect(_k('tags-drawer'), findsNothing);
      await t.pumpWidget(const SizedBox());
      final s = await pumpTasksApp(
        t,
        notes: [
          Note(uid: 'n', summary: 'Tagged', categories: ['red']),
        ],
      );
      expect(_k('tags-drawer'), findsOneWidget);
      expect(t.getRect(_k('tags-drawer')).bottom, greaterThan(850));
      await t.tap(find.text('Tags (1)'));
      await t.pumpAndSettle();
      await t.tap(_k('tag-red'));
      await t.pumpAndSettle();
      expect(s.tag, 'red');
    });

    testWidgets('Tasks: no tags, no drawer', (t) async {
      final s = await pumpTasksApp(t, tasks: [mkTask('a')]);
      s.openTasksPanel();
      await t.pumpAndSettle();
      expect(_k('tasks-tags-drawer'), findsNothing);
    });

    testWidgets('Events: filters the agenda incl. past, reset on switch', (
      t,
    ) async {
      final (s, other) = await _catalogApp(t);
      DateTime at(int d) => DateTime.now().toUtc().add(Duration(days: d));
      await t.runAsync(() async {
        await s.addEvent('Alpha', start: at(0), tags: ['work']);
        await s.addEvent('Beta', start: at(1), tags: ['fun']);
        await s.addEvent('Oldie', start: at(-3), tags: ['fun']);
        await s.addEvent('Oldwork', start: at(-2), tags: ['work']);
        await s.addEvent('Gamma', start: at(2));
      });
      s.setSection(Section.events);
      await t.pumpAndSettle();
      expect(_k('events-tags-drawer'), findsOneWidget);
      await t.tap(find.text('Tags (2)'));
      await t.pumpAndSettle();
      expect(s.eventTagsExpanded, isTrue);
      await t.tap(_k('tag-fun'));
      await t.pumpAndSettle();
      expect(s.eventTagFilter, 'fun');
      Finder inView(String x) =>
          find.descendant(of: _k('events-view'), matching: find.text(x));
      expect(inView('Beta'), findsOneWidget);
      expect(inView('Oldie'), findsOneWidget);
      expect(inView('Alpha'), findsNothing);
      expect(inView('Oldwork'), findsNothing);
      expect(inView('Gamma'), findsNothing);
      await t.tap(_k('tag-fun'));
      await t.pumpAndSettle();
      expect(s.eventTagFilter, isNull);
      expect(inView('Alpha'), findsOneWidget);
      s.setEventTagFilter('work');
      await t.runAsync(() => s.switchSpace(other));
      await t.pumpAndSettle();
      expect(s.eventTagFilter, isNull);
      expect(_k('events-tags-drawer'), findsNothing);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('Events: phone sheet with a long tag does not overflow', (
      t,
    ) async {
      final s = await pumpTasksApp(
        t,
        size: const Size(320, 700),
        events: [
          mkEvent('a', days: 0, tags: ['x' * 80, 'b']),
        ],
      );
      expect(s.section, Section.notes);
      await t.tap(_k('menu'));
      await t.pumpAndSettle();
      await t.tap(_k('menu-filter'));
      await t.pumpAndSettle();
      await t.tap(_k('filter-events'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tags (2)'));
      await t.pumpAndSettle();
      expect(_k('tag-${'x' * 80}'), findsOneWidget);
      expect(t.getRect(_k('events-tags-drawer')).right, lessThanOrEqualTo(320));
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 1));
    });
  });
}
