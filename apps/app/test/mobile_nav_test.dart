import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/section_registry.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

const _phones = [Size(320, 568), Size(360, 640)];

/// A state whose Space cannot hold tasks.
class _NoTasks extends FlagState {
  _NoTasks(super.source);
  @override
  bool get supportsTasks => false;
}

/// An org-style Space: no notes (tasks and events only).
class _NoNotes extends FlagState {
  _NoNotes(super.source);
  @override
  bool get supportsNotes => false;
}

Finder _k(String k) => find.byKey(Key(k));
String _text(WidgetTester t, String k) => t.widget<Text>(_k(k)).data!;

void _noError(WidgetTester t) {
  final ex = t.takeException();
  expect(ex, isNull, reason: ex is FlutterError ? ex.toStringDeep() : '$ex');
}

Note _note(String uid, String title) => Note(
  uid: uid,
  summary: title,
  description: 'Body of $title',
  lastModified: DateTime.now().toUtc(),
);

Future<void> _openMenu(WidgetTester t) async {
  await t.tap(_k('menu'));
  await t.pumpAndSettle();
}

/// Picks [name] on the menu's rail strip, opening the menu first if need be.
Future<void> _section(WidgetTester t, String name) async {
  if (_k('rail-$name').evaluate().isEmpty) await _openMenu(t);
  await t.tap(_k('rail-$name'));
  await t.pumpAndSettle();
}

Future<AppState> _pumpState(
  WidgetTester t,
  AppState Function(NoteSource src) make,
  Size size,
) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s = make(SpaceNoteSource(space, seed: SeedNotes(const [])));
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

/// The border colour of a grid card.
Color _border(WidgetTester t, String key) {
  final c = t.widget<Container>(
    find.descendant(of: _k(key), matching: find.byType(Container)).first,
  );
  return (c.decoration as BoxDecoration).border!.top.color;
}

void main() {
  for (final size in _phones) {
    group('narrow at $size', () {
      testWidgets(
        'the bar has Back, Home, Search, counter at 44dp; + floats above',
        (t) async {
          await pumpTasksApp(t, size: size);
          expect(_k('mobile-bar'), findsOneWidget);
          for (final k in ['bar-back', 'bar-home', 'bar-search', 'bar-count']) {
            expect(_k(k), findsOneWidget);
            expect(t.getRect(_k(k)).height, greaterThanOrEqualTo(44));
          }
          // Order: Menu, Back, Home, Search, counter; the logo tops the screen.
          final order = [
            'menu',
            'bar-back',
            'bar-home',
            'bar-search',
            'bar-count',
          ];
          final xs = [for (final k in order) t.getRect(_k(k)).left];
          expect(xs, [...xs]..sort());
          expect(_k('top-logo'), findsOneWidget);
          expect(_k('bar-count-box'), findsOneWidget);
          // The + is a floating button above the bar, at its right end.
          expect(
            t.getRect(_k('bar-add')).bottom,
            lessThanOrEqualTo(t.getRect(_k('mobile-bar')).top),
          );
          expect(t.getRect(_k('bar-add')).right, greaterThan(size.width / 2));
          // No pill: the bar has a top rule only.
          final deco =
              t.widget<DecoratedBox>(_k('mobile-bar')).decoration
                  as BoxDecoration;
          expect(deco.borderRadius, isNull);
          expect(deco.color, isNull);
          // The old chrome is gone.
          expect(_k('bottom-nav'), findsNothing);
          expect(_k('fab-add'), findsNothing);
          expect(_k('peek-sheet'), findsNothing);
          // Space chip on Home, centred in the top bar.
          expect(_k('space-chip'), findsOneWidget);
          _noError(t);
        },
      );

      testWidgets(
        'side menu: button, rail strip beside the panel, gear, logo',
        (t) async {
          final s = await pumpTasksApp(
            t,
            notes: [_note('n1', 'Alpha')],
            tasks: [mkTask('k1', summary: 'Pay rent')],
            size: size,
          );
          await _openMenu(t);
          expect(_k('side-menu'), findsOneWidget);
          expect(_k('space-chip'), findsWidgets);
          expect(find.text('Alpha'), findsWidgets);
          // The rail strip is a column on the left edge, one tap per
          // section; no Back of its own (the bar's Menu closes it).
          expect(_k('side-menu-back'), findsNothing);
          final strip = t.getRect(_k('icon-rail'));
          expect(strip.left, 0);
          expect(strip.width, lessThan(60));
          expect(
            t.getRect(_k('rail-notes')).left,
            greaterThanOrEqualTo(strip.left),
          );
          expect(
            t.getRect(_k('rail-notes')).right,
            lessThanOrEqualTo(strip.right),
          );
          expect(_k('menu-fold'), findsOneWidget);
          // The fold control sits inline with + and new-folder; no Space
          // chip heads the menu.
          expect(
            t.getRect(_k('menu-fold')).center.dy,
            closeTo(t.getRect(_k('new-note')).center.dy, 1),
          );
          expect(
            find.descendant(of: _k('side-menu'), matching: _k('space-chip')),
            findsNothing,
          );
          await _section(t, 'tasks');
          expect(s.section, Section.tasks);
          expect(_k('menu-fold'), findsNothing);
          expect(_k('tasks-view'), findsOneWidget);
          await _section(t, 'events');
          expect(_k('events-panel'), findsOneWidget);
          // Account and Settings are on the strip, below the sections.
          await t.tap(_k('rail-settings'));
          await t.pumpAndSettle();
          expect(s.section, Section.settings);
          expect(_k('side-menu'), findsOneWidget);
          // The bar stays; its Menu toggle is still there and closes the
          // menu; the top bar keeps the plain logo throughout.
          expect(_k('mobile-bar'), findsOneWidget);
          expect(_k('menu'), findsOneWidget);
          expect(_k('top-logo'), findsOneWidget);
          await t.tap(_k('menu'));
          await t.pumpAndSettle();
          expect(_k('side-menu'), findsNothing);
          expect(_k('menu'), findsOneWidget);
          _noError(t);
        },
      );

      testWidgets('a left-edge swipe opens the side menu', (t) async {
        await pumpTasksApp(t, size: size);
        await t.dragFrom(Offset(4, size.height / 2), const Offset(120, 0));
        await t.pumpAndSettle();
        expect(_k('side-menu'), findsOneWidget);
      });

      testWidgets('a short drag from 28dp in opens the menu', (t) async {
        await pumpTasksApp(t, size: size);
        await t.dragFrom(Offset(28, size.height / 2), const Offset(40, 0));
        await t.pumpAndSettle();
        expect(_k('side-menu'), findsOneWidget);
        _noError(t);
      });

      testWidgets('a vertical drag in the edge strip does not open the menu', (
        t,
      ) async {
        await pumpTasksApp(t, size: size);
        await t.dragFrom(Offset(4, size.height / 2), const Offset(0, -120));
        await t.pumpAndSettle();
        expect(_k('side-menu'), findsNothing);
        _noError(t);
      });

      testWidgets('the + hides on an open item and while the keyboard is up', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          notes: [_note('n1', 'Alpha')],
          size: size,
        );
        expect(_k('bar-add'), findsOneWidget);
        await s.openNote('n1');
        await t.pumpAndSettle();
        expect(_k('main-note'), findsOneWidget);
        expect(_k('bar-add'), findsNothing);
        await s.activateTab(null);
        await t.pumpAndSettle();
        expect(_k('bar-add'), findsOneWidget);
        t.view.viewInsets = const FakeViewPadding(bottom: 250);
        addTearDown(t.view.resetViewInsets);
        await t.pumpAndSettle();
        expect(_k('bar-add'), findsNothing);
      });

      testWidgets('the closed bar names the page; the menu names the Space', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          notes: [_note('n1', 'Alpha')],
          size: size,
        );
        expect(_text(t, 'top-title'), 'Home');
        await s.openNote('n1');
        await t.pumpAndSettle();
        expect(_text(t, 'top-title'), 'Alpha');
        // The menu keeps its Space heading while it is open.
        await _openMenu(t);
        expect(_text(t, 'scope-pill-space'), 'Spaces');
        // Back Home updates the closed bar again.
        await t.tap(_k('menu'));
        await t.pumpAndSettle();
        await t.tap(_k('bar-home'));
        await t.pumpAndSettle();
        expect(_text(t, 'top-title'), 'Home');
        _noError(t);
      });

      testWidgets('the Space chip is a joined tab on the top bar edge', (
        t,
      ) async {
        await pumpTasksApp(t, size: size);
        final chip = find.descendant(
          of: _k('space-chip'),
          matching: _k('joined-tab'),
        );
        expect(chip, findsOneWidget);
        // Flush on the bottom edge of the top bar (over its hairline).
        final bar = t.getRect(_k('top-bar'));
        expect(t.getRect(chip).bottom, closeTo(bar.bottom + 1, 1.5));
        expect(t.getRect(_k('top-logo')).right, lessThan(t.getRect(chip).left));
        // The tab takes the full header height and is its own hit box.
        final box = t.getRect(_k('space-chip'));
        expect(box.height, closeTo(bar.height, 1.5));
        // Tapping it opens the Projects panel: the scope picker.
        await t.tapAt(Offset(box.center.dx, box.top + 3));
        await t.pumpAndSettle();
        expect(_k('side-menu'), findsOneWidget);
        expect(_k('projects-view'), findsOneWidget);
        _noError(t);
      });

      testWidgets('the page title is on the logo centre line', (t) async {
        await pumpTasksApp(t, size: size);
        final logo = t.getRect(_k('top-logo'));
        // The same pill as the menu: its Space icon and one label line.
        final icon = find.descendant(
          of: _k('space-chip'),
          matching: find.byType(Icon),
        );
        expect(icon, findsOneWidget);
        expect(t.getSize(icon).height, Tokens.light.icons.lg);
        final label = find.descendant(
          of: _k('space-chip'),
          matching: find.byType(Text),
        );
        expect(t.getRect(label).center.dy, closeTo(logo.center.dy, 1.5));
        // The sync button stays on the right.
        expect(
          t.getRect(find.byIcon(FLucideIcons.refreshCw)).left,
          greaterThan(t.getRect(_k('space-chip')).right),
        );
        _noError(t);
      });

      testWidgets('Home, project and menu pills share one structure', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          notes: [
            Note(
              uid: 'c',
              summary: 'Projects',
              categories: const [folderTag, projectsTag],
            ),
            Note(
              uid: 'p',
              summary: 'Alpha',
              parentUid: 'c',
              categories: const [folderTag],
            ),
          ],
          size: size,
        );
        Rect box() => t.getRect(_k('space-chip'));
        Finder icon() =>
            find.descendant(of: _k('space-chip'), matching: find.byType(Icon));
        IconData iconOf() => t.widget<Icon>(icon()).icon!;
        final homeBox = box();
        final homeStyle = t.widget<Text>(_k('top-title')).style;
        final homeIconSize = t.getSize(icon());
        // Home: the Home tab's icon.
        expect(iconOf(), FLucideIcons.house);

        // A project page: the project tab's icon.
        s.openProjectTab('p');
        await t.pumpAndSettle();
        expect(_text(t, 'top-title'), 'Alpha');
        expect(iconOf(), FLucideIcons.folderKanban);
        expect(box().height, homeBox.height);
        expect(box().center.dx, closeTo(homeBox.center.dx, 0.5));
        expect(t.getSize(icon()), homeIconSize);
        expect(t.widget<Text>(_k('top-title')).style, homeStyle);

        // Menu open: the Space icon and name, same pill.
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        expect(_k('side-menu'), findsOneWidget);
        expect(_text(t, 'scope-pill-space'), 'Spaces');
        expect(iconOf(), spacesIcon);
        expect(box().height, homeBox.height);
        expect(t.getSize(icon()), homeIconSize);
        expect(t.widget<Text>(_k('scope-pill-space')).style, homeStyle);
        _noError(t);
      });

      testWidgets('the top bar, chip and sync show on an open item too', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          notes: [_note('n1', 'Alpha')],
          tasks: [mkTask('k1', summary: 'Pay rent')],
          size: size,
        );
        for (final uid in ['n1', 'k1']) {
          await s.openNote(uid);
          await t.pumpAndSettle();
          expect(s.activeTab, isNotNull);
          expect(_k('top-bar'), findsOneWidget, reason: uid);
          expect(_k('space-chip'), findsOneWidget, reason: uid);
          expect(find.byIcon(FLucideIcons.refreshCw), findsOneWidget);
          // Tapping the chip still opens the scope picker.
          await t.tap(_k('space-chip'));
          await t.pumpAndSettle();
          expect(_k('projects-view'), findsOneWidget);
          expect(await t.binding.handlePopRoute(), isTrue);
          await t.pumpAndSettle();
        }
        _noError(t);
      });

      testWidgets('the strip ends with Settings below a gap', (t) async {
        final s = await pumpTasksApp(t, size: size);
        await _openMenu(t);
        // The sections in rail order, then Settings (no sign-in here).
        final ys = [
          for (final k in [
            'rail-home',
            'rail-notes',
            'rail-tasks',
            'rail-events',
            'rail-search',
            'rail-views',
            'rail-spaces',
            'rail-settings',
          ])
            t.getRect(_k(k)).top,
        ];
        expect(ys, [...ys]..sort());
        // Set apart: bigger gaps between the groups (the lists, the tools)
        // than between two items of one group.
        final step = ys[1] - ys[0];
        expect(ys[4] - ys[3], greaterThan(step)); // lists -> tools
        expect(ys[5] - ys[4], step); // within the tools
        // The strip is 44dp targets.
        expect(t.getRect(_k('rail-notes')).height, 44);
        // Spaces is a section of its own, like the others (one fixed source
        // here: nothing to switch to, so no row and no manage actions).
        await t.tap(_k('rail-spaces'));
        await t.pumpAndSettle();
        expect(find.text('One fixed notes source'), findsOneWidget);
        expect(find.text('MANAGE'), findsNothing);
        await t.tap(_k('rail-settings'));
        await t.pumpAndSettle();
        expect(s.section, Section.settings);
        expect(_k('side-menu'), findsOneWidget);
        // The chip's picker shows the Projects panel, not the strip.
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        expect(_k('projects-view'), findsOneWidget);
        expect(_k('rail-settings'), findsOneWidget);
        _noError(t);
      });

      testWidgets(
        'a stored section the Space cannot hold marks the one shown',
        (t) async {
          final s = await _pumpState(t, (src) => _NoNotes(src), size);
          // A restored section the Space cannot hold (Notes here): the panel
          // shows another, and the strip marks that one.
          s.section = Section.notes;
          await t.pumpAndSettle();
          await _openMenu(t);
          expect(_k('rail-notes'), findsNothing);
          expect(
            find.descendant(of: _k('rail-tasks'), matching: _k('rail-tab')),
            findsOneWidget,
          );
          _noError(t);
        },
      );

      testWidgets('Search on the strip focuses the field', (t) async {
        final s = await pumpTasksApp(t, size: size);
        await _openMenu(t);
        await t.tap(_k('rail-search'));
        await t.pumpAndSettle();
        expect(s.section, Section.search);
        expect(s.nav.searchNode.hasFocus, isTrue);
        _noError(t);
      });

      testWidgets('system Back closes the menu', (t) async {
        await pumpTasksApp(t, size: size);
        await _openMenu(t);
        expect(await t.binding.handlePopRoute(), isTrue);
        await t.pumpAndSettle();
        expect(_k('side-menu'), findsNothing);
        _noError(t);
      });

      testWidgets('Search keeps its field pinned when the list scrolls', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          notes: [for (var i = 0; i < 30; i++) _note('n$i', 'Alpha $i')],
          size: size,
        );
        await t.tap(_k('bar-search'));
        await t.pumpAndSettle();
        expect(s.section, Section.search);
        final top = t.getRect(_k('search-all-field')).top;
        await t.enterText(_k('search-all-field'), 'Alpha');
        await t.pumpAndSettle();
        await t.drag(find.byType(ListView).last, const Offset(0, -400));
        await t.pumpAndSettle();
        expect(t.getRect(_k('search-all-field')).top, top);
        // With the keyboard up (shorter body) the field is still on screen.
        t.view.viewInsets = FakeViewPadding(bottom: size.height * 0.4);
        addTearDown(t.view.resetViewInsets);
        await t.pumpAndSettle();
        expect(t.getRect(_k('search-all-field')).top, greaterThanOrEqualTo(0));
        // ... above the keyboard, with the results list taking what is left.
        final field = t.getRect(_k('search-all-field'));
        expect(field.bottom, lessThan(size.height * 0.6));
        expect(t.getRect(find.byType(ListView).last).height, greaterThan(40));
        _noError(t);
      });

      testWidgets('the covered page is out of focus and semantics', (t) async {
        await pumpTasksApp(t, size: size);
        await _openMenu(t);
        expect(
          find
              .byType(ExcludeSemantics)
              .evaluate()
              .any((e) => (e.widget as ExcludeSemantics).excluding),
          isTrue,
        );
        _noError(t);
      });

      testWidgets('a task swipe starting inside the row completes it', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          tasks: [mkTask('k1', summary: 'Pay rent')],
          size: size,
        );
        await _openMenu(t);
        await _section(t, 'tasks');
        final row = t.getRect(_k('task-row-k1'));
        await t.dragFrom(
          Offset(row.left + 4, row.center.dy),
          const Offset(220, 0),
        );
        await t.pumpAndSettle();
        expect(s.taskById('k1')!.isClosed, isTrue);
        _noError(t);
      });

      testWidgets('+ menu follows the filter and the Space flags', (t) async {
        await pumpTasksApp(t, size: size);
        await t.tap(_k('bar-add'));
        await t.pumpAndSettle();
        expect(_k('add-note'), findsOneWidget);
        expect(_k('add-task'), findsOneWidget);
        expect(_k('add-event'), findsOneWidget);
        // Notes is the default filter, so it comes first.
        expect(
          t.getTopLeft(_k('add-note')).dy,
          lessThan(t.getTopLeft(_k('add-task')).dy),
        );
        await t.tap(_k('add-task'));
        await t.pumpAndSettle();
        await t.enterText(_k('new-task-title'), 'Buy milk');
        await t.tap(_k('new-task-add'));
        await t.pumpAndSettle();
        expect(_k('new-task-title'), findsNothing);
        expect(_k('menu'), findsOneWidget);
        _noError(t);

        // With the Tasks filter, task comes first.
        await _openMenu(t);
        await _section(t, 'tasks');
        await t.tap(_k('menu'));
        await t.pumpAndSettle();
        await t.tap(_k('bar-add'));
        await t.pumpAndSettle();
        expect(
          t.getTopLeft(_k('add-task')).dy,
          lessThan(t.getTopLeft(_k('add-note')).dy),
        );
        _noError(t);
      });

      testWidgets('read-only tasks and events have no + entries', (t) async {
        await pumpTasksApp(t, size: size, readOnly: true);
        await t.tap(_k('bar-add'), warnIfMissed: false);
        await t.pumpAndSettle();
        // Tasks and events are read-only here; notes are not.
        expect(_k('add-task'), findsNothing);
        expect(_k('add-event'), findsNothing);
        _noError(t);
      });

      testWidgets('unsupported sections: no tasks entry or filter', (t) async {
        final s = await _pumpState(t, (src) => _NoTasks(src), size);
        await t.tap(_k('bar-add'));
        await t.pumpAndSettle();
        expect(_k('add-task'), findsNothing);
        expect(_k('add-note'), findsOneWidget);
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();
        await _openMenu(t);
        expect(_k('rail-tasks'), findsNothing);
        expect(_k('rail-notes'), findsOneWidget);
        expect(s.supportsTasks, isFalse);
        _noError(t);
      });

      testWidgets('org-style Space (no notes) shows Tasks and Events', (
        t,
      ) async {
        final s = await _pumpState(t, (src) => _NoNotes(src), size);
        await t.tap(_k('bar-add'));
        await t.pumpAndSettle();
        expect(_k('add-note'), findsNothing);
        expect(_k('add-task'), findsOneWidget);
        expect(_k('add-event'), findsOneWidget);
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();
        await _openMenu(t);
        // The strip shows only the sections the Space holds.
        expect(s.section, isNot(Section.notes));
        expect(_k('rail-notes'), findsNothing);
        expect(_k('rail-tasks'), findsOneWidget);
        expect(_k('rail-events'), findsOneWidget);
        _noError(t);
      });

      testWidgets('open-items grid: cards, close, Done, last goes Home', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          notes: [_note('n1', 'Alpha'), _note('n2', 'Beta')],
          tasks: [mkTask('k1', summary: 'Pay rent')],
          size: size,
        );
        s.openNoteTab('n1');
        s.openNoteTab('n2');
        s.openTaskTab('k1');
        await t.pumpAndSettle();
        await t.tap(_k('bar-count'));
        await t.pumpAndSettle();
        expect(_k('open-grid'), findsOneWidget);
        expect(find.text('Open items (4)'), findsOneWidget);
        for (final c in ['n:n1', 'n:n2', 't:k1']) {
          expect(_k('grid-card-$c'), findsOneWidget);
        }
        // Title and first text line show.
        expect(find.text('Body of Alpha'), findsOneWidget);
        // The active card (the task) is highlighted.
        expect(
          _border(t, 'grid-card-t:k1'),
          isNot(_border(t, 'grid-card-n:n1')),
        );
        // Close one card.
        await t.tap(_k('grid-close-n:n1'));
        await t.pumpAndSettle();
        expect(_k('grid-card-n:n1'), findsNothing);
        expect(s.tabs.length, 2);
        // Open another by tapping it: the grid closes.
        await t.tap(_k('grid-card-n:n2'));
        await t.pumpAndSettle();
        expect(_k('open-grid'), findsNothing);
        expect(s.mainNoteUid, 'n2');
        // Done leaves; closing the last card goes Home.
        await t.tap(_k('bar-count'));
        await t.pumpAndSettle();
        await t.tap(_k('grid-done'));
        await t.pumpAndSettle();
        expect(_k('open-grid'), findsNothing);
        await t.tap(_k('bar-count'));
        await t.pumpAndSettle();
        await t.tap(_k('grid-close-n:n2'));
        await t.pumpAndSettle();
        await t.tap(_k('grid-close-t:k1'));
        await t.pumpAndSettle();
        expect(_k('open-grid'), findsNothing);
        expect(s.activeTab, isNull);
        expect(s.tabs, isEmpty);
        _noError(t);
      });

      testWidgets('the grid + adds and closes the grid', (t) async {
        await pumpTasksApp(t, size: size);
        await t.tap(_k('bar-count'));
        await t.pumpAndSettle();
        // Home is always a card now; there are no item cards yet.
        expect(_k('grid-card-home'), findsOneWidget);
        await t.tap(_k('grid-add'));
        await t.pumpAndSettle();
        await t.tap(_k('grid-add-task'));
        await t.pumpAndSettle();
        expect(_k('open-grid'), findsNothing);
        expect(_k('new-task-title'), findsOneWidget);
        _noError(t);
      });

      testWidgets('Back closes grid, sheet, menu, then the item', (t) async {
        final s = await pumpTasksApp(
          t,
          notes: [_note('n1', 'Alpha')],
          size: size,
        );
        s.openNoteTab('n1');
        await t.pumpAndSettle();
        await t.tap(_k('bar-count'));
        await t.pumpAndSettle();
        expect(await t.binding.handlePopRoute(), isTrue);
        await t.pumpAndSettle();
        expect(_k('open-grid'), findsNothing);
        expect(s.activeTab, isNotNull);
        await _openMenu(t);
        // A sheet above the menu closes before the menu.
        await t.longPress(
          find
              .descendant(of: _k('side-menu'), matching: find.text('Alpha'))
              .first,
        );
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsOneWidget);
        expect(await t.binding.handlePopRoute(), isTrue);
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(_k('side-menu'), findsOneWidget);
        expect(await t.binding.handlePopRoute(), isTrue);
        await t.pumpAndSettle();
        expect(_k('side-menu'), findsNothing);
        expect(s.activeTab, isNotNull);
        // The bar's Back does the same: item to Home.
        await t.tap(_k('bar-back'));
        await t.pumpAndSettle();
        expect(s.activeTab, isNull);
        expect(_k('space-chip'), findsOneWidget);
        _noError(t);
      });
    });
  }

  testWidgets('wide layout is unchanged: rail, no bar, menu, grid or edge', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      notes: [_note('n1', 'Alpha')],
      tasks: [mkTask('k1')],
      size: const Size(1280, 900),
    );
    for (final k in [
      'mobile-bar',
      'menu',
      'menu-edge',
      'side-menu',
      'open-grid',
      'space-chip',
    ]) {
      expect(_k(k), findsNothing, reason: k);
    }
    expect(_k('rail-tasks'), findsOneWidget);
    // The peek stays on desktop.
    await s.openNote('n1', mode: OpenMode.peek);
    await t.pumpAndSettle();
    expect(s.peekUid, 'n1');
    expect(_k('peek-promote'), findsOneWidget);
    await t.tap(_k('rail-tasks'));
    await t.pumpAndSettle();
    expect(find.byType(Dismissible), findsNothing);
    await t.longPress(_k('task-row-k1'));
    await t.pumpAndSettle();
    expect(_k('menu-sheet'), findsNothing);
    _noError(t);
  });

  testWidgets('880 wide keeps the rail and no bar', (t) async {
    await pumpTasksApp(t, size: const Size(880, 700));
    expect(_k('mobile-bar'), findsNothing);
    expect(_k('rail-notes'), findsOneWidget);
    _noError(t);
  });

  testWidgets('growing to wide closes the menu and keeps the desktop shell', (
    t,
  ) async {
    await pumpTasksApp(t, size: const Size(360, 640));
    await _openMenu(t);
    t.view.physicalSize = const Size(1280, 900);
    await t.pumpAndSettle();
    expect(_k('side-menu'), findsNothing);
    expect(_k('rail-notes'), findsOneWidget);
    _noError(t);
  });
}
