import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/state/tab_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

Finder _k(String k) => find.byKey(Key(k));

Note _folder(
  String uid,
  String name, {
  String? parent,
  bool container = false,
}) => Note(
  uid: uid,
  summary: name,
  parentUid: parent,
  categories: [folderTag, if (container) projectsTag],
);

final _notes = [
  _folder('c', 'Projects', container: true),
  _folder('p', 'Alpha', parent: 'c'),
  _folder('q', 'Beta', parent: 'c'),
  Note(uid: 'loose', summary: 'Loose note'),
];

const _slow = Duration(milliseconds: 400);

Future<void> _settle(WidgetTester t) async {
  await t.pump(_slow);
  await t.pump(_slow);
}

String _title(WidgetTester t) => t.widget<Text>(_k('page-title')).data ?? '';

void main() {
  group('a tab tap syncs scope, page and title', () {
    testWidgets('project tabs by tap: scope, page and title follow together', (
      t,
    ) async {
      final s = await pumpTasksApp(t, notes: _notes);
      s.openProjectTab('p');
      s.openProjectTab('q');
      await _settle(t);
      expect(s.scopeUid, 'q');
      expect(_title(t), 'Beta');

      await t.tap(_k('tab-p:p'));
      await _settle(t);
      expect(s.activeTab, const DocTab.project('p'));
      expect(s.scopeUid, 'p');
      expect(s.mainProjectUid, 'p');
      expect(_title(t), 'Alpha');
      expect(_k('overview-page'), findsOneWidget);

      await t.tap(_k('tab-p:q'));
      await _settle(t);
      expect(s.scopeUid, 'q');
      expect(_title(t), 'Beta');
    });

    testWidgets('tapping Home clears the scope and shows the Home page', (
      t,
    ) async {
      final s = await pumpTasksApp(t, notes: _notes);
      s.openProjectTab('p');
      await _settle(t);
      expect(s.scopeUid, 'p');
      await t.tap(_k('tab-home'));
      await _settle(t);
      expect(s.activeTab, isNull);
      expect(s.scopeUid, isNull);
      expect(s.mainProjectUid, isNull);
      expect(_k('home-page'), findsOneWidget);
      expect(_k('overview-page'), findsNothing);
    });

    testWidgets('a tab tap leaves the panel section as it was', (t) async {
      final s = await pumpTasksApp(t, notes: _notes);
      s.setSection(Section.tasks);
      s.openProjectTab('p');
      s.openProjectTab('q');
      await _settle(t);
      await t.tap(_k('tab-p:p'));
      await _settle(t);
      expect(s.section, Section.tasks);
      await t.tap(_k('tab-home'));
      await _settle(t);
      expect(s.section, Section.tasks);
    });

    testWidgets('tapping between a project tab and a note tab swaps the page', (
      t,
    ) async {
      final s = await pumpTasksApp(t, notes: _notes);
      s.openProjectTab('p');
      s.openNoteTab('loose');
      await _settle(t);
      await t.tap(_k('tab-p:p'));
      await _settle(t);
      expect(s.scopeUid, 'p');
      await t.tap(_k('tab-n:loose'));
      await _settle(t);
      expect(s.activeTab, const DocTab.note('loose'));
      expect(_k('overview-page'), findsNothing);
      expect(s.mainProjectUid, isNull);
    });
  });

  group('restart restores tab, section and scope', () {
    /// Pumps a first run, lets [setup] change it, then boots a second app
    /// on the same storage and Space.
    Future<AppState> restart(
      WidgetTester t,
      void Function(AppState) setup,
    ) async {
      final prefs = MemoryStorage();
      final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
      final first = await pumpTasksApp(
        t,
        notes: _notes,
        prefs: prefs,
        into: space,
      );
      setup(first);
      await _settle(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      return pumpTasksApp(t, notes: _notes, prefs: prefs, into: space);
    }

    testWidgets('saved Tasks section and a project tab come back', (t) async {
      final s = await restart(t, (a) {
        a.setSection(Section.tasks);
        a.openProjectTab('p');
      });
      expect(s.section, Section.tasks);
      expect(s.activeTab, const DocTab.project('p'));
      expect(s.scopeUid, 'p');
      expect(_title(t), 'Alpha');
    });

    testWidgets('saved Events section on Home comes back, no scope', (t) async {
      final s = await restart(t, (a) => a.setSection(Section.events));
      expect(s.section, Section.events);
      expect(s.activeTab, isNull);
      expect(s.scopeUid, isNull);
      expect(_k('home-page'), findsOneWidget);
    });

    testWidgets('a saved Projects picker is not a landing page: Notes', (
      t,
    ) async {
      final s = await restart(t, (a) {
        a.setSection(Section.projects);
        a.openProjectTab('q');
      });
      expect(s.section, isNot(Section.projects));
      expect(s.section, Section.notes);
      expect(s.activeTab, const DocTab.project('q'));
      expect(s.scopeUid, 'q');
    });

    testWidgets('stale pair: saved section stays, deleted project tab drops', (
      t,
    ) async {
      final prefs = MemoryStorage()
        ..write('davdart.section.v1', 'tasks')
        ..write('davdart.tabs.v1.default', '["p:gone","p:p"]')
        ..write('davdart.activetab.v1.default', 'p:gone');
      final s = await pumpTasksApp(t, notes: _notes, prefs: prefs);
      expect(s.section, Section.tasks);
      expect(s.activeTab, isNull);
      expect(s.scopeUid, isNull);
      expect(s.tabs, [const DocTab.project('p')]);
      expect(_k('home-page'), findsOneWidget);
    });

    testWidgets('an unknown saved section falls back to Notes', (t) async {
      final prefs = MemoryStorage()
        ..write('davdart.section.v1', 'nonsense')
        ..write('davdart.tabs.v1.default', '["p:p"]')
        ..write('davdart.activetab.v1.default', 'p:p');
      final s = await pumpTasksApp(t, notes: _notes, prefs: prefs);
      expect(s.section, Section.notes);
      expect(s.activeTab, const DocTab.project('p'));
      expect(s.scopeUid, 'p');
    });

    testWidgets('saved tab with another saved scope: the tab owns the scope', (
      t,
    ) async {
      final prefs = MemoryStorage()
        ..write('davdart.section.v1', 'tasks')
        ..write('davdart.tabs.v1.default', '["p:p","p:q"]')
        ..write('davdart.activetab.v1.default', 'p:q');
      final s = await pumpTasksApp(t, notes: _notes, prefs: prefs);
      expect(s.activeTab, const DocTab.project('q'));
      expect(s.scopeUid, 'q');
      expect(s.section, Section.tasks);
    });
  });
}
