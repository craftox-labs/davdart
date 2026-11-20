import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

const _phones = [Size(320, 568), Size(360, 640)];

/// A state whose Space cannot hold tasks.
class _NoTasks extends FlagState {
  _NoTasks(super.source, {super.prefs});
  @override
  bool get supportsTasks => false;
}

Finder _k(String k) => find.byKey(Key(k));

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

void main() {
  for (final size in _phones) {
    group('phase 2 at $size', () {
      testWidgets('bottom nav maps the sections and More holds the rest', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          notes: [_note('n1', 'Alpha')],
          size: size,
        );
        expect(_k('bottom-nav'), findsOneWidget);
        for (final k in ['notes', 'tasks', 'events', 'search', 'more']) {
          expect(_k('bnav-$k'), findsOneWidget);
          // 44dp touch targets.
          expect(t.getRect(_k('bnav-$k')).height, greaterThanOrEqualTo(44));
        }
        await t.tap(_k('bnav-tasks'));
        await t.pumpAndSettle();
        expect(s.section, Section.tasks);
        expect(_k('tasks-view'), findsOneWidget);
        await t.tap(_k('bnav-events'));
        await t.pumpAndSettle();
        expect(s.section, Section.events);
        expect(_k('events-panel'), findsOneWidget);
        await t.tap(_k('bnav-search'));
        await t.pumpAndSettle();
        expect(s.section, Section.search);
        await t.tap(_k('bnav-more'));
        await t.pumpAndSettle();
        expect(_k('more-page'), findsOneWidget);
        expect(_k('more-views'), findsOneWidget);
        expect(_k('more-settings'), findsOneWidget);
        await t.tap(_k('more-settings'));
        await t.pumpAndSettle();
        expect(s.section, Section.settings);
        await t.tap(_k('bnav-notes'));
        await t.pumpAndSettle();
        expect(find.text('Alpha'), findsWidgets);
        // The Home button leads back to Home.
        await t.tap(_k('nav-home'));
        await t.pumpAndSettle();
        expect(_k('home-today'), findsOneWidget);
        _noError(t);
      });

      testWidgets('a section the Space cannot hold has no tab', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
        final s = _NoTasks(
          SpaceNoteSource(space, seed: SeedNotes(const [])),
          prefs: MemoryStorage(),
        );
        await t.pumpWidget(DavdartApp(state: s));
        await t.pumpAndSettle();
        expect(_k('bnav-notes'), findsOneWidget);
        expect(_k('bnav-tasks'), findsNothing);
        expect(_k('bnav-events'), findsOneWidget);
        _noError(t);
      });

      testWidgets('Space chip opens a sheet with the Space actions', (t) async {
        final s = await pumpTasksApp(t, size: size);
        expect(_k('space-chip'), findsOneWidget);
        expect(t.getRect(_k('space-chip')).height, greaterThanOrEqualTo(44));
        await t.tap(_k('space-chip'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsOneWidget);
        // This app has one fixed source, so the popup's single row shows.
        expect(find.text('One fixed notes source'), findsOneWidget);
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(s.section, Section.notes);
        _noError(t);
      });

      testWidgets('the quick-add button follows the section', (t) async {
        final s = await pumpTasksApp(t, size: size);
        expect(_k('fab-add'), findsOneWidget);
        expect(t.getRect(_k('fab-add')).width, greaterThanOrEqualTo(44));
        await t.tap(_k('bnav-notes'));
        await t.pumpAndSettle();
        await t.tap(_k('fab-add'));
        await t.pumpAndSettle();
        expect(find.text('New note'), findsWidgets);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();

        await t.tap(_k('bnav-tasks'));
        await t.pumpAndSettle();
        await t.tap(_k('fab-add'));
        await t.pumpAndSettle();
        await t.enterText(_k('new-task-title'), 'Buy milk');
        await t.tap(_k('new-task-add'));
        await t.pumpAndSettle();
        expect(s.tasks.map((k) => k.summary), contains('Buy milk'));

        await t.tap(_k('bnav-events'));
        await t.pumpAndSettle();
        await t.tap(_k('fab-add'));
        await t.pumpAndSettle();
        expect(_k('new-event-title'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();

        // Nothing to add on Search and More.
        await t.tap(_k('bnav-search'));
        await t.pumpAndSettle();
        expect(_k('fab-add'), findsNothing);
        await t.tap(_k('bnav-more'));
        await t.pumpAndSettle();
        expect(_k('fab-add'), findsNothing);
        _noError(t);
      });

      testWidgets('no quick-add in a read-only Space', (t) async {
        await pumpTasksApp(t, size: size, readOnly: true);
        await t.tap(_k('bnav-tasks'));
        await t.pumpAndSettle();
        expect(_k('fab-add'), findsNothing);
        _noError(t);
      });

      testWidgets('the peek is a draggable sheet; promote goes full screen', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          notes: [_note('n1', 'Alpha')],
          size: size,
        );
        await t.tap(_k('bnav-notes'));
        await t.pumpAndSettle();
        s.setOpenMode(OpenMode.peek);
        await s.openNote('n1', mode: OpenMode.peek);
        await t.pumpAndSettle();
        expect(_k('peek-sheet'), findsOneWidget);
        // The list stays under it.
        expect(_k('bottom-nav'), findsOneWidget);
        final half = t.getRect(_k('peek-sheet')).height;
        await t.drag(_k('peek-sheet-handle'), Offset(0, -size.height));
        await t.pumpAndSettle();
        expect(t.getRect(_k('peek-sheet')).height, greaterThan(half));
        await t.drag(_k('peek-sheet-handle'), Offset(0, size.height * 0.3));
        await t.pumpAndSettle();
        expect(t.getRect(_k('peek-sheet')).height, lessThanOrEqualTo(half));
        _noError(t);

        // Dragging far down closes it.
        await t.drag(_k('peek-sheet-handle'), Offset(0, size.height));
        await t.pumpAndSettle();
        expect(s.peekUid, isNull);
        expect(_k('peek-sheet'), findsNothing);

        // Promote: the note fills the screen, Back returns.
        await s.openNote('n1', mode: OpenMode.peek);
        await t.pumpAndSettle();
        await t.tap(_k('peek-promote'));
        await t.pumpAndSettle();
        expect(s.peekUid, isNull);
        expect(_k('peek-sheet'), findsNothing);
        expect(_k('main-note'), findsOneWidget);
        expect(_k('bottom-nav'), findsNothing);
        _noError(t);
      });

      testWidgets('long press on a row opens its actions as a sheet', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          notes: [_note('n1', 'Alpha')],
          tasks: [mkTask('k1', summary: 'Pay rent')],
          size: size,
        );
        await t.tap(_k('bnav-notes'));
        await t.pumpAndSettle();
        await t.longPress(find.text('Alpha').first);
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsOneWidget);
        expect(_k('menu-open-peek'), findsOneWidget);
        await t.tap(_k('menu-open-peek'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsNothing);
        expect(s.peekUid, 'n1');
        s.select(null);
        await t.pumpAndSettle();

        await t.tap(_k('bnav-tasks'));
        await t.pumpAndSettle();
        await t.longPress(_k('task-row-k1'));
        await t.pumpAndSettle();
        expect(_k('menu-sheet'), findsOneWidget);
        _noError(t);
      });

      testWidgets('swipe right completes an open task, Undo reopens it', (
        t,
      ) async {
        final s = await pumpTasksApp(
          t,
          tasks: [
            mkTask('k1', summary: 'Pay rent'),
            mkTask('k2', summary: 'Done already', status: 'COMPLETED'),
          ],
          size: size,
        );
        await t.tap(_k('bnav-tasks'));
        await t.pumpAndSettle();
        // A closed task does not swipe.
        await t.tap(_k('tasks-filter-completed'));
        await t.pumpAndSettle();
        await t.drag(_k('task-row-k2'), const Offset(300, 0));
        await t.pumpAndSettle();
        expect(s.taskById('k2')!.isClosed, isTrue);
        expect(_k('swipe-undo'), findsNothing);
        await t.tap(_k('tasks-filter-open'));
        await t.pumpAndSettle();

        await t.drag(_k('task-row-k1'), const Offset(300, 0));
        await t.pumpAndSettle();
        expect(s.taskById('k1')!.isClosed, isTrue);
        await t.tap(_k('swipe-undo'));
        await t.pumpAndSettle();
        expect(s.taskById('k1')!.isClosed, isFalse);
        expect(_k('task-row-k1'), findsOneWidget);
        _noError(t);
      });
    });
  }

  testWidgets('Back closes the peek, then the page, then Home', (t) async {
    final s = await pumpTasksApp(
      t,
      notes: [_note('n1', 'Alpha')],
      size: const Size(360, 640),
    );
    await t.tap(_k('bnav-notes'));
    await t.pumpAndSettle();
    await s.openNote('n1', mode: OpenMode.peek);
    await t.pumpAndSettle();
    expect(_k('peek-sheet'), findsOneWidget);
    expect(await t.binding.handlePopRoute(), isTrue);
    await t.pumpAndSettle();
    expect(_k('peek-sheet'), findsNothing);
    expect(_k('bnav-notes'), findsOneWidget);
    expect(await t.binding.handlePopRoute(), isTrue);
    await t.pumpAndSettle();
    expect(_k('home-today'), findsOneWidget);
    // A menu sheet closes first.
    await t.tap(_k('bnav-notes'));
    await t.pumpAndSettle();
    await t.tap(_k('space-chip'));
    await t.pumpAndSettle();
    expect(_k('menu-sheet'), findsOneWidget);
    expect(await t.binding.handlePopRoute(), isTrue);
    await t.pumpAndSettle();
    expect(_k('menu-sheet'), findsNothing);
    expect(_k('bnav-notes'), findsOneWidget);
    _noError(t);
  });

  testWidgets('More with an unavailable section opens the More page', (
    t,
  ) async {
    final s = await pumpTasksApp(t, size: const Size(360, 640));
    s.section = Section.account; // no sign-in here
    await t.tap(_k('bnav-more'));
    await t.pumpAndSettle();
    expect(_k('more-page'), findsOneWidget);
    expect(s.section, Section.views);
    _noError(t);
  });

  testWidgets('growing to wide closes an open sheet', (t) async {
    await pumpTasksApp(t, size: const Size(360, 640));
    await t.tap(_k('space-chip'));
    await t.pumpAndSettle();
    expect(_k('menu-sheet'), findsOneWidget);
    t.view.physicalSize = const Size(1280, 900);
    await t.pumpAndSettle();
    expect(_k('menu-sheet'), findsNothing);
    _noError(t);
  });

  testWidgets('wide layout is unchanged: no bottom nav, chip, FAB or sheet', (
    t,
  ) async {
    final s = await pumpTasksApp(
      t,
      notes: [_note('n1', 'Alpha')],
      tasks: [mkTask('k1')],
      size: const Size(1280, 900),
    );
    expect(_k('bottom-nav'), findsNothing);
    expect(_k('space-chip'), findsNothing);
    expect(_k('fab-add'), findsNothing);
    expect(_k('nav-home'), findsNothing);
    expect(_k('rail-tasks'), findsOneWidget);
    s.setOpenMode(OpenMode.peek);
    await s.openNote('n1', mode: OpenMode.peek);
    await t.pumpAndSettle();
    expect(_k('peek-sheet'), findsNothing);
    expect(_k('peek-promote'), findsOneWidget);
    // No swipe wrapper and a popup (not a sheet) for the menu.
    await t.tap(_k('rail-tasks'));
    await t.pumpAndSettle();
    expect(find.byType(Dismissible), findsNothing);
    await t.longPress(_k('task-row-k1'));
    await t.pumpAndSettle();
    expect(_k('menu-sheet'), findsNothing);
    _noError(t);
  });

  testWidgets('880 wide (just wide) keeps the rail and no bottom nav', (
    t,
  ) async {
    await pumpTasksApp(t, size: const Size(880, 700));
    expect(_k('bottom-nav'), findsNothing);
    expect(_k('rail-notes'), findsOneWidget);
    _noError(t);
  });
}
